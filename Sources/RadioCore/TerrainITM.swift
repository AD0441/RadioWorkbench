import Foundation

public enum ITMClimate: Int, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case equatorial = 1, continentalSubtropical, maritimeSubtropical, desert, continentalTemperate, maritimeTemperateLand, maritimeTemperateSea
    public var id: Int { rawValue }
    public var title: String {
        switch self {
        case .equatorial: "Ecuatorial"
        case .continentalSubtropical: "Subtropical continental"
        case .maritimeSubtropical: "Subtropical marítimo"
        case .desert: "Desértico"
        case .continentalTemperate: "Templado continental"
        case .maritimeTemperateLand: "Templado marítimo · tierra"
        case .maritimeTemperateSea: "Templado marítimo · mar"
        }
    }
}

public struct TerrainITMInput: Sendable, Equatable {
    public let frequencyMHz: Double
    public let txHeightMeters: Double
    public let rxHeightMeters: Double
    public let climate: ITMClimate
    public let refractivityN0: Double
    public let verticalPolarization: Bool
    public let relativePermittivity: Double
    public let conductivity: Double
    public let confidencePercent: Double
    public let reliabilityPercent: Double
    public let transmitWatts: Double
    public let txGainDBi: Double
    public let rxGainDBi: Double

    public init(frequencyMHz: Double, txHeightMeters: Double, rxHeightMeters: Double, climate: ITMClimate = .continentalTemperate,
                refractivityN0: Double = 301, verticalPolarization: Bool = true, relativePermittivity: Double = 15,
                conductivity: Double = 0.005, confidencePercent: Double = 50, reliabilityPercent: Double = 50,
                transmitWatts: Double = 10, txGainDBi: Double = 0, rxGainDBi: Double = 0) {
        self.frequencyMHz = frequencyMHz; self.txHeightMeters = txHeightMeters; self.rxHeightMeters = rxHeightMeters
        self.climate = climate; self.refractivityN0 = refractivityN0; self.verticalPolarization = verticalPolarization
        self.relativePermittivity = relativePermittivity; self.conductivity = conductivity
        self.confidencePercent = confidencePercent; self.reliabilityPercent = reliabilityPercent
        self.transmitWatts = transmitWatts; self.txGainDBi = txGainDBi; self.rxGainDBi = rxGainDBi
    }

    public var isValid: Bool {
        let values = [frequencyMHz, txHeightMeters, rxHeightMeters, refractivityN0, relativePermittivity,
                      conductivity, confidencePercent, reliabilityPercent, transmitWatts, txGainDBi, rxGainDBi]
        return values.allSatisfy(\.isFinite) && (20...20_000).contains(frequencyMHz)
            && (0.5...3_000).contains(txHeightMeters) && (0.5...3_000).contains(rxHeightMeters)
            && (150...400).contains(refractivityN0) && (1...100).contains(relativePermittivity)
            && (0.0001...10).contains(conductivity) && (1...99).contains(confidencePercent)
            && (1...99).contains(reliabilityPercent) && (0.001...1_000_000).contains(transmitWatts)
            && (-40...60).contains(txGainDBi) && (-40...60).contains(rxGainDBi)
    }
}

public struct TerrainITMResult: Codable, Sendable, Equatable {
    public let basicTransmissionLossDB: Double
    public let receivedPowerDBm: Double
    public let terrainIrregularityMeters: Double
    public let distanceKm: Double
    public let warningFlags: Int
    public let propagationMode: String
}

public enum TerrainITMError: LocalizedError {
    case invalidInput, helperUnavailable, invalidOutput
    public var errorDescription: String? {
        switch self {
        case .invalidInput: "Revisa frecuencia, alturas, potencia, clima y perfil de terreno para ITM."
        case .helperUnavailable: "No se encontró el motor ITM incluido con la app."
        case .invalidOutput: "El motor ITM no pudo calcular una pérdida válida para este perfil."
        }
    }
}

public actor TerrainITMEngine {
    private let helperURL: URL?
    public init(helperURL: URL? = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("itm-helper")) {
        self.helperURL = helperURL
    }

    public func predict(input: TerrainITMInput, profile: TerrainProfile) throws -> TerrainITMResult {
        guard input.isValid, profile.points.count >= 3, profile.points.count <= TerrainProfileGeometry.maximumPoints,
              profile.distanceKm.isFinite, (1...TerrainProfileGeometry.maximumDistanceKm).contains(profile.distanceKm),
              profile.elevationsMeters.allSatisfy({ $0.isFinite && (-12_000...12_000).contains($0) }) else { throw TerrainITMError.invalidInput }
        guard let helperURL, FileManager.default.isExecutableFile(atPath: helperURL.path) else { throw TerrainITMError.helperUnavailable }
        let inputText = ([
            input.frequencyMHz, input.txHeightMeters, input.rxHeightMeters, Double(input.climate.rawValue), input.refractivityN0,
            input.verticalPolarization ? 1.0 : 0.0, input.relativePermittivity, input.conductivity,
            input.confidencePercent, input.reliabilityPercent, input.transmitWatts, input.txGainDBi, input.rxGainDBi,
            Double(profile.points.count), profile.distanceKm * 1_000 / Double(profile.points.count - 1)
        ] + profile.elevationsMeters).map { String($0) }.joined(separator: " ") + "\n"
        let process = Process()
        process.executableURL = helperURL
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin; process.standardOutput = stdout; process.standardError = stderr
        do { try process.run() } catch { throw TerrainITMError.helperUnavailable }
        stdin.fileHandleForWriting.write(Data(inputText.utf8))
        try? stdin.fileHandleForWriting.close()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let result = try? JSONDecoder().decode(TerrainITMResult.self, from: output),
              result.basicTransmissionLossDB.isFinite, (0...300).contains(result.basicTransmissionLossDB),
              result.receivedPowerDBm.isFinite, (-300...200).contains(result.receivedPowerDBm),
              result.distanceKm.isFinite, (1...TerrainProfileGeometry.maximumDistanceKm).contains(result.distanceKm) else { throw TerrainITMError.invalidOutput }
        return result
    }
}
