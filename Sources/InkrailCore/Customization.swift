/// Stable persisted choices for paper treatments and local fonts/sounds.
public enum PaperMotion: String, Codable, CaseIterable, Identifiable, Sendable {
    case sheet, roll

    public var id: String { rawValue }
    public var label: String { self == .sheet ? "Sheet" : "Paper roll" }

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value) ?? WritingPreferences.defaults.paperMotion
    }
}

public enum PaperTexture: String, Codable, CaseIterable, Identifiable, Sendable {
    case classic, smooth, laid, cotton

    public var id: String { rawValue }
    public var label: String { rawValue.capitalized }
    public var subtitle: String {
        switch self {
        case .classic: return "The original fine grain"
        case .smooth: return "A clean, even surface"
        case .laid: return "Fine lines in the paper"
        case .cotton: return "Soft, irregular fibres"
        }
    }
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value) ?? .classic
    }
}

public enum PaperMarginStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, botanical, ledger, artDeco, celestial

    public var id: String { rawValue }
    public var label: String { self == .artDeco ? "Art Deco" : rawValue.capitalized }

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value) ?? .none
    }
}

public enum PaperEmbossing: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, botanical, monogram, sunburst, makerMark

    public var id: String { rawValue }
    public var label: String { self == .makerMark ? "Maker’s mark" : rawValue.capitalized }
    public var subtitle: String {
        switch self {
        case .none: return "Unmarked paper"
        case .botanical: return "A quiet botanical impression"
        case .monogram: return "A small Inkrail imprint"
        case .sunburst: return "A subtle radiating seal"
        case .makerMark: return "The carriage initials pressed into paper"
        }
    }
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value) ?? WritingPreferences.defaults.paperEmbossing
    }
}

public enum WritingFont: String, Codable, CaseIterable, Identifiable, Sendable {
    case courier, americanTypewriter, menlo, georgia
    case courierNew = "courierNew"
    case typewriterLight = "typewriterLight"
    case typewriterCondensed = "typewriterCondensed"
    case monaco = "monaco"

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .courier: return "Courier"
        case .americanTypewriter: return "American Typewriter"
        case .menlo: return "Menlo"
        case .georgia: return "Georgia"
        case .courierNew: return "Courier New"
        case .typewriterLight: return "Typewriter Light"
        case .typewriterCondensed: return "Typewriter Condensed"
        case .monaco: return "Monaco"
        }
    }
    public var subtitle: String {
        switch self {
        case .courier: return "Classic monospaced serif"
        case .americanTypewriter: return "Rounded typewriter serif"
        case .menlo: return "Clean monospaced text"
        case .georgia: return "Warm, readable serif"
        case .courierNew: return "Fine, familiar typewriter serif"
        case .typewriterLight: return "Airy American Typewriter"
        case .typewriterCondensed: return "Narrow American Typewriter"
        case .monaco: return "Compact, rounded monospaced text"
        }
    }
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value) ?? .courier
    }
}

public enum TypewriterSound: String, Codable, CaseIterable, Identifiable, Sendable {
    case classic, soft, royal, vintage, portable, electric

    public var id: String { rawValue }
    public var label: String { rawValue.capitalized }
    public var subtitle: String {
        switch self {
        case .classic: return "Loud Hermes Precisa 305 manual clacks"
        case .soft: return "Damped Hermes 3000 keys"
        case .royal: return "Royal Quiet De Luxe keys and carriage"
        case .vintage: return "Clatter from a 1930s manual"
        case .portable: return "Hermes Baby keys and carriage"
        case .electric: return "Powered IBM Selectric II strikes"
        }
    }
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "office": self = .royal
        case "crisp": self = .vintage
        default: self = Self(rawValue: value) ?? .classic
        }
    }
}
