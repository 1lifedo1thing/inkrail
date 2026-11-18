import AppKit
import InkrailCore

private let blockPrefixKey = NSAttributedString.Key("Inkrail.MarkdownBlockPrefix")
private let openFenceKey = NSAttributedString.Key("Inkrail.OpenMarkdownFence")
private let headingMarkerKey = NSAttributedString.Key("Inkrail.HeadingMarker")
private let nonWhitespace = CharacterSet.whitespacesAndNewlines.inverted

private func activeMarkdownBlock(in text: NSString, paragraph: NSRange) -> MarkdownBlockPrefix? {
    guard let prefix = MarkdownBlockPrefix.read(in: text, paragraph: paragraph) else { return nil }
    let body = NSRange(NSMaxRange(prefix.range)..<NSMaxRange(paragraph))
    guard text.rangeOfCharacter(from: nonWhitespace, options: [], range: body).location != NSNotFound else { return nil }
    return prefix
}

extension InkLayoutManager: NSLayoutManagerDelegate {
    func layoutManager(_ layoutManager: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                       properties: UnsafePointer<NSLayoutManager.GlyphProperty>, characterIndexes: UnsafePointer<Int>,
                       font: NSFont, forGlyphRange glyphRange: NSRange) -> Int {
        guard let storage = layoutManager.textStorage else { return 0 }
        var attributeRange = NSRange()
        var isMarker = false
        var adjusted: [NSLayoutManager.GlyphProperty]?
        for index in 0..<glyphRange.length {
            let character = characterIndexes[index]
            if !NSLocationInRange(character, attributeRange) {
                isMarker = character < storage.length &&
                    storage.attribute(headingMarkerKey, at: character, effectiveRange: &attributeRange) != nil
            }
            if isMarker {
                if adjusted == nil { adjusted = Array(UnsafeBufferPointer(start: properties, count: glyphRange.length)) }
                adjusted?[index].insert(.null)
            }
        }
        guard let adjusted else { return 0 }
        // Null glyphs consume no ink or horizontal space. TextKit keeps the
        // original character indices for typing, selection, undo and export.
        layoutManager.setGlyphs(glyphs, properties: adjusted, characterIndexes: characterIndexes,
                                font: font, forGlyphRange: glyphRange)
        return glyphRange.length
    }
}

@MainActor
extension InkTextView {
    /// Refresh touched paragraphs, including the next paragraph when a Return
    /// splits a heading. Block appearance follows the literal prefix in the letter.
    func refreshMarkdownBlocks(in editedRange: NSRange? = nil) {
        guard let storage = textStorage, baseAttributes[.font] is NSFont, !hasMarkedText() else { return }
        let text = storage.string as NSString
        let edit = editedRange ?? NSRange(location: 0, length: text.length)
        guard edit.location >= 0, edit.length >= 0, edit.location <= text.length,
              edit.length <= text.length - edit.location else { return }
        var start = text.paragraphRange(for: NSRange(location: edit.location, length: 0)).location
        let last = text.paragraphRange(for: NSRange(location: NSMaxRange(edit), length: 0))
        func fenceEnteringParagraph(at location: Int) -> MarkdownFence? {
            guard location > 0 else { return nil }
            let previous = text.paragraphRange(for: NSRange(location: location - 1, length: 0))
            let marker = storage.attribute(openFenceKey, at: previous.location, effectiveRange: nil) as? String
            let prior = marker.flatMap(MarkdownFence.init(marker:))
            guard let delimiter = MarkdownFence.delimiter(in: text, paragraph: previous, closing: prior) else { return prior }
            return prior == nil ? delimiter : nil
        }
        var fence = fenceEnteringParagraph(at: start)
        storage.beginEditing()
        while start < text.length {
            // Editing a fence can also change later paragraphs. Stop once the
            // text beyond the edit has the same incoming fence as before.
            if start >= NSMaxRange(last),
               storage.attribute(openFenceKey, at: start, effectiveRange: nil) as? String == fence?.marker { break }
            let paragraph = text.paragraphRange(for: NSRange(location: start, length: 0))
            let delimiter = MarkdownFence.delimiter(in: text, paragraph: paragraph, closing: fence)
            let block = fence == nil && delimiter == nil ? activeMarkdownBlock(in: text, paragraph: paragraph) : nil
            func style(_ span: NSRange, hideMarker: Bool = false) {
                storage.enumerateAttributes(in: span) { current, range, _ in
                    guard current[blockPrefixKey] as? String != block?.source ||
                          current[openFenceKey] as? String != fence?.marker ||
                          (current[headingMarkerKey] != nil) != hideMarker else { return }
                    let inlineStyle = self.emphasis(current[emphasisKey])
                    var updated = self.attributes(for: inlineStyle, in: block)
                    updated[openFenceKey] = fence?.marker
                    if hideMarker { updated[headingMarkerKey] = true }
                    storage.setAttributes(updated, range: range)
                }
            }
            if let block, case .heading = block.kind {
                style(block.range, hideMarker: true)
                style(NSRange(NSMaxRange(block.range)..<NSMaxRange(paragraph)))
            } else {
                style(paragraph)
            }
            if let delimiter { fence = fence == nil ? delimiter : nil }
            start = NSMaxRange(paragraph)
        }
        storage.endEditing()

        let caret = selectedRange()
        guard caret.length == 0, caret.location <= text.length else { return }
        let paragraph = text.paragraphRange(for: caret)
        let typingFence = fenceEnteringParagraph(at: paragraph.location)
        let block = typingFence == nil ? activeMarkdownBlock(in: text, paragraph: paragraph) : nil
        let current = typingAttributes
        if current[blockPrefixKey] as? String != block?.source ||
            current[openFenceKey] as? String != typingFence?.marker || current[headingMarkerKey] != nil {
            var updated = attributes(for: emphasis(current[emphasisKey]), in: block)
            updated[openFenceKey] = typingFence?.marker
            typingAttributes = updated
        }
    }

    private func attributes(for style: TextEmphasis, in block: MarkdownBlockPrefix?) -> [NSAttributedString.Key: Any] {
        guard let block else { return attributes(for: style) }
        var result = attributes(for: style)
        guard let font = result[.font] as? NSFont,
              let paragraph = (result[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle else {
            return result
        }
        switch block.kind {
        case .heading(let level):
            // Headings use the letter's own face and its native/synthetic bold.
            // Only explicit inline emphasis belongs in the saved formatting runs.
            let semanticEmphasis = result[emphasisKey]
            result = attributes(for: style.union(.bold))
            result[emphasisKey] = semanticEmphasis
            let boldFont = result[.font] as? NSFont ?? font
            let scale = 1.05 + CGFloat(6 - level) * 0.08
            result[.font] = NSFontManager.shared.convert(boldFont, toSize: font.pointSize * scale)
            paragraph.paragraphSpacingBefore = font.pointSize * 0.30
            paragraph.paragraphSpacing = font.pointSize * 0.20
        case .quote:
            paragraph.firstLineHeadIndent = font.pointSize
            paragraph.headIndent = paragraph.firstLineHeadIndent
        case .list:
            paragraph.firstLineHeadIndent = font.pointSize * 0.5
            let markerWidth = (block.source as NSString).size(withAttributes: [.font: baseAttributes[.font] ?? font]).width
            paragraph.headIndent = paragraph.firstLineHeadIndent + markerWidth
        }
        result[.paragraphStyle] = paragraph
        result[blockPrefixKey] = block.source
        return result
    }
}
