import Foundation
import Observation
import RadioCore

@MainActor @Observable final class PropagationStore {
    var autoRefreshEnabled = true
    var autoRefreshMinutes = 3
    var weather = SpaceWeatherSnapshot()
    var weatherBusy = false
    var weatherStatus = "Los datos se consultan con conexión y se conserva la última copia."
    var shareGridWithPSKReporter = UserDefaults.standard.bool(forKey: "shareGridWithPSKReporter")
    var pskSnapshot: PSKReporterSnapshot?
    var pskBusy = false
    var pskStatus = "Los spots son reportes de recepción amateur, no una predicción ni una garantía de contacto."
    var sourceErrors: [String: String] = [:]
    var ionosphere: IonosondeSnapshot?
    var ionosphereStatus = "Se consultan observaciones de estaciones ionosonda; la ubicación no se envía."
    var noaaForecast: NoaaThreeDayForecast?
    var noaaForecastStatus = "Pronóstico NOAA SWPC de tres días; se actualiza cada seis horas."
    var bandChanges: [String] = []
    var bandChangesAt: Date?
    var originCountry = ""
    var targetCountry = ""
    var listening = true {
        didSet { if oldValue != listening { cancelCalculation(); report = nil; returnReport = nil } }
    }
    var estimatesReception = false {
        didSet { if listening && !estimatesReception { cancelCalculation() } }
    }
    var returnReport: HFPropagationReport?
    var planningBroadcast: BroadcastEntry?
    private struct Assumptions {
        var watts = "100", bandwidth = "2400", requiredSNR = "10", txGain = "0", rxGain = "0"
        var noise = 2
    }
    private var receiveAssumptions = Assumptions(watts: "")
    private var linkAssumptions = Assumptions()
    var returnWatts = "100"
    var returnTXGain = "0"
    var returnRXGain = "0"
    var returnBandwidth = "2400"
    var returnRequiredSNR = "10"
    var returnNoise = 2
    var targetLatitude = ""
    var targetLongitude = ""
    var targetName = "Destino del enlace"
    var stationTransferNotice = ""
    var stationSites: [BroadcastSite] = []
    var selectedStationSite: Int?
    var stationPowerCandidate: HFCCTransmission?
    var planningDate = Date()
    var usesCurrentPlanningTime = true
    var watts: String {
        get { listening ? receiveAssumptions.watts : linkAssumptions.watts }
        set { if listening { receiveAssumptions.watts = newValue } else { linkAssumptions.watts = newValue } }
    }
    private var wattsReference: Double?
    private var wattsDescription = "Potencia TX manual; introduce un valor conocido o un supuesto explícito."
    var wattsSource: String {
        get {
            if !listening { return "Potencia de la estación A; ganancias, ruido y requisitos de B se introducen para A → B. El regreso usa parámetros propios." }
            if let wattsReference, number(watts) != wattsReference { return "Potencia TX modificada manualmente; ya no coincide con el supuesto HFCC elegido." }
            return wattsDescription
        }
        set { wattsDescription = newValue }
    }
    var bandwidth: String {
        get { listening ? receiveAssumptions.bandwidth : linkAssumptions.bandwidth }
        set { if listening { receiveAssumptions.bandwidth = newValue } else { linkAssumptions.bandwidth = newValue } }
    }
    var requiredSNR: String {
        get { listening ? receiveAssumptions.requiredSNR : linkAssumptions.requiredSNR }
        set { if listening { receiveAssumptions.requiredSNR = newValue } else { linkAssumptions.requiredSNR = newValue } }
    }
    var txGain: String {
        get { listening ? receiveAssumptions.txGain : linkAssumptions.txGain }
        set { if listening { receiveAssumptions.txGain = newValue } else { linkAssumptions.txGain = newValue } }
    }
    var rxGain: String {
        get { listening ? receiveAssumptions.rxGain : linkAssumptions.rxGain }
        set { if listening { receiveAssumptions.rxGain = newValue } else { linkAssumptions.rxGain = newValue } }
    }
    var frequencyMHz = "7.1"
    var r12 = ""
    private var r12Reference: Double?
    private var r12Month: String?
    private var r12Description = "Introduce R12 o usa la circular mensual de ITU."
    var r12Source: String {
        if let value = number(r12), value != r12Reference { return "R12 introducido manualmente; comprueba su mes y procedencia." }
        return r12Description
    }
    var noise: Int {
        get { listening ? receiveAssumptions.noise : linkAssumptions.noise }
        set { if listening { receiveAssumptions.noise = newValue } else { linkAssumptions.noise = newValue } }
    }
    var report: HFPropagationReport?
    var calculationBusy = false
    var calculationError: String?
    var terrainOriginLatitude = UserDefaults.standard.string(forKey: "terrainOriginLatitude") ?? "" {
        didSet { UserDefaults.standard.set(terrainOriginLatitude, forKey: "terrainOriginLatitude"); invalidateTerrainLocation() }
    }
    var terrainOriginLongitude = UserDefaults.standard.string(forKey: "terrainOriginLongitude") ?? "" {
        didSet { UserDefaults.standard.set(terrainOriginLongitude, forKey: "terrainOriginLongitude"); invalidateTerrainLocation() }
    }
    var terrainTargetLatitude = UserDefaults.standard.string(forKey: "terrainTargetLatitude") ?? "" {
        didSet { UserDefaults.standard.set(terrainTargetLatitude, forKey: "terrainTargetLatitude"); invalidateTerrainDestination() }
    }
    var terrainTargetLongitude = UserDefaults.standard.string(forKey: "terrainTargetLongitude") ?? "" {
        didSet { UserDefaults.standard.set(terrainTargetLongitude, forKey: "terrainTargetLongitude"); invalidateTerrainDestination() }
    }
    var txHeight = UserDefaults.standard.string(forKey: "terrainTxHeight") ?? "10" {
        didSet { UserDefaults.standard.set(txHeight, forKey: "terrainTxHeight"); invalidateTerrainResult() }
    }
    var rxHeight = UserDefaults.standard.string(forKey: "terrainRxHeight") ?? "2" {
        didSet { UserDefaults.standard.set(rxHeight, forKey: "terrainRxHeight"); invalidateTerrainResult() }
    }
    var terrainFrequencyMHz = UserDefaults.standard.string(forKey: "terrainFrequencyMHz") ?? "144.39" {
        didSet { UserDefaults.standard.set(terrainFrequencyMHz, forKey: "terrainFrequencyMHz"); invalidateTerrainResult() }
    }
    var terrainWatts = UserDefaults.standard.string(forKey: "terrainWatts") ?? "10" {
        didSet { UserDefaults.standard.set(terrainWatts, forKey: "terrainWatts"); invalidateTerrainResult() }
    }
    var terrainTxGain = UserDefaults.standard.string(forKey: "terrainTxGain") ?? "0" {
        didSet { UserDefaults.standard.set(terrainTxGain, forKey: "terrainTxGain"); invalidateTerrainResult() }
    }
    var terrainRxGain = UserDefaults.standard.string(forKey: "terrainRxGain") ?? "0" {
        didSet { UserDefaults.standard.set(terrainRxGain, forKey: "terrainRxGain"); invalidateTerrainResult() }
    }
    var terrainSensitivityDBm = UserDefaults.standard.string(forKey: "terrainSensitivityDBm") ?? "-110" {
        didSet { UserDefaults.standard.set(terrainSensitivityDBm, forKey: "terrainSensitivityDBm"); invalidateTerrainResult() }
    }
    var terrainCoverageMaximumKm = UserDefaults.standard.string(forKey: "terrainCoverageMaximumKm") ?? "100" {
        didSet {
            UserDefaults.standard.set(terrainCoverageMaximumKm, forKey: "terrainCoverageMaximumKm")
            invalidateTerrainCoverage()
        }
    }
    var terrainMapSelection = "destination"
    var terrainMapShowingRelief = true
    var terrainClimate = ITMClimate(rawValue: UserDefaults.standard.integer(forKey: "terrainITMClimate")) ?? .continentalTemperate {
        didSet { UserDefaults.standard.set(terrainClimate.rawValue, forKey: "terrainITMClimate"); invalidateTerrainResult() }
    }
    var terrainVerticalPolarization = UserDefaults.standard.object(forKey: "terrainVerticalPolarization") as? Bool ?? true {
        didSet { UserDefaults.standard.set(terrainVerticalPolarization, forKey: "terrainVerticalPolarization"); invalidateTerrainResult() }
    }
    var terrainProfile: TerrainProfile?
    var terrainResult: TerrainITMResult?
    var terrainBusy = false
    var terrainStatus = "El perfil se consulta solo al pulsar Calcular con terreno."
    var terrainCoverageReport: TerrainCoverageReport?
    var terrainCoverageOriginElevationMeters: Double?
    var terrainCoverageBusy = false
    var terrainCoverageProgress = 0.0
    var terrainCoverageStatus = "Calcula una malla de recepción con el relieve de cada trayecto."
    var terrainCoverageQuality: TerrainCoverageQuality = .detailed {
        didSet { invalidateTerrainCoverage() }
    }
    var terrainCoverageShowShadows = false
    var terrainMapShowingHorizon = false
    var terrainProfileSource = "Mapzen Terrain Tiles · DEM"
    var terrainOrigin: RadioLocation? { RadioLocation(latitude: terrainOriginLatitude, longitude: terrainOriginLongitude) }
    var terrainTarget: RadioLocation? { RadioLocation(latitude: terrainTargetLatitude, longitude: terrainTargetLongitude) }
    private let service = SpaceWeatherService()
    private let ionosondeService = IonosondeService()
    private let noaaForecastService = NoaaThreeDayForecastService()
    private let pskReporterService = PSKReporterService()
    private let engine = HFPropagationEngine()
    private let terrainEngine = TerrainITMEngine()
    private let terrainDEMService = TerrainDEMService()
    private var terrainCoverageTask: Task<TerrainCoverageReport, Error>?
    private var terrainCoverageGeneration = UUID()
    private var terrainLinkGeneration = UUID()
    private var activated = false
    private var lastAttempt: Date?
    private var calculationTask: Task<Void, Never>?
    private var generation = UUID()

    func seedTerrainCoordinates(origin: RadioLocation?, destination: RadioLocation?) {
        if terrainOriginLatitude.isEmpty && terrainOriginLongitude.isEmpty, let origin { setTerrainOrigin(origin) }
        if terrainTargetLatitude.isEmpty && terrainTargetLongitude.isEmpty, let destination { setTerrainTarget(destination) }
    }
    func setTerrainOrigin(_ location: RadioLocation) {
        terrainOriginLatitude = Self.coordinateText(location.latitude)
        terrainOriginLongitude = Self.coordinateText(location.longitude)
    }
    func setTerrainTarget(_ location: RadioLocation) {
        terrainTargetLatitude = Self.coordinateText(location.latitude)
        terrainTargetLongitude = Self.coordinateText(location.longitude)
    }
    func copyLocationToTerrainOrigin(_ location: RadioLocation?) {
        guard let location else { return }
        setTerrainOrigin(location)
    }
    func copyHFEndpointToTerrainTarget() {
        guard let target = RadioLocation(latitude: targetLatitude, longitude: targetLongitude) else { return }
        setTerrainTarget(target)
    }
    private static func coordinateText(_ value: Double) -> String {
        String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
    private func invalidateTerrainLocation() {
        terrainProfile = nil
        invalidateTerrainResult()
    }
    private func invalidateTerrainDestination() {
        terrainLinkGeneration = UUID()
        terrainProfile = nil; terrainResult = nil
        terrainStatus = "Cambió el destino; vuelve a calcular el enlace. La malla del origen se conserva."
    }
    private func invalidateTerrainCoverage() {
        terrainCoverageGeneration = UUID()
        terrainCoverageTask?.cancel(); terrainCoverageTask = nil
        terrainCoverageBusy = false; terrainCoverageReport = nil
        terrainCoverageOriginElevationMeters = nil; terrainCoverageProgress = 0
        terrainCoverageStatus = "Cambió un parámetro; vuelve a calcular la malla."
    }
    private func invalidateTerrainResult() {
        terrainLinkGeneration = UUID()
        terrainResult = nil
        invalidateTerrainCoverage()
        terrainStatus = "Cambió un parámetro; vuelve a calcular el enlace."
    }
    func cancelTerrainCoverage() {
        invalidateTerrainCoverage()
        terrainCoverageStatus = "Cálculo cancelado; no se muestra una malla incompleta."
    }

    func runAutoRefresh() async {
        if !activated {
            activated = true
            weather = await service.cached() ?? SpaceWeatherSnapshot()
            ionosphere = await ionosondeService.cached()
            noaaForecast = await noaaForecastService.cached()
            if autoRefreshEnabled { await refresh() }
        }
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(60)) } catch { return }
            if autoRefreshEnabled, lastAttempt.map({ Date().timeIntervalSince($0) >= Double(autoRefreshMinutes) * 60 }) ?? true { await refresh() }
        }
    }
    func refresh(forceIndices: Bool = false) async {
        guard !weatherBusy else { return }
        weatherBusy = true; lastAttempt = Date()
        defer { weatherBusy = false }
        async let ionosphereTask = ionosondeService.download()
        async let forecastTask = noaaForecastService.download()
        let update = await service.download(previous: weather, forceIndices: forceIndices)
        guard !Task.isCancelled else { return }
        if let new = update.snapshot.bandInformation, let old = weather.bandInformation {
            let changes = new.changes(from: old)
            if !changes.isEmpty { bandChanges = changes; bandChangesAt = new.updatedAt }
        }
        weather = update.snapshot
        for name in update.attemptedSources { sourceErrors[name] = update.errors[name] }
        sourceErrors["cache"] = update.errors["cache"]
        do {
            ionosphere = try await ionosphereTask
            ionosphereStatus = "GIRO/KC2G · \(ionosphere?.observations.count ?? 0) estaciones con mediciones recientes; copia local actualizada."
        } catch {
            ionosphereStatus = ionosphere == nil ? "Ionosondas no disponibles: \(error.localizedDescription)." : "Ionosondas: se conserva la copia anterior (\(error.localizedDescription))."
        }
        do {
            noaaForecast = try await forecastTask
            let utcStyle = Date.FormatStyle(date: .abbreviated, time: .shortened, timeZone: TimeZone(secondsFromGMT: 0)!)
            noaaForecastStatus = "Pronóstico NOAA SWPC · emitido \(noaaForecast?.issuedAt.formatted(utcStyle) ?? "sin fecha") UTC · nueva emisión aproximadamente cada 12 h."
        } catch {
            noaaForecastStatus = noaaForecast == nil ? "Pronóstico NOAA no disponible: \(error.localizedDescription)." : "NOAA conserva el pronóstico anterior (\(error.localizedDescription))."
        }
        weatherStatus = sourceErrors.isEmpty ? "Fuentes consultadas. Las comprobaciones automáticas siguen la política de Ajustes." : "Hay fuentes sin actualizar. Se conservan las copias y las fechas; los reintentos siguen las cadencias de cada fuente."
    }
    func useITUIndex(at date: Date) {
        guard let index = weather.index(at: date) else {
            r12Description = "No hay R12 de ITU para este mes en la copia disponible. Puedes introducirlo manualmente."; return
        }
        r12 = String(index.r12)
        r12Reference = index.r12
        r12Month = index.id
        r12Description = "ITU · \(index.id) · \(index.predicted ? "pronosticado" : "observado suavizado") · consulta \(weather.indicesFetchedAt?.formatted(date: .abbreviated, time: .shortened) ?? "sin fecha")"
    }
    func useManualR12() {
        r12Reference = nil; r12Month = nil
        r12Description = "R12 manual elegido como supuesto; documenta su mes y procedencia."
    }
    func r12MonthMismatch(at date: Date) -> Bool {
        guard let reference = r12Reference, number(r12) == reference, let month = r12Month else { return false }
        let calendar = BroadcastCalendar.utc
        let selected = String(format: "%04d-%02d", calendar.component(.year, from: date), calendar.component(.month, from: date))
        return month != selected
    }
    func setPSKGridSharing(_ enabled: Bool) {
        shareGridWithPSKReporter = enabled
        UserDefaults.standard.set(enabled, forKey: "shareGridWithPSKReporter")
        if !enabled {
            pskSnapshot = nil
            pskStatus = "Consulta desactivada. No se enviará tu cuadrícula a PSK Reporter."
        } else {
            pskStatus = "Al activar, se consulta la cuadrícula Maidenhead de 4 caracteres (aprox. 100 km) cada 5 minutos como máximo."
        }
    }
    func refreshReceptionSpots(location: RadioLocation?) async {
        guard shareGridWithPSKReporter else { return }
        guard let location, let grid = Maidenhead.grid4(latitude: location.latitude, longitude: location.longitude) else {
            pskStatus = "Guarda coordenadas válidas para calcular una cuadrícula local."
            return
        }
        guard !pskBusy else { return }
        pskBusy = true
        defer { pskBusy = false }
        do {
            pskSnapshot = try await pskReporterService.download(grid: grid)
            let count = pskSnapshot?.spots.count ?? 0
            pskStatus = "PSK Reporter · \(grid) · \(count) recepciones en la última hora · consulta limitada a una cada 5 min."
        } catch {
            pskStatus = "PSK Reporter no disponible: \(error.localizedDescription). Se mantiene la condición modelada por separado."
        }
    }
    func planningTime(at now: Date) -> Date { usesCurrentPlanningTime ? now : planningDate }
    @discardableResult func useSelectedStation(_ guide: BroadcastStore) -> Bool {
        guard let entry = guide.selectedEntry else {
            stationTransferNotice = "Elige una fila en la Guía de radios o pulsa Enviar al Planificador HF en su detalle."
            calculationError = stationTransferNotice; return false
        }
        useStation(entry, guide: guide); return true
    }
    func useStation(_ entry: BroadcastEntry, guide: BroadcastStore) {
        cancelCalculation(); report = nil
        listening = true; estimatesReception = false; planningBroadcast = entry
        returnReport = nil
        guide.selectedID = entry.id
        targetLatitude = ""; targetLongitude = ""; targetCountry = ""
        targetName = "\(entry.station) · \(entry.frequencyKHz) kHz · \(entry.time) UTC"
        frequencyMHz = String(entry.frequencyKHz / 1000)
        stationSites = guide.snapshot?.reference.siteCandidates(for: entry) ?? []
        selectedStationSite = nil
        if let site = guide.snapshot?.reference.site(for: entry) {
            targetLatitude = Self.coordinateText(site.latitude); targetLongitude = Self.coordinateText(site.longitude)
            selectedStationSite = stationSites.firstIndex(of: site)
        }
        stationPowerCandidate = guide.hfccMatch(for: entry)
        watts = ""; wattsReference = nil
        wattsSource = "Falta potencia TX: introduce un dato conocido o un supuesto. Una coincidencia de frecuencia y horario HFCC no demuestra por sí sola el mismo transmisor."
        txGain = "0"
        if entry.modulation.hasPrefix("AM") { bandwidth = "9000" }
        else if entry.modulation == "USB" || entry.modulation == "LSB" { bandwidth = "2700" }
        else if entry.modulation.hasPrefix("CW") { bandwidth = "500" }
        else if entry.modulation.hasPrefix("DRM") { bandwidth = "10000" }
        else { bandwidth = "" }
        listening = true
        stationTransferNotice = "Preparada escucha de emisora: nombre, frecuencia y sintonía. " + (targetLatitude.isEmpty ? "El sitio EiBi no es único o no tiene coordenadas: elige un sitio o completa el emisor remoto. " : "Coordenadas del transmisor tomadas de EiBi. ") + "Distancia y geometría disponibles sin potencia. Activa P.533 solo si conoces la potencia remota o eliges un supuesto explícito."
        calculationError = nil
    }
    func useChosenStationSite() {
        guard let index = selectedStationSite, stationSites.indices.contains(index) else { return }
        cancelCalculation(); report = nil
        let site = stationSites[index]
        targetLatitude = Self.coordinateText(site.latitude); targetLongitude = Self.coordinateText(site.longitude)
        stationTransferNotice = "Sitio elegido: \(site.name). Revisa la potencia, el ancho de ruido RX y el R12 antes de calcular."
    }
    func useCandidatePowerAsAssumption() {
        guard let tx = stationPowerCandidate, let value = tx.scheduledPowerWatts else { return }
        watts = String(Int(value))
        wattsReference = value
        wattsSource = "Supuesto elegido: \(tx.powerKW ?? 0) kW declarados por HFCC, sitio \(tx.siteCode), \(tx.startUTC)–\(tx.stopUTC) UTC. Verifica que sea el transmisor correcto; no es potencia medida ni ERP."
    }
    func hfPlanningDataText(origin: RadioLocation?, date: Date) -> String {
        let local = origin.map { "\($0.latitude), \($0.longitude)" } ?? "pendiente"
        let remote = "\(targetLatitude), \(targetLongitude)"
        let frequency = RadioNumericText.frequencyMHz(frequencyMHz).map { String($0) } ?? frequencyMHz
        let returning = listening ? "" : "\nB → A · potencia TX B: \(returnWatts) W · ganancia TX B: \(returnTXGain) dBi · ganancia RX A: \(returnRXGain) dBi · ancho RX A: \(returnBandwidth) Hz · SNR requerido A: \(returnRequiredSNR) dB · ruido RX A: \(returnNoise)"
        return "\(listening ? "Escucha" : "Enlace A → B y B → A") · \(targetName)\nTX: \(listening ? remote : local)\nRX: \(listening ? local : remote)\nFecha UTC: \(ISO8601DateFormatter().string(from: date))\nFrecuencia: \(frequency) MHz\nPotencia TX: \(watts.isEmpty ? "pendiente" : watts) W\nAncho de ruido RX: \(bandwidth) Hz · SNR requerido: \(requiredSNR) dB\nGanancias TX/RX: \(txGain)/\(rxGain) dBi · R12: \(r12)\n\(r12Source)\n\(wattsSource)\nP.533: estimación mensual por hora UTC, antenas de ganancia constante.\(returning)"
    }
    func inputProblems(origin: RadioLocation?, date: Date) -> [String] {
        var problems: [String] = []
        if r12MonthMismatch(at: date) { problems.append("R12 ITU pertenece a \(r12Month ?? "otro mes"); usa el índice del mes UTC elegido o conviértelo explícitamente en un supuesto manual.") }
        if origin == nil { problems.append("Tu ubicación: latitud y longitud válidas.") }
        let target = RadioLocation(latitude: targetLatitude, longitude: targetLongitude)
        if target == nil { problems.append("\(listening ? "Emisor remoto" : "Destino"): completa coordenadas válidas.") }
        if let origin, let target, origin.distance(to: target) < 10 { problems.append("El trayecto debe medir al menos 10 km.") }
        if RadioNumericText.frequencyMHz(frequencyMHz).map({ !(1.6...30).contains($0) }) ?? true { problems.append("Frecuencia HF: 1,6–30 MHz; puedes pegar un valor con kHz o MHz.") }
        for (label, value, range) in [("Potencia TX", watts, 1.0...1_000_000), ("Ancho de ruido RX (Hz)", bandwidth, 1.0...100_000), ("SNR requerido (dB)", requiredSNR, -30.0...100), ("R12 mensual", r12, 0.0...311), ("Ganancia TX (dBi)", txGain, -40.0...40), ("Ganancia RX (dBi)", rxGain, -40.0...40)] {
            if number(value).map({ !range.contains($0) }) ?? true { problems.append("\(label): introduce un valor entre \(range.lowerBound) y \(range.upperBound).") }
        }
        if !(1900...2100).contains(BroadcastCalendar.utc.component(.year, from: date)) { problems.append("La fecha debe estar entre 1900 y 2100.") }
        return problems
    }
    func input(origin: RadioLocation?, date: Date) -> HFPropagationInput? {
        guard !r12MonthMismatch(at: date), let origin, let target = RadioLocation(latitude: targetLatitude, longitude: targetLongitude),
              let r = number(r12), let p = number(watts), let bw = number(bandwidth), let snr = number(requiredSNR),
              let tx = number(txGain), let rx = number(rxGain), let f = RadioNumericText.frequencyMHz(frequencyMHz) else { return nil }
        let input = HFPropagationInput(origin: listening ? target : origin, target: listening ? origin : target, date: date, r12: r, watts: p, bandwidth: bw, requiredSNR: snr, txGain: tx, rxGain: rx, noise: noise, frequencyMHz: f)
        return input.isValid ? input : nil
    }
    func reverseInput(origin: RadioLocation?, date: Date) -> HFPropagationInput? {
        guard !listening, let forward = input(origin: origin, date: date),
              let power = number(returnWatts), let tx = number(returnTXGain), let rx = number(returnRXGain),
              let bw = number(returnBandwidth), let snr = number(returnRequiredSNR) else { return nil }
        return forward.reversed(watts: power, bandwidth: bw, requiredSNR: snr, txGain: tx, rxGain: rx, noise: returnNoise)
    }
    func pathSummary(origin: RadioLocation?, date: Date) -> String {
        guard let origin, let target = RadioLocation(latitude: targetLatitude, longitude: targetLongitude) else {
            return "Completa ubicación RX y sitio remoto para distancia, rumbo e iluminación. La potencia no es necesaria para esta ficha."
        }
        let midpoint = origin.destination(km: origin.distance(to: target) / 2, bearing: origin.bearing(to: target))
        let sun = [origin.solarElevation(at: date), midpoint?.solarElevation(at: date) ?? 0, target.solarElevation(at: date)]
        return String(format: "%.0f km · rumbo local → remoto %.0f° · Sol local / punto medio / remoto: %.1f° / %.1f° / %.1f°", origin.distance(to: target), origin.bearing(to: target), sun[0], sun[1], sun[2])
    }
    var limitingDirection: String? {
        guard let a = report, let b = returnReport,
              let ar = a.hourly.first(where: { $0.hour == a.hourUTC })?.reliability,
              let br = b.hourly.first(where: { $0.hour == b.hourUTC })?.reliability else { return nil }
        return "Dirección limitante por BCR mensual: \(ar <= br ? "A → B" : "B → A") · \(min(ar, br).formatted(.number.precision(.fractionLength(1)))) %. No es una probabilidad de contacto bilateral en tiempo real."
    }
    func calculate(origin: RadioLocation?, date: Date) {
        var problems = inputProblems(origin: origin, date: date)
        if !listening && reverseInput(origin: origin, date: date) == nil {
            problems.append("Completa los parámetros de regreso B → A: potencia B, ganancia TX B, ganancia RX A, ancho/SNR y ruido RX A.")
        }
        guard problems.isEmpty, let input = input(origin: origin, date: date) else {
            calculationError = problems.joined(separator: "\n"); return
        }
        cancelCalculation(); calculationBusy = true; calculationError = nil
        let token = generation
        let reverse = listening ? nil : reverseInput(origin: origin, date: date)
        report = nil; returnReport = nil
        calculationTask = Task {
            do {
                let result = try await engine.predict(input)
                guard token == generation else { return }
                var returning: HFPropagationReport?
                if let reverse { returning = try await engine.predict(reverse) }
                guard token == generation, !Task.isCancelled else { return }
                report = result; returnReport = returning
            } catch is CancellationError { }
            catch { if token == generation { calculationError = error.localizedDescription } }
            if token == generation { calculationBusy = false }
        }
    }
    func cancelCalculation() {
        generation = UUID(); calculationTask?.cancel(); calculationTask = nil; calculationBusy = false
    }
    func calculateTerrain() async {
        guard !terrainBusy, !terrainCoverageBusy else { return }
        guard let origin = terrainOrigin, let target = terrainTarget,
              let txHeight = number(txHeight), let rxHeight = number(rxHeight),
              let frequency = number(terrainFrequencyMHz), let watts = number(terrainWatts),
              let txGain = number(terrainTxGain), let rxGain = number(terrainRxGain),
              (0.5...3_000).contains(txHeight), (0.5...3_000).contains(rxHeight),
              (20...20_000).contains(frequency), (0.001...1_000_000).contains(watts),
              (-40...60).contains(txGain), (-40...60).contains(rxGain),
              let sensitivity = number(terrainSensitivityDBm), (-200...0).contains(sensitivity) else {
            terrainStatus = "Completa coordenadas válidas, alturas sobre el terreno, frecuencia 20 MHz–20 GHz, potencia, ganancias y umbral RX."
            return
        }
        let token = terrainLinkGeneration
        terrainBusy = true
        terrainResult = nil
        terrainStatus = "Cargando relieve DEM de todo el trayecto desde teselas y caché…"
        defer { terrainBusy = false }
        do {
            let profile: TerrainProfile
            let source: String
            if let coverage = terrainCoverageReport, coverage.layout.origin == origin,
               let cached = try? coverage.mosaic.profile(from: origin, to: target) {
                profile = cached; source = "Mapzen Terrain Tiles · DEM de la malla"
            } else {
                profile = try await terrainDEMService.profile(from: origin, to: target)
                source = "Mapzen Terrain Tiles · DEM del trayecto"
            }
            guard token == terrainLinkGeneration else { return }
            terrainProfile = profile; terrainProfileSource = source
            terrainStatus = "Perfil: \(profile.points.count) puntos · paso \(Int(profile.resolutionMeters)) m · \(source). Ejecutando NTIA ITM…"
            let input = TerrainITMInput(frequencyMHz: frequency, txHeightMeters: txHeight, rxHeightMeters: rxHeight,
                                        climate: terrainClimate, verticalPolarization: terrainVerticalPolarization,
                                        transmitWatts: watts, txGainDBi: txGain, rxGainDBi: rxGain)
            let result = try await terrainEngine.predict(input: input, profile: profile)
            guard token == terrainLinkGeneration else { return }
            terrainResult = result
            let margin = result.receivedPowerDBm - sensitivity
            terrainStatus = "NTIA ITM · \(result.distanceKm.formatted(.number.precision(.fractionLength(1)))) km · margen estimado \(margin >= 0 ? "+" : "")\(margin.formatted(.number.precision(.fractionLength(1)))) dB frente al umbral RX · DEM consultado \(profile.fetchedAt.formatted(date: .abbreviated, time: .shortened))."
        } catch {
            if token == terrainLinkGeneration { terrainStatus = "No se pudo calcular con terreno: \(error.localizedDescription)" }
        }
    }
    func calculateTerrainCoverage() async {
        guard !terrainBusy, !terrainCoverageBusy else { return }
        guard let origin = terrainOrigin, let tx = number(txHeight), let rx = number(rxHeight),
              let frequency = number(terrainFrequencyMHz), let watts = number(terrainWatts),
              let txGain = number(terrainTxGain), let rxGain = number(terrainRxGain),
              let sensitivity = number(terrainSensitivityDBm), (-200...0).contains(sensitivity),
              let maximumKm = number(terrainCoverageMaximumKm),
              let layout = try? TerrainCoverageLayout(origin: origin, radiusKm: maximumKm, side: terrainCoverageQuality.side) else {
            terrainCoverageStatus = "Completa origen, alturas, frecuencia, potencia, ganancias y área de 5–200 km (latitudes ±80°)."
            return
        }
        let input = TerrainITMInput(frequencyMHz: frequency, txHeightMeters: tx, rxHeightMeters: rx,
            climate: terrainClimate, verticalPolarization: terrainVerticalPolarization, transmitWatts: watts,
            txGainDBi: txGain, rxGainDBi: rxGain)
        guard input.isValid else { terrainCoverageStatus = TerrainITMError.invalidInput.localizedDescription; return }
        let token = UUID(); terrainCoverageGeneration = token
        terrainCoverageBusy = true; terrainCoverageProgress = 0; terrainCoverageReport = nil
        terrainCoverageOriginElevationMeters = nil
        terrainCoverageStatus = "Cargando teselas DEM para cada trayecto de la malla…"
        let service = terrainDEMService
        let job = Task { [weak self] in
            let mosaic = try await service.load(keys: layout.suitableTileKeys) { [weak self] completed, total in
                await MainActor.run {
                    guard let self, self.terrainCoverageGeneration == token else { return }
                    self.terrainCoverageProgress = 0.25 * Double(completed) / Double(total)
                    self.terrainCoverageStatus = "Relieve DEM · \(completed)/\(total) teselas · caché local y descarga bajo demanda"
                }
            }
            let native = try TerrainITMNative()
            return try await TerrainCoverageCalculator.calculate(layout: layout, input: input, thresholdDBm: sensitivity,
                mosaic: mosaic, native: native) { [weak self] completed, total in
                    await MainActor.run {
                        guard let self, self.terrainCoverageGeneration == token else { return }
                        self.terrainCoverageProgress = 0.25 + 0.75 * Double(completed) / Double(total)
                        self.terrainCoverageStatus = "ITM por celda · fila \(completed)/\(total) · paso de malla \(Int(layout.spacingMeters)) m"
                    }
                }
        }
        terrainCoverageTask = job
        defer { if terrainCoverageGeneration == token { terrainCoverageBusy = false; terrainCoverageTask = nil } }
        do {
            let result = try await job.value
            guard terrainCoverageGeneration == token else { return }
            terrainCoverageReport = result; terrainCoverageProgress = 1
            terrainCoverageOriginElevationMeters = result.mosaic.elevation(at: origin).map { max(0, $0) }
            terrainCoverageStatus = "Malla ITM: \(result.coveredCount)/\(result.modeledCount) celdas sobre umbral · \(Int(layout.spacingMeters.rounded())) m/celda · DEM ≈\(Int(result.mosaic.resolutionMeters(at: origin).rounded())) m/píxel · \(result.warnedCount) con avisos."
            if result.missingTerrainCells + result.modelErrorCells > 0 {
                terrainCoverageStatus += " \(result.missingTerrainCells) sin DEM, \(result.modelErrorCells) sin resultado; quedan transparentes."
            }
            if result.edgeCoveredCount > 0 {
                terrainCoverageStatus += " Hay señal estimada en el borde: el área limita el análisis, no define el alcance máximo."
            }
        } catch is CancellationError {
            if terrainCoverageGeneration == token { terrainCoverageStatus = "Cálculo cancelado." }
        } catch {
            if terrainCoverageGeneration == token { terrainCoverageStatus = "No se pudo modelar el terreno: \(error.localizedDescription)" }
        }
    }
    func number(_ value: String) -> Double? {
        RadioNumericText.number(value)
    }
    var horizon: Double? {
        guard let tx = number(txHeight), let rx = number(rxHeight), tx <= 10_000, rx <= 10_000 else { return nil }
        return RadioLinkBudget.horizonKm(txHeight: tx, rxHeight: rx)
    }
    /// Flat-ground comparison uses structural AGL heights, not absolute altitude above sea level.
    var terrainHorizon: Double? { horizon }
}
