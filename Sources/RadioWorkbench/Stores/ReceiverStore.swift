import AppKit
import AVFoundation
import Observation
import RadioCore
import UniformTypeIdentifiers

enum ReceiverInputSource: String, CaseIterable, Identifiable {
    case device = "Dispositivo de audio", tcp = "Audio TCP local"
    var id: String { rawValue }
}
@MainActor @Observable
final class ReceiverStore {
    let rigctl = RigctlStore()
    let signalWorkshop = SignalWorkshopStore()
    let satDumpOffline = SatDumpOfflineStore()
    let receptionLibrary = ReceptionLibraryStore()
    let receptionEvents = ReceptionEventStore()
    var inputSource: ReceiverInputSource = .device
    var networkPCM = NetworkPCMConfiguration()
    var networkNotice = ""
    @ObservationIgnored let tcpInput = TCPAudioInput()
    var destination: WorkbenchDestination = .decoder(.morse)
    var isDecoderSelected: Bool { if case .decoder = destination { return true }; return false }
    var mode: RadioMode = .morse
    var settings = DecoderSettings()
    var text = ""
    var acarsMessages: [ACARSMessage] = []
    var multimonRecords: [MultimonRecord] = []
    var engineRecords: [AudioEngineRecord] = []
    var voiceURL: URL?
    var voiceProtocol: DigitalVoiceProtocol?
    var voiceFinalizing = false
    var dmrStatus: DMRStatus?
    var voiceFrames: UInt64 = 0
    var voiceOutputDropped: UInt64 = 0
    @ObservationIgnored private var dmrVoiceMonitor: DMRVoiceMonitor?
    @ObservationIgnored private var voiceFinalization: Task<Void, Never>?
    var engineDownloading = false
    var engineNotice = ""
    @ObservationIgnored private var voicePlayer: AVAudioPlayer?
    var selectedACARSMessage: UUID?
    var showsACARSSpectrum = false
    let visualization = ReceiverVisualization()
    var frame: SpectrumFrame? { visualization.frame }
    var waterfall: CGImage? { visualization.waterfall }
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
        if inputSource == .tcp { return max(1, min(32, networkPCM.channels)) }
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
    @ObservationIgnored var microphoneDiagnosticStarted = false

    init() {
        refreshDevices()
        selectedDeviceID = devices.first(where: { $0.uid.lowercased().contains("vbcable") })?.id ?? 0
        input.configurationChanged = { [weak self] in
            guard let self, self.live, self.inputSource == .device else { return }
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
        inputSource = .device
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
        stop(); mode = value; text = ""; visualization.reset(); error = nil
        acarsMessages = []; selectedACARSMessage = nil
        multimonRecords = []; engineRecords = []; clearVoice()
        progress = 0; dropped = 0
        source = lastURL?.lastPathComponent ?? "Sin fuente"
        detail = lastURL == nil
            ? "Abre un archivo de audio o inicia la entrada del sistema."
            : "Archivo de la sesión anterior disponible. Pulsa Volver a decodificar para analizarlo como \(value.title)."
        settings.frequency = value.receptionProfile.center
        if value == .hell { settings.inverted = false; settings.imageStartSeconds = 0 }
        if value == .selectiveTones { settings.threshold = 0.02 }
        else if previous == .selectiveTones { settings.threshold = 0.08 }
        rfModulation = value.receptionProfile.modulation; rfBandwidth = value.receptionProfile.rfBandwidth
        if value == .hell { applyHellVariant() }
        if value == .gmdss { applyDSCVariant() }
        if value == .mt63 { applyMT63Variant() }
        receivedImage = nil; imageCaption = ""
    }
    func applyDSCVariant() {
        if settings.dscVariant == .vhf { settings.frequency = 1700; rfModulation = .fm; rfBandwidth = 16000 }
        else { settings.frequency = 1700; rfModulation = .usb; rfBandwidth = 2400 }
    }
    func applyDigitalVoicePreset() {
        guard !busy, mode == .digitalVoice else { return }
        let preset = settings.digitalVoiceProtocol.receptionPreset
        rfModulation = preset.modulation
        rfBandwidth = preset.rfBandwidthHz
    }
    func openAudio() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]; panel.allowsMultipleSelection = false
        panel.message = "WAV, AIFF u otro formato que macOS pueda leer."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        decode(url)
    }
    func decode(_ url: URL) {
        stop(); text = ""; error = nil; visualization.reset(); receivedImage = nil; imageCaption = ""
        acarsMessages = []; selectedACARSMessage = nil
        multimonRecords = []; engineRecords = []; clearVoice()
        lastURL = url; source = url.lastPathComponent; progress = 0; busy = true
        sourceChannelCount = 0; captureSampleRate = 0; dropped = 0; samplesReceived = 0
        let token = session, mode = mode, settings = settings
        task = Task {
            do {
                let voiceOutput = try prepareDMRVoiceOutput()
                try await worker.decodeFile(url: url, mode: mode, settings: settings, voiceOutput: voiceOutput) { [weak self] value in
                    await self?.apply(value, token: token)
                }
            } catch is CancellationError { }
            catch { if session == token { self.error = error.localizedDescription; stop() } }
        }
    }
    func startLive() {
        if mode == .digitalVoice && (!ExternalAudioEngine.dsdSupported || ExternalAudioEngine.dsdInstalledURL == nil) {
            error = ExternalAudioEngine.dsdSupported ? "Descarga DSD-neo antes de iniciar la entrada." : "El motor oficial DSD-neo requiere macOS 26."; return
        }
        if mode == .morse && settings.cwEngine != .manual && !CWEngine.isSupported { error = "CWKit requiere macOS 15. Selecciona Manual."; return }
        if inputSource == .tcp { startTCP(); return }
        voicePlayer?.stop()
        stop(); text = ""; error = nil; busy = true; live = true
        acarsMessages = []; selectedACARSMessage = nil
        multimonRecords = []; engineRecords = []; clearVoice()
        lastURL = nil
        sourceChannelCount = 0; captureSampleRate = 0; samplesReceived = 0; dropped = 0; progress = 0
        visualization.reset(); receivedImage = nil; imageCaption = ""; sstvCalibration = nil
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
                let voiceOutput = try prepareDMRVoiceOutput()
                let visualize = visualization.startLive()
                try await worker.decodeLive(ring: stream.ring, sampleRate: stream.sampleRate, mode: mode, settings: settings, source: inputName, voiceOutput: voiceOutput, visualize: visualize) { [weak self] value in
                    await self?.apply(value, token: token)
                }
            } catch is CancellationError { }
            catch { if session == token { self.error = error.localizedDescription; stop() } }
        }
    }
    private func startTCP() {
        stop(); text = ""; error = nil; busy = true; live = true; lastURL = nil
        acarsMessages = []; selectedACARSMessage = nil; multimonRecords = []; engineRecords = []; clearVoice()
        sourceChannelCount = 0; captureSampleRate = 0; samplesReceived = 0; dropped = 0; progress = 0
        visualization.reset(); receivedImage = nil; imageCaption = ""; sstvCalibration = nil
        let configuration = networkPCM, token = session, mode = mode, settings = settings
        let name = "TCP \(configuration.host):\(configuration.port) · \(configuration.format.rawValue)"
        source = name; detail = "Conectando al audio local…"; networkNotice = ""
        task = Task { [self] in
            do {
                try settings.validated(sampleRate: configuration.sampleRate, mode: mode)
                let stream = try await tcpInput.start(configuration: configuration, channel: settings.audioChannel) { [weak self] message in
                    guard let self, self.session == token else { return }
                    self.networkNotice = message
                }
                guard token == session, !Task.isCancelled else { return }
                sourceChannelCount = stream.channels; captureSampleRate = stream.sampleRate
                let voiceOutput = try prepareDMRVoiceOutput()
                let visualize = visualization.startLive()
                try await worker.decodeLive(ring: stream.ring, sampleRate: stream.sampleRate, mode: mode, settings: settings, source: name, voiceOutput: voiceOutput, visualize: visualize) { [weak self] value in
                    await self?.apply(value, token: token)
                }
                if session == token {
                    tcpInput.stop(); busy = false; live = false
                    if !networkNotice.isEmpty { detail += " · " + networkNotice }
                }
            } catch is CancellationError { }
            catch { if token == session { self.error = error.localizedDescription; stop() } }
        }
    }
    func installDSD() {
        guard !engineDownloading else { return }
        engineDownloading = true; engineNotice = "Descargando DSD-neo 2.10.0 y verificando su huella…"
        Task {
            defer { engineDownloading = false }
            do { try await DSDEngineInstaller.install(); engineNotice = "DSD-neo 2.10.0 instalado y listo." }
            catch { engineNotice = error.localizedDescription }
        }
    }
    func openReception(_ item: ReceptionSession, url: URL) {
        select(item.mode)
        settings = item.settings
        rfModulation = item.rf.modulation; rfBandwidth = item.rf.bandwidthHz
        decode(url)
    }
    func clearVoice() {
        dmrVoiceMonitor?.stop(); dmrVoiceMonitor = nil
        dmrStatus = nil; voiceFrames = 0; voiceOutputDropped = 0
        voicePlayer?.stop(); voicePlayer = nil
        if let url = voiceURL, url.lastPathComponent.hasPrefix("RadioWorkbench-voice-") { let finishing = voiceFinalization; Task { await finishing?.value; try? FileManager.default.removeItem(at: url) } }
        voiceURL = nil; voiceProtocol = nil
    }
    private func prepareDMRVoiceOutput() throws -> (@Sendable (DigitalVoicePCMChunk) -> Void)? {
        guard mode == .digitalVoice, settings.digitalVoiceProtocol == .dmr, settings.dmrMonitorVoice else { return nil }
        let monitor = try DMRVoiceMonitor(); dmrVoiceMonitor = monitor
        return { chunk in monitor.enqueue(chunk) }
    }
    func playVoice() {
        guard !busy, !voiceFinalizing, let url = voiceURL else { return }
        dmrVoiceMonitor?.stop(); dmrVoiceMonitor = nil
        do { voicePlayer = try AVAudioPlayer(contentsOf: url); voicePlayer?.play() } catch { self.error = "No hay voz reproducible en esta sesión: " + error.localizedDescription }
    }
    func exportVoice() {
        guard !busy, !voiceFinalizing, let url = voiceURL else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.wav]; panel.nameFieldStringValue = "voz-\((voiceProtocol ?? settings.digitalVoiceProtocol).rawValue).wav"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do { try Data(contentsOf: url).write(to: destination, options: .atomic) } catch { self.error = error.localizedDescription }
    }
    func exportEngineJSON() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "\(mode.rawValue)-recibido.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601; try encoder.encode(engineRecords).write(to: url, options: .atomic) } catch { self.error = error.localizedDescription }
    }
    func exportDMRStatus() {
        guard let status = dmrStatus else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "estado-dmr.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(status).write(to: url, options: .atomic)
        } catch { self.error = error.localizedDescription }
    }
    func stop() {
        visualization.stopLive()
        let previous = task
        session = UUID(); let token = session
        voiceOutputDropped = dmrVoiceMonitor?.snapshot.dropped ?? voiceOutputDropped
        dmrVoiceMonitor?.stop(); dmrVoiceMonitor = nil
        task?.cancel(); task = nil; input.stop(); tcpInput.stop(); busy = false; live = false
        if previous != nil && voiceURL != nil {
            voiceFinalizing = true
            voiceFinalization = Task { [weak self] in
                await previous?.value
                guard let self, self.session == token else { return }
                self.voiceFinalizing = false
            }
        } else { voiceFinalizing = false }
    }
    private func apply(_ value: RadioUpdate, token: UUID) {
        guard session == token else { return }
        let newText = String(value.text.suffix(40000))
        if text != newText { text = newText }
        if progress != value.progress { progress = value.progress }
        if source != value.source { source = value.source }
        let kind: ReceptionEventSource = live ? (inputSource == .tcp ? .networkAudio : .audioLive) : .audioFile
        for packet in value.packetReceptions {
            if let point = packet.position {
                receptionEvents.ingest(ReceptionEvent(id: "packet|" + packet.id.uuidString, source: value.source, sourceKind: kind,
                    protocolName: "APRS", entityID: point.id, receivedAt: packet.receivedAt,
                    latitude: point.latitude, longitude: point.longitude, message: packet.monitorLine, integrity: "Trama AX.25 UI con CRC verificado; hora de captura desconocida para archivos."))
            }
        }
        for message in value.acarsMessages {
            if let point = message.aircraftPosition {
                receptionEvents.ingest(ReceptionEvent(id: "acars|" + message.id.uuidString, source: value.source, sourceKind: kind,
                    protocolName: "ACARS", entityID: message.tail.isEmpty ? "Sin matrícula" : message.tail, receivedAt: message.decodedAt,
                    latitude: point.latitude, longitude: point.longitude, message: message.body,
                    integrity: "CRC ACARS verificado; posición ADS-C interpretada por libacars; no confirma identidad ni fecha de captura del archivo."))
            }
        }

        if mode == .acars {
            acarsMessages = value.acarsMessages
            if selectedACARSMessage == nil || !acarsMessages.contains(where: { $0.id == selectedACARSMessage }) { selectedACARSMessage = acarsMessages.last?.id }
        }
        if mode.isMultimon { multimonRecords = value.multimonRecords }
        engineRecords = value.engineRecords
        if let voice = value.voiceURL { voiceURL = voice; voiceProtocol = settings.digitalVoiceProtocol }
        dmrStatus = value.dmrStatus; voiceFrames = value.voiceFrames
        voiceOutputDropped = dmrVoiceMonitor?.snapshot.dropped ?? voiceOutputDropped
        if detail != value.detail { detail = value.detail }
        if dropped != value.dropped { dropped = value.dropped }
        samplesReceived = value.samplesReceived
        sstvCalibration = value.sstvCalibration
        if let count = value.channelCount { sourceChannelCount = count }
        if let image = value.image {
            receivedImage = Self.rgbImage(image); imageCaption = image.caption
        }
        if let frame = value.frame {
            visualization.update(frame)
        }
        if value.finished { visualization.stopLive(); dmrVoiceMonitor?.finish(); busy = false; live = false; task = nil }
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
    func loadACARSApplicationExample() {
        guard let url = Bundle.main.url(forResource: "acars_adsc_12000", withExtension: "wav", subdirectory: "Examples") else { error = "No se encontró el ejemplo ADS-C."; return }
        settings.audioChannel = .mix; decode(url)
    }
    func loadExample() {
        guard !busy else { return }
        if mode == .digitalVoice { confirmM17DataExample(); return }
        if mode == .ft8 || mode == .ft4 { settings.ftxStartSeconds = 0 }
        let name = switch mode {
        case .digitalVoice: "m17_packet_48000_synthetic"
        case .ft8: "ft8_12000_cq_clean"
        case .ft4: "ft4_12000_cq_clean"
        case .mt63: settings.mt63Variant.fixtureName
        case .ale: "ale2g_8000_synthetic"
        case .gmdss: settings.dscVariant == .vhf ? "dsc_vhf_48000_synthetic" : "dsc_mf_hf_48000_synthetic"
        case .morse: "morse_8000_mono_clean"
        case .rtty: settings.rttyEncoding == .ascii7 ? "rtty_ascii7_8000_75baud" : settings.rttyEncoding == .ascii8 ? "rtty_ascii8_8000_110baud" : "rtty_8000_mono_clean"
        case .bitAnalysis: "rtty_8000_mono_clean"
        case .psk31: "bpsk31_8000_mono_clean"
        case .navtex: "navtex_8000_mono_clean"
        case .acars: "acars_upstream_12000_mono"
        case .packet: "packet_8000_mono_clean"
        case .selectiveTones: "ctcss_8000_mono_100hz"
        case .pocsag: "pocsag_1200_22050_discriminator_clean"
        case .fiveTones: "selcall_zvei1_22050_12345"
        case .hell: "hell_feld_8000_cq_clean"
        case .sstv: sstvExampleName()
        case .wefax: "wefax_hf120_ioc576_8000_mono_manual"
        case .satelliteAPT: "noaa_apt_2400am_48000_mono_24lines"
        default: "dtmf_8000_mono_clean"
        }
        let url = Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "Examples")
        guard let url else { error = "No se encontró la grabación de ejemplo en el paquete."; return }
        if mode == .wefax { settings.imageStartSeconds = 0.5 }
        if mode == .gmdss { settings.frequency = 1700; settings.inverted = false; settings.dscDeemphasized = false }
        settings.audioChannel = .mix
        if mode == .navtex { settings.frequency = 1700; settings.inverted = false }
        if mode == .rtty && settings.rttyEncoding != .ita2 { settings.baud = settings.rttyEncoding == .ascii7 ? 75 : 110; settings.frequency = 1500; settings.shift = 170; settings.inverted = false }
        if mode == .packet { settings.frequency = 1700 }
        if mode == .mt63 { settings.frequency = 1500 }
        if mode == .selectiveTones { settings.threshold = 0.02 }
        if mode == .pocsag { settings.pagerRate = .automatic; settings.pagerShowEmpty = false }
        if mode == .fiveTones { settings.fiveToneStandard = .zvei1 }
        if mode == .hell { settings.hellVariant = .feld; settings.frequency = 1500; settings.threshold = 0.04; settings.imageStartSeconds = 0.2; settings.imageClockPPM = 0; settings.inverted = false }
        if mode == .sstv {
            settings.frequency = 1900; settings.imageAutoSync = true; settings.imageStartSeconds = 0
            settings.imageClockPPM = 0; settings.sstvColorRange = .bt601
        }
        decode(url)
    }
    private func confirmM17DataExample() {
        guard let url = Bundle.main.url(forResource: "m17_packet_48000_synthetic", withExtension: "wav", subdirectory: "Examples") else {
            error = "No se encontró el ejemplo M17 de datos en el paquete."; return
        }
        let alert = NSAlert()
        alert.messageText = "Abrir ejemplo M17 de datos"
        alert.informativeText = "Se seleccionará M17 y su guía RF para procesar un paquete sintético de datos a 48 kHz. No es una conversación de voz ni una prueba DMR. El protocolo actual es \(settings.digitalVoiceProtocol.rawValue)."
        alert.addButton(withTitle: "Abrir ejemplo M17")
        alert.addButton(withTitle: "Cancelar")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        settings.digitalVoiceProtocol = .m17
        settings.audioChannel = .mix
        applyDigitalVoicePreset()
        decode(url)
    }
    func applyHellVariant() {
        guard mode == .hell else { return }
        settings.frequency = max(settings.frequency, settings.hellVariant.bandwidthHz / 2 + 300)
        rfBandwidth = max(2400, settings.hellVariant.bandwidthHz + 600)
    }
    func applyMT63Variant() {
        guard mode == .mt63 else { return }
        let lower = max(1000, Double(settings.mt63Variant.bandwidth) / 2 + 1)
        settings.frequency = min(2500, max(lower, settings.frequency))
        updateMT63Bandwidth()
    }
    func updateMT63Bandwidth() {
        guard mode == .mt63, settings.frequency.isFinite else { return }
        rfBandwidth = max(3000, settings.frequency + Double(settings.mt63Variant.bandwidth) / 2 + 200)
    }
    func exportMultimonJSON() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "\(mode.rawValue)-mensajes.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(multimonRecords).write(to: url, options: .atomic) }
        catch { self.error = error.localizedDescription }
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
}
