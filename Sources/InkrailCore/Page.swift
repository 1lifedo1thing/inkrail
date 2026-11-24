import Foundation

public struct TextEmphasis: OptionSet, Codable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let bold = Self(rawValue: 1 << 0)
    public static let italic = Self(rawValue: 1 << 1)
    public static let underline = Self(rawValue: 1 << 2)
    public static let strikethrough = Self(rawValue: 1 << 3)
    public static let code = Self(rawValue: 1 << 4)
}

/// A span in the letter's UTF-16 text, matching NSTextStorage coordinates.
public struct TextFormatRun: Codable, Equatable, Sendable {
    public let location: Int
    public let length: Int
    public let emphasis: TextEmphasis

    public init(location: Int, length: Int, emphasis: TextEmphasis) {
        self.location = location
        self.length = length
        self.emphasis = emphasis
    }
}

public struct Page: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public var modifiedAt: Date
    public private(set) var privateTitle: String?
    private var storedSeal: LetterSeal?
    public var seal: LetterSeal? {
        get { storedSeal }
        set { storedSeal = newValue != nil && canApplySeal ? newValue : nil }
    }
    public var canApplySeal: Bool { text.contains { !$0.isWhitespace } }
    public var text: String {
        didSet {
            storedFormatting = nil
            if storedSeal != nil && !canApplySeal { storedSeal = nil }
        }
    }
    private var storedFormatting: [TextFormatRun]?
    public var formatting: [TextFormatRun] {
        get { storedFormatting ?? [] }
        set {
            let runs = Self.validated(newValue, for: text)
            storedFormatting = runs.isEmpty ? nil : runs
        }
    }

    public init(id: UUID = UUID(), createdAt: Date = Date(), modifiedAt: Date? = nil,
                text: String = "", formatting: [TextFormatRun] = [], seal: LetterSeal? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt ?? createdAt
        self.text = text
        self.formatting = formatting
        self.seal = seal
    }

    private enum CodingKeys: String, CodingKey {
        case id, createdAt, modifiedAt, text, privateTitle
        case storedSeal = "seal"
        case storedFormatting = "formatting"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // Letters written before emphasis was supported have no formatting key.
        // Unreadable styling should never cost the writer their text.
        let formatting = (try? values.decode([TextFormatRun].self, forKey: .storedFormatting)) ?? []
        self.init(id: try values.decode(UUID.self, forKey: .id),
                  createdAt: try values.decode(Date.self, forKey: .createdAt),
                  modifiedAt: try values.decode(Date.self, forKey: .modifiedAt),
                  text: try values.decode(String.self, forKey: .text),
                  formatting: formatting,
                  seal: try? values.decode(LetterSeal.self, forKey: .storedSeal))
        if let title = try? values.decode(String.self, forKey: .privateTitle) {
            setPrivateTitle(title)
        }
    }

    private static func validated(_ runs: [TextFormatRun], for text: String) -> [TextFormatRun] {
        guard !runs.isEmpty else { return [] }
        let source = text as NSString
        let supported: TextEmphasis = [.bold, .italic, .underline, .strikethrough, .code]
        var result: [TextFormatRun] = []
        var end = 0
        for run in runs.sorted(by: { $0.location < $1.location }) {
            let emphasis = run.emphasis.intersection(supported)
            guard !emphasis.isEmpty, run.location >= end, run.length > 0,
                  run.location < source.length, run.length <= source.length - run.location else { continue }
            let nextEnd = run.location + run.length
            guard !UTF16.isTrailSurrogate(source.character(at: run.location)),
                  nextEnd == source.length || !UTF16.isTrailSurrogate(source.character(at: nextEnd)) else { continue }
            result.append(TextFormatRun(location: run.location, length: run.length, emphasis: emphasis))
            end = nextEnd
        }
        return result
    }

    public mutating func setPrivateTitle(_ title: String) {
        let singleLine = title.split(whereSeparator: \.isNewline).joined(separator: " ")
        let trimmed = singleLine.trimmingCharacters(in: .whitespacesAndNewlines)
        privateTitle = trimmed.isEmpty ? nil : trimmed
    }

    public var title: String { privateTitle ?? openingLineTitle }

    private var openingLineTitle: String {
        let first = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? "Untitled letter"
        return String(first.prefix(64))
    }

    // A period needs a word boundary so decimals and domains stay together.
    // Other sentence marks, such as 。 and ！, can run into the next word.
    private static let sentenceEnding = try! NSRegularExpression(pattern: #"""
        (?:
            (?<!\b(?:Mr|Mrs|Ms|Dr|Prof|Sr|Jr|\p{L}\.\p{L}))
            \. (?=[\s\p{Pe}\p{Pf}"']|$)
          | [\p{Sentence_Terminal}&&[^.]]
        )
        [\p{Sentence_Terminal}]* [\p{Pe}\p{Pf}"']*
        """#, options: [.allowCommentsAndWhitespace, .caseInsensitive])

    public var preview: String {
        let body = text as NSString
        var excerptRange = NSRange(location: 0, length: body.length)
        var sentenceCount = 0
        Self.sentenceEnding.enumerateMatches(in: text, range: excerptRange) { match, _, stop in
            guard let match else { return }
            sentenceCount += 1
            if sentenceCount == 2 {
                excerptRange.length = NSMaxRange(match.range)
                stop.pointee = true
            }
        }

        var excerpt = body.substring(with: excerptRange).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !excerpt.isEmpty else { return "" }
        if sentenceCount == 0 {
            // Keep a long, unpunctuated draft compact in the letter box.
            excerpt = String(excerpt.prefix(140)).trimmingCharacters(in: .whitespaces)
        }
        while excerpt.last == "." { excerpt.removeLast() }
        return excerpt + "..."
    }

    public var wordCount: Int { text.split(whereSeparator: \.isWhitespace).count }
    public var characterCount: Int { text.count }

    public var exportName: String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r\t")
        let cleaned = openingLineTitle.components(separatedBy: invalid).joined(separator: "-")
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

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value) ?? WritingPreferences.defaults.paperStartPosition
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
    public static let defaults = WritingPreferences()

    public var mechanismStyle: MechanismStyle = .walnut
    public var matchRailToStyle: Bool = true
    public var paper: PaperKind = .ivory
    public var paperStartPosition: PaperStartPosition = .bottom
    public var paperMotion: PaperMotion = .roll
    public var paperTexture: PaperTexture = .classic
    public var textureStrength: Double = 0.70
    public var paperEmbossing: PaperEmbossing = .makerMark
    public var embossingDepth: Double = 0.70
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
    public var marginStyle: PaperMarginStyle = .none
    /// Compatibility with the original Botanical margins toggle.
    public var garden: Bool {
        get { marginStyle == .botanical }
        set {
            if newValue { marginStyle = .botanical }
            else if marginStyle == .botanical { marginStyle = .none }
        }
    }
    public var deskFinish: DeskFinish = .charcoal
    public var deskAccent: DeskAccent = .none
    public var widerFocusPaper: Bool = true
    public var soundEnabled: Bool = true
    public var soundVolume: Double = 0.55
    public var typewriterSound: TypewriterSound = .classic
    public var nightMode: Bool = false
    public var lampIntensity: Double = 0.85
    public var lampWarmth: Double = 0.55
    public init() {}

    /// Paper motion changes drawing and feed timing, never the chosen
    /// starting position. Both Sheet and Roll honor Top and Bottom.
    public var effectivePaperStartPosition: PaperStartPosition {
        paperStartPosition
    }

    /// Distance from the sheet edge to the writing area, in points.
    public var writingMargin: Double { wideMargins ? 76 : 46 }

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
        case marginStyle
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

    private enum LegacyCodingKeys: String, CodingKey { case garden }

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
        if let style = try values.decodeIfPresent(PaperMarginStyle.self, forKey: .marginStyle) {
            marginStyle = style
        } else {
            let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
            if try legacy.decodeIfPresent(Bool.self, forKey: .garden) == true {
                marginStyle = .botanical
            }
        }
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
        textureStrength = min(1, max(0, textureStrength.isFinite ? textureStrength : Self.defaults.textureStrength))
        embossingDepth = min(1, max(0, embossingDepth.isFinite ? embossingDepth : Self.defaults.embossingDepth))
        fontSize = min(28, max(15, fontSize.isFinite ? fontSize : Self.defaults.fontSize))
        inkStrength = min(1, max(0.35, inkStrength.isFinite ? inkStrength : Self.defaults.inkStrength))
        inkBuildup = min(1, max(0, inkBuildup.isFinite ? inkBuildup : Self.defaults.inkBuildup))
        soundVolume = min(1, max(0, soundVolume.isFinite ? soundVolume : Self.defaults.soundVolume))
        lampIntensity = min(1, max(0.25, lampIntensity.isFinite ? lampIntensity : Self.defaults.lampIntensity))
        lampWarmth = min(1, max(0, lampWarmth.isFinite ? lampWarmth : Self.defaults.lampWarmth))
    }
}
