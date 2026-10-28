import Foundation

public struct HFPropagationInput: Sendable, Equatable {
    public let origin: RadioLocation
    public let target: RadioLocation
    public let date: Date
    public let r12: Double
    public let watts: Double
    public let bandwidth: Double
    public let requiredSNR: Double
    public let txGain: Double
    public let rxGain: Double
    public let noise: Int
    public let frequencyMHz: Double
    public init(origin: RadioLocation, target: RadioLocation, date: Date, r12: Double, watts: Double, bandwidth: Double, requiredSNR: Double, txGain: Double, rxGain: Double, noise: Int, frequencyMHz: Double) {
        self.origin = origin; self.target = target; self.date = date; self.r12 = r12; self.watts = watts
        self.bandwidth = bandwidth; self.requiredSNR = requiredSNR; self.txGain = txGain; self.rxGain = rxGain
        self.noise = noise; self.frequencyMHz = frequencyMHz
    }
    public func reversed(watts: Double, bandwidth: Double, requiredSNR: Double, txGain: Double, rxGain: Double, noise: Int) -> HFPropagationInput? {
        let result = HFPropagationInput(origin: target, target: origin, date: date, r12: r12,
            watts: watts, bandwidth: bandwidth, requiredSNR: requiredSNR, txGain: txGain, rxGain: rxGain,
            noise: noise, frequencyMHz: frequencyMHz)
        return result.isValid ? result : nil
    }
    public var isValid: Bool {
        let values = [r12, watts, bandwidth, requiredSNR, txGain, rxGain, frequencyMHz]
        return values.allSatisfy(\.isFinite) && (0...311).contains(r12) && (1...1_000_000).contains(watts)
            && (1...100_000).contains(bandwidth) && (-30...100).contains(requiredSNR)
            && (-40...40).contains(txGain) && (-40...40).contains(rxGain) && (0...3).contains(noise)
            && (1.6...30).contains(frequencyMHz) && origin.distance(to: target) >= 10
    }
}
public struct HFPathPrediction: Decodable, Sendable, Identifiable {
    public let id: Int
    public let hour: Int
    public let frequencyMHz: Double
    public let distanceKm: Double
    public let snrDB: Double?
    public let reliability: Double?
    public let muf50MHz: Double?
    public let receivedDBm: Double?
    public let noiseFactorDB: Double?
    public let atmosphericNoiseDB: Double?
    public let manMadeNoiseDB: Double?
    public let galacticNoiseDB: Double?
    public var isValid: Bool {
        (0..<600).contains(id) && (0...23).contains(hour) && (1.6...30).contains(frequencyMHz)
            && distanceKm.isFinite && (0...40_100).contains(distanceKm)
            && [snrDB, reliability, muf50MHz, receivedDBm, noiseFactorDB, atmosphericNoiseDB, manMadeNoiseDB, galacticNoiseDB].compactMap { $0 }.allSatisfy(\.isFinite)
            && (reliability.map { (-0.01...100.01).contains($0) } ?? true)
    }
}
public struct HFPropagationReport: Sendable {
    public let input: HFPropagationInput
    public let computedAt: Date
    public let predictions: [HFPathPrediction]
    public var hourUTC: Int {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c.component(.hour, from: input.date)
    }
    public var bands: [HFPathPrediction] { predictions.filter { $0.id < 240 && $0.hour == hourUTC } }
    public var hourly: [HFPathPrediction] { predictions.filter { (240..<264).contains($0.id) } }
    public var reach: [HFPathPrediction] { predictions.filter { $0.id >= 264 && abs($0.frequencyMHz-input.frequencyMHz) < 0.001 } }
    public func contactSamples(frequencyMHz: Double, category: RadioContactDistance) -> [HFPathPrediction] {
        predictions.filter { $0.id >= 264 && abs($0.frequencyMHz-frequencyMHz) < 0.001 && RadioContactDistance.classify(km: $0.distanceKm) == category }
    }
}

private final class HFCalculationProcess: @unchecked Sendable {
    // The owned Process and cancellation flag are accessed only under this lock.
    private let lock = NSLock()
    private let process = Process()
    private var cancelled = false
    func cancel() {
        lock.withLock {
            cancelled = true
            if process.isRunning { process.terminate() }
        }
    }
    func run(executable: URL, dataDirectory: URL, input: String) throws -> Data {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("radio-p533-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let inputURL = folder.appendingPathComponent("input.txt")
        try Data(input.utf8).write(to: inputURL)
        let handle = try FileHandle(forReadingFrom: inputURL)
        defer { try? handle.close() }
        let output = Pipe(), errors = Pipe()
        try lock.withLock {
            if cancelled { throw CancellationError() }
            process.executableURL = executable; process.arguments = [dataDirectory.path]
            process.standardInput = handle; process.standardOutput = output; process.standardError = errors
            try process.run()
        }
        let timeout = DispatchWorkItem { [weak self] in self?.cancel() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: timeout)
        defer { timeout.cancel() }
        var bytes = Data()
        while let chunk = try output.fileHandleForReading.read(upToCount: 8192), !chunk.isEmpty {
            bytes.append(chunk)
            if bytes.count > 1_000_000 { cancel(); throw URLError(.dataLengthExceedsMaximum) }
        }
        process.waitUntilExit()
        let diagnostic = String(decoding: errors.fileHandleForReading.readDataToEndOfFile().prefix(4096), as: UTF8.self)
        if lock.withLock({ cancelled }) { throw CancellationError() }
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "P533", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: diagnostic.isEmpty ? "El motor P.533 no pudo completar el cálculo. Comprueba sus datos." : diagnostic])
        }
        return bytes
    }
}

public actor HFPropagationEngine {
    private let executableURL: URL?
    private let dataDirectory: URL?
    public init(executableURL: URL? = nil, dataDirectory: URL? = nil) {
        self.executableURL = executableURL ?? ProcessInfo.processInfo.environment["PROPAGATION_HELPER_PATH"].map { URL(fileURLWithPath: $0) } ?? Bundle.main.url(forAuxiliaryExecutable: "propagation-helper")
        self.dataDirectory = dataDirectory ?? ProcessInfo.processInfo.environment["PROPAGATION_DATA_PATH"].map { URL(fileURLWithPath: $0) } ?? Bundle.main.resourceURL?.appendingPathComponent("Propagation")
    }
    public func predict(_ input: HFPropagationInput) async throws -> HFPropagationReport {
        guard input.isValid else { throw URLError(.badURL) }
        guard let executableURL, let dataDirectory, dataDirectory.path.utf8.count <= 200,
              FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw NSError(domain: "P533", code: 1, userInfo: [NSLocalizedDescriptionKey: "No se encuentra el motor P.533 incluido en la app."])
        }
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!
        let year = c.component(.year, from: input.date), month = c.component(.month, from: input.date), hour = c.component(.hour, from: input.date)
        guard (1900...2100).contains(year) else { throw URLError(.badURL) }
        let fields = [String(year), String(month), String(Int(input.r12.rounded())), String(input.origin.latitude), String(input.origin.longitude), String(input.watts), String(input.bandwidth), String(input.requiredSNR), String(input.txGain), String(input.rxGain), String(input.noise)]
        var lines = [fields.joined(separator: " ")], id = 0
        func add(hour: Int, location: RadioLocation, frequency: Double) {
            lines.append("\(id) \(hour) \(location.latitude) \(location.longitude) \(frequency)"); id += 1
        }
        for h in 0..<24 { for band in HFBand.all { add(hour: h, location: input.target, frequency: band.frequencyMHz) } }
        for h in 0..<24 { add(hour: h, location: input.target, frequency: input.frequencyMHz) }
        // Sample the chosen bearing, retaining skip-zone gaps rather than inventing one circular range.
        let bearing = input.origin.bearing(to: input.target)
        var frequencies = HFBand.all.map(\.frequencyMHz)
        if !frequencies.contains(where: { abs($0-input.frequencyMHz) < 0.001 }) { frequencies.append(input.frequencyMHz) }
        for frequency in frequencies {
            for km in [100.0, 250, 500, 750, 1000, 1500, 2000, 3000, 4000, 6000, 8000, 10000, 12000, 15000, 18000] {
                if let location = input.origin.destination(km: km, bearing: bearing) { add(hour: hour, location: location, frequency: frequency) }
            }
        }
        let text = lines.joined(separator: "\n") + "\n", runner = HFCalculationProcess()
        let data: Data = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do { continuation.resume(returning: try runner.run(executable: executableURL, dataDirectory: dataDirectory, input: text)) }
                    catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { runner.cancel() }
        try Task.checkCancellation()
        let results = try data.split(separator: 10).map { try JSONDecoder().decode(HFPathPrediction.self, from: Data($0)) }
        guard results.count == id, Set(results.map(\.id)).count == id, results.allSatisfy(\.isValid) else { throw URLError(.cannotParseResponse) }
        return HFPropagationReport(input: input, computedAt: Date(), predictions: results)
    }
}
