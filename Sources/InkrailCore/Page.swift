import Foundation

public struct Page: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public var modifiedAt: Date
    public var text: String

    public init(id: UUID = UUID(), createdAt: Date = Date(), modifiedAt: Date? = nil, text: String = "") {
        self.id = id
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt ?? createdAt
        self.text = text
    }

    public var title: String {
        let first = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? "Untitled letter"
        return String(first.prefix(64))
    }

    public var preview: String {
        String(text.replacingOccurrences(of: "\n", with: " ").prefix(140))
    }

    public var wordCount: Int { text.split(whereSeparator: \.isWhitespace).count }
    public var characterCount: Int { text.count }

    public var exportName: String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r\t")
        let cleaned = title.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.init(charactersIn: ".")))
        return cleaned.isEmpty ? "Untitled letter" : String(cleaned.prefix(64))
    }
}

public enum PaperKind: String, Codable, CaseIterable, Sendable {
    case ivory, cream, white
    public var label: String { rawValue.capitalized }
}
/// Stable identifiers for where a letter's first writing line begins.
public enum PaperStartPosition: String, Codable, CaseIterable, Identifiable, Sendable {
    case top, bottom

    public var id: String { rawValue }
    public var label: String { rawValue.capitalized }

    /// Unknown future positions keep the established top-starting layout.
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value) ?? .top
    }
}
public enum CapsuleFinish: String, Codable, CaseIterable, Sendable {
    case porcelain, sage, cobalt, terracotta, graphite
    public var label: String { rawValue.capitalized }
}
public enum RailFinish: String, Codable, CaseIterable, Sendable {
    case steel, brass, charcoal
    public var label: String { rawValue.capitalized }
}
public enum RibbonColor: String, Codable, CaseIterable, Sendable {
    case carbon, midnight, oxblood
    public var label: String { rawValue.capitalized }
}

/// Global preferences. Additive keys retain the existing v1 storage location.
public struct WritingPreferences: Codable, Equatable, Sendable {
    public var mechanismStyle: MechanismStyle = .classic
    public var matchRailToStyle: Bool = true
    public var paper: PaperKind = .ivory
    public var paperStartPosition: PaperStartPosition = .top
    public var paperMotion: PaperMotion = .sheet
    public var paperTexture: PaperTexture = .classic
    public var textureStrength: Double = 0.55
    public var paperEmbossing: PaperEmbossing = .none
    public var embossingDepth: Double = 0.45
    public var capsule: CapsuleFinish = .porcelain
    public var rail: RailFinish = .steel
    public var ribbon: RibbonColor = .carbon
    public var fontSize: Double = 20
    public var writingFont: WritingFont = .courier
    public var inkStrength: Double = 0.88
    public var wornInk: Bool = true
    public var inkBuildup: Double = 0.55
    public var wideMargins: Bool = true
    public var curvedPaper: Bool = true
    public var garden: Bool = false
    public var deskFinish: DeskFinish = .charcoal
    public var deskAccent: DeskAccent = .none
    public var widerFocusPaper: Bool = true
    public var soundEnabled: Bool = true
    public var soundVolume: Double = 0.30
    public var typewriterSound: TypewriterSound = .classic
    public var nightMode: Bool = false
    public var lampIntensity: Double = 0.82
    public var lampWarmth: Double = 0.65
    public init() {}

    /// Paper motion changes drawing and feed timing, never the chosen
    /// starting position. Both Sheet and Roll honor Top and Bottom.
    public var effectivePaperStartPosition: PaperStartPosition {
        paperStartPosition
    }

    private enum CodingKeys: String, CodingKey {
        case mechanismStyle
        case matchRailToStyle
        case paper
        case paperStartPosition
        case paperMotion
        case paperTexture
        case textureStrength
        case paperEmbossing
        case embossingDepth
        case capsule
        case rail
        case ribbon
        case fontSize
        case writingFont
        case inkStrength
        case wornInk
        case inkBuildup
        case wideMargins
        case curvedPaper
        case garden
        case deskFinish
        case deskAccent
        case widerFocusPaper
        case soundEnabled
        case soundVolume
        case typewriterSound
        case nightMode
        case lampIntensity
        case lampWarmth
    }

    /// Decode additive fields independently so new layout or style options never
    /// reset the user's existing paper, sound or lamp preferences.
    public init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        mechanismStyle = try values.decodeIfPresent(MechanismStyle.self, forKey: .mechanismStyle) ?? mechanismStyle
        matchRailToStyle = try values.decodeIfPresent(Bool.self, forKey: .matchRailToStyle) ?? matchRailToStyle
        paper = try values.decodeIfPresent(PaperKind.self, forKey: .paper) ?? paper
        paperStartPosition = try values.decodeIfPresent(PaperStartPosition.self, forKey: .paperStartPosition) ?? paperStartPosition
        paperMotion = try values.decodeIfPresent(PaperMotion.self, forKey: .paperMotion) ?? paperMotion
        paperTexture = try values.decodeIfPresent(PaperTexture.self, forKey: .paperTexture) ?? paperTexture
        textureStrength = try values.decodeIfPresent(Double.self, forKey: .textureStrength) ?? textureStrength
        paperEmbossing = try values.decodeIfPresent(PaperEmbossing.self, forKey: .paperEmbossing) ?? paperEmbossing
        embossingDepth = try values.decodeIfPresent(Double.self, forKey: .embossingDepth) ?? embossingDepth
        capsule = try values.decodeIfPresent(CapsuleFinish.self, forKey: .capsule) ?? capsule
        rail = try values.decodeIfPresent(RailFinish.self, forKey: .rail) ?? rail
        ribbon = try values.decodeIfPresent(RibbonColor.self, forKey: .ribbon) ?? ribbon
        fontSize = try values.decodeIfPresent(Double.self, forKey: .fontSize) ?? fontSize
        writingFont = try values.decodeIfPresent(WritingFont.self, forKey: .writingFont) ?? writingFont
        inkStrength = try values.decodeIfPresent(Double.self, forKey: .inkStrength) ?? inkStrength
        wornInk = try values.decodeIfPresent(Bool.self, forKey: .wornInk) ?? wornInk
        inkBuildup = try values.decodeIfPresent(Double.self, forKey: .inkBuildup) ?? inkBuildup
        wideMargins = try values.decodeIfPresent(Bool.self, forKey: .wideMargins) ?? wideMargins
        curvedPaper = try values.decodeIfPresent(Bool.self, forKey: .curvedPaper) ?? curvedPaper
        garden = try values.decodeIfPresent(Bool.self, forKey: .garden) ?? garden
        deskFinish = try values.decodeIfPresent(DeskFinish.self, forKey: .deskFinish) ?? deskFinish
        deskAccent = try values.decodeIfPresent(DeskAccent.self, forKey: .deskAccent) ?? deskAccent
        widerFocusPaper = try values.decodeIfPresent(Bool.self, forKey: .widerFocusPaper) ?? widerFocusPaper
        soundEnabled = try values.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? soundEnabled
        soundVolume = try values.decodeIfPresent(Double.self, forKey: .soundVolume) ?? soundVolume
        typewriterSound = try values.decodeIfPresent(TypewriterSound.self, forKey: .typewriterSound) ?? typewriterSound
        nightMode = try values.decodeIfPresent(Bool.self, forKey: .nightMode) ?? nightMode
        lampIntensity = try values.decodeIfPresent(Double.self, forKey: .lampIntensity) ?? lampIntensity
        lampWarmth = try values.decodeIfPresent(Double.self, forKey: .lampWarmth) ?? lampWarmth
        clamp()
    }

    public mutating func clamp() {
        textureStrength = min(1, max(0, textureStrength.isFinite ? textureStrength : 0.55))
        embossingDepth = min(1, max(0, embossingDepth.isFinite ? embossingDepth : 0.45))
        fontSize = min(28, max(15, fontSize.isFinite ? fontSize : 20))
        inkStrength = min(1, max(0.35, inkStrength.isFinite ? inkStrength : 0.88))
        inkBuildup = min(1, max(0, inkBuildup.isFinite ? inkBuildup : 0.55))
        soundVolume = min(1, max(0, soundVolume.isFinite ? soundVolume : 0.30))
        lampIntensity = min(1, max(0.25, lampIntensity.isFinite ? lampIntensity : 0.82))
        lampWarmth = min(1, max(0, lampWarmth.isFinite ? lampWarmth : 0.65))
    }
}
