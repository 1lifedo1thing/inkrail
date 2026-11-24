import AppKit
import SwiftUI
import InkrailCore

@MainActor
enum LetterPDFExport {
    private struct Sheet {
        let glyphs: NSRange
        let textTop: CGFloat
    }

    static func data(for page: Page, preferences: WritingPreferences, paperSize: CGSize) throws -> Data {
        let width = paperSize.width
        let writingWidth = width - 2 * preferences.writingMargin
        guard writingWidth > 0, width.isFinite, paperSize.height.isFinite, paperSize.height > 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
        let height = max(paperSize.height, ceil(width * 11 / 8.5))
        var media = CGRect(x: 0, y: 0, width: width, height: height)
        let top = PaperFeedLayout.topInset(viewportHeight: height, lineHeight: preferences.fontSize, position: .top)
        let bottom: CGFloat = 28

        // A detached TextKit stack keeps the live caret, composition and scroll position intact.
        // Lay out at the desk's exact writing width once, then draw complete lines in each PDF page.
        var flat = preferences
        flat.paperMotion = .sheet
        let storage = NSTextStorage()
        let layout = InkLayoutManager()
        layout.outlinesInkSpread = true
        layout.delegate = layout
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: CGSize(width: writingWidth, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.widthTracksTextView = false
        container.heightTracksTextView = false
        layout.addTextContainer(container)
        let editor = InkTextView(frame: CGRect(x: 0, y: 0, width: writingWidth, height: height), textContainer: container)
        editor.isRichText = true
        editor.textContainerInset = .zero
        editor.string = page.text
        editor.applyWritingStyle(flat, runs: page.formatting, restoreTypingFromText: true)
        layout.ensureLayout(for: container)
        var textBottom = layout.usedRect(for: container).maxY
        if layout.extraLineFragmentTextContainer === container {
            textBottom = max(textBottom, layout.extraLineFragmentRect.maxY)
        }
        let seal = try page.seal.map {
            try image(of: LetterSealMark(text: $0.text, shape: $0.shape, color: $0.color))
        }
        let sealBottom = seal.map { _ in textBottom + CaretPosition.sealSpacing + CaretPosition.sealSize.height }
        let sheets = paginate(layout, writingHeight: height - top - bottom, sealBottom: sealBottom)
        let firstPaper = try paper(flat, size: media.size)
        var continuationPaper = firstPaper
        if sheets.count > 1 && (flat.paperEmbossing != .none || flat.marginStyle != .none) {
            var continuation = flat
            continuation.paperEmbossing = .none
            continuation.marginStyle = .none
            continuationPaper = try paper(continuation, size: media.size)
        }

        let bytes = NSMutableData()
        guard let consumer = CGDataConsumer(data: bytes),
              let pdf = CGContext(consumer: consumer, mediaBox: &media, nil) else { throw CocoaError(.fileWriteUnknown) }
        for (index, sheet) in sheets.enumerated() {
            autoreleasepool {
                pdf.beginPDFPage(nil)
                pdf.draw(index == 0 ? firstPaper : continuationPaper, in: media)
                let origin = CGPoint(x: flat.writingMargin, y: top - sheet.textTop)
                pdf.saveGState()
                pdf.translateBy(x: 0, y: height)
                pdf.scaleBy(x: 1, y: -1)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: pdf, flipped: true)
                layout.drawBackground(forGlyphRange: sheet.glyphs, at: origin)
                layout.drawGlyphs(forGlyphRange: sheet.glyphs, at: origin)
                NSGraphicsContext.restoreGraphicsState()
                pdf.restoreGState()
                if index == sheets.count - 1, let seal, let sealBottom {
                    let size = CaretPosition.sealSize
                    pdf.draw(seal, in: CGRect(x: (width - size.width) / 2, y: height - origin.y - sealBottom,
                                              width: size.width, height: size.height))
                }
                pdf.endPDFPage()
            }
        }
        withExtendedLifetime(editor) { pdf.closePDF() }
        return bytes as Data
    }

    private static func paginate(_ layout: InkLayoutManager, writingHeight: CGFloat, sealBottom: CGFloat?) -> [Sheet] {
        let all = NSRange(location: 0, length: layout.numberOfGlyphs)
        var sheets: [Sheet] = []
        var start = 0
        var top: CGFloat = 0
        layout.enumerateLineFragments(forGlyphRange: all) { line, _, _, glyphs, _ in
            // Keep the last line and its seal together, including the space
            // occupied by a trailing Return. Every glyph belongs to exactly one page.
            let bottom = NSMaxRange(glyphs) == all.length ? (sealBottom ?? line.maxY) : line.maxY
            if bottom - top > writingHeight, glyphs.location > start {
                sheets.append(Sheet(glyphs: NSRange(start..<glyphs.location), textTop: top))
                start = glyphs.location
                top = line.minY
            }
        }
        sheets.append(Sheet(glyphs: NSRange(start..<all.length), textTop: top))
        return sheets
    }

    private static func paper(_ preferences: WritingPreferences, size: CGSize) throws -> CGImage {
        let stationery = PaperStock(preferences: preferences)
            .frame(width: size.width, height: size.height)
            .clipped()
        return try image(of: stationery)
    }

    // Only the textured stationery and wax need a bitmap. Reuse paper images
    // across sheets so a long letter never requires a letter-sized bitmap.
    private static func image<V: View>(of view: V) throws -> CGImage {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .light))
        renderer.scale = 2
        guard let image = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
        return image
    }
}
