import Foundation
import ImageIO
import CoreGraphics

public enum TerrainMercator {
    public static let circumferenceMeters = 2 * Double.pi * 6_378_137
    public static func point(_ location: RadioLocation) -> (x: Double, y: Double) {
        ((location.longitude + 180) / 360, (1 - asinh(tan(location.latitude * .pi / 180)) / .pi) / 2)
    }
    public static func location(x: Double, y: Double) -> RadioLocation? {
        guard x.isFinite, y.isFinite, (0...1).contains(y) else { return nil }
        let wrappedX = x - floor(x)
        return RadioLocation(latitude: atan(sinh(.pi * (1 - 2 * y))) * 180 / .pi, longitude: wrappedX * 360 - 180)
    }
}

public struct TerrainTileKey: Hashable, Codable, Sendable {
    public let zoom: Int
    public let x: Int
    public let y: Int
    public init(zoom: Int, x: Int, y: Int) {
        self.zoom = zoom
        let n = 1 << zoom
        self.x = ((x % n) + n) % n; self.y = y
    }
    public var path: String { "\(zoom)/\(x)/\(y).png" }
}

public enum TerrainDEMError: LocalizedError {
    case invalidTile, unsupportedArea, missingOrigin
    public var errorDescription: String? {
        switch self {
        case .invalidTile: "La tesela DEM no contiene alturas Terrarium válidas."
        case .unsupportedArea: "El área DEM debe estar entre 5 y 200 km y dentro de latitudes ±80°."
        case .missingOrigin: "Falta relieve en el origen. No se asumirá terreno plano para sustituirlo."
        }
    }
}

public struct TerrainElevationTile: Sendable {
    public let key: TerrainTileKey
    public let elevations: [Float]
    public init(key: TerrainTileKey, elevations: [Float]) throws {
        guard elevations.count == 256 * 256 else { throw TerrainDEMError.invalidTile }
        self.key = key; self.elevations = elevations
    }
    public static func elevation(red: UInt8, green: UInt8, blue: UInt8) -> Float {
        Float(red) * 256 + Float(green) + Float(blue) / 256 - 32_768
    }
    public static func decode(_ data: Data, key: TerrainTileKey) throws -> Self {
        guard data.count <= 2_000_000, let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) as String? == "public.png",
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue == 256,
              (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue == 256,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil), image.bitsPerComponent == 8,
              [24, 32].contains(image.bitsPerPixel), let provider = image.dataProvider, let bytes = provider.data else {
            throw TerrainDEMError.invalidTile
        }
        let components = image.bitsPerPixel / 8, stride = image.bytesPerRow
        guard CFDataGetLength(bytes) >= stride * 256, let pointer = CFDataGetBytePtr(bytes) else { throw TerrainDEMError.invalidTile }
        let alphaFirst = [CGImageAlphaInfo.first, .premultipliedFirst, .noneSkipFirst].contains(image.alphaInfo)
        let little = image.bitmapInfo.contains(.byteOrder32Little)
        let offsets: [Int]
        if components == 3 { offsets = [0, 1, 2] }
        else if little { offsets = alphaFirst ? [2, 1, 0] : [3, 2, 1] }
        else { offsets = alphaFirst ? [1, 2, 3] : [0, 1, 2] }
        var heights = [Float](repeating: .nan, count: 256 * 256)
        for row in 0..<256 {
            for column in 0..<256 {
                let index = row * stride + column * components
                let h = elevation(red: pointer[index + offsets[0]], green: pointer[index + offsets[1]], blue: pointer[index + offsets[2]])
                if (-12_000...12_000).contains(h) { heights[row * 256 + column] = h }
            }
        }
        return try Self(key: key, elevations: heights)
    }
}

public struct TerrainDEMMosaic: Sendable {
    public let zoom: Int
    public let tiles: [TerrainTileKey: TerrainElevationTile]
    public let missingTiles: Int
    public let cachedTiles: Int
    public let fetchedAt: Date
    public init(zoom: Int, tiles: [TerrainTileKey: TerrainElevationTile], missingTiles: Int = 0, cachedTiles: Int = 0, fetchedAt: Date = Date()) {
        self.zoom = zoom; self.tiles = tiles; self.missingTiles = missingTiles; self.cachedTiles = cachedTiles; self.fetchedAt = fetchedAt
    }
    public func resolutionMeters(at location: RadioLocation) -> Double {
        TerrainMercator.circumferenceMeters * cos(location.latitude * .pi / 180) / Double((1 << zoom) * 256)
    }
    public func elevation(at location: RadioLocation) -> Double? {
        let p = TerrainMercator.point(location), worldPixels = (1 << zoom) * 256
        let x = p.x * Double(worldPixels) - 0.5, y = p.y * Double(worldPixels) - 0.5
        let ix = Int(floor(x)), iy = Int(floor(y)), fx = x - floor(x), fy = y - floor(y)
        func pixel(_ col: Int, _ row: Int) -> Double? {
            guard row >= 0, row < worldPixels else { return nil }
            let col = ((col % worldPixels) + worldPixels) % worldPixels
            let key = TerrainTileKey(zoom: zoom, x: col / 256, y: row / 256)
            guard let tile = tiles[key] else { return nil }
            let value = Double(tile.elevations[(row % 256) * 256 + col % 256])
            return value.isFinite ? value : nil
        }
        guard let a = pixel(ix, iy), let b = pixel(ix + 1, iy), let c = pixel(ix, iy + 1), let d = pixel(ix + 1, iy + 1) else { return nil }
        return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy
    }
    public func profile(from origin: RadioLocation, to target: RadioLocation) throws -> TerrainProfile {
        let km = origin.distance(to: target)
        guard km >= 1 else { throw TerrainProfileError.pathTooShort }
        guard km <= 500 else { throw TerrainProfileError.pathTooLong }
        let spacing = max(90, resolutionMeters(at: origin), resolutionMeters(at: target))
        let count = min(4097, max(3, Int(ceil(km * 1_000 / spacing)) + 1))
        let bearing = origin.bearing(to: target)
        var points: [TerrainPoint] = []; points.reserveCapacity(count)
        for index in 0..<count {
            guard let location = index == count - 1 ? target : origin.destination(km: km * Double(index) / Double(count - 1), bearing: bearing),
                  let elevation = elevation(at: location) else { throw TerrainDEMError.invalidTile }
            // Bathymetry is not an RF reflecting surface: use sea level for negative DEM samples.
            points.append(TerrainPoint(location: location, elevationMeters: max(0, elevation)))
        }
        return TerrainProfile(origin: origin, target: target, points: points, fetchedAt: fetchedAt,
                              resolutionMeters: km * 1_000 / Double(count - 1))
    }
}

public actor TerrainDEMService {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    public static let endpoint = URL(string: "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/")!
    private let cacheURL: URL
    private let transport: Transport
    public init(cacheURL: URL? = nil, transport: @escaping Transport = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }) {
        self.cacheURL = cacheURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RadioWorkbench/terrain-tiles")
        self.transport = transport
    }
    /// Select a narrow tiled corridor for an exact link, including bilinear interpolation neighbors.
    /// The sparse locations select tiles only; the actual ITM profile uses the DEM pixel spacing.
    public static func profileTileKeys(from origin: RadioLocation, to target: RadioLocation) throws -> [TerrainTileKey] {
        let locations = try TerrainProfileGeometry.sampleLocations(from: origin, to: target)
        guard locations.allSatisfy({ abs($0.latitude) <= 80 }) else { throw TerrainDEMError.unsupportedArea }
        func keys(at zoom: Int) -> [TerrainTileKey] {
            let n = 1 << zoom
            var tiles: Set<TerrainTileKey> = []
            for location in locations {
                let point = TerrainMercator.point(location)
                let x = Int(floor(point.x * Double(n))), y = Int(floor(point.y * Double(n)))
                for row in max(0, y - 1)...min(n - 1, y + 1) {
                    for column in (x - 1)...(x + 1) { tiles.insert(TerrainTileKey(zoom: zoom, x: column, y: row)) }
                }
            }
            return tiles.sorted { $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y }
        }
        var zoom = origin.distance(to: target) <= 50 ? 11 : 10
        var selected = keys(at: zoom)
        while zoom > 7 && selected.count > 128 { zoom -= 1; selected = keys(at: zoom) }
        return selected
    }
    public func profile(from origin: RadioLocation, to target: RadioLocation) async throws -> TerrainProfile {
        let keys = try Self.profileTileKeys(from: origin, to: target)
        let mosaic = try await load(keys: keys)
        return try mosaic.profile(from: origin, to: target)
    }
    public func load(keys: [TerrainTileKey], progress: @escaping @Sendable (Int, Int) async -> Void = { _, _ in }) async throws -> TerrainDEMMosaic {
        guard let zoom = keys.first?.zoom, (0...15).contains(zoom), keys.count <= 512,
              keys.allSatisfy({ $0.zoom == zoom && (0..<(1 << zoom)).contains($0.y) }) else { throw TerrainDEMError.unsupportedArea }
        var tiles: [TerrainTileKey: TerrainElevationTile] = [:], cached = 0, missing = 0
        for start in stride(from: 0, to: keys.count, by: 4) {
            try Task.checkCancellation()
            let batch = Array(keys[start..<min(start + 4, keys.count)])
            let loader = transport, directory = cacheURL
            await withTaskGroup(of: (TerrainTileKey, TerrainElevationTile?, Bool).self) { group in
                for key in batch {
                    group.addTask {
                        let file = directory.appendingPathComponent(key.path)
                        if let data = try? Data(contentsOf: file), let tile = try? TerrainElevationTile.decode(data, key: key) { return (key, tile, true) }
                        do {
                            try Task.checkCancellation()
                            let url = Self.endpoint.appendingPathComponent(key.path)
                            var request = URLRequest(url: url, timeoutInterval: 20)
                            request.setValue("RadioWorkbench/0.8.10 (optional terrain coverage)", forHTTPHeaderField: "User-Agent")
                            let (data, response) = try await loader(request)
                            guard response.statusCode == 200, response.url?.host == Self.endpoint.host,
                                  response.url?.scheme == "https", data.count <= 2_000_000 else { throw TerrainDEMError.invalidTile }
                            let tile = try TerrainElevationTile.decode(data, key: key)
                            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                            try? data.write(to: file, options: .atomic)
                            return (key, tile, false)
                        } catch { return (key, nil, false) }
                    }
                }
                for await (key, tile, wasCached) in group {
                    if let tile { tiles[key] = tile; if wasCached { cached += 1 } }
                    else { missing += 1 }
                }
            }
            try Task.checkCancellation()
            await progress(min(start + 4, keys.count), keys.count)
        }
        trimCache(protecting: Set(keys.map { cacheURL.appendingPathComponent($0.path) }))
        return TerrainDEMMosaic(zoom: zoom, tiles: tiles, missingTiles: missing, cachedTiles: cached)
    }
    private func trimCache(protecting activeFiles: Set<URL>) {
        let fields: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(at: cacheURL, includingPropertiesForKeys: fields) else { return }
        var entries: [(URL, Int, Date)] = [], total = 0
        for case let file as URL in enumerator where file.pathExtension == "png" {
            guard let info = try? file.resourceValues(forKeys: Set(fields)), let size = info.fileSize else { continue }
            total += size; entries.append((file, size, info.contentModificationDate ?? .distantPast))
        }
        for (file, size, _) in entries.sorted(by: { $0.2 < $1.2 }) where total > 256 * 1_024 * 1_024 && !activeFiles.contains(file) {
            if (try? FileManager.default.removeItem(at: file)) != nil { total -= size }
        }
    }
}
