import AppKit
import InkrailCore

extension Notification.Name {
    static let inkrailToggleEmphasis = Notification.Name("Inkrail.ToggleEmphasis")
}

let emphasisKey = NSAttributedString.Key("Inkrail.Emphasis")

/// RTF can represent the appearance of a heading or code span, but it loses
/// the distinction between that appearance and a writer's explicit emphasis.
struct LetterSelection: Codable {
    static let pasteboardType = NSPasteboard.PasteboardType("dev.inkrail.letter-selection")
    let text: String
    let formatting: [TextFormatRun]
}

private extension NSAttributedString {
    var letterFormatRuns: [TextFormatRun] {
        var runs: [TextFormatRun] = []
        enumerateAttribute(emphasisKey, in: NSRange(location: 0, length: length)) { value, range, _ in
            let style = TextEmphasis(rawValue: (value as? NSNumber)?.intValue ?? 0)
            if !style.isEmpty {
                runs.append(TextFormatRun(location: range.location, length: range.length, emphasis: style))
            }
        }
        return runs
    }
}

@MainActor
extension InkTextView {
    func emphasis(_ value: Any?) -> TextEmphasis {
        TextEmphasis(rawValue: (value as? NSNumber)?.intValue ?? 0)
    }

    var formattingRuns: [TextFormatRun] {
        textStorage?.letterFormatRuns ?? []
    }

    func encodedSelection() -> Data? {
        guard selectedRanges.count == 1, let selection = textStorage?.attributedSubstring(from: selectedRange()) else { return nil }
        return try? JSONEncoder().encode(LetterSelection(text: selection.string, formatting: selection.letterFormatRuns))
    }

    func decodeSelection(_ data: Data) -> NSAttributedString? {
        guard let selection = try? JSONDecoder().decode(LetterSelection.self, from: data) else { return nil }
        let page = Page(text: selection.text, formatting: selection.formatting)
        let result = NSMutableAttributedString(string: page.text, attributes: baseAttributes)
        for run in page.formatting {
            result.setAttributes(attributes(for: run.emphasis), range: NSRange(location: run.location, length: run.length))
        }
        return result
    }

    var activeEmphasis: TextEmphasis {
        let selections = selectedRanges.map(\.rangeValue).filter { $0.length > 0 }
        guard !selections.isEmpty, let storage = textStorage else { return emphasis(typingAttributes[emphasisKey]) }
        var common: TextEmphasis = [.bold, .italic, .underline, .strikethrough, .code]
        for range in selections {
            storage.enumerateAttribute(emphasisKey, in: range) { value, _, stop in
                common.formIntersection(self.emphasis(value))
                if common.isEmpty { stop.pointee = true }
            }
        }
        return common
    }

    func attributes(for style: TextEmphasis) -> [NSAttributedString.Key: Any] {
        var result = baseAttributes
        guard !style.isEmpty, var font = result[.font] as? NSFont else { return result }
        result[emphasisKey] = NSNumber(value: style.rawValue)
        let manager = NSFontManager.shared
        // Some desk typefaces have no italic or bold face. Keep the chosen
        // face and apply the missing trait to its glyphs in that case.
        for (flag, trait) in [(TextEmphasis.bold, NSFontTraitMask.boldFontMask), (.italic, .italicFontMask)]
        where style.contains(flag) {
            let converted = manager.convert(font, toHaveTrait: trait)
            if converted.familyName == font.familyName && manager.traits(of: converted).contains(trait) {
                font = converted
            } else if flag == .bold {
                result[.strokeWidth] = -3.0
            } else {
                result[.obliqueness] = 0.18
            }
        }
        result[.font] = font
        if style.contains(.underline) { result[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if style.contains(.strikethrough) { result[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if style.contains(.code), let ink = result[.foregroundColor] as? NSColor {
            result[.backgroundColor] = ink.withAlphaComponent(0.09)
        }
        return result
    }

    // Match against the proposed paragraph so AppKit records the closing
    // keystroke and the conversion as one text replacement in its undo stack.
    func markdownReplacement(for input: String, at insertion: NSRange) -> (range: NSRange, text: NSAttributedString)? {
        guard ["*", "_", "~", "`"].contains(input), insertion.length == 0,
              let storage = textStorage, insertion.location <= storage.length,
              !activeEmphasis.contains(.code) else { return nil }
        let source = storage.mutableString
        let paragraph = source.paragraphRange(for: insertion)
        let candidate = NSMutableString(string: source.substring(with: paragraph))
        let offset = insertion.location - paragraph.location
        candidate.insert(input, at: offset)
        guard let shortcut = MarkdownShortcut.match(in: candidate, at: offset + 1) else { return nil }
        let start = paragraph.location + shortcut.range.location
        guard !MarkdownFence.isLiteral(in: source, at: start),
              !emphasis(storage.attribute(emphasisKey, at: start, effectiveRange: nil)).contains(.code) else { return nil }
        let range = NSRange(location: paragraph.location + shortcut.contentRange.location, length: shortcut.contentRange.length)
        let content = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
        content.enumerateAttribute(emphasisKey, in: NSRange(location: 0, length: content.length)) { value, span, _ in
            content.setAttributes(self.attributes(for: self.emphasis(value).union(shortcut.emphasis)), range: span)
        }
        return (NSRange(location: start, length: shortcut.range.length - 1), content)
    }

    func applyLetterStyle(_ attributes: [NSAttributedString.Key: Any], runs: [TextFormatRun],
                          restoreTypingFromText: Bool) {
        guard let storage = textStorage else { return }
        let selection = selectedRanges
        var typingStyle = emphasis(typingAttributes[emphasisKey])
        baseAttributes = attributes
        storage.beginEditing()
        storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
        for run in runs {
            storage.setAttributes(self.attributes(for: run.emphasis), range: NSRange(location: run.location, length: run.length))
        }
        storage.endEditing()
        selectedRanges = selection
        if restoreTypingFromText {
            let index = min(storage.length - 1, max(0, selectedRange().location - 1))
            typingStyle = index >= 0 ? emphasis(storage.attribute(emphasisKey, at: index, effectiveRange: nil)) : []
        }
        typingAttributes = self.attributes(for: typingStyle)
    }

    func toggleEmphasis(_ flag: TextEmphasis) {
        let remove = activeEmphasis.contains(flag)
        updateEmphasis { remove ? $0.subtracting(flag) : $0.union(flag) }
    }

    @objc func clearLetterFormatting(_ sender: Any?) {
        updateEmphasis { _ in [] }
    }

    private func updateEmphasis(_ transform: (TextEmphasis) -> TextEmphasis) {
        guard !hasMarkedText(), let storage = textStorage else { return }
        let selections = selectedRanges.filter { $0.rangeValue.length > 0 }
        breakUndoCoalescing()
        if selections.isEmpty {
            typingAttributes = attributes(for: transform(activeEmphasis))
            refreshMarkdownBlocks(in: selectedRange())
            onLayout?()
            return
        }
        guard shouldChangeText(inRanges: selections, replacementStrings: nil) else { return }
        storage.beginEditing()
        for selection in selections {
            storage.enumerateAttribute(emphasisKey, in: selection.rangeValue) { value, range, _ in
                let current = self.emphasis(value)
                storage.setAttributes(self.attributes(for: transform(current)), range: range)
            }
        }
        storage.endEditing()
        didChangeText()
    }

    func styledPaste(_ source: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(string: source.string, attributes: baseAttributes)
        source.enumerateAttributes(in: NSRange(location: 0, length: source.length)) { attrs, range, _ in
            var style: TextEmphasis = []
            let traits = (attrs[.font] as? NSFont).map { NSFontManager.shared.traits(of: $0) } ?? []
            let stroke = (attrs[.strokeWidth] as? NSNumber)?.doubleValue ?? 0
            let slant = (attrs[.obliqueness] as? NSNumber)?.doubleValue ?? 0
            if traits.contains(.boldFontMask) || stroke < 0 { style.insert(.bold) }
            if traits.contains(.italicFontMask) || slant != 0 { style.insert(.italic) }
            if (attrs[.underlineStyle] as? NSNumber)?.intValue ?? 0 != 0 { style.insert(.underline) }
            if (attrs[.strikethroughStyle] as? NSNumber)?.intValue ?? 0 != 0 { style.insert(.strikethrough) }
            result.setAttributes(self.attributes(for: style), range: range)
        }
        return result
    }
}
