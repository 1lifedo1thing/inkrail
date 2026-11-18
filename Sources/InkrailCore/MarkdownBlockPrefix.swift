import Foundation

/// A supported Markdown paragraph marker, including its separating space or tab.
public struct MarkdownBlockPrefix: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case heading(level: Int)
        case quote
        case list
    }

    public let kind: Kind
    public let range: NSRange
    public let source: String

    public static func read(in text: NSString, paragraph: NSRange) -> Self? {
        guard paragraph.location >= 0, paragraph.length > 0, paragraph.location < text.length,
              paragraph.length <= text.length - paragraph.location else { return nil }
        // The longest marker is a nine-digit list number plus punctuation and a space.
        let prefix = NSRange(location: paragraph.location, length: min(11, paragraph.length))
        let separator = text.rangeOfCharacter(from: separators, options: [], range: prefix)
        guard separator.location != NSNotFound, separator.location > paragraph.location else { return nil }
        let tokenRange = NSRange(location: paragraph.location, length: separator.location - paragraph.location)
        let token = text.substring(with: tokenRange)
        let kind: Kind
        switch token {
        case ">": kind = .quote
        case "-", "*", "+": kind = .list
        default:
            if token.count <= 6 && token.allSatisfy({ $0 == "#" }) {
                kind = .heading(level: token.count)
            } else if token.count > 1, token.last == "." || token.last == ")",
                      token.dropLast().allSatisfy({ $0.isASCII && $0.isNumber }) {
                kind = .list
            } else {
                return nil
            }
        }
        let range = NSUnionRange(tokenRange, separator)
        return Self(kind: kind, range: range, source: text.substring(with: range))
    }

    private static let separators = CharacterSet(charactersIn: " \t")
}

/// An open Markdown code fence. Its closing fence must use the same character
/// at least as many times and may only have whitespace after it.
public struct MarkdownFence: Equatable, Sendable {
    public let marker: String

    public init?(marker: String) {
        guard let first = marker.first, first == "`" || first == "~",
              marker.utf8.count >= 3, marker.allSatisfy({ $0 == first }) else { return nil }
        self.marker = marker
    }

    public static func delimiter(in text: NSString, paragraph: NSRange, closing open: Self? = nil) -> Self? {
        guard paragraph.location >= 0, paragraph.length >= 3, paragraph.location <= text.length,
              paragraph.length <= text.length - paragraph.location else { return nil }
        var start = paragraph.location
        let end = NSMaxRange(paragraph)
        while start < end && start - paragraph.location < 3 && text.character(at: start) == 32 { start += 1 }
        guard end - start >= 3 else { return nil }
        let character = text.character(at: start)
        guard character == 96 || character == 126 else { return nil } // backtick or tilde
        var after = start + 1
        while after < end && text.character(at: after) == character { after += 1 }
        let count = after - start
        guard count >= 3 else { return nil }
        let tail = NSRange(location: after, length: end - after)
        if let open {
            let expected = open.marker.first == "`" ? 96 : 126
            guard character == expected, count >= open.marker.utf8.count,
                  text.rangeOfCharacter(from: nonFenceWhitespace, options: [], range: tail).location == NSNotFound
            else { return nil }
        } else if character == 96, text.range(of: "`", options: .literal, range: tail).location != NSNotFound {
            return nil
        }
        return Self(marker: text.substring(with: NSRange(location: start, length: count)))
    }

    public static func isLiteral(in text: NSString, at location: Int) -> Bool {
        guard location >= 0, location <= text.length else { return false }
        let target = text.paragraphRange(for: NSRange(location: location, length: 0))
        let search = NSRange(location: 0, length: NSMaxRange(target))
        guard text.range(of: "```", options: .literal, range: search).location != NSNotFound ||
              text.range(of: "~~~", options: .literal, range: search).location != NSNotFound else { return false }
        var fence: Self?
        var start = 0
        while start < NSMaxRange(target) {
            let paragraph = text.paragraphRange(for: NSRange(location: start, length: 0))
            let boundary = delimiter(in: text, paragraph: paragraph, closing: fence)
            if start == target.location { return fence != nil || boundary != nil }
            if let boundary { fence = fence == nil ? boundary : nil }
            start = NSMaxRange(paragraph)
        }
        return fence != nil
    }

    private static let nonFenceWhitespace = CharacterSet(charactersIn: " \t")
        .union(.newlines).inverted
}
