import Foundation

public enum SealShape: String, CaseIterable, Codable, Sendable {
    case round, oval, scalloped
}

public enum SealColor: String, CaseIterable, Codable, Sendable {
    case oxblood, forest, navy, plum
}

/// A wax impression attached to the end of one letter.
public struct LetterSeal: Codable, Equatable, Sendable {
    public static let maximumTextLength = 24
    public let text: String
    public let shape: SealShape
    public let color: SealColor

    public static func singleLine(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    public init(text: String = "Sealed", shape: SealShape = .round, color: SealColor = .oxblood) {
        let inscription = Self.singleLine(text)
        self.text = inscription.isEmpty ? "Sealed" : inscription.prefix(Self.maximumTextLength).trimmingCharacters(in: .whitespaces)
        self.shape = shape
        self.color = color
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let text = Self.singleLine(try values.decode(String.self, forKey: .text))
        guard !text.isEmpty, text.count <= Self.maximumTextLength else {
            throw DecodingError.dataCorruptedError(forKey: .text, in: values, debugDescription: "Invalid seal inscription")
        }
        self.init(text: text, shape: try values.decode(SealShape.self, forKey: .shape),
                  color: try values.decode(SealColor.self, forKey: .color))
    }
}
