import Foundation
import Darwin

/// Immutable library handle, retained throughout a calculation; calls only touch local C++ values.
public final class TerrainITMNative: @unchecked Sendable {
    private typealias Prediction = @convention(c) (UnsafePointer<Double>?, UnsafePointer<Double>?, Int32, Double, UnsafeMutablePointer<Double>?) -> Int32
    private let handle: UnsafeMutableRawPointer
    private let prediction: Prediction
    public init(libraryURL: URL? = nil) throws {
        let url = libraryURL ?? ProcessInfo.processInfo.environment["ITM_LIBRARY_PATH"].map { URL(fileURLWithPath: $0) }
            ?? Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("libitm.dylib")
        guard let url, let handle = dlopen(url.path, RTLD_NOW | RTLD_LOCAL) else { throw TerrainITMError.helperUnavailable }
        guard let symbol = dlsym(handle, "rw_itm_predict") else { dlclose(handle); throw TerrainITMError.helperUnavailable }
        self.handle = handle
        prediction = unsafeBitCast(symbol, to: Prediction.self)
    }
    deinit { dlclose(handle) }

    public func predict(input: TerrainITMInput, elevations: [Double], spacingMeters: Double) throws -> TerrainITMResult {
        let distance = spacingMeters * Double(elevations.count - 1) / 1_000
        guard input.isValid, (3...4097).contains(elevations.count), spacingMeters.isFinite, spacingMeters > 0,
              (1...500).contains(distance), elevations.allSatisfy({ $0.isFinite && (-12_000...12_000).contains($0) }) else {
            throw TerrainITMError.invalidInput
        }
        let parameters = [input.frequencyMHz, input.txHeightMeters, input.rxHeightMeters, Double(input.climate.rawValue),
            input.refractivityN0, input.verticalPolarization ? 1 : 0, input.relativePermittivity, input.conductivity,
            input.confidencePercent, input.reliabilityPercent, input.transmitWatts, input.txGainDBi, input.rxGainDBi, Double(input.variabilityMode)]
        var output = [Double](repeating: 0, count: 6)
        let status = parameters.withUnsafeBufferPointer { p in
            elevations.withUnsafeBufferPointer { heights in
                output.withUnsafeMutableBufferPointer { values in
                    prediction(p.baseAddress, heights.baseAddress, Int32(elevations.count), spacingMeters, values.baseAddress)
                }
            }
        }
        guard (status == 0 || status == 1), output.allSatisfy(\.isFinite), (0...300).contains(output[0]),
              (-300...200).contains(output[1]) else { throw TerrainITMError.invalidOutput }
        let mode = Int(output[5])
        return TerrainITMResult(basicTransmissionLossDB: output[0], receivedPowerDBm: output[1], terrainIrregularityMeters: output[2],
            distanceKm: output[3], warningFlags: Int(output[4]), propagationMode: mode == 1 ? "Visibilidad" : mode == 2 ? "Difracción" : mode == 3 ? "Dispersión troposférica" : "Sin clasificar")
    }
}
