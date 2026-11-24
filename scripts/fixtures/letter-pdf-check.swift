import AppKit
import PDFKit
import SwiftUI
import InkrailCore

// Stand in for SwiftPM's asset bundle when compiling the native check directly.
extension Bundle {
    static let module = Bundle(url: URL(fileURLWithPath: CommandLine.arguments[1])
        .appendingPathComponent("FixtureResources.bundle"))!
}

private struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private func require(_ condition: Bool, _ message: String) throws {
    guard condition else { throw Failure(message) }
}

// Raster checks inspect what the PDF paints, including decorations that never
// appear in its text layer. Sample at one pixel per PDF point.
private func pixels(in document: PDFDocument, at index: Int = 0) throws -> [UInt8] {
    guard let page = document.page(at: index) else { throw Failure("Missing PDF page \(index)") }
    let bounds = page.bounds(for: .mediaBox)
    let width = Int(bounds.width.rounded()), height = Int(bounds.height.rounded())
    guard let pdf = page.pageRef,
          let context = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
          let data = context.data else { throw Failure("Could not rasterize the PDF") }
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.concatenate(pdf.getDrawingTransform(.mediaBox, rect: bounds, rotate: 0, preserveAspectRatio: true))
    context.drawPDFPage(pdf)
    return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: width * height * 4))
}

private func redWaxPixels(_ image: [UInt8]) -> Int {
    stride(from: 0, to: image.count, by: 4).reduce(0) { count, index in
        let r = Int(image[index]), g = Int(image[index + 1]), b = Int(image[index + 2])
        return count + (r > 55 && r > g + 35 && r > b + 35 && g < 125 ? 1 : 0)
    }
}

private func printedFont(for word: String, in text: NSAttributedString) throws -> NSFont {
    let range = (text.string as NSString).range(of: word)
    guard range.location != NSNotFound,
          let font = text.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont else {
        throw Failure("No printed font for \(word)")
    }
    return font
}

@MainActor @main private enum LetterPDFCheck {
    static let output = URL(fileURLWithPath: CommandLine.arguments[1])
    static let sheet = CGSize(width: 610, height: 800)

    static func export(_ page: Page, _ preferences: WritingPreferences, name: String) throws -> PDFDocument {
        let data = try LetterPDFExport.data(for: page, preferences: preferences, paperSize: sheet)
        try data.write(to: output.appendingPathComponent(name + ".pdf"))
        guard let document = PDFDocument(data: data), document.pageCount > 0 else {
            throw Failure("\(name): output was not a readable PDF")
        }
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { throw Failure("\(name): missing page \(index)") }
            let bounds = page.bounds(for: .mediaBox)
            try require(bounds.width == sheet.width && bounds.height == sheet.height,
                        "\(name): sheet size differs from the writing desk, \(bounds.size)")
        }
        // PDFPage holds a weak reference to its document. Keep the owner for text and artwork checks.
        return document
    }

    static func checkWrapping(focus: Bool, preferences: WritingPreferences) throws -> Int {
        let width = DeskLayout.paperWidth(windowWidth: 1280, focusMode: focus, widerFocusPaper: preferences.widerFocusPaper)
        let rect = CGRect(x: 0, y: 0, width: width, height: 720)
        let letter = Page(markdown: "I walked past the **garden gate** just after dawn and stopped to read your " +
            "letter beside the old fountain. The page was still folded where you had tucked the *violets* " +
            "between the lines. By the time I reached home, the wind had lifted the morning mist.")
        weak var coordinator: PaperEditor.Coordinator?
        let host = NSHostingView(rootView: PaperEditor(page: letter, preferences: preferences,
            onChange: { _, _, _ in }, onCaret: { _ in }, onStroke: { _ in },
            onConnect: { coordinator = $0 as? PaperEditor.Coordinator }))
        let window = NSWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        host.sizingOptions = []
        host.frame = rect
        window.contentView = host
        let writingWidth = CGFloat(width - 2 * preferences.writingMargin)
        let deadline = Date(timeIntervalSinceNow: 2)
        repeat {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        } while coordinator?.editor?.textContainer?.containerSize.width != writingWidth && Date() < deadline
        guard let editor = coordinator?.editor, let layout = editor.layoutManager, let container = editor.textContainer,
              container.containerSize.width == writingWidth else { throw Failure("The writing desk did not lay out") }
        layout.ensureLayout(for: container)
        var live: [String] = []
        layout.enumerateLineFragments(forGlyphRange: layout.glyphRange(for: container)) { _, _, _, glyphs, _ in
            let characters = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            let line = (editor.string as NSString).substring(with: characters)
            live.append(line.trimmingCharacters(in: .whitespaces))
        }
        let data = try LetterPDFExport.data(for: letter, preferences: preferences, paperSize: rect.size)
        guard let document = PDFDocument(data: data), document.pageCount == 1,
              let printed = document.page(at: 0)?.string else { throw Failure("Missing wrapped PDF text") }
        let lines = printed.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        try require(live.count > 1 && lines == live, "The PDF changed the editor's line breaks at \(width) pt")
        return lines.count
    }

    static func checkMarginStyles() throws {
        var preferences = WritingPreferences()
        preferences.wideMargins = false
        preferences.textureStrength = 0
        let letter = Page(markdown: "Dear Ada,\n\nI found your letter waiting on the writing desk.")
        let plain = try pixels(in: export(letter, preferences, name: "margin-none"))
        let width = Int(sheet.width), inset = Int(preferences.writingMargin)
        var silhouettes: [PaperMarginStyle: Set<Int>] = [:]
        for style in PaperMarginStyle.allCases where style != .none {
            preferences.marginStyle = style
            let decorated = try pixels(in: export(letter, preferences, name: "margin-" + style.rawValue))
            let ink = Set((0..<(plain.count / 4)).filter { pixel in
                let offset = pixel * 4
                return (0..<3).contains { abs(Int(decorated[offset + $0]) - Int(plain[offset + $0])) > 4 }
            })
            let left = ink.filter { $0 % width < inset }.count
            let right = ink.filter { $0 % width >= width - inset }.count
            try require(left > 100 && right > 100, "\(style) did not leave visible ink in both margins")
            try require(ink.count == left + right, "\(style) drew inside the narrow writing area")
            for (other, silhouette) in silhouettes {
                try require(ink.symmetricDifference(silhouette).count > 100, "\(style) looks the same as \(other)")
            }
            silhouettes[style] = ink
        }
        print("PASS: all \(silhouettes.count) decorative margins have distinct artwork and leave the writing area clear.")
    }

    static func main() throws {
        _ = NSApplication.shared.setActivationPolicy(.prohibited)
        try checkMarginStyles()
        var preferences = WritingPreferences()
        preferences.paper = .cream
        preferences.paperTexture = .cotton
        preferences.paperEmbossing = .makerMark
        preferences.embossingDepth = 0.90
        preferences.writingFont = .georgia
        preferences.ribbon = .midnight
        preferences.marginStyle = .botanical
        // Keep each character drawn once for the text extraction checks.
        preferences.wornInk = false
        let regularLines = try checkWrapping(focus: false, preferences: preferences)
        var focusPaper = preferences
        focusPaper.wideMargins = false
        let focusLines = try checkWrapping(focus: true, preferences: focusPaper)
        try require(focusLines < regularLines, "The wider Focus paper did not reflow the paragraph")
        var letter = Page(markdown: "# Garden notes\n\nDear Ada,\n\nThe **roses** and *violets* have bloomed.\n\nYours,\nMira")
        letter.seal = LetterSeal(text: "M. A.", shape: .oval, color: .oxblood)
        let short = try export(letter, preferences, name: "garden-notes")
        try require(short.pageCount == 1, "A short letter should fit on one sheet")
        let printed = short.string ?? ""
        try require(printed.contains("Garden notes") && printed.contains("violets") && printed.contains("Mira"),
                    "The PDF lost the heading, body, or closing")
        try require(!printed.contains("#") && !printed.contains("*"), "Markdown source markers appeared on the page")
        guard let styled = short.selectionForEntireDocument?.attributedString else {
            throw Failure("PDFKit could not read the formatted text in garden-notes.pdf")
        }
        let bodyFont = try printedFont(for: "Dear Ada", in: styled)
        let expectedFont = preferences.writingFont.nsFont(size: preferences.fontSize)
        try require(bodyFont.familyName == expectedFont.familyName && bodyFont.pointSize == expectedFont.pointSize,
                    "The PDF substituted the chosen typeface or size")
        try require(try printedFont(for: "Garden notes", in: styled).pointSize > bodyFont.pointSize,
                    "The heading lost its size")
        let bold = try printedFont(for: "roses", in: styled)
        let italic = try printedFont(for: "violets", in: styled)
        try require(NSFontManager.shared.traits(of: bold).contains(.boldFontMask)
                    && NSFontManager.shared.traits(of: italic).contains(.italicFontMask),
                    "The PDF lost an inline Markdown style")
        let shortPixels = try pixels(in: short)
        try require(redWaxPixels(shortPixels) > 1_000, "The seal was missing from the rendered letter")

        var worn = preferences
        worn.wornInk = true
        let wornLetter = try export(letter, worn, name: "worn-ink")
        try require(wornLetter.string == printed, "Ink overprints changed the selectable text")
        try require(try pixels(in: wornLetter) != shortPixels, "The worn ink effect was lost")

        let blank = try export(Page(), preferences, name: "blank-letter")
        try require(blank.pageCount == 1 && (blank.string ?? "").isEmpty,
                    "An empty letter should export as one blank sheet")
        try require(redWaxPixels(try pixels(in: blank)) == 0, "An unsealed letter gained a seal")
        var unembossed = preferences
        unembossed.paperEmbossing = .none
        let other = try pixels(in: export(letter, unembossed, name: "no-embossing"))
        let embossPixels = stride(from: 0, to: other.count, by: 4).filter {
            abs(Int(other[$0]) - Int(shortPixels[$0])) > 2
        }.count
        try require(embossPixels > 80, "The selected embossing did not affect the rendered paper")

        let entries = (1...80).map { String(format: "Entry%03d", $0) }
        // One long paragraph must be split at complete wrapped lines.
        var journal = Page(text: entries.map { "\($0) The leaves held the morning rain." }.joined(separator: " "))
        journal.seal = letter.seal
        preferences.paperMotion = .roll
        preferences.paperStartPosition = .bottom
        preferences.curvedPaper = true
        let rollDocument = try export(journal, preferences, name: "long-letter")
        try require(rollDocument.pageCount > 1, "The long letter was clipped to one page")
        let combined = rollDocument.string ?? ""
        let tokens = combined.components(separatedBy: .whitespacesAndNewlines).filter { $0.hasPrefix("Entry") }
        try require(tokens == entries, "PDF pagination skipped, duplicated, or reordered text")
        var sheetDesk = preferences
        sheetDesk.paperMotion = .sheet
        sheetDesk.curvedPaper = false
        let sheetDocument = try export(journal, sheetDesk, name: "long-letter-desk-flat")
        try require(sheetDocument.pageCount == rollDocument.pageCount, "Rolling the desk paper changed PDF pagination")
        let width = Int(sheet.width), height = Int(sheet.height)
        for index in 0..<rollDocument.pageCount {
            let image = try pixels(in: rollDocument, at: index)
            try require(try pixels(in: sheetDocument, at: index) == image,
                        "The on-desk curl or roller changed the exported artwork on page \(index + 1)")
            for y in [0, height - 1] {
                for x in [0, width - 1] {
                    let corner = (y * width + x) * 4
                    try require(Int(image[corner]) - Int(image[corner + 2]) > 20,
                                "The cream stock did not fill corner (\(x), \(y)) on page \(index + 1)")
                }
            }
            if index > 0 {
                // The continuation sheet has bare margins. Average across the grain to
                // distinguish a roller's dark side shadow from the stock's gentle gradient.
                let band = (height / 2)..<(height / 2 + 32)
                for (edge, interior) in [(0, 32), (width - 1, width - 33)] {
                    let difference = band.reduce(0) { sum, y in
                        sum + Int(image[(y * width + edge) * 4]) - Int(image[(y * width + interior) * 4])
                    }
                    try require(abs(difference) < band.count * 6, "The side of page \(index + 1) still has a curl shadow")
                }
            }
            let sealPixels = redWaxPixels(image)
            try require(index == rollDocument.pageCount - 1 ? sealPixels > 1_000 : sealPixels == 0,
                        "The wax seal was missing or appeared before the end (page \(index + 1))")
        }
        print("PASS: short letter styling, embossing, and \(rollDocument.pageCount) complete sheets with a single closing seal.")
        print("PASS: square, edge-to-edge stationery in Sheet and Roll modes.")
        print("PASS: PDF wrapping matches the live editor on regular (\(regularLines) lines) and wider Focus paper (\(focusLines) lines).")
    }
}
