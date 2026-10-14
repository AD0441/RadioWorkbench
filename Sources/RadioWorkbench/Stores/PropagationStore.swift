import Foundation
import Observation
import RadioCore

@MainActor @Observable final class PropagationStore {
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
    var listening = false
    var targetLatitude = ""
    var targetLongitude = ""
    var targetName = "Destino del enlace"
    var watts = "100"
    var wattsSource = "Potencia TX manual; introduce un valor conocido o un supuesto explícito."
    var bandwidth = "2400"
    var requiredSNR = "10"
    var txGain = "0"
    var rxGain = "0"
    var frequencyMHz = "7.1"
    var r12 = ""
    private var r12Reference: Double?
    private var r12Description = "Introduce R12 o usa la circular mensual de ITU."
    var r12Source: String {
        if let value = number(r12), value != r12Reference { return "R12 introducido manualmente; comprueba su mes y procedencia." }
        return r12Description
    }
    var noise = 2
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
        didSet { UserDefaults.standard.set(terrainTargetLatitude, forKey: "terrainTargetLatitude"); invalidateTerrainLocation() }
    }
    var terrainTargetLongitude = UserDefaults.standard.string(forKey: "terrainTargetLongitude") ?? "" {
        didSet { UserDefaults.standard.set(terrainTargetLongitude, forKey: "terrainTargetLongitude"); invalidateTerrainLocation() }
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
            terrainCoverageBoundary = []; terrainCoverageReachByBearing = []
            terrainCoverageOriginElevationMeters = nil
            terrainCoverageStatus = "El alcance de cobertura se calcula solo al pulsar Calcular zona."
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
    var terrainCoverageBoundary: [RadioLocation] = []
    var terrainCoverageReachByBearing: [Double] = []
    var terrainCoverageOriginElevationMeters: Double?
    var terrainCoverageBusy = false
    var terrainCoverageCompletedBearings = 0
    var terrainCoverageStatus = "El alcance de cobertura se calcula solo al pulsar Calcular zona."
    var terrainOrigin: RadioLocation? { RadioLocation(latitude: terrainOriginLatitude, longitude: terrainOriginLongitude) }
    var terrainTarget: RadioLocation? { RadioLocation(latitude: terrainTargetLatitude, longitude: terrainTargetLongitude) }
    private let service = SpaceWeatherService()
    private let ionosondeService = IonosondeService()
    private let noaaForecastService = NoaaThreeDayForecastService()
    private let pskReporterService = PSKReporterService()
    private let engine = HFPropagationEngine()
    private let terrainService = TerrainElevationService()
    private let terrainEngine = TerrainITMEngine()
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
    private func invalidateTerrainResult() {
        let hadResult = terrainResult != nil || !terrainCoverageBoundary.isEmpty
        terrainResult = nil
        terrainCoverageBoundary = []; terrainCoverageReachByBearing = []
        terrainCoverageOriginElevationMeters = nil
        terrainCoverageStatus = "Cambió un parámetro; vuelve a calcular la zona de cobertura."
        if hadResult { terrainStatus = "Cambió un parámetro desde el último cálculo; vuelve a calcular el enlace." }
    }

    func runAutoRefresh() async {
        if !activated {
            activated = true
            weather = await service.cached() ?? SpaceWeatherSnapshot()
            ionosphere = await ionosondeService.cached()
            noaaForecast = await noaaForecastService.cached()
            await refresh()
        }
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(60)) } catch { return }
            if lastAttempt.map({ Date().timeIntervalSince($0) >= 180 }) ?? true { await refresh() }
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
        weatherStatus = sourceErrors.isEmpty ? "Actualización automática: NOAA cada 3 min, Band Info cada 1 h, R12 cada 24 h." : "Hay fuentes sin actualizar. Se conservan las fechas; NOAA reintenta en 3 min y Band Info en 1 h."
    }
    func useITUIndex(at date: Date) {
        guard let index = weather.index(at: date) else {
            r12Description = "No hay R12 de ITU para este mes en la copia disponible. Puedes introducirlo manualmente."; return
        }
        r12 = String(index.r12)
        r12Reference = index.r12
        r12Description = "ITU · \(index.id) · \(index.predicted ? "pronosticado" : "observado suavizado") · consulta \(weather.indicesFetchedAt?.formatted(date: .abbreviated, time: .shortened) ?? "sin fecha")"
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
    func useSelectedStation(_ guide: BroadcastStore) {
        guard let id = guide.selectedID, let snapshot = guide.snapshot,
              let entry = snapshot.entries.first(where: { $0.id == id }), let site = snapshot.reference.site(for: entry) else {
            calculationError = "Selecciona una emisora con coordenadas resueltas en la Guía de radios."; return
        }
        targetLatitude = String(site.latitude); targetLongitude = String(site.longitude)
        targetName = "\(entry.station) · \(site.name)"
        frequencyMHz = String(entry.frequencyKHz / 1000)
        if let transmission = guide.hfccMatch(for: entry), let scheduledWatts = transmission.scheduledPowerWatts {
            watts = String(Int(scheduledWatts))
            wattsSource = "\(transmission.powerKW ?? 0) kW declarados en HFCC para esta frecuencia y horario; no es potencia medida ni ERP."
            switch transmission.modulationCode.uppercased() {
            case "D": bandwidth = "9000"
            case "T": bandwidth = "2700"
            case "N": bandwidth = "10000"
            default: break
            }
        } else {
            watts = ""
            wattsSource = "HFCC no aporta una potencia inequívoca para esta emisora. Introduce un valor si lo conoces; no se asumirá 100 W."
        }
        listening = true
        calculationError = nil
    }
    func input(origin: RadioLocation?, date: Date) -> HFPropagationInput? {
        guard let origin, let target = RadioLocation(latitude: targetLatitude, longitude: targetLongitude),
              let r = number(r12), let p = number(watts), let bw = number(bandwidth), let snr = number(requiredSNR),
              let tx = number(txGain), let rx = number(rxGain), let f = number(frequencyMHz) else { return nil }
        let input = HFPropagationInput(origin: listening ? target : origin, target: listening ? origin : target, date: date, r12: r, watts: p, bandwidth: bw, requiredSNR: snr, txGain: tx, rxGain: rx, noise: noise, frequencyMHz: f)
        return input.isValid ? input : nil
    }
    func calculate(origin: RadioLocation?, date: Date) {
        guard let input = input(origin: origin, date: date) else {
            calculationError = "Completa ubicación y destino separados al menos 10 km, 1–1.000.000 W, 1,6–30 MHz, R12 1–311, ancho 1–100.000 Hz y SNR −30 a 100 dB. Ganancias: −40 a 40 dBi."; return
        }
        cancelCalculation(); calculationBusy = true; calculationError = nil
        let token = generation
        calculationTask = Task {
            do {
                let result = try await engine.predict(input)
                guard token == generation else { return }
                report = result
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
        terrainBusy = true
        terrainResult = nil
        terrainStatus = "Descargando perfil de terreno Copernicus GLO-90 en lotes de hasta 100 puntos…"
        defer { terrainBusy = false }
        do {
            let profile = try await terrainService.download(from: origin, to: target)
            terrainProfile = profile
            terrainStatus = "Perfil recibido: \(profile.points.count) puntos · relieve \(Int(profile.terrainReliefMeters ?? 0)) m · Open-Meteo/Copernicus GLO-90. Ejecutando NTIA ITM…"
            let input = TerrainITMInput(frequencyMHz: frequency, txHeightMeters: txHeight, rxHeightMeters: rxHeight,
                                        climate: terrainClimate, verticalPolarization: terrainVerticalPolarization,
                                        transmitWatts: watts, txGainDBi: txGain, rxGainDBi: rxGain)
            let result = try await terrainEngine.predict(input: input, profile: profile)
            terrainResult = result
            let margin = result.receivedPowerDBm - sensitivity
            terrainStatus = "NTIA ITM · \(result.distanceKm.formatted(.number.precision(.fractionLength(1)))) km · margen estimado \(margin >= 0 ? "+" : "")\(margin.formatted(.number.precision(.fractionLength(1)))) dB frente al umbral RX · perfil actualizado \(profile.fetchedAt.formatted(date: .abbreviated, time: .shortened))."
        } catch {
            terrainStatus = "No se pudo calcular con terreno: \(error.localizedDescription)"
        }
    }
    func calculateTerrainCoverage() async {
        guard !terrainBusy, !terrainCoverageBusy else { return }
        guard let origin = terrainOrigin,
              let txHeight = number(txHeight), let rxHeight = number(rxHeight),
              let frequency = number(terrainFrequencyMHz), let watts = number(terrainWatts),
              let txGain = number(terrainTxGain), let rxGain = number(terrainRxGain),
              let sensitivity = number(terrainSensitivityDBm), let maximumKm = number(terrainCoverageMaximumKm),
              (0.5...3_000).contains(txHeight), (0.5...3_000).contains(rxHeight),
              (20...20_000).contains(frequency), (0.001...1_000_000).contains(watts),
              (-40...60).contains(txGain), (-40...60).contains(rxGain), (-200...0).contains(sensitivity),
              (20...200).contains(maximumKm) else {
            terrainCoverageStatus = "Completa origen, alturas, potencia, ganancias, umbral y un radio de 20–200 km."
            return
        }
        terrainCoverageBusy = true
        terrainCoverageBoundary = []; terrainCoverageReachByBearing = []; terrainCoverageCompletedBearings = 0
        terrainCoverageOriginElevationMeters = nil
        terrainCoverageStatus = "Consultando perfiles de relieve y modelando 32 rumbos con pasos de hasta 5 km…"
        defer { terrainCoverageBusy = false }

        let input = TerrainITMInput(frequencyMHz: frequency, txHeightMeters: txHeight, rxHeightMeters: rxHeight,
                                    climate: terrainClimate, verticalPolarization: terrainVerticalPolarization,
                                    transmitWatts: watts, txGainDBi: txGain, rxGainDBi: rxGain)
        let stepCount = max(2, Int(ceil(maximumKm / 5)))
        var reaches = Array(repeating: 0.0, count: TerrainCoverageGeometry.bearingCount)
        var failedBearings = 0
        for bearingIndex in 0..<TerrainCoverageGeometry.bearingCount {
            guard let endpoint = origin.destination(km: maximumKm, bearing: Double(bearingIndex) * 360 / Double(TerrainCoverageGeometry.bearingCount)) else {
                failedBearings += 1; terrainCoverageCompletedBearings += 1; continue
            }
            do {
                let fullProfile = try await terrainService.download(from: origin, to: endpoint)
                if terrainCoverageOriginElevationMeters == nil {
                    terrainCoverageOriginElevationMeters = fullProfile.points.first?.elevationMeters
                }
                for step in 1...stepCount {
                    let testDistance = maximumKm * Double(step) / Double(stepCount)
                    let pathPoints = fullProfile.points.prefix {
                        origin.distance(to: $0.location) <= testDistance + fullProfile.resolutionMeters / 2_000
                    }
                    guard pathPoints.count >= 3, let end = pathPoints.last?.location else { continue }
                    let candidate = TerrainProfile(origin: origin, target: end, points: Array(pathPoints),
                                                   fetchedAt: fullProfile.fetchedAt, resolutionMeters: fullProfile.resolutionMeters)
                    let result = try await terrainEngine.predict(input: input, profile: candidate)
                    if result.receivedPowerDBm >= sensitivity { reaches[bearingIndex] = candidate.distanceKm }
                }
            } catch {
                failedBearings += 1
            }
            terrainCoverageCompletedBearings = bearingIndex + 1
            terrainCoverageStatus = "Zona ITM · rumbo \(bearingIndex + 1) de \(TerrainCoverageGeometry.bearingCount) · paso radial ≤ 5 km · \(Int(maximumKm)) km máx."
        }
        terrainCoverageReachByBearing = reaches
        terrainCoverageBoundary = TerrainCoverageGeometry.boundary(from: origin, reachByBearingKm: reaches)
        let modeled = TerrainCoverageGeometry.bearingCount - failedBearings
        let reaching = reaches.filter { $0 > 0 }.count
        if modeled == 0 {
            terrainCoverageStatus = "No se pudo modelar la zona: fallaron los 32 perfiles radiales. Revisa la conexión e inténtalo de nuevo."
        } else if reaching == 0 {
            terrainCoverageStatus = "Ninguno de los \(modeled) rumbos modelados superó el umbral RX de \(sensitivity.formatted(.number.precision(.fractionLength(0)))) dBm hasta \(Int(maximumKm)) km.\(failedBearings > 0 ? " Fallaron \(failedBearings) consultas." : "")"
        } else {
            let farthest = reaches.max() ?? 0
            terrainCoverageStatus = "Envolvente ITM orientativa · \(reaching)/\(modeled) rumbos superan el umbral RX · alcance máximo estimado \(farthest.formatted(.number.precision(.fractionLength(0)))) km.\(failedBearings > 0 ? " \(failedBearings) rumbos no respondieron." : "")"
        }
    }
    func number(_ value: String) -> Double? {
        guard let n = Double(value.replacingOccurrences(of: ",", with: ".")), n.isFinite else { return nil }
        return n
    }
    var horizon: Double? {
        guard let tx = number(txHeight), let rx = number(rxHeight), tx <= 10_000, rx <= 10_000 else { return nil }
        return RadioLinkBudget.horizonKm(txHeight: tx, rxHeight: rx)
    }
    var terrainHorizon: Double? {
        guard let tx = number(txHeight), let rx = number(rxHeight), tx <= 10_000, rx <= 10_000 else { return nil }
        let txGround = terrainProfile.flatMap { $0.origin == terrainOrigin ? $0.points.first?.elevationMeters : nil }
            ?? terrainCoverageOriginElevationMeters ?? 0
        let rxGround = terrainProfile.flatMap { $0.target == terrainTarget ? $0.points.last?.elevationMeters : nil } ?? 0
        return RadioLinkBudget.horizonKm(txHeight: max(0, txGround + tx), rxHeight: max(0, rxGround + rx))
    }
}
