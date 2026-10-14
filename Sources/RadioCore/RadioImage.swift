import Foundation

public enum SSTVColorRange: String, CaseIterable, Identifiable, Codable, Sendable {
    case bt601 = "BT.601 · limitado", full = "Completo"
    public var id: String { rawValue }
}

public enum SSTVFormat: String, CaseIterable, Identifiable, Codable, Sendable {
    case automatic = "Auto VIS"
    case martinM1 = "Martin M1", martinM2 = "Martin M2", martinM3 = "Martin M3", martinM4 = "Martin M4"
    case scottieS1 = "Scottie S1", scottieS2 = "Scottie S2", scottieS3 = "Scottie S3", scottieS4 = "Scottie S4", scottieDX = "Scottie DX"
    case pd50 = "PD50", pd90 = "PD90", pd120 = "PD120", pd160 = "PD160", pd180 = "PD180", pd240 = "PD240", pd290 = "PD290"
    case robot36 = "Robot 36", robot72 = "Robot 72"
    case pasokonP3 = "Pasokon P3", pasokonP5 = "Pasokon P5", pasokonP7 = "Pasokon P7", wraase180 = "Wraase SC2-180"
    case mp73 = "MP73", mp115 = "MP115", mp140 = "MP140", mp175 = "MP175"
    case mr73 = "MR73", mr90 = "MR90", mr115 = "MR115", mr140 = "MR140", mr175 = "MR175"
    case ml180 = "ML180", ml240 = "ML240", ml280 = "ML280", ml320 = "ML320"
    case mp73N = "MP73-N", mp110N = "MP110-N", mp140N = "MP140-N"
    case mc110N = "MC110-N", mc140N = "MC140-N", mc180N = "MC180-N"
    public var id: String { rawValue }
    public var isNarrow: Bool { descriptor?.identification == .narrow24 }
}

struct SSTVDescriptor {
    enum Family: Equatable { case martin, scottie, pd, robot36, robot72, pasokon, wraase, mp, mrml, mcN }
    enum Identification: Equatable { case vis7, extended16, narrow24 }
    let family: Family
    let vis: Int
    let width: Int
    let height: Int
    let scan: Double
    let identification: Identification
    init(family: Family, vis: Int, width: Int, height: Int, scan: Double, identification: Identification = .vis7) {
        self.family = family; self.vis = vis; self.width = width; self.height = height
        self.scan = scan; self.identification = identification
    }
    var paired: Bool { family == .pd || family == .mp }
    var colorDifference: Bool { paired || family == .robot36 || family == .robot72 || family == .mrml }
    var black: Double { identification == .narrow24 ? 2044 : 1500 }
    var toneSpan: Double { identification == .narrow24 ? 256 : 800 }
    var initialSync: Double { family == .scottie ? 0.009 : 0 }
    // Scottie places its recurring line sync after the green and blue scans.
    // The 9 ms leading sync is separate and is represented by initialSync.
    var lineSyncOffset: Double { family == .scottie ? 0.003 + 2 * scan : 0 }
    var sync: Double {
        switch family {
        case .martin: 0.004862
        case .scottie, .robot36, .robot72, .mp, .mrml: 0.009
        case .mcN: 0.008
        case .pd: 0.020
        case .pasokon: vis == 113 ? 0.005208 : vis == 114 ? 0.007813 : 0.010417
        case .wraase: 0.0055225
        }
    }
    var porch: Double {
        switch family {
        case .pasokon: vis == 113 ? 0.001042 : vis == 114 ? 0.001563 : 0.002083
        case .mp, .mrml: 0.001
        case .mcN: 0.0005
        default: 0
        }
    }
    var period: Double {
        switch family {
        case .martin: 0.004862 + 0.000572 * 4 + scan * 3
        case .scottie: 0.009 + 0.0015 * 3 + scan * 3
        case .pd: 0.022080 + scan * 4
        case .robot36: 0.150
        case .robot72: 0.300
        case .pasokon: sync + porch * 4 + scan * 3
        case .wraase: 0.0060225 + scan * 3
        case .mp: 0.010 + scan * 4
        case .mrml: 0.0103 + scan * 2
        case .mcN: 0.0085 + scan * 3
        }
    }
    var windows: [(start: Double, duration: Double, plane: Int, rowOffset: Int)] {
        switch family {
        case .martin:
            return (0..<3).map { (0.005434 + Double($0) * (scan + 0.000572), scan, [1,2,0][$0], 0) }
        case .scottie:
            return [(0.0015,scan,1,0), (0.003 + scan,scan,2,0), (0.0135 + scan * 2,scan,0,0)]
        case .pasokon:
            return (0..<3).map { (sync + porch + Double($0) * (scan + porch), scan, $0, 0) }
        case .wraase:
            return (0..<3).map { (0.0060225 + Double($0) * scan, scan, $0, 0) }
        case .pd:
            return [(0.02208,scan,0,0), (0.02208+scan,scan,1,0), (0.02208+scan*2,scan,2,0), (0.02208+scan*3,scan,0,1)]
        case .robot36: return [(0.012,0.088,0,0), (0.106,0.044,1,0)]
        case .robot72: return [(0.012,0.138,0,0), (0.156,0.069,1,0), (0.231,0.069,2,0)]
        case .mp:
            return [(0.010,scan,0,0), (0.010+scan,scan,1,0), (0.010+scan*2,scan,2,0), (0.010+scan*3,scan,0,1)]
        case .mrml:
            return [(0.010,scan,0,0), (0.0101+scan,scan/2,1,0), (0.0102+scan*1.5,scan/2,2,0)]
        case .mcN:
            return (0..<3).map { (0.0085 + Double($0) * scan, scan, $0, 0) }
        }
    }
}

extension SSTVFormat {
    var descriptor: SSTVDescriptor? {
        switch self {
        case .automatic: nil
        case .martinM1: .init(family:.martin,vis:44,width:320,height:256,scan:0.146432)
        case .martinM2: .init(family:.martin,vis:40,width:320,height:256,scan:0.073216)
        case .martinM3: .init(family:.martin,vis:36,width:320,height:128,scan:0.146432)
        case .martinM4: .init(family:.martin,vis:32,width:320,height:128,scan:0.073216)
        case .scottieS1: .init(family:.scottie,vis:60,width:320,height:256,scan:0.138240)
        case .scottieS2: .init(family:.scottie,vis:56,width:320,height:256,scan:0.088064)
        case .scottieS3: .init(family:.scottie,vis:52,width:320,height:128,scan:0.138240)
        case .scottieS4: .init(family:.scottie,vis:48,width:320,height:128,scan:0.088064)
        case .scottieDX: .init(family:.scottie,vis:76,width:320,height:256,scan:0.345600)
        case .pd50: .init(family:.pd,vis:93,width:320,height:256,scan:0.091520)
        case .pd90: .init(family:.pd,vis:99,width:320,height:256,scan:0.170240)
        case .pd120: .init(family:.pd,vis:95,width:640,height:496,scan:0.121600)
        case .pd160: .init(family:.pd,vis:98,width:512,height:400,scan:0.195584)
        case .pd180: .init(family:.pd,vis:96,width:640,height:496,scan:0.183040)
        case .pd240: .init(family:.pd,vis:97,width:640,height:496,scan:0.244480)
        case .pd290: .init(family:.pd,vis:94,width:800,height:616,scan:0.228800)
        case .robot36: .init(family:.robot36,vis:8,width:320,height:240,scan:0.088)
        case .robot72: .init(family:.robot72,vis:12,width:320,height:240,scan:0.138)
        case .pasokonP3: .init(family:.pasokon,vis:113,width:640,height:496,scan:0.133333)
        case .pasokonP5: .init(family:.pasokon,vis:114,width:640,height:496,scan:0.200)
        case .pasokonP7: .init(family:.pasokon,vis:115,width:640,height:496,scan:0.266666)
        case .wraase180: .init(family:.wraase,vis:55,width:320,height:256,scan:0.235)
        case .mp73: .init(family:.mp,vis:0x2523,width:320,height:256,scan:0.140,identification:.extended16)
        case .mp115: .init(family:.mp,vis:0x2923,width:320,height:256,scan:0.223,identification:.extended16)
        case .mp140: .init(family:.mp,vis:0x2A23,width:320,height:256,scan:0.270,identification:.extended16)
        case .mp175: .init(family:.mp,vis:0x2C23,width:320,height:256,scan:0.340,identification:.extended16)
        case .mr73: .init(family:.mrml,vis:0x4523,width:320,height:256,scan:0.138,identification:.extended16)
        case .mr90: .init(family:.mrml,vis:0x4623,width:320,height:256,scan:0.171,identification:.extended16)
        case .mr115: .init(family:.mrml,vis:0x4923,width:320,height:256,scan:0.220,identification:.extended16)
        case .mr140: .init(family:.mrml,vis:0x4A23,width:320,height:256,scan:0.269,identification:.extended16)
        case .mr175: .init(family:.mrml,vis:0x4C23,width:320,height:256,scan:0.337,identification:.extended16)
        case .ml180: .init(family:.mrml,vis:0x8523,width:640,height:496,scan:0.1765,identification:.extended16)
        case .ml240: .init(family:.mrml,vis:0x8623,width:640,height:496,scan:0.2365,identification:.extended16)
        case .ml280: .init(family:.mrml,vis:0x8923,width:640,height:496,scan:0.2775,identification:.extended16)
        case .ml320: .init(family:.mrml,vis:0x8A23,width:640,height:496,scan:0.3175,identification:.extended16)
        case .mp73N: .init(family:.mp,vis:0x02,width:320,height:256,scan:0.140,identification:.narrow24)
        case .mp110N: .init(family:.mp,vis:0x04,width:320,height:256,scan:0.212,identification:.narrow24)
        case .mp140N: .init(family:.mp,vis:0x05,width:320,height:256,scan:0.270,identification:.narrow24)
        case .mc110N: .init(family:.mcN,vis:0x14,width:320,height:256,scan:0.143,identification:.narrow24)
        case .mc140N: .init(family:.mcN,vis:0x15,width:320,height:256,scan:0.180,identification:.narrow24)
        case .mc180N: .init(family:.mcN,vis:0x16,width:320,height:256,scan:0.232,identification:.narrow24)
        }
    }
}

public struct RadioImage: Sendable {
    public let width: Int
    public let height: Int
    public let rgb: [UInt8]
    public let caption: String
    public init(width: Int, height: Int, rgb: [UInt8], caption: String) {
        self.width = width; self.height = height; self.rgb = rgb; self.caption = caption
    }
}
