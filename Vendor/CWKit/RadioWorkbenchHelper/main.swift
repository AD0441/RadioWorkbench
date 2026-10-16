import Foundation
import CWKit
struct Output: Encodable {
    let text: String, tentative: String
    let toneHz: Double, wpm: Double, snrDB: Double
}
let args = CommandLine.arguments
let neural = args.contains("neural")
let modelURL = args.firstIndex(of: "--model").flatMap { $0 + 1 < args.count ? URL(fileURLWithPath: args[$0+1]) : nil }
let complete = DispatchSemaphore(value: 0)
do {
    let model = neural ? try CWNetModel(modelURL: modelURL) : nil
    let runner = PipelineRunner(settings: PipelineSettings(autoTune: true, decoder: neural ? .neural : .classic), neuralModel: model) { event in
        let output: PipelineOutput
        switch event { case .output(let value), .finished(let value): output = value }
        let record = Output(text: output.text, tentative: output.tentativeText, toneHz: output.toneFrequency, wpm: output.wpm, snrDB: output.snrDB)
        if let data = try? JSONEncoder().encode(record) { FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data([10])) }
        if case .finished = event { complete.signal() }
    }
    // fread fills a bounded block; callbacks never enqueue an unbounded audio backlog.
    var samples = [Float](repeating: 0, count: 960)
    while true {
        let n = samples.withUnsafeMutableBytes { fread($0.baseAddress, 4, 960, stdin) }
        if n == 0 { break }
        runner.submitAndWait(Array(samples.prefix(n)).map { $0.isFinite ? $0 : 0 }, sampleRate: 12000)
    }
    runner.finish()
    if complete.wait(timeout: .now() + 20) != .success { exit(3) }
} catch {
    FileHandle.standardError.write(Data(error.localizedDescription.utf8)); exit(2)
}
