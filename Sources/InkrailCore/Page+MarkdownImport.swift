import Foundation

/// The importer and exporter share the editable range of each Markdown line.
/// Fenced/indented examples, block markers and the original newline stay literal.
@discardableResult
func forEachMarkdownLine(in source: NSString, _ visit: (NSRange, NSRange) -> Void) -> MarkdownFence? {
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
    return fence
}

extension MarkdownFence {
    static func openAtEnd(of text: String) -> MarkdownFence? {
        guard text.contains("```") || text.contains("~~~") else { return nil }
        return forEachMarkdownLine(in: text as NSString) { _, _ in }
    }
}

extension Page {
    // Read only the complete footer written by Inkrail. Keep malformed or
    // unfamiliar footer markup in the editable letter like any other HTML.
    private static let sealFooter = try! NSRegularExpression(pattern:
        #"(?:\r\n\r\n|\n\n|\A)(<p data-inkrail-seal="([a-z]+) ([a-z]+)"( data-inkrail-closed-fence)?>✦ ([^<>\r\n]+) ✦</p>)(?:\r?\n)?\z"#)
    private static let footerFence = try! NSRegularExpression(pattern: #"(?:\r\n\r\n|\n\n)(`{3,}|~{3,})\z"#)

    private static func splitSealFooter(_ markdown: String) -> (body: NSString, seal: LetterSeal?) {
        let source = markdown as NSString
        guard let match = sealFooter.firstMatch(in: markdown, range: NSRange(location: 0, length: source.length)),
              let shape = SealShape(rawValue: source.substring(with: match.range(at: 2))),
              let color = SealColor(rawValue: source.substring(with: match.range(at: 3))) else { return (source, nil) }
        let closesFence = match.range(at: 4).location != NSNotFound
        let inscription = source.substring(with: match.range(at: 5))
            .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
        let seal = LetterSeal(text: inscription, shape: shape, color: color)
        guard seal.markdownFooter(closesFence: closesFence) == source.substring(with: match.range(at: 1)) else { return (source, nil) }
        var body = source.substring(to: match.range.location)
        if closesFence {
            let encoded = body as NSString
            guard let closing = footerFence.firstMatch(in: body, range: NSRange(location: 0, length: encoded.length)) else { return (source, nil) }
            body = encoded.substring(to: closing.range.location)
            guard MarkdownFence.openAtEnd(of: body)?.marker == encoded.substring(with: closing.range(at: 1)) else { return (source, nil) }
        } else if MarkdownFence.openAtEnd(of: body) != nil { return (source, nil) }
        return (body as NSString, seal)
    }

    /// Import the inline syntax Inkrail can edit. Other Markdown, including
    /// block markers, link destinations and fenced examples, stays in the text.
    public init(markdown: String) {
        let (source, seal) = Self.splitSealFooter(markdown)
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
            if source.range(of: "<p data-inkrail-seal=", options: .anchored, range: line).location != NSNotFound {
                append(line)
                return
            }
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
        self.init(text: output, formatting: formatting, seal: seal)
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
