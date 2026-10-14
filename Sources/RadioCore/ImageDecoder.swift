import Foundation

final class ImageDecoder {
    private var analytic: AnalyticAudio
    private var sstvBand: SSTVAudioBand?
    private var headerTones: SSTVHeaderTones?
    private var sstv: SSTVDecoder?
    private var sstvVideo: SSTVVideoDemodulator?
    private var lineSync: SSTVLineSync?
    private var carrier: SSTVCarrierEstimator?
    private var generation = 0, processedSamples = 0
    private let sampleRate: Double, threshold: Double
    private var fax: WEFAXDecoder?
    private var apt: APTDecoder?
    private let frequencyOffset: Double
    init(mode: RadioMode, sampleRate: Double, settings: DecoderSettings) {
        self.sampleRate = sampleRate; threshold = settings.threshold
        analytic = AnalyticAudio(sampleRate: sampleRate)
        sstvBand = mode == .sstv ? SSTVAudioBand(sampleRate: sampleRate, center: settings.frequency) : nil
        headerTones = mode == .sstv ? SSTVHeaderTones(sampleRate: sampleRate, center: settings.frequency) : nil
        sstvVideo = mode == .sstv ? SSTVVideoDemodulator(sampleRate: sampleRate, center: settings.frequency, reduction: settings.sstvNoiseReduction) : nil
        carrier = mode == .sstv && settings.sstvAutoCalibrate ? SSTVCarrierEstimator(sampleRate: sampleRate, center: settings.frequency) : nil
        frequencyOffset = mode == .satelliteAPT ? 0 : 1900 - settings.frequency
        switch mode {
        case .sstv: sstv = SSTVDecoder(sampleRate: sampleRate, settings: settings)
        case .wefax: fax = WEFAXDecoder(settings: settings)
        case .satelliteAPT: apt = APTDecoder(sampleRate: sampleRate, settings: settings)
        default: break
        }
    }
    func process(_ samples: [Float]) {
        for sample in samples {
            let filtered = sstvBand?.push(sample) ?? sample
            if let header = headerTones?.push(filtered) { sstv?.observeHeader(frequency: header.frequency, amplitude: header.amplitude, time: header.time) }
            if let sstv {
                if let frequency = carrier?.push(filtered, measuring: sstv.measuringLeader, threshold: threshold) { sstv.observeCarrier(frequency + frequencyOffset) }
                if sstv.rasterGeneration != generation, let tone = sstv.syncTone {
                    generation = sstv.rasterGeneration
                    lineSync = SSTVLineSync(sampleRate: sampleRate, tone: tone, timeOffset: Double(processedSamples) / sampleRate)
                }
                if let pulse = lineSync?.push(filtered, threshold: threshold) { sstv.observeSync(center: pulse.center, duration: pulse.duration) }
                if let value = sstvVideo?.push(filtered) { sstv.push(frequency: value.frequency + frequencyOffset, amplitude: value.amplitude, time: value.time) }
                processedSamples += 1; continue
            }
            guard let value = analytic.push(filtered) else { continue }
            fax?.push(frequency: value.frequency + frequencyOffset, amplitude: value.amplitude, time: value.time)
            apt?.push(amplitude: value.amplitude)
        }
    }
    func finish() { fax?.finish() }
    var image: RadioImage? { sstv?.image ?? fax?.image ?? apt?.image }
    var status: String { sstv?.status ?? fax?.status ?? apt?.status ?? "" }
    var calibration: SSTVCalibration? { sstv?.calibration }
}
