import AppKit
import Observation
import RadioCore
import UniformTypeIdentifiers

@MainActor @Observable
final class ReceiverStore {
    var destination: WorkbenchDestination = .decoder(.morse)
    var isDecoderSelected: Bool { if case .decoder = destination { return true }; return false }
    var mode: RadioMode = .morse
    var settings = DecoderSettings()
    var text = ""
    var acarsMessages: [ACARSMessage] = []
    var selectedACARSMessage: UUID?
    var showsACARSSpectrum = false
    var frame: SpectrumFrame?
    var waterfall: CGImage?
    var busy = false
    var live = false
    var progress = 0.0
    var source = "Sin fuente"
    var detail = "Abre un archivo de audio o inicia la entrada del sistema."
    var error: String?
    var dropped: UInt64 = 0
    var lastURL: URL?
    var devices: [AudioInputDevice] = []
    var selectedDeviceID: UInt32 = 0
    var sourceChannelCount = 0
    var captureSampleRate = 0.0
    var samplesReceived: UInt64 = 0
    var availableChannelCount: Int {
        let deviceID = selectedDeviceID == 0 ? AudioInputDevices.defaultID() : selectedDeviceID
        return max(1, sourceChannelCount > 0 ? sourceChannelCount : devices.first(where: { $0.id == deviceID })?.channels ?? 1)
    }
    var selectedInput: AudioInputDevice? {
        let id = selectedDeviceID == 0 ? AudioInputDevices.defaultID() : selectedDeviceID
        return devices.first { $0.id == id }
    }
    var rfModulation: RFModulation = .usb
    var rfBandwidth = 2400.0
    var receivedImage: CGImage?
    var imageCaption = ""
    var showSSTVCatalog = false
    var sstvCatalogSearch = ""
    var inputProfiles = InputProfileLibrary()
    var selectedProfileID: UUID?
    var profileNotice = ""
    var showsProfileEditor = false
    var newProfileName = ""
    var sstvCalibration: SSTVCalibration?
    @ObservationIgnored private let worker = RadioWorker()
    @ObservationIgnored private let input = LiveAudioInput()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var session = UUID()
    @ObservationIgnored private var rows: [[Float]] = []
    @ObservationIgnored var microphoneDiagnosticStarted = false

    init() {
        refreshDevices()
        selectedDeviceID = devices.first(where: { $0.uid.lowercased().contains("vbcable") })?.id ?? 0
        input.configurationChanged = { [weak self] in
            guard let self, self.live else { return }
            self.stop(); self.refreshDevices()
            self.error = "La entrada cambió de formato o se desconectó. Revisa el dispositivo y pulsa Escuchar para reiniciar."
        }
        loadInputProfiles()
    }
    func refreshDevices() {
        devices = AudioInputDevices.list()
        if selectedDeviceID != 0 && !devices.contains(where: { $0.id == selectedDeviceID }) { selectedDeviceID = 0 }
    }
    func inputSelectionChanged() {
        sourceChannelCount = 0
        if case .channel(let index) = settings.audioChannel, index >= availableChannelCount { settings.audioChannel = .mix }
    }
    @discardableResult func prepareSSTVMicrophone() -> Bool {
        select(.sstv); refreshDevices()
        guard let microphone = devices.first(where: { $0.isBuiltIn }) else {
            error = "No se encontró el micrófono integrado. Selecciona otra entrada de audio."; return false
        }
        selectedDeviceID = microphone.id; sourceChannelCount = 0
        settings.audioChannel = .mix; settings.frequency = 1900; settings.threshold = 0.001
        settings.sstvFormat = .automatic; settings.imageAutoSync = true
        settings.imageStartSeconds = 0; settings.imageClockPPM = 0; settings.sstvColorRange = .bt601
        settings.sstvAutoCalibrate = true; settings.sstvNoiseReduction = .balanced
        source = microphone.name
        detail = "Micrófono listo. Pulsa Escuchar antes de reproducir la señal SSTV del celular."
        return true
    }

    func select(_ value: RadioMode) {
        destination = .decoder(value)
        let previous = mode
        stop(); mode = value; text = ""; rows = []; waterfall = nil; frame = nil; error = nil
        acarsMessages = []; selectedACARSMessage = nil
        progress = 0; dropped = 0
        source = lastURL?.lastPathComponent ?? "Sin fuente"
        detail = lastURL == nil
            ? "Abre un archivo de audio o inicia la entrada del sistema."
            : "Archivo de la sesión anterior disponible. Pulsa Volver a decodificar para analizarlo como \(value.title)."
        settings.frequency = value.receptionProfile.center
        if value == .selectiveTones { settings.threshold = 0.02 }
        else if previous == .selectiveTones { settings.threshold = 0.08 }
        rfModulation = value.receptionProfile.modulation; rfBandwidth = value.receptionProfile.rfBandwidth
        receivedImage = nil; imageCaption = ""
    }
    func openAudio() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]; panel.allowsMultipleSelection = false
        panel.message = "WAV, AIFF u otro formato que macOS pueda leer."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        decode(url)
    }
    func decode(_ url: URL) {
        stop(); text = ""; error = nil; rows = []; waterfall = nil; receivedImage = nil; imageCaption = ""
        acarsMessages = []; selectedACARSMessage = nil
        lastURL = url; source = url.lastPathComponent; progress = 0; busy = true
        let token = session, mode = mode, settings = settings
        task = Task {
            do {
                try await worker.decodeFile(url: url, mode: mode, settings: settings) { [weak self] value in
                    await self?.apply(value, token: token)
                }
            } catch is CancellationError { }
            catch { if session == token { self.error = error.localizedDescription; busy = false } }
        }
    }
    func startLive() {
        stop(); text = ""; error = nil; busy = true; live = true
        acarsMessages = []; selectedACARSMessage = nil
        sourceChannelCount = 0; captureSampleRate = 0; samplesReceived = 0; dropped = 0; progress = 0
        rows = []; waterfall = nil; frame = nil; receivedImage = nil; imageCaption = ""; sstvCalibration = nil
        let token = session, mode = mode, settings = settings, deviceID = selectedDeviceID
        let inputName: String
        if deviceID == 0 { inputName = "Entrada predeterminada" }
        else if let device = devices.first(where: { $0.id == deviceID }) { inputName = device.name }
        else { inputName = "Entrada de audio" }
        source = inputName; detail = "Preparando entrada y comprobando permiso de micrófono…"
        task = Task {
            do {
                let stream = try await input.start(deviceID: deviceID, channel: settings.audioChannel)
                guard session == token, !Task.isCancelled else { input.stop(); return }
                sourceChannelCount = stream.channels; captureSampleRate = stream.sampleRate
                detail = "Captura iniciada · \(Int(stream.sampleRate)) Hz · \(stream.channels) canal(es) · esperando audio"
                try await worker.decodeLive(ring: stream.ring, sampleRate: stream.sampleRate, mode: mode, settings: settings, source: inputName) { [weak self] value in
                    await self?.apply(value, token: token)
                }
            } catch is CancellationError { }
            catch { if session == token { self.error = error.localizedDescription; stop() } }
        }
    }
    func stop() {
        session = UUID(); task?.cancel(); task = nil; input.stop(); busy = false; live = false
    }
    private func apply(_ value: RadioUpdate, token: UUID) {
        guard session == token else { return }
        text = String(value.text.suffix(40000)); progress = value.progress; source = value.source
        if mode == .acars {
            acarsMessages = value.acarsMessages
            if selectedACARSMessage == nil || !acarsMessages.contains(where: { $0.id == selectedACARSMessage }) { selectedACARSMessage = acarsMessages.last?.id }
        }
        detail = value.detail; dropped = value.dropped; samplesReceived = value.samplesReceived
        sstvCalibration = value.sstvCalibration
        if let count = value.channelCount { sourceChannelCount = count }
        if let image = value.image {
            receivedImage = Self.rgbImage(image); imageCaption = image.caption
        }
        if let frame = value.frame {
            self.frame = frame
            let row = (0..<256).map { frame.bins[min(frame.bins.count - 1, $0 * frame.bins.count / 256)] }
            rows.insert(row, at: 0); if rows.count > 80 { rows.removeLast() }
            waterfall = Self.image(rows)
        }
        if value.finished { busy = false; live = false; task = nil }
    }
    func exportText() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.plainText]; panel.nameFieldStringValue = "\(mode.rawValue)-recepcion.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try text.write(to: url, atomically: true, encoding: .utf8) } catch { self.error = error.localizedDescription }
    }
    func exportImage() {
        guard let receivedImage else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.png]; panel.nameFieldStringValue = "\(mode.rawValue)-imagen.png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let bitmap = NSBitmapImageRep(cgImage: receivedImage)
            guard let data = bitmap.representation(using: .png, properties: [:]) else { throw RadioError.invalidAudio }
            try data.write(to: url, options: .atomic)
        } catch { self.error = error.localizedDescription }
    }
    func loadExample() {
        let name = switch mode {
        case .morse: "morse_8000_mono_clean"
        case .rtty, .bitAnalysis: "rtty_8000_mono_clean"
        case .psk31: "bpsk31_8000_mono_clean"
        case .navtex: "navtex_8000_mono_clean"
        case .acars: "acars_upstream_12000_mono"
        case .packet: "packet_8000_mono_clean"
        case .selectiveTones: "ctcss_8000_mono_100hz"
        case .sstv: sstvExampleName()
        case .wefax: "wefax_hf120_ioc576_8000_mono_manual"
        case .satelliteAPT: "noaa_apt_2400am_48000_mono_24lines"
        default: "dtmf_8000_mono_clean"
        }
        let url = Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "Examples")
        guard let url else { error = "No se encontró la grabación de ejemplo en el paquete."; return }
        if mode == .wefax { settings.imageStartSeconds = 0.5 }
        settings.audioChannel = .mix
        if mode == .navtex { settings.frequency = 1700; settings.inverted = false }
        if mode == .packet { settings.frequency = 1700 }
        if mode == .selectiveTones { settings.threshold = 0.02 }
        if mode == .sstv {
            settings.frequency = 1900; settings.imageAutoSync = true; settings.imageStartSeconds = 0
            settings.imageClockPPM = 0; settings.sstvColorRange = .bt601
        }
        decode(url)
    }
    func exportACARSJSON() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "acars_messages.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(acarsMessages).write(to: url, options: .atomic)
        } catch { self.error = error.localizedDescription }
    }
    private func sstvExampleName() -> String {
        let format = settings.sstvFormat == .automatic ? SSTVFormat.martinM1 : settings.sstvFormat
        var key = format.rawValue.lowercased().replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "-", with: "_")
        if format == .robot36 { key = "robot36" }
        if format == .robot72 { key = "robot72" }
        if format == .wraase180 { key = "wraasesc2_180" }
        if ["mp", "mr", "ml", "mc"].contains(where: { key.hasPrefix($0) }) { return "sstv_mmsstv_\(key)_8000_clean" }
        return "sstv_\(key)_8000_mono_clean"
    }
    private static func rgbImage(_ image: RadioImage) -> CGImage? {
        guard image.width > 0, image.height > 0, image.rgb.count == image.width * image.height * 3,
              let provider = CGDataProvider(data: Data(image.rgb) as CFData) else { return nil }
        return CGImage(width: image.width, height: image.height, bitsPerComponent: 8, bitsPerPixel: 24,
                       bytesPerRow: image.width * 3, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
    private static func image(_ rows: [[Float]]) -> CGImage? {
        var bytes = [UInt8](); bytes.reserveCapacity(rows.count * 256 * 4)
        for row in rows {
            for db in row {
                let value = min(1, max(0, (Double(db) + 80) / 70))
                bytes.append(UInt8(30 * value)); bytes.append(UInt8(190 * value)); bytes.append(UInt8(255 * value)); bytes.append(255)
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: 256, height: rows.count, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 1024,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
