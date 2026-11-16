import AppKit
import InkrailCore

private struct InkCheckError: Error, CustomStringConvertible {
    let description: String
}

private struct InkBitmap {
    let image: CGImage
    let pixels: [UInt8]
    let width: Int
    let height: Int

    func darkness(in region: CGRect) -> Double {
        let left = max(0, Int(floor(region.minX * 2)))
        let right = min(width, Int(ceil(region.maxX * 2)))
        let top = max(0, Int(floor(region.minY * 2)))
        let bottom = min(height, Int(ceil(region.maxY * 2)))
        guard left < right, top < bottom else { return 0 }
        var total = 0.0
        for y in top..<bottom {
            for x in left..<right {
                total += 255 - Double(pixels[(y * width + x) * 4])
            }
        }
        return total
    }
}

/// The production layout manager owns all glyph shaping and drawing. Drawing
/// to an explicit bitmap avoids display dithering and window capture timing.
/// This is an isolated native component render, not a running-app screenshot.
@MainActor
private final class InkProbe {
    let storage: NSTextStorage
    let layout = InkLayoutManager()
    let container: NSTextContainer
    let editor: NSTextView
    let origin = NSPoint(x: 32, y: 28)
    let size = NSSize(width: 760, height: 260)

    init(text: String, font: NSFont, ligatures: Int = 0) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 7
        storage = NSTextStorage(string: text, attributes: [
            .font: font, .foregroundColor: NSColor(calibratedWhite: 0.15, alpha: 0.88),
            .paragraphStyle: paragraph, .ligature: ligatures
        ])
        container = NSTextContainer(size: NSSize(width: 696, height: 204))
        container.lineFragmentPadding = 0
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        editor = NSTextView(frame: NSRect(origin: .zero, size: size), textContainer: container)
        editor.isRichText = false
        editor.isEditable = true
        editor.allowsUndo = true
        editor.textContainerInset = NSSize(width: origin.x, height: origin.y)
        editor.setSelectedRange(NSRange(location: min(5, storage.length), length: 0))
        layout.ensureLayout(for: container)
    }

    func geometry() -> [String] {
        layout.ensureLayout(for: container)
        var result = [NSStringFromRect(layout.usedRect(for: container))]
        for glyph in 0..<layout.numberOfGlyphs {
            let range = NSRange(location: glyph, length: 1)
            let bounds = layout.boundingRect(forGlyphRange: range, in: container)
            let point = NSPoint(x: bounds.midX, y: bounds.midY)
            result.append("\(layout.characterIndexForGlyph(at: glyph)):\(NSStringFromPoint(layout.location(forGlyphAt: glyph))):\(NSStringFromRect(bounds)):\(layout.glyphIndex(for: point, in: container))")
        }
        return result
    }

    func render(worn: Bool, buildup: Double, composing: Bool = false) throws -> InkBitmap {
        layout.wornInk = worn
        layout.inkBuildup = buildup
        layout.composing = composing
        layout.ensureLayout(for: container)
        let width = Int(size.width * 2), height = Int(size.height * 2)
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw InkCheckError(description: "Cannot allocate native ink bitmap")
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 2, y: -2)
        context.setShouldAntialias(true)
        context.setShouldSmoothFonts(false)
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        let range = NSRange(location: 0, length: layout.numberOfGlyphs)
        layout.drawBackground(forGlyphRange: range, at: origin)
        layout.drawGlyphs(forGlyphRange: range, at: origin)
        NSGraphicsContext.current = previous
        guard let image = context.makeImage(), let data = context.data else {
            throw InkCheckError(description: "Cannot extract native ink bitmap")
        }
        return InkBitmap(image: image, pixels: Array(UnsafeBufferPointer(
            start: data.assumingMemoryBound(to: UInt8.self), count: width * height * 4)),
            width: width, height: height)
    }
}

@main
@MainActor
private enum InkRenderingCheck {
    static var checks = 0
    static var renders = 0
    static let output = URL(fileURLWithPath: CommandLine.arguments[1])

    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw InkCheckError(description: message) }
        checks += 1
    }

    static func save(_ bitmap: InkBitmap, _ name: String) throws {
        guard let png = NSBitmapImageRep(cgImage: bitmap.image).representation(using: .png, properties: [:]) else {
            throw InkCheckError(description: "Cannot encode \(name)")
        }
        try png.write(to: output.appendingPathComponent(name + ".png"))
        renders += 1
    }

    static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        for font in WritingFont.allCases {
            for size in [20.0, 28.0] {
                try checkStrikes(font: font, size: size)
            }
        }
        try checkUnicodeAndComposition()
        try checkNativeLigatures()
        print("PASS \(checks) native ink checks; \(renders) isolated component renders in \(output.path).")
        print("These are deterministic TextKit bitmap renders, not live screenshots or real OS input-method tests.")
    }

    static func checkStrikes(font: WritingFont, size: Double) throws {
        let text = String(repeating: "e", count: 36) + "\n\n"
            + "Old keys leave their marks.\nA little more ink, a little less certainty."
        let probe = InkProbe(text: text, font: font.nsFont(size: size))
        let beforeGeometry = probe.geometry()
        let beforeText = NSAttributedString(attributedString: probe.storage)
        let selection = probe.editor.selectedRange()
        let clean = try probe.render(worn: false, buildup: 1)
        let strong = try probe.render(worn: true, buildup: 1)
        let again = try probe.render(worn: true, buildup: 1)
        let restored = try probe.render(worn: false, buildup: 1)
        let label = "\(font.label) \(Int(size))pt"
        try require(strong.pixels == again.pixels, "\(label): repeated render changed its ink pattern")
        try require(clean.pixels == restored.pixels, "\(label): switching wear off did not restore native drawing")
        try require(beforeGeometry == probe.geometry(), "\(label): ink treatment changed glyph layout or hit testing")
        try require(probe.storage.isEqual(to: beforeText) && probe.editor.selectedRange() == selection,
                    "\(label): drawing mutated text attributes or selection")
        var heavier = 0, lighter = 0
        var ratios: [Double] = []
        for index in 0..<36 {
            let glyph = probe.layout.glyphIndexForCharacter(at: index)
            let bounds = probe.layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: probe.container)
                .offsetBy(dx: probe.origin.x, dy: probe.origin.y)
            let before = clean.darkness(in: bounds)
            let after = strong.darkness(in: bounds)
            try require(before > 500, "\(label): repeated letter \(index) is missing from its native glyph bounds")
            let ratio = after / before
            ratios.append(ratio)
            if ratio > 1.05 { heavier += 1 }
            if ratio < 0.95 { lighter += 1 }
        }
        try require(heavier >= 2 && heavier < 30, "\(label): expected occasional heavy strikes, found \(heavier)/36")
        try require(lighter >= 2, "\(label): expected lighter worn strikes, found \(lighter)/36")
        print("PASS \(label): \(heavier) heavier / \(lighter) lighter strikes; ink energy \(String(format: "%.2f", ratios.min()!))–\(String(format: "%.2f", ratios.max()!))× clean; geometry, text and selection preserved")
        let slug = "\(font.rawValue)-\(Int(size))"
        try save(clean, slug + "-clean")
        try save(strong, slug + "-worn")
    }

    static func checkUnicodeAndComposition() throws {
        let unicode = InkProbe(text: "नमस्ते हिन्दी\n漢字かなカナ\ne\u{301} a\u{308} n\u{303} 👩🏽‍💻",
                               font: WritingFont.courier.nsFont(size: 28))
        let geometry = unicode.geometry()
        let native = try unicode.render(worn: false, buildup: 1)
        let worn = try unicode.render(worn: true, buildup: 1)
        try require(native.pixels == worn.pixels, "Complex scripts, emoji or combining accents left native drawing")
        try require(geometry == unicode.geometry(), "Complex-script glyph layout changed")
        try save(worn, "unicode-native")

        let marked = InkProbe(text: "Composition remains native.", font: WritingFont.courier.nsFont(size: 28))
        marked.editor.setMarkedText("candidate", selectedRange: NSRange(location: 0, length: 9),
                                    replacementRange: NSRange(location: 0, length: 11))
        try require(marked.editor.hasMarkedText(), "Programmatic marked-text setup failed")
        let selection = marked.editor.selectedRange()
        let markedRange = marked.editor.markedRange()
        let cleanMarked = try marked.render(worn: false, buildup: 1, composing: true)
        let wornMarked = try marked.render(worn: true, buildup: 1, composing: true)
        try require(cleanMarked.pixels == wornMarked.pixels, "Composition guard changed native glyph rendering")
        try require(marked.editor.selectedRange() == selection && marked.editor.markedRange() == markedRange,
                    "Rendering altered marked-text selection/range")
        try save(wornMarked, "marked-text-native")
        print("PASS native Unicode, combining accents and programmatic marked-text composition guard")
    }

    static func checkNativeLigatures() throws {
        var exercised = 0
        for font in [WritingFont.georgia, .americanTypewriter] {
            for text in ["fi", "fl", "ffi", "ffl"] {
                let probe = InkProbe(text: text, font: font.nsFont(size: 28), ligatures: 2)
                // Only count strings this installed face actually shapes as
                // one multi-character glyph. TextKit can retain null glyph
                // slots for the additional characters; count the character
                // mapping rather than assuming just one glyph slot exists.
                guard probe.layout.numberOfGlyphs > 0 else { continue }
                let characters = probe.layout.characterRange(forGlyphRange: NSRange(location: 0, length: 1),
                                                              actualGlyphRange: nil)
                guard characters.length > 1 && characters.length == probe.storage.length else { continue }
                let clean = try probe.render(worn: false, buildup: 1)
                let worn = try probe.render(worn: true, buildup: 1)
                try require(clean.pixels == worn.pixels, "\(font.label) \(text): native ligature received ink overprints")
                exercised += 1
            }
        }
        try require(exercised > 0, "No installed font produced a native ligature; this guard was not exercised")
        print("PASS \(exercised) actual multi-character native ligatures retain native drawing")
    }
}
