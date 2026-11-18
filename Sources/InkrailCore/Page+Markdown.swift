import Foundation

extension Page {
    /// Source outside formatted spans passes through so handwritten Markdown
    /// keeps its meaning. Inline HTML supports underline and intraword spans.
    public var markdownText: String {
        let runs = formatting
        guard !runs.isEmpty else { return text }
        let source = text as NSString
        var output = ""
        var index = 0
        forEachMarkdownLine(in: source) { line, inline in
            var cursor = line.location
            while index < runs.count {
                let run = runs[index]
                let range = NSRange(location: run.location, length: run.length)
                guard range.location < NSMaxRange(line) else { break }
                let visible = NSIntersectionRange(range, inline)
                if visible.length > 0 {
                    output += source.substring(with: NSRange(location: cursor, length: visible.location - cursor))
                    output += Self.markdownSpan(source, range: visible, emphasis: run.emphasis)
                    cursor = NSMaxRange(visible)
                }
                if NSMaxRange(range) > NSMaxRange(line) { break }
                index += 1
            }
            output += source.substring(with: NSRange(location: cursor, length: NSMaxRange(line) - cursor))
        }
        return output
    }

    private static func markdownSpan(_ source: NSString, range: NSRange, emphasis: TextEmphasis) -> String {
        let line = source.substring(with: range)
        guard let first = line.firstIndex(where: { !$0.isWhitespace }),
              let last = line.lastIndex(where: { !$0.isWhitespace }) else { return line }
        func isBoundary(_ index: Int) -> Bool {
            guard index >= 0, index < source.length else { return true }
            let range = source.rangeOfComposedCharacterSequence(at: index)
            guard let adjacent = source.substring(with: range).first else { return true }
            return adjacent.isWhitespace || ".,;:!?()".contains(adjacent)
        }
        let tags: [(TextEmphasis, String)] = [(.bold, "strong"), (.italic, "em"),
                                              (.underline, "u"), (.strikethrough, "del")]
        let names = tags.compactMap { emphasis.contains($0.0) ? $0.1 : nil }
        var marker: String?
        if isBoundary(range.location - 1), isBoundary(NSMaxRange(range)) {
            switch emphasis {
            case .bold: marker = "**"
            case .italic: marker = "*"
            case .strikethrough: marker = "~~"
            default: break
            }
        }
        var output = String(line[..<first]) + (marker ?? names.map { "<\($0)>" }.joined())
        let content = line[first...last]
        if emphasis.contains(.code) {
            let ticks = content.split(whereSeparator: { $0 != "`" }).map(\.count).max() ?? 0
            let fence = String(repeating: "`", count: ticks + 1)
            let space = content.first == "`" || content.last == "`" ? " " : ""
            output += fence + space + content + space + fence
        } else {
            for scalar in content.unicodeScalars {
                switch scalar {
                case "&": output += "&amp;"
                case "<": output += "&lt;"
                case ">": output += "&gt;"
                case "\\", "`", "*", "_", "[", "]", "~", "|":
                    output += "\\"
                    output.unicodeScalars.append(scalar)
                default: output.unicodeScalars.append(scalar)
                }
            }
        }
        output += marker ?? names.reversed().map { "</\($0)>" }.joined()
        output += line[line.index(after: last)...]
        return output
    }
}
