import Foundation
import Testing
import CoreGraphics
import ImageIO
import MapKit
@testable import RadioCore
@testable import RadioWorkbench

private func testMosaic(_ layout: TerrainCoverageLayout, height: (Double, Double) -> Float) throws -> TerrainDEMMosaic {
    let zoom = 10, n = Double(1 << zoom), center = TerrainMercator.point(layout.origin)
    let scale = TerrainMercator.circumferenceMeters * cos(layout.origin.latitude * .pi / 180) / 1_000
    let tiles = try layout.tileKeys(zoom: zoom).map { key in
        var values = [Float](); values.reserveCapacity(65_536)
        for row in 0..<256 { for column in 0..<256 {
            let x = (Double(key.x) + (Double(column) + 0.5) / 256) / n
            let y = (Double(key.y) + (Double(row) + 0.5) / 256) / n
            values.append(height((x - center.x) * scale, (center.y - y) * scale))
        } }
        return try TerrainElevationTile(key: key, elevations: values)
    }
    return TerrainDEMMosaic(zoom: zoom, tiles: Dictionary(uniqueKeysWithValues: tiles.map { ($0.key, $0) }))
}

@Test func terrainDEMDecodesNumericRGBAndNeverAssumesMissingTerrainIsFlat() throws {
    #expect(TerrainElevationTile.elevation(red: 137, green: 219, blue: 68) == 2523.265625)
    let origin = try #require(RadioLocation(latitude: -33.45, longitude: -70.67))
    let layout = try TerrainCoverageLayout(origin: origin, radiusKm: 20, side: 33)
    let mosaic = try testMosaic(layout) { _, _ in 100 }
    #expect(abs((mosaic.elevation(at: origin) ?? 0) - 100) < 0.0001)
    #expect(TerrainDEMMosaic(zoom: 10, tiles: [:]).elevation(at: origin) == nil)
    let destination = try #require(origin.destination(km: 10, bearing: 90))
    let profile = try mosaic.profile(from: origin, to: destination)
    #expect(profile.points.count > 60)
    #expect(profile.points.first?.elevationMeters == 100)
    #expect(profile.antennaAltitudeAMSL(aglMeters: 10, atOrigin: true) == 110)
    let sea = try testMosaic(layout) { _, _ in -1_500 }
    #expect(try sea.profile(from: origin, to: destination).points.allSatisfy { $0.elevationMeters == 0 })
}

@Test func terrainCoverageGridIsNorthOrientedAndWrapsAtTheDateLine() throws {
    let origin = try #require(RadioLocation(latitude: -33.45, longitude: 179.98))
    let layout = try TerrainCoverageLayout(origin: origin, radiusKm: 20, side: 65)
    let north = try #require(layout.location(row: 0, column: 32))
    let south = try #require(layout.location(row: 64, column: 32))
    let east = try #require(layout.location(row: 32, column: 64))
    #expect(north.latitude > origin.latitude && south.latitude < origin.latitude)
    #expect(east.longitude < 0)
    #expect(layout.index(at: east) == 32 * 65 + 64)
    #expect(layout.index(at: origin) == 32 * 65 + 32)
    #expect(layout.suitableTileKeys.count <= 128)
    #expect(layout.suitableTileKeys.allSatisfy { $0.x >= 0 && $0.x < 1 << $0.zoom })
}

@Test func terrainExactLinkTileCorridorCoversEverySampleAcrossTheDateLine() throws {
    let origin = try #require(RadioLocation(latitude: 65, longitude: 179.8))
    let target = try #require(origin.destination(km: 480, bearing: 75))
    let keys = try TerrainDEMService.profileTileKeys(from: origin, to: target)
    #expect(keys.count <= 128)
    #expect(keys.contains { $0.x == 0 } && keys.contains { $0.x == (1 << $0.zoom) - 1 })
    let tiles = try keys.map { key in try TerrainElevationTile(key: key, elevations: Array(repeating: 100, count: 65_536)) }
    let mosaic = TerrainDEMMosaic(zoom: keys[0].zoom, tiles: Dictionary(uniqueKeysWithValues: tiles.map { ($0.key, $0) }))
    let profile = try mosaic.profile(from: origin, to: target)
    #expect(profile.points.count > 501 && profile.points.count <= 4097)
    #expect(profile.points.allSatisfy { abs($0.elevationMeters - 100) < 0.0001 })
    #expect(TerrainITMWarning.descriptions(flags: 0x100 | 0x40).count == 2)
}

@Test func terrainNativeITMPreservesWarningsAndMatchesTheCLI() throws {
    let native = try TerrainITMNative()
    let input = TerrainITMInput(frequencyMHz: 144.39, txHeightMeters: 10, rxHeightMeters: 0.5)
    let heights = [Double](repeating: 100, count: 201)
    let result = try native.predict(input: input, elevations: heights, spacingMeters: 50)
    #expect(result.warningFlags & 2 != 0)
    let helper = try #require(ProcessInfo.processInfo.environment["ITM_HELPER_PATH"])
    let process = Process(), stdin = Pipe(), stdout = Pipe()
    process.executableURL = URL(fileURLWithPath: helper); process.standardInput = stdin; process.standardOutput = stdout
    try process.run()
    let parameters = [144.39, 10, 0.5, 5, 301, 1, 15, 0.005, 50, 50, 10, 0, 0, 201, 50] + heights
    stdin.fileHandleForWriting.write(Data((parameters.map { String($0) }.joined(separator: " ") + "\n").utf8))
    try stdin.fileHandleForWriting.close()
    let data = stdout.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    #expect(process.terminationStatus == 0)
    let reference = try JSONDecoder().decode(TerrainITMResult.self, from: data)
    #expect(abs(result.receivedPowerDBm - reference.receivedPowerDBm) < 0.00001)
    #expect(result.warningFlags == reference.warningFlags)
    #expect(!TerrainITMInput(frequencyMHz: 144, txHeightMeters: 10, rxHeightMeters: 2, refractivityN0: 200).isValid)
    #expect(!TerrainITMInput(frequencyMHz: 144, txHeightMeters: 10, rxHeightMeters: 2, relativePermittivity: 1).isValid)
}

@Test func terrainNativeITMMatchesAllFivePublishedNTIAReferencePaths() throws {
    let directory = try #require(Bundle.module.url(forResource: "TerrainReference", withExtension: nil, subdirectory: "Fixtures"))
    let cases = try String(contentsOf: directory.appendingPathComponent("p2p.csv"), encoding: .utf8)
        .split(whereSeparator: \.isNewline).dropFirst().map { $0.split(separator: ",").compactMap { Double($0) } }
    let profiles = try String(contentsOf: directory.appendingPathComponent("pfls.csv"), encoding: .utf8)
        .split(whereSeparator: \.isNewline).map { $0.split(separator: ",").compactMap { Double($0) } }
    let native = try TerrainITMNative()
    #expect(cases.count == 5 && profiles.count == 5)
    for (row, profile) in zip(cases, profiles) {
        // mdvar=12 removes location variability; CR confidence=situation and reliability=time reproduce TLS cases.
        let input = TerrainITMInput(frequencyMHz: row[5], txHeightMeters: row[0], rxHeightMeters: row[1],
            climate: ITMClimate(rawValue: Int(row[7]))!, refractivityN0: row[4], verticalPolarization: row[6] == 1,
            relativePermittivity: row[2], conductivity: row[3], confidencePercent: row[10], reliabilityPercent: row[8],
            variabilityMode: Int(row[11]))
        let elevations = Array(profile.dropFirst(2))
        #expect(elevations.count == Int(profile[0]) + 1)
        let result = try native.predict(input: input, elevations: elevations, spacingMeters: profile[1])
        #expect(abs(result.basicTransmissionLossDB - row[12]) < 0.01)
    }
}

@Test func terrainCoverageRidgeCreatesARealShadowWithoutFillingFromTheFarthestPoint() async throws {
    let origin = try #require(RadioLocation(latitude: -33.45, longitude: -70.67))
    let layout = try TerrainCoverageLayout(origin: origin, radiusKm: 20, side: 33)
    let mosaic = try testMosaic(layout) { x, _ in (3...5).contains(x) ? 1800 : 100 }
    let native = try TerrainITMNative()
    let input = TerrainITMInput(frequencyMHz: 144.39, txHeightMeters: 10, rxHeightMeters: 2)
    let east = try #require(layout.location(row: 16, column: 25)), west = try #require(layout.location(row: 16, column: 7))
    let eastProfile = try mosaic.profile(from: origin, to: east), westProfile = try mosaic.profile(from: origin, to: west)
    let eastRX = try native.predict(input: input, elevations: eastProfile.elevationsMeters, spacingMeters: eastProfile.resolutionMeters).receivedPowerDBm
    let westRX = try native.predict(input: input, elevations: westProfile.elevationsMeters, spacingMeters: westProfile.resolutionMeters).receivedPowerDBm
    #expect(eastRX < westRX - 20)
    let threshold = (eastRX + westRX) / 2
    let report = try await TerrainCoverageCalculator.calculate(layout: layout, input: input, thresholdDBm: threshold, mosaic: mosaic, native: native)
    let eastCell = try #require(report.cell(at: east)), westCell = try #require(report.cell(at: west))
    #expect(eastCell.minimumClearanceMeters < -1_000)
    #expect(eastCell.receivedPowerDBm < threshold && westCell.receivedPowerDBm > threshold)
    let rgba = report.rgba(showShadows: false)
    #expect(rgba[(16 * 33 + 25) * 4 + 3] == 0)
    #expect(rgba[(16 * 33 + 7) * 4 + 3] > 0)
    #expect(report.missingTerrainCells == 0)
    print("ITM cresta: este \(eastRX) dBm; oeste \(westRX) dBm; diferencia \(westRX - eastRX) dB")
}

@Test func terrainCoverageKeepsAnInteriorHoleAndARemoteRecoveryAsSeparateCells() throws {
    let origin = try #require(RadioLocation(latitude: -33.45, longitude: -70.67))
    let layout = try TerrainCoverageLayout(origin: origin, radiusKm: 20, side: 9)
    var cells = [TerrainCoverageCell?](repeating: nil, count: 81)
    let valid = TerrainCoverageCell(receivedPowerDBm: -80, basicLossDB: 120, groundMeters: 100,
        minimumClearanceMeters: 2, warningFlags: 0, propagationMode: "Visibilidad")
    let shadow = TerrainCoverageCell(receivedPowerDBm: -125, basicLossDB: 165, groundMeters: 100,
        minimumClearanceMeters: -500, warningFlags: 0, propagationMode: "Difracción")
    cells[4 * 9 + 5] = valid; cells[4 * 9 + 6] = shadow; cells[4 * 9 + 7] = valid
    let report = TerrainCoverageReport(layout: layout, input: TerrainITMInput(frequencyMHz: 144, txHeightMeters: 10, rxHeightMeters: 2),
        thresholdDBm: -110, cells: cells, missingTerrainCells: 0, modelErrorCells: 0, mosaic: TerrainDEMMosaic(zoom: 10, tiles: [:]))
    let alpha = report.rgba(showShadows: false)
    #expect(alpha[(4 * 9 + 5) * 4 + 3] > 0)
    #expect(alpha[(4 * 9 + 6) * 4 + 3] == 0)
    #expect(alpha[(4 * 9 + 7) * 4 + 3] > 0)
    #expect(report.coveredCount == 2)
}

@MainActor @Test func terrainMapRendererKeepsNorthUpAndDoesNotPaintShadowHoles() throws {
    let origin = try #require(RadioLocation(latitude: -33.45, longitude: -70.67))
    let layout = try TerrainCoverageLayout(origin: origin, radiusKm: 20, side: 9)
    func cell(_ power: Double) -> TerrainCoverageCell {
        TerrainCoverageCell(receivedPowerDBm: power, basicLossDB: 120, groundMeters: 100,
            minimumClearanceMeters: 2, warningFlags: 0, propagationMode: "Visibilidad")
    }
    var cells = [TerrainCoverageCell?](repeating: nil, count: 81)
    cells[1 * 9 + 4] = cell(-80)   // north, green
    cells[4 * 9 + 4] = cell(-130)  // interior shadow, transparent
    cells[7 * 9 + 4] = cell(-105)  // south, amber
    let report = TerrainCoverageReport(layout: layout, input: TerrainITMInput(frequencyMHz: 144, txHeightMeters: 10, rxHeightMeters: 2),
        thresholdDBm: -110, cells: cells, missingTerrainCells: 0, modelErrorCells: 0, mosaic: TerrainDEMMosaic(zoom: 10, tiles: [:]))
    let overlay = try #require(TerrainCoverageOverlay(report: report, showShadows: false))
    let renderer = TerrainCoverageRenderer(overlay: overlay)
    let rect = renderer.rect(for: overlay.boundingMapRect)
    #expect(rect.width.isFinite && rect.width > 0)
    let context = try #require(CGContext(data: nil, width: 90, height: 90, bitsPerComponent: 8, bytesPerRow: 360,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    // MapKit gives renderers a north-to-south drawing space. Match that space in this bitmap.
    context.translateBy(x: 0, y: 90)
    context.scaleBy(x: 90 / rect.width, y: -90 / rect.height)
    context.translateBy(x: -rect.minX, y: -rect.minY)
    renderer.draw(overlay.boundingMapRect, zoomScale: 90 / rect.width, in: context)
    let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
    let north = 15 * 360 + 45 * 4, center = 45 * 360 + 45 * 4, south = 75 * 360 + 45 * 4
    #expect(bytes[north + 1] > bytes[north] && bytes[north + 3] > 0)
    #expect(bytes[center + 3] == 0)
    #expect(bytes[south] > bytes[south + 1] && bytes[south + 3] > 0)
}

@Test func terrainCoverageCancellationDoesNotPublishAPartialRaster() async throws {
    let origin = try #require(RadioLocation(latitude: -33.45, longitude: -70.67))
    let layout = try TerrainCoverageLayout(origin: origin, radiusKm: 20, side: 65)
    let mosaic = try testMosaic(layout) { _, _ in 100 }, native = try TerrainITMNative()
    let task = Task {
        try await TerrainCoverageCalculator.calculate(layout: layout,
            input: TerrainITMInput(frequencyMHz: 144, txHeightMeters: 10, rxHeightMeters: 2), thresholdDBm: -110, mosaic: mosaic, native: native)
    }
    task.cancel()
    do { _ = try await task.value; Issue.record("A cancelled computation must not publish a raster") }
    catch is CancellationError { }
}

private actor TerrainRequestCounter {
    var count = 0
    func increment() { count += 1 }
}

@Test func terrainDEMPNGIsDecodedWithoutColorConversionAndCacheAvoidsRepeatDownload() async throws {
    let key = TerrainTileKey(zoom: 10, x: 311, y: 613)
    let rgba = Data(Array(repeating: [UInt8(128), 100, 64, 255], count: 65_536).flatMap { $0 })
    let provider = try #require(CGDataProvider(data: rgba as CFData))
    let image = try #require(CGImage(width: 256, height: 256, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 1024,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    let tile = try TerrainElevationTile.decode(data as Data, key: key)
    #expect(tile.elevations.first == 100.25 && tile.elevations.last == 100.25)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let count = TerrainRequestCounter(), png = data as Data
    let service = TerrainDEMService(cacheURL: directory, transport: { request in
        await count.increment()
        return (png, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    })
    let first = try await service.load(keys: [key]), second = try await service.load(keys: [key])
    #expect(first.cachedTiles == 0 && second.cachedTiles == 1)
    #expect(await count.count == 1)
    #expect(second.tiles[key]?.elevations.first == 100.25)
}

@MainActor @Test func terrainDestinationSelectionKeepsCoverageAndAGLHorizonHasNoSeaLevelOffset() throws {
    let keys = ["terrainOriginLatitude", "terrainOriginLongitude", "terrainTargetLatitude", "terrainTargetLongitude", "terrainTxHeight", "terrainRxHeight"]
    let defaults = UserDefaults.standard
    let previous = keys.map { defaults.object(forKey: $0) }
    defer { for (key, value) in zip(keys, previous) { if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) } } }
    let origin = try #require(RadioLocation(latitude: -33.45, longitude: -70.67))
    let layout = try TerrainCoverageLayout(origin: origin, radiusKm: 20, side: 9)
    let store = PropagationStore()
    store.setTerrainOrigin(origin); store.txHeight = "10"; store.rxHeight = "2"
    let report = TerrainCoverageReport(layout: layout,
        input: TerrainITMInput(frequencyMHz: 144, txHeightMeters: 10, rxHeightMeters: 2), thresholdDBm: -110,
        cells: Array(repeating: nil, count: 81), missingTerrainCells: 0, modelErrorCells: 0, mosaic: TerrainDEMMosaic(zoom: 10, tiles: [:]))
    store.terrainCoverageReport = report; store.terrainCoverageOriginElevationMeters = 3000
    store.setTerrainTarget(try #require(origin.destination(km: 10, bearing: 90)))
    #expect(store.terrainCoverageReport?.id == report.id)
    #expect(store.terrainHorizon == RadioLinkBudget.horizonKm(txHeight: 10, rxHeight: 2))
    store.txHeight = "20"
    #expect(store.terrainCoverageReport == nil)
    #expect(!store.terrainMapShowingHorizon)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["RADIO_TERRAIN_BENCHMARK"] == "1"))
func terrainRealSantiagoBenchmark() async throws {
    let origin = try #require(RadioLocation(latitude: -33.4372, longitude: -70.6506))
    let layout = try TerrainCoverageLayout(origin: origin, radiusKm: 60, side: 129)
    let directory = URL(fileURLWithPath: "/private/tmp/radioworkbench-terrain-benchmark")
    let start = Date()
    let mosaic = try await TerrainDEMService(cacheURL: directory.appendingPathComponent("tiles")).load(keys: layout.suitableTileKeys)
    #expect(mosaic.missingTiles == 0)
    let report = try await TerrainCoverageCalculator.calculate(layout: layout,
        input: TerrainITMInput(frequencyMHz: 144.39, txHeightMeters: 10, rxHeightMeters: 2), thresholdDBm: -110,
        mosaic: mosaic, native: TerrainITMNative())
    #expect(report.modeledCount > 10_000)
    #expect(report.missingTerrainCells == 0)
    struct Export: Encodable {
        let origin: RadioLocation, side: Int, radiusKm: Double, cellSpacingMeters: Double, demSpacingMeters: Double
        let covered: Int, modeled: Int, warnings: Int, seconds: Double
        let positions: [RadioLocation], cells: [TerrainCoverageCell?]
    }
    let export = Export(origin: origin, side: layout.side, radiusKm: layout.radiusKm, cellSpacingMeters: layout.spacingMeters,
        demSpacingMeters: mosaic.resolutionMeters(at: origin), covered: report.coveredCount, modeled: report.modeledCount,
        warnings: report.warnedCount, seconds: Date().timeIntervalSince(start),
        positions: report.cells.indices.map { layout.location(row: $0 / layout.side, column: $0 % layout.side)! }, cells: report.cells)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try JSONEncoder().encode(export).write(to: directory.appendingPathComponent("santiago-coverage.json"))
    print("Santiago DEM: \(mosaic.tiles.count) teselas; \(report.coveredCount)/\(report.modeledCount) celdas; \(export.seconds) s")
}
