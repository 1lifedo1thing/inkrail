import Foundation

/// Stable, persisted identifiers. These are original Inkrail material designs.
public enum MechanismStyle: String, Codable, CaseIterable, Sendable {
    case classic, brushedSteel, champagne, walnut, porcelain, midnight
    case roseQuartz, seaGlass, lavender, racingGreen, copper, wildflower

    public var label: String {
        switch self {
        case .classic: return "Classic"
        case .brushedSteel: return "Brushed Steel"
        case .champagne: return "Champagne"
        case .walnut: return "Walnut"
        case .porcelain: return "Porcelain"
        case .midnight: return "Midnight"
        case .roseQuartz: return "Rose Quartz"
        case .seaGlass: return "Sea Glass"
        case .lavender: return "Lavender"
        case .racingGreen: return "Racing Green"
        case .copper: return "Copper"
        case .wildflower: return "Wildflower"
        }
    }

    public var subtitle: String {
        switch self {
        case .classic: return "The original capsule"
        case .brushedSteel: return "Satin metal · fine ribs"
        case .champagne: return "Soft gold · Art Deco"
        case .walnut: return "Wood grain · brass"
        case .porcelain: return "Ivory glaze · sage"
        case .midnight: return "Graphite · gold inlay"
        case .roseQuartz: return "Blush stone · pearl veins"
        case .seaGlass: return "Frosted teal · silver"
        case .lavender: return "Lilac enamel · soft shine"
        case .racingGreen: return "Deep green · ivory stripes"
        case .copper: return "Hammered metal · patina"
        case .wildflower: return "Cream enamel · tiny blooms"
        }
    }

    public var material: MechanismMaterial {
        switch self {
        case .classic:
            return .init(bodyColors: [0xE5E2D6, 0xD2CFC4, 0xB5B2A8], trim: 0x68705D,
                         cornerRadius: 22, texture: .none, preferredRail: .steel)
        case .brushedSteel:
            return .init(bodyColors: [0xE2E7E6, 0xB5BFBE, 0x899594, 0xC6CECC, 0x677270], trim: 0x4D5B58,
                         cornerRadius: 9, texture: .brushed, preferredRail: .steel)
        case .champagne:
            return .init(bodyColors: [0xF4E3B8, 0xCDB580, 0xAD8F54, 0xD9C394, 0x8A6D3C], trim: 0x725834,
                         cornerRadius: 16, texture: .brushed, preferredRail: .brass)
        case .walnut:
            return .init(bodyColors: [0x927052, 0x6F4D33, 0x503320, 0x6F4B32, 0x382416], trim: 0xCEB57B,
                         cornerRadius: 11, texture: .wood, preferredRail: .brass)
        case .porcelain:
            return .init(bodyColors: [0xFFFEF7, 0xF1EDE0, 0xE5DFD0, 0xF8F4E9, 0xC6C0AF], trim: 0x7D8D78,
                         cornerRadius: 23, texture: .ceramic, preferredRail: .charcoal)
        case .midnight:
            return .init(bodyColors: [0x4A504F, 0x303635, 0x222826, 0x323837, 0x151B19], trim: 0xCBB67C,
                         cornerRadius: 8, texture: .matte, preferredRail: .charcoal)
        case .roseQuartz:
            return .init(bodyColors: [0xFAE7E6, 0xE7BDBF, 0xD19B9F, 0xF0CBCC, 0xA66F79], trim: 0xA07063,
                         cornerRadius: 22, texture: .mineral, preferredRail: .brass)
        case .seaGlass:
            return .init(bodyColors: [0xCCE9DD, 0x83B8A8, 0x538E82, 0xA8D0BD, 0x34675F], trim: 0xC6DBD3,
                         cornerRadius: 20, texture: .frosted, preferredRail: .steel)
        case .lavender:
            return .init(bodyColors: [0xEEE5F5, 0xC7B4D9, 0xA18AB9, 0xD4C2E5, 0x7C6994], trim: 0xECE7EB,
                         cornerRadius: 18, texture: .enamel, preferredRail: .steel)
        case .racingGreen:
            return .init(bodyColors: [0x5B7968, 0x274E3C, 0x18372A, 0x3B614D, 0x11281E], trim: 0xC7AC70,
                         cornerRadius: 10, texture: .enamel, preferredRail: .brass)
        case .copper:
            return .init(bodyColors: [0xF0C7A4, 0xC68A60, 0x9D5E3C, 0xD59A73, 0x6F412D], trim: 0x416F64,
                         cornerRadius: 13, texture: .hammered, preferredRail: .charcoal)
        case .wildflower:
            return .init(bodyColors: [0xFFF7DF, 0xE9DFC1, 0xD4C7A5, 0xF4EACF, 0xB4A685], trim: 0x657D61,
                         cornerRadius: 21, texture: .ceramic, preferredRail: .brass)
        }
    }

    /// Unknown future styles degrade to Classic without discarding all preferences.
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value) ?? .classic
    }
}

public enum MechanismTexture: String, Sendable {
    case none, brushed, wood, ceramic, matte
    case mineral, frosted, enamel, hammered
}

/// Foundation-only design tokens, shared by native rendering and model tests.
public struct MechanismMaterial: Equatable, Sendable {
    public let bodyColors: [UInt32]
    public let trim: UInt32
    public let cornerRadius: Double
    public let texture: MechanismTexture
    public let preferredRail: RailFinish

    // Every housing occupies the original footprint. The lamp and hammer stay
    // aligned with the true caret; switching designs must not alter editing.
    public static let housingWidth: Double = 110
    public static let housingHeight: Double = 46
}

extension WritingPreferences {
    public var effectiveRailFinish: RailFinish {
        guard mechanismStyle != .classic, matchRailToStyle else { return rail }
        return mechanismStyle.material.preferredRail
    }
}
