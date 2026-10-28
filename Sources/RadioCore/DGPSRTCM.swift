import Foundation

/// A received RTCM 2 frame. Every word has passed chained IS-GPS parity.
/// These are broadcast observations, not a corrected position or a navigation solution.
public struct DGPSReception: Codable, Equatable, Sendable {
    public let sampleOffsetSeconds: Double
    public let bitRate: Int
    public let stationID: Int
    public let messageType: Int
    public let zCountSeconds: Double
    public let sequence: Int
    public let stationHealth: Int
    /// Recovered 24-bit data words, excluding the two headers and six parity bits.
    public let payloadWords: [UInt32]

    public var specialMessage: String? {
        guard messageType == 16 || messageType == 36 else { return nil }
        var bytes = payloadWords.flatMap { [UInt8(($0 >> 16) & 255), UInt8(($0 >> 8) & 255), UInt8($0 & 255)] }
        while bytes.last == 0 { bytes.removeLast() }
        return bytes.map { byte in
            if byte == 10 || byte == 13 || byte == 9 || (32...126).contains(byte) { return String(UnicodeScalar(byte)) }
            return String(format: "\\x%02X", byte)
        }.joined()
    }

    public var corrections: [DGPSCorrection] {
        guard messageType == 1 || messageType == 9 else { return [] }
        let bits = DGPSPayloadBits(words: payloadWords)
        return stride(from: 0, through: max(-1, bits.count - 40), by: 40).map { start in
            let scale = bits.unsigned(start, 1) == 0 ? 1.0 : 16.0
            let prn = bits.unsigned(start + 3, 5)
            return DGPSCorrection(satelliteID: prn == 0 ? 32 : prn,
                                  udre: bits.unsigned(start + 1, 2),
                                  issueOfData: bits.unsigned(start + 32, 8),
                                  pseudorangeMeters: Double(bits.signed(start + 8, 16)) * 0.02 * scale,
                                  rangeRateMetersPerSecond: Double(bits.signed(start + 24, 8)) * 0.002 * scale)
        }
    }

    /// Type 3/32 reports the reference station's ECEF position, never the listener's.
    /// The display uses a WGS84 ellipsoid approximation. The transmitted datum is
    /// not confirmed here (type32 can refer to PE-90); do not use this as surveyed
    /// WGS84 coordinates or silently substitute it for a receiver location.
    public var referencePosition: DGPSReferencePosition? {
        guard (messageType == 3 || messageType == 32), payloadWords.count >= 4 else { return nil }
        let x = Double(Int32(bitPattern: payloadWords[0] << 8 | payloadWords[1] >> 16)) * 0.01
        let y = Double(Int32(bitPattern: (payloadWords[1] & 0xffff) << 16 | payloadWords[2] >> 8)) * 0.01
        let z = Double(Int32(bitPattern: (payloadWords[2] & 255) << 24 | payloadWords[3])) * 0.01
        return DGPSReferencePosition(ecefX: x, ecefY: y, ecefZ: z)
    }

    public var monitorLine: String {
        var line = String(format: "DGPS %d bit/s · RTCM2 tipo %d · estación %d · Z %.1f s GPS/GLONASS · secuencia %d · salud %d · %d palabras · paridad válida", bitRate, messageType, stationID, zCountSeconds, sequence, stationHealth, payloadWords.count)
        if stationHealth == 7 { line += " · ESTACIÓN NO OPERATIVA" }
        if stationHealth == 6 { line += " · transmisión sin supervisión" }
        if let specialMessage { line += "\n" + specialMessage }
        if let referencePosition {
            line += String(format: "\nReferencia TX aproximada (WGS84 asumido, datum no confirmado): %.6f°, %.6f° · altura elipsoidal %.1f m", referencePosition.latitude, referencePosition.longitude, referencePosition.ellipsoidHeightMeters)
        }
        for correction in corrections {
            line += String(format: "\nGPS %02d · PRC %.3f m · RRC %.3f m/s · IOD %d · UDRE %d", correction.satelliteID, correction.pseudorangeMeters, correction.rangeRateMetersPerSecond, correction.issueOfData, correction.udre)
        }
        if specialMessage == nil && referencePosition == nil && corrections.isEmpty && !payloadWords.isEmpty {
            line += "\nDatos: " + payloadWords.map { String(format: "%06X", $0) }.joined(separator: " ")
        }
        return line
    }
}

public struct DGPSCorrection: Codable, Equatable, Sendable {
    public let satelliteID: Int
    public let udre: Int
    public let issueOfData: Int
    public let pseudorangeMeters: Double
    public let rangeRateMetersPerSecond: Double
}

public struct DGPSReferencePosition: Codable, Equatable, Sendable {
    public let ecefX: Double, ecefY: Double, ecefZ: Double
    public let latitude: Double, longitude: Double, ellipsoidHeightMeters: Double

    init?(ecefX x: Double, ecefY y: Double, ecefZ z: Double) {
        let p = hypot(x, y), radius = hypot(p, z)
        // Reject malformed/undefined origins instead of placing a transmitter at 0°,0°.
        guard radius.isFinite, (5_000_000...7_000_000).contains(radius) else { return nil }
        ecefX = x; ecefY = y; ecefZ = z
        let a = 6_378_137.0, e2 = 6.6943799901413165e-3
        var lat = atan2(z, p * (1 - e2))
        for _ in 0..<8 {
            let n = a / sqrt(1 - e2 * sin(lat) * sin(lat))
            lat = atan2(z + e2 * n * sin(lat), p)
        }
        latitude = lat * 180 / .pi; longitude = atan2(y, x) * 180 / .pi
        let n = a / sqrt(1 - e2 * sin(lat) * sin(lat))
        ellipsoidHeightMeters = p > 0.001 ? p / cos(lat) - n : abs(z) - a * sqrt(1 - e2)
    }
}

private struct DGPSPayloadBits {
    let words: [UInt32]
    var count: Int { words.count * 24 }
    func unsigned(_ offset: Int, _ length: Int) -> Int {
        var result = 0
        for i in offset..<(offset + length) {
            result = (result << 1) | Int((words[i / 24] >> (23 - i % 24)) & 1)
        }
        return result
    }
    func signed(_ offset: Int, _ length: Int) -> Int {
        let value = unsigned(offset, length)
        return value & (1 << (length - 1)) == 0 ? value : value - (1 << length)
    }
}

/// Own implementation of IS-GPS-200N §20.3.5/Table 20-XIV equations.
/// https://www.navcen.uscg.gov/sites/default/files/pdf/gps/IS-GPS-200N.pdf
/// RTCM2 framing/layout: ITU-R M.823-3 Fig.1 and Annex1; no GPSD code is copied.
enum DGPSParity {
    // Bits31/30 are D29*/D30*. Bits29...6 are de-whitened d1...d24.
    static let masks: [UInt32] = [0xbb1f3480, 0x5d8f9a40, 0xaec7cd00, 0x5763e680, 0x6bb1f340, 0x8b7a89c0]
    static func recoveredData(_ wire: UInt32) -> UInt32? {
        let clear = wire & 0x40000000 == 0 ? wire : wire ^ 0x3fffffc0
        var parity: UInt32 = 0
        for mask in masks { parity = (parity << 1) | UInt32((clear & mask).nonzeroBitCount & 1) }
        return parity == wire & 63 ? (clear >> 6) & 0xffffff : nil
    }
}

/// Bounded, bit-oriented RTCM2 framing. Never publishes a partial or bad-parity frame.
struct DGPSRTCMReceiver {
    private struct Candidate {
        var words: [UInt32]
        var wordBits = 0
        var expectedWords = 0
    }
    private var shift: UInt32 = 0
    private var seen = 0
    private var candidates: [Candidate] = []
    private(set) var rejectedParity = 0

    mutating func reset() { shift = 0; seen = 0; candidates.removeAll(keepingCapacity: true) }

    mutating func push(bit: Bool, time: Double, bitRate: Int) -> DGPSReception? {
        shift = (shift << 1) | (bit ? 1 : 0)
        seen = min(32, seen + 1)
        guard seen == 32 else { return nil }
        // Search in parallel with the current candidate. An insertion/corrupt length
        // must not hide a later valid preamble while an incomplete frame is pending.
        // A payload preamble never destroys the original candidate.
        var completed: DGPSReception?
        for index in candidates.indices.reversed() {
            candidates[index].wordBits += 1
            guard candidates[index].wordBits == 30 else { continue }
            candidates[index].wordBits = 0
            guard let data = DGPSParity.recoveredData(shift) else {
                rejectedParity += 1; candidates.remove(at: index); continue
            }
            candidates[index].words.append(data)
            let words = candidates[index].words
            if words.count == 2 {
                let type = Int((words[0] >> 10) & 63), length = Int((data >> 3) & 31)
                let validLength = type == 6 ? length <= 1 : type == 34 || length > 0
                guard data >> 11 < 6000, validLength,
                      ![3, 32].contains(type) || length >= 4,
                      ![1, 9, 31].contains(type) || length >= 2 else {
                    candidates.remove(at: index); continue
                }
                candidates[index].expectedWords = length + 2
            }
            guard words.count == candidates[index].expectedWords else { continue }
            completed = DGPSReception(sampleOffsetSeconds: time, bitRate: bitRate,
                                       stationID: Int(words[0] & 1023), messageType: Int((words[0] >> 10) & 63),
                                       zCountSeconds: Double(words[1] >> 11) * 0.6,
                                       sequence: Int((words[1] >> 8) & 7), stationHealth: Int(words[1] & 7),
                                       payloadWords: Array(words.dropFirst(2)))
        }
        if let completed { candidates.removeAll(keepingCapacity: true); return completed }
        if let data = DGPSParity.recoveredData(shift), data >> 16 == 0x66, (data >> 10) & 63 != 0 {
            candidates.append(Candidate(words: [data]))
            if candidates.count > 4 { candidates.removeFirst() }
        }
        return nil
    }
}
