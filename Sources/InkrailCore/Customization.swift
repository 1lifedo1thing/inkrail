/// Stable persisted choices for paper treatments and local fonts/sounds.
public enum PaperMotion: String, Codable, CaseIterable, Identifiable, Sendable {
    case sheet, roll

    public var id: String { rawValue }
    public var label: String { self == .sheet ? "Sheet" : "Paper roll" }

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value) ?? .sheet
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

public enum PaperEmbossing: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, botanical, monogram, sunburst

    public var id: String { rawValue }
    public var label: String { rawValue.capitalized }
    public var subtitle: String {
        switch self {
        case .none: return "Unmarked paper"
        case .botanical: return "A quiet botanical impression"
        case .monogram: return "A small Inkrail imprint"
        case .sunburst: return "A subtle radiating seal"
        }
    }
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value) ?? .none
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
    case classic, soft, crisp, portable, office, electric

    public var id: String { rawValue }
    public var label: String { rawValue.capitalized }
    public var subtitle: String {
        switch self {
        case .classic: return "The original mechanical keys"
        case .soft: return "A quieter, softer touch"
        case .crisp: return "A bright, distinct strike"
        case .portable: return "Light, lively mechanical clatter"
        case .office: return "Weighty keys and a ringing bell"
        case .electric: return "A quick, precise powered snap"
        }
    }
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value) ?? .classic
    }
}
