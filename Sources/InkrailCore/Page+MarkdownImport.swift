import Foundation

/// The importer and exporter share the editable range of each Markdown line.
/// Fenced/indented examples, block markers and the original newline stay literal.
func forEachMarkdownLine(in source: NSString, _ visit: (NSRange, NSRange) -> Void) {
    var start = 0
    var fence: MarkdownFence?
    while start < source.length {
        var end = 0, contentsEnd = 0
        source.getLineStart(nil, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: start, length: 0))
        let line = NSRange(location: start, length: end - start)
        var first = start
        if let boundary = MarkdownFence.delimiter(in: source, paragraph: line, closing: fence) {
            fence = fence == nil ? boundary : nil
            first = contentsEnd
        } else {
            let indent = source.substring(with: NSRange(location: start, length: min(4, contentsEnd - start)))
            if fence != nil || indent == "    " || indent.hasPrefix("\t") { first = contentsEnd }
            while first < contentsEnd, let prefix = MarkdownBlockPrefix.read(
                in: source, paragraph: NSRange(location: first, length: contentsEnd - first)) {
                first = NSMaxRange(prefix.range)
            }
        }
        visit(line, NSRange(location: first, length: contentsEnd - first))
        start = end
    }
}

extension Page {
    /// Import the inline syntax Inkrail can edit. Other Markdown, including
    /// block markers, link destinations and fenced examples, stays in the text.
    public init(markdown: String) {
        let source = markdown as NSString
        var output = ""
        var formatting: [TextFormatRun] = []
        var outputLength = 0
        func append(_ range: NSRange, with emphasis: TextEmphasis = []) {
            guard range.length > 0 else { return }
            var piece = source.substring(with: range)
            if !emphasis.isEmpty && !emphasis.contains(.code) {
                piece = Self.unescapeStyledMarkdown(piece)
            }
            let length = piece.utf16.count
            if !emphasis.isEmpty {
                var start = outputLength
                if let last = formatting.last, last.emphasis == emphasis, last.location + last.length == start {
                    start = last.location
                    formatting.removeLast()
                }
                formatting.append(TextFormatRun(location: start, length: outputLength + length - start, emphasis: emphasis))
            }
            output += piece
            outputLength += length
        }

        forEachMarkdownLine(in: source) { line, inline in
            var boundaries: [(range: NSRange, style: TextEmphasis, delta: Int)] = []
            MarkdownShortcut.scan(in: source, range: inline.location..<NSMaxRange(inline), importing: true) { span in
                var content = span.contentRange
                if span.emphasis == .code, content.length >= 2,
                   source.character(at: content.location) == 32, source.character(at: NSMaxRange(content) - 1) == 32,
                   source.rangeOfCharacter(from: Self.nonSpace, options: [], range: content).location != NSNotFound {
                    content.location += 1
                    content.length -= 2
                }
                let open = NSRange(location: span.range.location, length: content.location - span.range.location)
                let close = NSRange(location: NSMaxRange(content), length: NSMaxRange(span.range) - NSMaxRange(content))
                boundaries.append((open, span.emphasis, 1))
                boundaries.append((close, span.emphasis, -1))
            }
            var cursor = line.location
            var emphasis: TextEmphasis = []
            var depth: [Int: Int] = [:]
            for boundary in boundaries.sorted(by: { $0.range.location < $1.range.location }) {
                append(NSRange(location: cursor, length: boundary.range.location - cursor), with: emphasis)
                for flag in Self.inlineFlags where boundary.style.contains(flag) {
                    depth[flag.rawValue, default: 0] += boundary.delta
                    if depth[flag.rawValue] == 0 { emphasis.remove(flag) } else { emphasis.insert(flag) }
                }
                cursor = NSMaxRange(boundary.range)
            }
            append(NSRange(location: cursor, length: NSMaxRange(line) - cursor))
        }
        self.init(text: output, formatting: formatting)
    }

    private static let inlineFlags: [TextEmphasis] = [.bold, .italic, .underline, .strikethrough, .code]
    private static let nonSpace = CharacterSet(charactersIn: " ").inverted

    private static func unescapeStyledMarkdown(_ source: String) -> String {
        guard source.contains("\\") || source.contains("&") else { return source }
        var result = ""
        var escaped = false
        for character in source {
            if escaped {
                if !character.isPunctuation && !character.isSymbol { result.append("\\") }
                result.append(character)
                escaped = false
            } else if character == "\\" { escaped = true }
            else { result.append(character) }
        }
        if escaped { result.append("\\") }
        return result.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&amp;", with: "&")
    }
}
