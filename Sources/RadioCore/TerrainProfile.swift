import Foundation

public struct TerrainPoint: Codable, Hashable, Sendable {
    public let location: RadioLocation
    public let elevationMeters: Double
    public init(location: RadioLocation, elevationMeters: Double) {
        self.location = location
        self.elevationMeters = elevationMeters
    }
}

public struct TerrainProfile: Codable, Sendable {
    public let origin: RadioLocation
    public let target: RadioLocation
    public let distanceKm: Double
    public let points: [TerrainPoint]
    public let fetchedAt: Date
    public let resolutionMeters: Double

    public init(origin: RadioLocation, target: RadioLocation, points: [TerrainPoint], fetchedAt: Date, resolutionMeters: Double) {
        self.origin = origin
        self.target = target
        self.distanceKm = origin.distance(to: target)
        self.points = points
        self.fetchedAt = fetchedAt
        self.resolutionMeters = resolutionMeters
    }

    public var elevationsMeters: [Double] { points.map(\.elevationMeters) }
    public var terrainReliefMeters: Double? {
        guard let low = elevationsMeters.min(), let high = elevationsMeters.max() else { return nil }
        return high - low
    }

    public func antennaAltitudeAMSL(aglMeters: Double, atOrigin: Bool) -> Double? {
        guard aglMeters.isFinite, let ground = (atOrigin ? points.first : points.last)?.elevationMeters else { return nil }
        return ground + aglMeters
    }
}

public enum TerrainProfileError: LocalizedError {
    case pathTooShort, pathTooLong, invalidCoordinates, invalidResponse
    public var errorDescription: String? {
        switch self {
        case .pathTooShort: "El perfil ITM requiere un enlace de al menos 1 km."
        case .pathTooLong: "El perfil de terreno está limitado a 500 km para esta consulta."
        case .invalidCoordinates: "Las coordenadas del perfil no son válidas."
        case .invalidResponse: "El servicio de elevación devolvió un perfil incompleto o inválido."
        }
    }
}

public enum TerrainProfileGeometry {
    public static let maximumDistanceKm = 500.0
    /// A 500 m route spacing better resolves ridges while staying within the ITM PFL limit.
    /// At long distances the point cap increases the effective spacing as needed.
    public static let spacingMeters = 500.0
    public static let maximumPoints = 501
    public static let maximumBatchSize = 100

    public static func sampleLocations(from origin: RadioLocation, to target: RadioLocation) throws -> [RadioLocation] {
        let distance = origin.distance(to: target)
        guard distance.isFinite, distance >= 1 else { throw TerrainProfileError.pathTooShort }
        guard distance <= maximumDistanceKm else { throw TerrainProfileError.pathTooLong }
        guard distance > 0 else { throw TerrainProfileError.invalidCoordinates }
        let count = min(maximumPoints, max(3, Int(ceil(distance * 1_000 / spacingMeters)) + 1))
        let bearing = origin.bearing(to: target)
        return (0..<count).compactMap { index in
            if index == 0 { return origin }
            if index == count - 1 { return target }
            return origin.destination(km: distance * Double(index) / Double(count - 1), bearing: bearing)
        }
    }
}

public enum TerrainLinkGeometry {
    /// Ground projection of the 60% first-Fresnel clearance corridor for a point-to-point path.
    /// This is a geometric aid; it is not a coverage probability or an RF propagation model.
    public static func firstFresnelCorridor(from origin: RadioLocation, to target: RadioLocation,
                                            frequencyMHz: Double, clearanceFraction: Double = 0.6,
                                            steps: Int = 32) -> [RadioLocation] {
        let distanceKm = origin.distance(to: target)
        guard distanceKm >= 1, distanceKm.isFinite, (20...20_000).contains(frequencyMHz),
              (0.1...1).contains(clearanceFraction), (4...128).contains(steps) else { return [] }
        let bearing = origin.bearing(to: target)
        let wavelengthMeters = 299.792458 / frequencyMHz
        let totalMeters = distanceKm * 1_000
        var left: [RadioLocation] = []
        var right: [RadioLocation] = []
        left.reserveCapacity(steps + 1); right.reserveCapacity(steps + 1)
        for index in 0...steps {
            let fraction = Double(index) / Double(steps)
            guard let center = origin.destination(km: distanceKm * fraction, bearing: bearing) else { return [] }
            let radiusMeters = sqrt(wavelengthMeters * totalMeters * fraction * (1 - fraction)) * clearanceFraction
            let radiusKm = radiusMeters / 1_000
            guard let leftPoint = center.destination(km: radiusKm, bearing: bearing - 90),
                  let rightPoint = center.destination(km: radiusKm, bearing: bearing + 90) else { return [] }
            left.append(leftPoint); right.append(rightPoint)
        }
        return left + Array(right.reversed())
    }
}

public struct TerrainLineOfSightResult: Sendable, Equatable {
    public let txAntennaAltitudeAMSL: Double
    public let rxAntennaAltitudeAMSL: Double
    public let rayAltitudeAMSL: [Double]
    public let apparentTerrainAltitudeAMSL: [Double]
    public let clearanceMeters: [Double]
    public let minimumClearanceMeters: Double
    public let minimumClearanceDistanceKm: Double
    public var isClear: Bool { minimumClearanceMeters >= 0 }
}

public enum TerrainLineOfSight {
    /// Evaluates the direct ray against the sampled terrain and k=4/3 effective-Earth curvature.
    /// Negative clearance indicates terrain crossing the direct path; ITM may still predict diffraction.
    public static func evaluate(profile: TerrainProfile, txHeightAGLMeters: Double,
                                rxHeightAGLMeters: Double, effectiveEarthFactor: Double = 4.0 / 3) -> TerrainLineOfSightResult? {
        let distanceMeters = profile.distanceKm * 1_000
        guard profile.points.count >= 3, distanceMeters.isFinite, distanceMeters > 0,
              txHeightAGLMeters.isFinite, rxHeightAGLMeters.isFinite,
              txHeightAGLMeters >= 0, rxHeightAGLMeters >= 0,
              effectiveEarthFactor.isFinite, effectiveEarthFactor > 0,
              let txAltitude = profile.antennaAltitudeAMSL(aglMeters: txHeightAGLMeters, atOrigin: true),
              let rxAltitude = profile.antennaAltitudeAMSL(aglMeters: rxHeightAGLMeters, atOrigin: false) else { return nil }
        let effectiveRadiusMeters = 6_371_000 * effectiveEarthFactor
        var rayAltitudes: [Double] = []
        var apparentTerrain: [Double] = []
        var clearances: [Double] = []
        rayAltitudes.reserveCapacity(profile.points.count)
        apparentTerrain.reserveCapacity(profile.points.count)
        clearances.reserveCapacity(profile.points.count)
        for (index, point) in profile.points.enumerated() {
            let distance = distanceMeters * Double(index) / Double(profile.points.count - 1)
            let fraction = distance / distanceMeters
            let rayAltitude = txAltitude + (rxAltitude - txAltitude) * fraction
            let curvatureBulge = distance * (distanceMeters - distance) / (2 * effectiveRadiusMeters)
            let apparentTerrainAltitude = point.elevationMeters + curvatureBulge
            rayAltitudes.append(rayAltitude)
            apparentTerrain.append(apparentTerrainAltitude)
            clearances.append(rayAltitude - apparentTerrainAltitude)
        }
        guard let minimum = clearances.enumerated().min(by: { $0.element < $1.element }) else { return nil }
        return TerrainLineOfSightResult(txAntennaAltitudeAMSL: txAltitude, rxAntennaAltitudeAMSL: rxAltitude,
                                        rayAltitudeAMSL: rayAltitudes, apparentTerrainAltitudeAMSL: apparentTerrain,
                                        clearanceMeters: clearances, minimumClearanceMeters: minimum.element,
                                        minimumClearanceDistanceKm: distanceMeters * Double(minimum.offset) / Double(profile.points.count - 1) / 1_000)
    }
}

public enum TerrainElevationParser {
    public static func parse(_ data: Data, locations: [RadioLocation], fetchedAt: Date = Date()) throws -> TerrainProfile {
        guard data.count <= 100_000, locations.count >= 3, locations.count <= TerrainProfileGeometry.maximumPoints else {
            throw TerrainProfileError.invalidResponse
        }
        struct Response: Decodable { let elevation: [Double] }
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              response.elevation.count == locations.count,
              response.elevation.allSatisfy({ $0.isFinite && (-12_000...12_000).contains($0) }) else {
            throw TerrainProfileError.invalidResponse
        }
        let points = zip(locations, response.elevation).map { TerrainPoint(location: $0.0, elevationMeters: $0.1) }
        return TerrainProfile(origin: locations[0], target: locations[locations.count - 1], points: points,
                              fetchedAt: fetchedAt, resolutionMeters: (locations[0].distance(to: locations[1])) * 1_000)
    }
}

public actor TerrainElevationService {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    public static let endpoint = URL(string: "https://api.open-meteo.com/v1/elevation")!
    private let transport: Transport

    public init(transport: @escaping Transport = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }) { self.transport = transport }

    public func download(from origin: RadioLocation, to target: RadioLocation, now: Date = Date()) async throws -> TerrainProfile {
        let locations = try TerrainProfileGeometry.sampleLocations(from: origin, to: target)
        var elevations: [Double] = []
        elevations.reserveCapacity(locations.count)
        for start in stride(from: 0, to: locations.count, by: TerrainProfileGeometry.maximumBatchSize) {
            let batch = Array(locations[start..<min(start + TerrainProfileGeometry.maximumBatchSize, locations.count)])
            var components = URLComponents(url: Self.endpoint, resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "latitude", value: batch.map { String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), $0.latitude) }.joined(separator: ",")),
                URLQueryItem(name: "longitude", value: batch.map { String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), $0.longitude) }.joined(separator: ","))
            ]
            var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            request.setValue("RadioWorkbench/0.8 (optional terrain profile)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await transport(request)
            guard response.statusCode == 200, response.url?.scheme == "https", response.url?.host == Self.endpoint.host,
                  data.count <= 100_000,
                  let decoded = try? JSONDecoder().decode(ElevationResponse.self, from: data), decoded.elevation.count == batch.count,
                  decoded.elevation.allSatisfy({ $0.isFinite && (-12_000...12_000).contains($0) }) else { throw TerrainProfileError.invalidResponse }
            elevations.append(contentsOf: decoded.elevation)
        }
        let data = try JSONEncoder().encode(ElevationResponse(elevation: elevations))
        return try TerrainElevationParser.parse(data, locations: locations, fetchedAt: now)
    }

    private struct ElevationResponse: Codable { let elevation: [Double] }
}
