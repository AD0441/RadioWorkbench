import Foundation

public enum TerrainCoverageQuality: String, CaseIterable, Codable, Sendable, Identifiable {
    case quick, detailed
    public var id: String { rawValue }
    public var title: String { self == .quick ? "Rápida · 65 × 65" : "Detallada · 129 × 129" }
    public var side: Int { self == .quick ? 65 : 129 }
}

public struct TerrainCoverageLayout: Sendable {
    public let origin: RadioLocation
    public let radiusKm: Double
    public let side: Int
    public let minX: Double
    public let minY: Double
    public let span: Double
    public var spacingMeters: Double { radiusKm * 2_000 / Double(side) }
    public init(origin: RadioLocation, radiusKm: Double, side: Int) throws {
        guard (5...200).contains(radiusKm), abs(origin.latitude) <= 80, (9...129).contains(side), side % 2 == 1 else { throw TerrainDEMError.unsupportedArea }
        let center = TerrainMercator.point(origin)
        let delta = radiusKm * 1_000 / (TerrainMercator.circumferenceMeters * cos(origin.latitude * .pi / 180))
        guard center.y - delta > 0, center.y + delta < 1 else { throw TerrainDEMError.unsupportedArea }
        self.origin = origin; self.radiusKm = radiusKm; self.side = side
        minX = center.x - delta; minY = center.y - delta; span = 2 * delta
    }
    public func location(row: Int, column: Int) -> RadioLocation? {
        TerrainMercator.location(x: minX + span * (Double(column) + 0.5) / Double(side),
                                y: minY + span * (Double(row) + 0.5) / Double(side))
    }
    public func index(at location: RadioLocation) -> Int? {
        var p = TerrainMercator.point(location)
        let centerX = minX + span / 2
        p.x += round(centerX - p.x)
        let row = Int(floor((p.y - minY) / span * Double(side)))
        let col = Int(floor((p.x - minX) / span * Double(side)))
        guard (0..<side).contains(row), (0..<side).contains(col) else { return nil }
        return row * side + col
    }
    public func tileKeys(zoom: Int) -> [TerrainTileKey] {
        let n = Double(1 << zoom)
        let left = Int(floor(minX * n)) - 1, right = Int(floor((minX + span) * n)) + 1
        let top = max(0, Int(floor(minY * n)) - 1), bottom = min(Int(n) - 1, Int(floor((minY + span) * n)) + 1)
        var keys: Set<TerrainTileKey> = []
        for y in top...bottom { for x in left...right { keys.insert(TerrainTileKey(zoom: zoom, x: x, y: y)) } }
        return keys.sorted { $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y }
    }
    public var suitableTileKeys: [TerrainTileKey] {
        var zoom = radiusKm <= 50 ? 11 : 10
        while zoom > 7, tileKeys(zoom: zoom).count > 128 { zoom -= 1 }
        return tileKeys(zoom: zoom)
    }
}

public struct TerrainCoverageCell: Sendable, Codable {
    public let receivedPowerDBm: Double
    public let basicLossDB: Double
    public let groundMeters: Double
    public let minimumClearanceMeters: Double
    public let warningFlags: Int
    public let propagationMode: String
    public init(receivedPowerDBm: Double, basicLossDB: Double, groundMeters: Double, minimumClearanceMeters: Double,
                warningFlags: Int, propagationMode: String) {
        self.receivedPowerDBm = receivedPowerDBm; self.basicLossDB = basicLossDB; self.groundMeters = groundMeters
        self.minimumClearanceMeters = minimumClearanceMeters; self.warningFlags = warningFlags; self.propagationMode = propagationMode
    }
}

public struct TerrainCoverageReport: Sendable {
    public let id: UUID
    public let layout: TerrainCoverageLayout
    public let input: TerrainITMInput
    public let thresholdDBm: Double
    public let cells: [TerrainCoverageCell?]
    public let missingTerrainCells: Int
    public let modelErrorCells: Int
    public let mosaic: TerrainDEMMosaic
    public init(layout: TerrainCoverageLayout, input: TerrainITMInput, thresholdDBm: Double, cells: [TerrainCoverageCell?],
                missingTerrainCells: Int, modelErrorCells: Int, mosaic: TerrainDEMMosaic) {
        id = UUID(); self.layout = layout; self.input = input; self.thresholdDBm = thresholdDBm; self.cells = cells
        self.missingTerrainCells = missingTerrainCells; self.modelErrorCells = modelErrorCells; self.mosaic = mosaic
    }
    public var modeledCount: Int { cells.compactMap { $0 }.count }
    public var coveredCount: Int { cells.compactMap { $0 }.filter { $0.receivedPowerDBm >= thresholdDBm }.count }
    public var warnedCount: Int { cells.compactMap { $0 }.filter { $0.warningFlags != 0 }.count }
    public var edgeCoveredCount: Int {
        cells.indices.filter { index in
            guard let cell = cells[index], cell.receivedPowerDBm >= thresholdDBm,
                  let point = layout.location(row: index / layout.side, column: index % layout.side) else { return false }
            return layout.origin.distance(to: point) >= layout.radiusKm - layout.spacingMeters / 1_000
        }.count
    }
    public func cell(at location: RadioLocation) -> TerrainCoverageCell? {
        guard let index = layout.index(at: location), cells.indices.contains(index) else { return nil }
        return cells[index]
    }
    /// Rows are north-to-south. Each pixel is independently modeled; no filling toward a maximum radial range.
    public func rgba(showShadows: Bool) -> [UInt8] {
        cells.flatMap { cell -> [UInt8] in
            guard let cell else { return [0, 0, 0, 0] }
            let margin = cell.receivedPowerDBm - thresholdDBm
            if margin >= 10 { return [30, 178, 100, 155] }
            if margin >= 0 { return [246, 163, 45, 165] }
            return showShadows ? [166, 50, 60, 105] : [0, 0, 0, 0]
        }
    }
}

public enum TerrainCoverageCalculator {
    public static func calculate(layout: TerrainCoverageLayout, input: TerrainITMInput, thresholdDBm: Double,
                                 mosaic: TerrainDEMMosaic, native: TerrainITMNative,
                                 progress: @escaping @Sendable (Int, Int) async -> Void = { _, _ in }) async throws -> TerrainCoverageReport {
        guard input.isValid, thresholdDBm.isFinite, (-200...0).contains(thresholdDBm) else { throw TerrainITMError.invalidInput }
        guard mosaic.elevation(at: layout.origin) != nil else { throw TerrainDEMError.missingOrigin }
        let task = Task.detached(priority: .userInitiated) {
            var cells = [TerrainCoverageCell?](repeating: nil, count: layout.side * layout.side)
            var missing = 0, errors = 0
            for row in 0..<layout.side {
                try Task.checkCancellation()
                for column in 0..<layout.side {
                    guard let target = layout.location(row: row, column: column) else { continue }
                    let distance = layout.origin.distance(to: target)
                    guard distance >= 1, distance <= layout.radiusKm else { continue }
                    let profile: TerrainProfile
                    do { profile = try mosaic.profile(from: layout.origin, to: target) }
                    catch { missing += 1; continue }
                    do {
                        let result = try native.predict(input: input, elevations: profile.elevationsMeters,
                                                       spacingMeters: profile.resolutionMeters)
                        guard let sight = TerrainLineOfSight.evaluate(profile: profile, txHeightAGLMeters: input.txHeightMeters,
                                                                      rxHeightAGLMeters: input.rxHeightMeters) else { errors += 1; continue }
                        cells[row * layout.side + column] = TerrainCoverageCell(receivedPowerDBm: result.receivedPowerDBm,
                            basicLossDB: result.basicTransmissionLossDB, groundMeters: profile.points.last!.elevationMeters,
                            minimumClearanceMeters: sight.minimumClearanceMeters, warningFlags: result.warningFlags,
                            propagationMode: result.propagationMode)
                    } catch { errors += 1 }
                }
                await progress(row + 1, layout.side)
            }
            return TerrainCoverageReport(layout: layout, input: input, thresholdDBm: thresholdDBm, cells: cells,
                missingTerrainCells: missing, modelErrorCells: errors, mosaic: mosaic)
        }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
}
