import Foundation

/// A completed inline Markdown shortcut in the paragraph being typed.
/// TextKit uses these UTF-16 ranges to remove the markers as one edit.
public struct MarkdownShortcut: Equatable, Sendable {
    public let range: NSRange
    public let contentRange: NSRange
    public let emphasis: TextEmphasis

    private enum Marker: UInt16 {
        case asterisk = 42, underscore = 95, tilde = 126, backtick = 96

        func emphasis(length: Int) -> TextEmphasis? {
            switch (self, length) {
            case (.asterisk, 1), (.underscore, 1): return .italic
            case (.asterisk, 2), (.underscore, 2): return .bold
            case (.asterisk, 3), (.underscore, 3): return [.bold, .italic]
            case (.tilde, 2): return .strikethrough
            case (.backtick, _): return .code
            default: return nil
            }
        }
    }

    /// Call after a user types a possible closing marker, with the caret just
    /// past that marker. Already balanced markers cannot open another span.
    public static func match(in text: NSString, at caret: Int) -> Self? {
        guard caret > 0, caret <= text.length,
              let marker = Marker(rawValue: text.character(at: caret - 1)),
              caret == text.length || text.character(at: caret) != marker.rawValue else { return nil }
        var start = 0
        text.getLineStart(&start, end: nil, contentsEnd: nil, for: NSRange(location: caret - 1, length: 1))
        let indent = text.substring(with: NSRange(location: start, length: min(4, caret - start)))
        guard indent != "    ", !indent.hasPrefix("\t") else { return nil }
        var result: Self?
        scan(in: text, range: start..<caret, importing: false) { shortcut in
            if NSMaxRange(shortcut.range) == caret { result = shortcut }
        }
        return result
    }

    /// A paragraph is scanned once during import, rather than replaying typing
    /// for each potential closer. A code span shields its literal contents.
    static func scan(in text: NSString, range: Range<Int>, importing: Bool, emit: (Self) -> Void) {
        var pending: [String: [NSRange]] = [:]
        var code: NSRange?
        func pair(_ open: NSRange, _ close: NSRange, _ style: TextEmphasis) {
            guard NSMaxRange(open) < close.location else { return }
            emit(Self(range: NSRange(location: open.location, length: NSMaxRange(close) - open.location),
                      contentRange: NSRange(location: NSMaxRange(open), length: close.location - NSMaxRange(open)),
                      emphasis: style))
        }
        var i = range.lowerBound
        while i < range.upperBound {
            let head = i
            let unit = text.character(at: i)
            i += 1
            guard Marker(rawValue: unit) != nil || unit == 91 || (importing && unit == 60) else { continue }
            // A backslash escapes one character. The rest of the run can
            // still close a span, as in a bold word ending in a literal '*'.
            if code == nil, escaped(in: text, at: head, since: range.lowerBound) { continue }
            if code == nil, unit == 91 {
                // Keep link labels, image alt text and destinations as source.
                i = afterBalanced(in: text, from: head, until: range.upperBound, open: 91, close: 93)
                if i < range.upperBound, text.character(at: i) == 40 {
                    i = afterBalanced(in: text, from: i, until: range.upperBound, open: 40, close: 41)
                }
                continue
            }
            if importing, code == nil, unit == 60, i < range.upperBound {
                let next = text.character(at: i)
                if next == 47 || (65...90).contains(next) || (97...122).contains(next) {
                    let tail = text.range(of: ">", options: [], range: NSRange(location: i, length: range.upperBound - i))
                    guard tail.location != NSNotFound else { break }
                    i = NSMaxRange(tail)
                    let tagRange = NSRange(location: head, length: i - head)
                    let tag = text.substring(with: tagRange)
                    let closing = next == 47
                    let name = String(tag.dropFirst(closing ? 2 : 1).dropLast()).lowercased()
                    if let style = htmlEmphasis[name] {
                        if !closing { pending[name, default: []].append(tagRange) }
                        else if let open = pending[name]?.popLast() { pair(open, tagRange, style) }
                    }
                    continue
                }
            }
            guard let marker = Marker(rawValue: unit) else { continue }
            while i < range.upperBound, text.character(at: i) == unit { i += 1 }
            let token = NSRange(location: head, length: i - head)
            if marker == .backtick {
                if let open = code {
                    if open.length == token.length { pair(open, token, .code); code = nil }
                } else { code = token }
                continue
            }
            guard code == nil, let style = marker.emphasis(length: token.length) else { continue }
            let key = text.substring(with: token)
            let edges = flanking(text, head..<i, marker: marker)
            if edges.canClose, let open = pending[key]?.popLast() { pair(open, token, style) }
            else if edges.canOpen { pending[key, default: []].append(token) }
        }
    }

    private static let htmlEmphasis: [String: TextEmphasis] = [
        "strong": .bold, "em": .italic, "u": .underline, "del": .strikethrough
    ]

    private static func afterBalanced(in text: NSString, from start: Int, until end: Int,
                                      open: UInt16, close: UInt16) -> Int {
        var depth = 1
        var i = start + 1
        while i < end, depth > 0 {
            switch text.character(at: i) {
            case 92 where i + 1 < end: i += 1
            case open: depth += 1
            case close: depth -= 1
            default: break
            }
            i += 1
        }
        return i
    }

    private static func escaped(in text: NSString, at index: Int, since start: Int) -> Bool {
        var i = index
        while i > start, text.character(at: i - 1) == 92 { i -= 1 }
        return !(index - i).isMultiple(of: 2)
    }

    private enum Edge { case whitespace, punctuation, word }

    private static func edge(in text: NSString, at index: Int) -> Edge {
        guard index >= 0, index < text.length else { return .whitespace }
        let range = text.rangeOfComposedCharacterSequence(at: index)
        guard let character = text.substring(with: range).first, !character.isWhitespace else { return .whitespace }
        return character.isPunctuation || character.isSymbol ? .punctuation : .word
    }

    private static func flanking(_ text: NSString, _ range: Range<Int>, marker: Marker)
        -> (canOpen: Bool, canClose: Bool) {
        let before = edge(in: text, at: range.lowerBound - 1)
        let after = edge(in: text, at: range.upperBound)
        let left = after != .whitespace && (after != .punctuation || before != .word)
        let right = before != .whitespace && (before != .punctuation || after != .word)
        guard marker == .underscore else { return (left, right) }
        return (left && (!right || before == .punctuation), right && (!left || after == .punctuation))
    }
}
