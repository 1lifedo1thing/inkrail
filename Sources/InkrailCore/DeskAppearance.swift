/// Stable persisted choices for the space around the paper. Materials and
/// lighting retain the paper geometry, typewriter and stored letter contents.
public enum DeskFinish: String, Codable, CaseIterable, Identifiable, Sendable {
    case charcoal, walnut, felt, linen, oak, leather

    public var id: String { rawValue }
    public var label: String { self == .oak ? "Honey Oak" : rawValue.capitalized }
    public var subtitle: String {
        switch self {
        case .charcoal: return "The original quiet desk"
        case .walnut: return "Warm, understated wood grain"
        case .felt: return "A soft, muted green surface"
        case .linen: return "A fine, dark woven texture"
        case .oak: return "Warm honey wood with flowing grain"
        case .leather: return "Warm brown leather with a fine natural grain"
        }
    }

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value) ?? .charcoal
    }
}

public enum DeskAccent: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, sprig, paperclip, envelope, brassLamps, linenLamps

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .none: return "None"
        case .sprig: return "Botanical sprig"
        case .paperclip: return "Paperclip"
        case .envelope: return "Envelope"
        case .brassLamps: return "Paired bronze lamps"
        case .linenLamps: return "Paired linen lamps"
        }
    }
    public var subtitle: String {
        switch self {
        case .none: return "Leave the desk clear"
        case .sprig: return "A small branch beside the paper"
        case .paperclip: return "A quiet brass detail"
        case .envelope: return "A letter waiting at the edge"
        case .brassLamps: return "Two bronze shades with warm light along the paper"
        case .linenLamps: return "Two softly lit linen shades beside the page"
        }
    }

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value) ?? .none
    }
}

/// The paper is laid out at its actual width, never scaled. Keeping its height
/// and the established side inset leaves paper-feed and curl geometry intact.
public enum DeskLayout {
    public static let regularPaperWidth = 720.0
    public static let focusPaperWidth = 960.0
    public static let minimumSideInset = 52.0

    public static func paperWidth(windowWidth: Double, focusMode: Bool,
                                  widerFocusPaper: Bool) -> Double {
        // A 1pt drawable fallback handles invalid/subpoint sizes during setup.
        guard windowWidth.isFinite, windowWidth >= 1 else { return 1 }
        let maximum = focusMode && widerFocusPaper ? focusPaperWidth : regularPaperWidth
        return min(maximum, max(1, windowWidth - minimumSideInset * 2))
    }
}
