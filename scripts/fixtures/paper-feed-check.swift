import AppKit
import SwiftUI
import InkrailCore
import Darwin

// The editor needs these two application-level declarations, but it does not
// need AppModel, saved preferences, audio resources or the real app entry point.
enum StrokeKind { case key, space, carriage, erase, navigation }
extension Notification.Name {
    static let inkrailFocusEditor = Notification.Name("Inkrail.FocusEditor")
}

private struct ProbeError: Error, CustomStringConvertible {
    let description: String
}

@MainActor
private final class ProbeWindow: NSWindow {
    let probeUndoManager = UndoManager()
    override var undoManager: UndoManager? { probeUndoManager }
}

/// Runs actual NSTextView operations in an isolated, unshown native window.
/// Synthetic marked text exercises the programmatic composition path only:
/// it does not test OS keyboard input methods or their candidate windows.
@MainActor
private final class PaperFeedProbe {
    private let window: ProbeWindow
    private var pageID = UUID()
    private var text = ""
    private var formatting: [TextFormatRun] = []
    private var activeEmphasis: TextEmphasis = []
    private var preferences = WritingPreferences()
    private var latestCaret: CaretPosition?
    private var changeCount = 0
    private var checkCount = 0
    private var failures: [String] = []
    private var recordedOffsets: [CGFloat] = []
    private var strokes: [StrokeKind] = []
    private lazy var host = NSHostingView(rootView: representation())
    private var editor: InkTextView!
    private var scroll: NSScrollView!

    init() {
        window = ProbeWindow(contentRect: NSRect(x: 40, y: 40, width: 720, height: 640),
                             styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Inkrail isolated paper-feed checks"
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        window.probeUndoManager.groupsByEvent = false
        preferences.soundEnabled = false
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        host.frame = NSRect(x: 0, y: 0, width: 720, height: 640)
        window.contentView = host
    }

    private func representation() -> PaperEditor {
        PaperEditor(pageID: pageID, text: text, formatting: formatting, preferences: preferences,
                    onChange: { [weak self] text, formatting in
                        guard let self else { return }
                        self.text = text
                        self.formatting = formatting
                        self.changeCount += 1
                        DispatchQueue.main.async { [weak self] in self?.refresh() }
                    },
                    onCaret: { [weak self] value in
                        self?.latestCaret = value
                        self?.recordedOffsets.append(value.scrollOffset)
                    },
                    onStroke: { [weak self] kind in self?.strokes.append(kind) },
                    onEmphasisChange: { [weak self] in self?.activeEmphasis = $0 })
    }

    private func refresh() { host.rootView = representation() }

    private func settle(_ interval: TimeInterval = 0.16) {
        let deadline = Date(timeIntervalSinceNow: interval)
        repeat {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        } while Date() < deadline
        host.layoutSubtreeIfNeeded()
    }

    private func descendant<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for child in view.subviews {
            if let match = descendant(type, in: child) { return match }
        }
        return nil
    }

    private func check(_ condition: @autoclosure () -> Bool, _ label: String,
                       detail: @autoclosure () -> String = "") {
        checkCount += 1
        if condition() {
            print("PASS: \(label)")
        } else {
            let explanation = detail()
            let message = label + (explanation.isEmpty ? "" : " — " + explanation)
            failures.append(message)
            print("FAIL: \(message)")
        }
    }

    private func resize(width: CGFloat = 720, height: CGFloat) {
        window.setContentSize(NSSize(width: width, height: height))
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        settle()
    }

    private func mode(_ position: PaperStartPosition, height: CGFloat) {
        preferences.paperStartPosition = position
        refresh()
        resize(height: height)
    }

    private func edit(_ operation: () -> Void) {
        editor.breakUndoCoalescing()
        window.probeUndoManager.beginUndoGrouping()
        operation()
        editor.breakUndoCoalescing()
        window.probeUndoManager.endUndoGrouping()
        settle()
    }

    private func insert(_ value: String) {
        edit { editor.insertText(value, replacementRange: NSRange(location: NSNotFound, length: 0)) }
    }

    private func caretBottom() -> CGFloat {
        let selection = editor.selectedRange()
        let screen = editor.firstRect(forCharacterRange: NSRange(location: selection.location, length: 0),
                                      actualRange: nil)
        let clip = scroll.contentView
        let rect = clip.convert(window.convertFromScreen(screen), from: nil)
        return clip.isFlipped ? rect.maxY - clip.bounds.minY : clip.bounds.maxY - rect.minY
    }

    private func checkBottomBand(_ label: String) {
        let actual = caretBottom()
        let expected = scroll.contentView.bounds.height - 4
        check(actual.isFinite && abs(actual - expected) <= 3, label,
              detail: "caret \(actual), expected \(expected), scroll \(scroll.contentView.bounds.minY), inset \(editor.textContainerInset), frame \(editor.frame), container \(editor.textContainer?.containerSize ?? .zero)")
    }

    private func usedHeight() -> CGFloat {
        guard let container = editor.textContainer, let layout = editor.layoutManager else { return 0 }
        layout.ensureLayout(for: container)
        return layout.usedRect(for: container).height
    }

    private func checkMigration() throws {
        print("Preference checks (standalone Foundation assertions, not XCTest):")
        // Actual old-format data: the new paperStartPosition field is absent.
        let legacy = """
        {"mechanismStyle":"walnut","matchRailToStyle":false,"paper":"cream",
         "capsule":"cobalt","rail":"charcoal","ribbon":"oxblood","fontSize":24,
         "inkStrength":0.73,"wornInk":false,"wideMargins":false,"curvedPaper":true,
         "garden":true,"soundEnabled":false,"soundVolume":0.12,"nightMode":true,
         "lampIntensity":0.49,"lampWarmth":0.91}
        """
        let decoder = JSONDecoder()
        let old = try decoder.decode(WritingPreferences.self, from: Data(legacy.utf8))
        check(old.paperStartPosition == .top, "legacy preferences default to Top")
        check(old.paperMotion == .sheet && old.effectivePaperStartPosition == .top,
              "legacy preferences keep Sheet motion and their original starting position")
        check(old.paperTexture == .classic && old.textureStrength == 0.55
              && old.paperEmbossing == .none && old.embossingDepth == 0.45
              && old.writingFont == .courier && old.typewriterSound == .classic,
              "legacy preferences retain original paper, Courier and Classic sounds")
        check(old.mechanismStyle == .walnut && !old.matchRailToStyle && old.rail == .charcoal
              && old.fontSize == 24 && old.nightMode && old.paper == .cream
              && old.capsule == .cobalt && old.ribbon == .oxblood
              && !old.soundEnabled && old.lampWarmth == 0.91,
              "legacy style, manual rail, typography and lamp preferences survive")
        for field in ["null", "\"future-paper-feed\""] {
            let json = "{\"paperStartPosition\":\(field),\"mechanismStyle\":\"walnut\",\"fontSize\":24}"
            let decoded = try decoder.decode(WritingPreferences.self, from: Data(json.utf8))
            check(decoded.paperStartPosition == .top && decoded.mechanismStyle == .walnut
                  && decoded.fontSize == 24, "\(field) position falls back without resetting other values")
        }
        var bottom = old
        bottom.paperStartPosition = .bottom
        let restored = try decoder.decode(WritingPreferences.self, from: JSONEncoder().encode(bottom))
        check(restored == bottom, "Bottom preference round-trips with all existing values")
        let customized = try decoder.decode(WritingPreferences.self, from: Data("""
        {"paperStartPosition":"bottom","paperTexture":"cotton","textureStrength":0.71,
         "paperEmbossing":"botanical","embossingDepth":0.32,"writingFont":"georgia",
         "typewriterSound":"soft","mechanismStyle":"champagne","lampWarmth":0.19}
        """.utf8))
        check(customized.paperTexture == .cotton && customized.paperEmbossing == .botanical
              && customized.writingFont == .georgia && customized.typewriterSound == .soft
              && customized.paperStartPosition == .bottom && customized.mechanismStyle == .champagne,
              "customization choices decode alongside paper feed and mechanism style")
        let restoredCustomization = try decoder.decode(WritingPreferences.self, from: JSONEncoder().encode(customized))
        check(restoredCustomization == customized, "all customization values persist through encoding")
        let future = try decoder.decode(WritingPreferences.self, from: Data("""
        {"paperTexture":"future","paperEmbossing":"future","writingFont":"future",
         "typewriterSound":"future","textureStrength":-2,"embossingDepth":7,
         "paperStartPosition":"bottom","lampWarmth":0.19}
        """.utf8))
        check(future.paperTexture == .classic && future.paperEmbossing == .none
              && future.writingFont == .courier && future.typewriterSound == .classic
              && future.textureStrength == 0 && future.embossingDepth == 1
              && future.paperStartPosition == .bottom && future.lampWarmth == 0.19,
              "unknown customization values fall back and amounts clamp without resetting other settings")
        let roll = try decoder.decode(WritingPreferences.self, from: Data("""
        {"paperMotion":"roll","paperStartPosition":"top","typewriterSound":"recorded",
         "mechanismStyle":"walnut","fontSize":24,"lampWarmth":0.19}
        """.utf8))
        check(roll.paperMotion == .roll && roll.paperStartPosition == .top
              && roll.effectivePaperStartPosition == .top && roll.typewriterSound == .classic,
              "legacy Roll honors Top and removed Recorded falls back to Classic")
        let restoredRoll = try decoder.decode(WritingPreferences.self, from: JSONEncoder().encode(roll))
        check(restoredRoll == roll,
              "Roll and its chosen starting position round-trip with existing customizations")
        for value in ["null", "\"future-motion\""] {
            let decoded = try decoder.decode(WritingPreferences.self, from: Data(
                "{\"paperMotion\":\(value),\"paperStartPosition\":\"bottom\",\"fontSize\":24}".utf8))
            check(decoded.paperMotion == .sheet && decoded.paperStartPosition == .bottom && decoded.fontSize == 24,
                  "\(value) paper motion falls back without resetting layout or type size")
        }
    }

    private func checkScrollCallback(_ label: String) {
        check(latestCaret != nil && abs((latestCaret?.scrollOffset ?? -1) - max(0, scroll.contentView.bounds.minY)) <= 1,
              label, detail: "callback \(latestCaret?.scrollOffset ?? -1), native \(scroll.contentView.bounds.minY)")
    }

    private func checkArrowNavigation() throws {
        pageID = UUID()
        text = "abc\ndef\nghi"
        formatting = []
        refresh()
        settle()
        window.makeFirstResponder(editor)
        strokes.removeAll()
        let start = NSRange(location: 5, length: 0)
        editor.setSelectedRange(start)
        check(strokes.isEmpty, "placing the caret programmatically makes no navigation stroke")

        func press(_ key: NSEvent.SpecialKey, code: UInt16, flags: NSEvent.ModifierFlags = [], repeatKey: Bool = false) throws {
            let character = String(key.unicodeScalar)
            guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: flags.union([.numericPad, .function]), timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: character,
                charactersIgnoringModifiers: character, isARepeat: repeatKey, keyCode: code) else {
                throw ProbeError(description: "Could not create arrow key event")
            }
            editor.keyDown(with: event)
        }

        try press(.leftArrow, code: 123)
        check(editor.selectedRange().location == 4, "Left moves the caret back a character")
        try press(.rightArrow, code: 124, repeatKey: true)
        check(editor.selectedRange() == start, "a repeated Right moves the caret forward")
        try press(.upArrow, code: 126)
        check(editor.selectedRange().location < 4, "Up moves the caret to the previous line")
        try press(.downArrow, code: 125)
        check(editor.selectedRange() == start, "Down moves the caret back to the same column")
        try press(.rightArrow, code: 124, flags: .shift)
        check(editor.selectedRange() == NSRange(location: 5, length: 1), "Shift-Right extends the selection")
        check(strokes == Array(repeating: .navigation, count: 5), "each arrow generates exactly one navigation stroke",
              detail: "\(strokes)")
        check(editor.string == "abc\ndef\nghi", "arrow events preserve the letter")
    }

    private func checkFormatting() throws {
        let letter = "🪶 Ink and paper"
        let words = letter as NSString
        let boldRange = words.range(of: "Ink and")
        let italicRange = words.range(of: "and paper")
        let overlap = NSIntersectionRange(boldRange, italicRange)
        let bold = TextFormatRun(location: boldRange.location, length: boldRange.length, emphasis: .bold)
        let combined = [
            TextFormatRun(location: boldRange.location, length: overlap.location - boldRange.location, emphasis: .bold),
            TextFormatRun(location: overlap.location, length: overlap.length, emphasis: [.bold, .italic]),
            TextFormatRun(location: NSMaxRange(overlap), length: NSMaxRange(italicRange) - NSMaxRange(overlap), emphasis: .italic)
        ]
        pageID = UUID()
        text = letter
        formatting = []
        preferences.writingFont = .courier
        refresh()
        settle()
        guard let storage = editor.textStorage else { throw ProbeError(description: "Missing editor storage") }
        editor.setSelectedRange(boldRange)
        edit { editor.toggleEmphasis(.bold) }
        check(formatting == [bold] && text == letter && editor.selectedRange() == boldRange,
              "bold applies to the selected UTF-16 range and preserves the selection")
        editor.setSelectedRange(italicRange)
        edit { editor.toggleEmphasis(.italic) }
        check(formatting == combined && activeEmphasis == .italic,
              "overlapping bold and italic keep both styles and report the shared selection style")

        if window.probeUndoManager.canUndo { window.probeUndoManager.undo(); settle() }
        check(formatting == [bold] && editor.string == letter,
              "Undo restores the prior emphasis without changing the words")
        if window.probeUndoManager.canRedo { window.probeUndoManager.redo(); settle() }
        check(formatting == combined && editor.string == letter, "Redo restores overlapping emphasis")

        preferences.writingFont = .georgia
        preferences.fontSize = 23
        refresh()
        settle()
        func checkLetterAppearance(_ label: String) {
            let chosen = preferences.writingFont.nsFont(size: preferences.fontSize)
            let attributes = storage.attributes(at: overlap.location, effectiveRange: nil)
            let displayFont = attributes[.font] as? NSFont
            let plainFont = storage.attribute(.font, at: boldRange.location - 1, effectiveRange: nil) as? NSFont
            let traits = displayFont?.fontDescriptor.symbolicTraits ?? []
            let boldInk = traits.contains(.bold) || ((attributes[.strokeWidth] as? NSNumber)?.doubleValue ?? 0) < 0
            let slanted = traits.contains(.italic) || ((attributes[.obliqueness] as? NSNumber)?.doubleValue ?? 0) != 0
            check(formatting == combined && boldInk && slanted && plainFont?.fontName == chosen.fontName
                  && displayFont?.familyName == chosen.familyName
                  && displayFont?.pointSize == chosen.pointSize, label)
        }
        checkLetterAppearance("changing writing preferences renders the emphasis in the chosen font family and size")
        if window.probeUndoManager.canUndo { window.probeUndoManager.undo(); settle() }
        let undoFont = storage.attribute(.font, at: overlap.location, effectiveRange: nil) as? NSFont
        let chosen = preferences.writingFont.nsFont(size: preferences.fontSize)
        check(formatting == [bold] && undoFont?.familyName == chosen.familyName && undoFont?.pointSize == chosen.pointSize,
              "undoing an earlier style change keeps the current typeface and size")
        if window.probeUndoManager.canRedo { window.probeUndoManager.redo(); settle() }
        checkLetterAppearance("redoing emphasis after a font change uses the current typeface and size")
        preferences.writingFont = .monaco
        refresh()
        settle()
        checkLetterAppearance("a face without bold or italic variants retains its typeface and displays both styles")
        let savedPage = pageID
        pageID = UUID()
        text = "New "
        formatting = []
        refresh()
        settle()
        check(activeEmphasis.isEmpty, "opening an unformatted letter clears active styles")
        edit { editor.toggleEmphasis(.underline) }
        check(activeEmphasis == .underline && formatting.isEmpty,
              "underline at the caret chooses the style for upcoming text")
        insert("in")
        insert("k")
        edit { editor.toggleEmphasis(.underline) }
        insert(".")
        let underline = TextFormatRun(location: 4, length: 3, emphasis: .underline)
        check(text == "New ink." && formatting == [underline],
              "underline applies across consecutive edits and stops when toggled off")
        let underlineValue = storage.attribute(.underlineStyle, at: 4, effectiveRange: nil) as? NSNumber
        check(underlineValue?.intValue == NSUnderlineStyle.single.rawValue, "typed underline reaches the rendered text")
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        insert("🪶")
        check(formatting == [TextFormatRun(location: 6, length: 3, emphasis: .underline)],
              "editing before formatted text shifts its UTF-16 range")

        pageID = savedPage
        text = letter
        formatting = combined
        refresh()
        settle()
        checkLetterAppearance("reopening a letter restores its formatting in the active typeface")
        editor.setSelectedRange(italicRange)
        edit { editor.toggleEmphasis(.italic) }
        check(formatting == [bold], "toggling off italic preserves overlapping bold")
    }

    private func checkMarkdownTyping() throws {
        pageID = UUID()
        text = ""
        formatting = []
        refresh()
        settle()
        let source = "# Letter\n🪶 **bold** then _italic_, ~~strike~~ and `code`.\n```\n**literal**\n```\n    *literal*\n"
        edit {
            for character in source {
                editor.insertText(String(character), replacementRange: NSRange(location: NSNotFound, length: 0))
            }
        }
        let expected = Page(markdown: source)
        check(text == expected.text && formatting == expected.formatting,
              "typed shortcuts match Markdown import, including literal fenced code and plain text after a span")
        let headingFont = editor.textStorage?.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
        let bodyFont = preferences.writingFont.nsFont(size: preferences.fontSize)
        check(headingFont?.familyName == bodyFont.familyName && (headingFont?.pointSize ?? 0) > bodyFont.pointSize,
              "typing a heading styles it in the letter's typeface")
        editor.setSelectedRange(NSRange(location: 0, length: (text as NSString).length))
        guard let selection = editor.encodedSelection(), let copy = editor.decodeSelection(selection) else {
            throw ProbeError(description: "The formatted selection could not round-trip.")
        }
        let strike = (copy.string as NSString).range(of: "strike")
        check(copy.string == text && strike.location != NSNotFound
              && (copy.attribute(.strikethroughStyle, at: strike.location, effectiveRange: nil) as? NSNumber)?.intValue == 1,
              "copying and pasting a letter selection preserves Markdown emphasis")
        editor.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        insert("**end*")
        insert("*")
        check(text == expected.text + "end" && formatting.last?.emphasis == .bold,
              "the closing keystroke converts the delimiters to bold")
        window.probeUndoManager.undo()
        settle()
        check(text == expected.text + "**end*", "one Undo restores the text before the closing keystroke")
        window.probeUndoManager.redo()
        settle()
        check(text == expected.text + "end" && formatting.last?.emphasis == .bold,
              "Redo restores the converted Markdown")
    }

    private func checkHeadingMarkers() throws {
        guard let layout = editor.layoutManager, let container = editor.textContainer else {
            throw ProbeError(description: "Heading marker checks require the native text layout.")
        }
        func glyphX(at character: Int) -> CGFloat {
            let glyph = layout.glyphIndexForCharacter(at: character)
            return layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minX
                + layout.location(forGlyphAt: glyph).x
        }
        func drawsInk(_ characters: NSRange) throws -> Bool {
            let width = 256, height = 160
            guard let canvas = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                         bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                         bitmapInfo: CGImageAlphaInfo.none.rawValue), let data = canvas.data else {
                throw ProbeError(description: "Could not render the heading glyphs.")
            }
            canvas.setFillColor(gray: 1, alpha: 1)
            canvas.fill(CGRect(x: 0, y: 0, width: width, height: height))
            canvas.translateBy(x: 8, y: 96)
            canvas.scaleBy(x: 1, y: -1)
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            NSGraphicsContext.current = NSGraphicsContext(cgContext: canvas, flipped: true)
            let glyphs = layout.glyphRange(forCharacterRange: characters, actualCharacterRange: nil)
            layout.drawGlyphs(forGlyphRange: glyphs, at: .zero)
            canvas.flush()
            return UnsafeRawBufferPointer(start: data, count: width * height).contains { $0 < 240 }
        }

        let bodySize = CGFloat(preferences.fontSize)
        func fontSize(at character: Int) -> CGFloat? {
            (editor.textStorage?.attribute(.font, at: character, effectiveRange: nil) as? NSFont)?.pointSize
        }
        pageID = UUID()
        text = ""
        formatting = []
        preferences.paperMotion = .sheet
        refresh()
        settle()
        insert("#")
        insert(" ")
        let pendingHash = try drawsInk(NSRange(location: 0, length: 1))
        check(pendingHash && fontSize(at: 0) == bodySize
              && (editor.typingAttributes[.font] as? NSFont)?.pointSize == bodySize,
              "a hash and space stay visible in the selected body style")
        insert("H")
        let hiddenMarker = try !drawsInk(NSRange(location: 0, length: 2))
        let visibleH = try drawsInk(NSRange(location: 2, length: 1))
        check(hiddenMarker && visibleH && (fontSize(at: 2) ?? 0) > bodySize,
              "the first heading letter immediately renders the heading")
        edit { editor.deleteBackward(nil) }
        let revealedHash = try drawsInk(NSRange(location: 0, length: 1))
        check(text == "# " && revealedHash && fontSize(at: 0) == bodySize
              && (editor.typingAttributes[.font] as? NSFont)?.pointSize == bodySize,
              "deleting the last heading letter restores the visible marker and body style")

        pageID = UUID()
        text = "# \t\nBody"
        refresh()
        settle()
        let whitespaceOnlyHash = try drawsInk(NSRange(location: 0, length: 1))
        check(whitespaceOnlyHash && fontSize(at: 0) == bodySize,
              "reopening a marker followed by whitespace and a newline keeps it literal")

        pageID = UUID()
        text = ""
        refresh()
        settle()
        insert(">")
        insert(" ")
        let pendingQuote = editor.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        check(pendingQuote?.headIndent == 0, "a quote marker waits for content before indenting")
        insert("Q")
        let quote = editor.textStorage?.attribute(.paragraphStyle, at: 2, effectiveRange: nil) as? NSParagraphStyle
        check((quote?.headIndent ?? 0) > 0, "the first quote letter indents the paragraph")

        let sample = "## HI\nBody"
        pageID = UUID()
        text = ""
        refresh()
        settle()
        insert("#")
        insert("#")
        layout.ensureLayout(for: container)
        let literalHashes = try drawsInk(NSRange(location: 0, length: 2))
        check(literalHashes, "incomplete heading syntax still shows the literal hashes")
        for character in " HI" { insert(String(character)) }
        edit { editor.insertNewline(nil) }
        insert("Body")
        layout.ensureLayout(for: container)
        let prefixInk = try drawsInk(NSRange(location: 0, length: 3))
        let headingInk = try drawsInk(NSRange(location: 3, length: 2))
        check(!prefixInk && headingInk, "typed heading draws HI and suppresses the two hashes and separator")
        check(abs(glyphX(at: 3) - glyphX(at: 6)) <= 0.5,
              "heading text aligns with the body at the writing margin")
        let bodyFont = editor.textStorage?.attribute(.font, at: 6, effectiveRange: nil) as? NSFont
        let headingFont = editor.textStorage?.attribute(.font, at: 3, effectiveRange: nil) as? NSFont
        check(bodyFont?.pointSize == bodySize && (headingFont?.pointSize ?? 0) > bodySize,
              "Return after the heading resumes the selected body size")
        check(text == sample && Page(text: text, formatting: formatting).markdownText == sample,
              "the heading's Markdown source survives typing and export")
        editor.setSelectedRange(NSRange(location: 3, length: 0))
        edit { editor.deleteBackward(nil) }
        let editedHashes = try drawsInk(NSRange(location: 0, length: 2))
        check(editor.string == "##HI\nBody" && editedHashes,
              "deleting the heading separator restores literal hashes")
        window.probeUndoManager.undo()
        settle()
        let restoredPrefix = try drawsInk(NSRange(location: 0, length: 3))
        check(text == sample && !restoredPrefix, "Undo restores the formatted heading and hides its marker")
        pageID = UUID()
        preferences.paperMotion = .roll
        preferences.paperStartPosition = .bottom
        refresh()
        settle()
        layout.ensureLayout(for: container)
        check(editor.string == sample && abs(glyphX(at: 3) - glyphX(at: 6)) <= 0.5,
              "opening the heading in Bottom Paper Roll keeps its text at the writing margin")
    }

    private func checkUnbrokenTyping() throws {
        guard let layout = editor.layoutManager, let container = editor.textContainer else {
            throw ProbeError(description: "Missing native text layout for continuous typing checks.")
        }
        let beginning = "First line.\n"
        let word = String(repeating: "w", count: 128)
        for motion in [PaperMotion.sheet, .roll] {
            strokes.removeAll()
            preferences.paperMotion = motion
            preferences.paperStartPosition = motion == .sheet ? .top : .bottom
            preferences.wideMargins = motion == .roll
            pageID = UUID()
            text = beginning
            refresh()
            resize(width: 720, height: 430)
            let previousWidth = editor.frame.width
            let previousContainerSize = container.containerSize
            let paperWidth: CGFloat = 420
            resize(width: paperWidth, height: 430)
            let clip = scroll.contentView
            let firstGlyph = NSRange(location: 0, length: 1)
            let initialLeft = editor.textContainerOrigin.x
                + layout.boundingRect(forGlyphRange: firstGlyph, in: container).minX
            // Exercise a document that still has its earlier width when the
            // next edit arrives in the narrower viewport.
            if motion == .roll {
                editor.setFrameSize(NSSize(width: previousWidth, height: editor.frame.height))
                container.containerSize = previousContainerSize
            }
            let label = "\(motion.rawValue) continuous typing"
            check(strokes.isEmpty, "\(label) loading and resizing the paper emit no strokes")
            check(abs(editor.frame.width - paperWidth) <= 1,
                  "\(label) starts with the document sized to the current viewport",
                  detail: "document width \(editor.frame.width), paper width \(paperWidth)")
            var maxHorizontalOffset: CGFloat = 0
            var furthestGlyphEdge: CGFloat = 0
            edit {
                for character in word {
                    editor.insertText(String(character), replacementRange: NSRange(location: NSNotFound, length: 0))
                    settle(0.01)
                    maxHorizontalOffset = max(maxHorizontalOffset, abs(clip.bounds.minX))
                    layout.ensureLayout(for: container)
                    if layout.numberOfGlyphs > 0 {
                        let glyph = NSRange(location: layout.numberOfGlyphs - 1, length: 1)
                        let bounds = layout.boundingRect(forGlyphRange: glyph, in: container)
                        furthestGlyphEdge = max(furthestGlyphEdge, editor.textContainerOrigin.x + bounds.maxX)
                    }
                }
            }
            let expected = beginning + word
            let expectedCaret = NSRange(location: expected.utf16.count, length: 0)
            check(text == expected && editor.string == expected && editor.selectedRange() == expectedCaret,
                  "\(label) keeps the original text and caret at its end")
            guard layout.numberOfGlyphs > beginning.utf16.count else {
                throw ProbeError(description: "\(label) did not lay out the typed word.")
            }
            let firstWordGlyph = layout.glyphIndexForCharacter(at: beginning.utf16.count)
            let glyphs = NSRange(location: firstWordGlyph, length: layout.numberOfGlyphs - firstWordGlyph)
            var wordLines = 0
            layout.enumerateLineFragments(forGlyphRange: glyphs) { _, _, _, _, _ in wordLines += 1 }
            let returns = strokes.filter { $0 == .carriage }.count
            check(wordLines > 1 && returns == wordLines - 1,
                  "\(label) emits one carriage sound for each automatic line wrap",
                  detail: "\(wordLines) visual lines, \(returns) carriage strokes")
            let firstLine = layout.lineFragmentRect(forGlyphAt: firstWordGlyph, effectiveRange: nil)
            let lastLine = layout.lineFragmentRect(forGlyphAt: layout.numberOfGlyphs - 1, effectiveRange: nil)
            let rightMargin = paperWidth - editor.textContainerInset.width
            check(lastLine.minY > firstLine.minY && furthestGlyphEdge <= rightMargin + 1,
                  "\(label) wraps a word without spaces inside the paper margins",
                  detail: "first row \(firstLine.minY), last row \(lastLine.minY), rightmost glyph \(furthestGlyphEdge), margin \(rightMargin)")
            check(maxHorizontalOffset <= 1, "\(label) keeps the viewport horizontally stationary",
                  detail: "largest horizontal offset \(maxHorizontalOffset)")
            let left = editor.textContainerOrigin.x - clip.bounds.minX
                + layout.boundingRect(forGlyphRange: firstGlyph, in: container).minX
            check(abs(left - initialLeft) <= 1, "\(label) keeps the previous paragraph at the left margin")

            strokes.removeAll()
            resize(width: 720, height: 430)
            check(strokes.isEmpty, "\(label) reflowing existing words emits no strokes")
            edit { editor.insertNewline(nil) }
            insert("x")
            insert(" ")
            check(strokes == [.carriage, .key, .space],
                  "\(label) explicit Return, a letter, and a space each emit only their own stroke",
                  detail: "\(strokes)")
        }
    }

    private func checkTopContinuousFeed() {
        print("Top feed checks (continuous native word insertion, without added newlines):")
        let beginning = "A quiet beginning. "
        insert(beginning)
        check(abs(scroll.contentView.bounds.minY) <= 1,
              "Top leaves the paper still while short writing fits above the lower band")
        checkScrollCallback("Top short-writing callback reports the native paper offset")

        let words = Array(repeating: "Paper rolls upward as each new word arrives.", count: 32)
            .joined(separator: " ").split(separator: " ").map { String($0) + " " }
        let continuousText = beginning + words.joined()
        editor.breakUndoCoalescing()
        window.probeUndoManager.beginUndoGrouping()
        for word in words {
            editor.insertText(word, replacementRange: NSRange(location: NSNotFound, length: 0))
            // Let real layout and the model callback settle between words so
            // this exercises continuous feed, rather than a single large paste.
            settle(0.01)
        }
        editor.breakUndoCoalescing()
        window.probeUndoManager.endUndoGrouping()
        settle()
        let clip = scroll.contentView
        let limit = PaperFeedLayout.caretLimit(viewportHeight: clip.bounds.height, position: .top)
        check(editor.string == continuousText && text == continuousText && !text.contains("\n"),
              "continuous Top typing wraps natively without changing or adding characters")
        check(clip.bounds.minY > 100 && caretBottom() > 0 && caretBottom() <= limit + 3,
              "Top rolls upward after the writing reaches the lower band and keeps the active line visible",
              detail: "offset \(clip.bounds.minY), caret \(caretBottom()), limit \(limit)")
        checkScrollCallback("Top rolling callback carries the actual native paper offset")

        let readingOffset = max(0, clip.bounds.minY - 120)
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: readingOffset))
        scroll.reflectScrolledClipView(clip)
        settle()
        check(abs(clip.bounds.minY - readingOffset) <= 1,
              "Top reading scroll remains where the user places the paper")
        checkScrollCallback("Top manual scrolling keeps the paper-surface callback synchronized")

        window.probeUndoManager.beginUndoGrouping()
        editor.setMarkedText("に", selectedRange: NSRange(location: 1, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        settle()
        let compositionReadingOffset = max(0, clip.bounds.minY - 100)
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: compositionReadingOffset))
        scroll.reflectScrolledClipView(clip)
        settle()
        check(editor.hasMarkedText() && abs(clip.bounds.minY - compositionReadingOffset) <= 1,
              "Top composition leaves manual native scrolling alone until commit")
        checkScrollCallback("Top composition reports scroll changes without forcing the writing band")
        editor.insertText("日本語", replacementRange: NSRange(location: NSNotFound, length: 0))
        editor.breakUndoCoalescing()
        window.probeUndoManager.endUndoGrouping()
        settle()
        check(!editor.hasMarkedText() && editor.string == continuousText + "日本語" && text == editor.string,
              "Top composition commits exact native text after a reading scroll")
        check(caretBottom() > 0 && caretBottom() <= limit + 3,
              "Top commit resumes feeding with the insertion line visible")
        checkScrollCallback("Top composition commit publishes the resumed paper offset")

        check(window.probeUndoManager.canUndo, "Top composition registers native undo")
        if window.probeUndoManager.canUndo {
            window.probeUndoManager.undo()
            settle()
            check(editor.string == continuousText && text == continuousText,
                  "Top native undo removes the composition without losing wrapped writing")
        }
        check(window.probeUndoManager.canUndo, "continuous Top typing registers native undo")
        if window.probeUndoManager.canUndo {
            window.probeUndoManager.undo()
            settle()
            check(editor.string == beginning && text == beginning,
                  "Top native undo restores the exact short text before continuous typing")
            check(abs(clip.bounds.minY) <= 1 && caretBottom() > 0 && caretBottom() < 150,
                  "Top undo reveals the restored short writing without a stale scroll offset")
            checkScrollCallback("Top undo publishes its restored native paper offset")
        }

        pageID = UUID()
        text = ""
        refresh()
        settle()
    }

    private func checkFontSwitching() {
        print("Font checks (installed faces with native NSTextView editing):")
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        let initialText = editor.string
        let initialSelection = editor.selectedRange()
        let choices: [(WritingFont, String)] = [
            (.courier, "Courier"), (.americanTypewriter, "AmericanTypewriter"),
            (.menlo, "Menlo-Regular"), (.georgia, "Georgia"),
            (.courierNew, "CourierNewPSMT"), (.typewriterLight, "AmericanTypewriter-Light"),
            (.typewriterCondensed, "AmericanTypewriter-Condensed"), (.monaco, "Monaco")
        ]
        for (choice, installedName) in choices {
            preferences.writingFont = choice
            refresh()
            settle()
            let resolved = choice.nsFont(size: preferences.fontSize)
            if let installed = NSFont(name: installedName, size: preferences.fontSize) {
                check(resolved.fontName == installed.fontName, "\(choice.label) resolves the installed face")
            } else {
                check(!resolved.fontName.isEmpty && resolved.pointSize == preferences.fontSize,
                      "unavailable \(choice.label) resolves a local fallback")
            }
            print("Resolved font: \(choice.label) → \(resolved.fontName)")
            let typingFont = editor.typingAttributes[.font] as? NSFont
            check(editor.font?.fontName == resolved.fontName && typingFont?.fontName == resolved.fontName,
                  "\(choice.label) applies to native editor and future input")
            check(editor.string == initialText && text == initialText && editor.selectedRange() == initialSelection,
                  "switching to \(choice.label) preserves exact text and native selection")
            checkBottomBand("\(choice.label) recomputes the Bottom writing band")
            let suffix = " [\(choice.label)] नमस्ते 👩🏽‍💻"
            insert(suffix)
            check(editor.string == initialText + suffix && text == initialText + suffix,
                  "\(choice.label) keeps programmatic Unicode input native")
            check(window.probeUndoManager.canUndo, "\(choice.label) typing registers native undo")
            if window.probeUndoManager.canUndo {
                window.probeUndoManager.undo()
                settle()
                check(editor.string == initialText && text == initialText,
                      "\(choice.label) native undo restores pre-insertion text")
                checkBottomBand("\(choice.label) undo restores the writing band")
            }
        }

        let selection = NSRange(location: 0, length: min(6, (editor.string as NSString).length))
        editor.setSelectedRange(selection)
        preferences.writingFont = .menlo
        refresh()
        settle()
        check(editor.selectedRange() == selection && editor.string == initialText && text == initialText,
              "font-family changes preserve a nonempty selection and exact content")

        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        let beforeCompositionFont = editor.font?.fontName
        window.probeUndoManager.beginUndoGrouping()
        editor.setMarkedText("に", selectedRange: NSRange(location: 1, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        settle()
        preferences.writingFont = .georgia
        refresh()
        settle()
        check(editor.hasMarkedText() && editor.font?.fontName == beforeCompositionFont,
              "font-family changes defer while native marked text is active")
        editor.insertText("日本語", replacementRange: NSRange(location: NSNotFound, length: 0))
        editor.breakUndoCoalescing()
        window.probeUndoManager.endUndoGrouping()
        settle()
        check(!editor.hasMarkedText() && editor.string == initialText + "日本語" && text == editor.string,
              "deferred font switch preserves programmatic composition commit")
        check(editor.font?.fontName == WritingFont.georgia.nsFont(size: preferences.fontSize).fontName,
              "chosen font applies after native composition finishes")
        checkBottomBand("deferred font switch restores the Bottom writing band after commit")
    }

    private func checkRollMotion() {
        print("Paper roll checks (native text, actual scroll interpolation, isolated document):")
        preferences.paperStartPosition = .bottom
        preferences.paperMotion = .roll
        preferences.writingFont = .courier
        pageID = UUID()
        text = ""
        refresh()
        let rollHeight = PaperFeedLayout.editorHeight(paperHeight: 708, position: .bottom, motion: .roll)
        resize(height: rollHeight)
        settle(0.25)
        check(abs(rollHeight - 536) <= 0.01,
              "Roll Bottom uses the lower writing band rather than forcing an upper rail")
        checkBottomBand("empty Roll Bottom letter starts directly above its fixed lower rail")
        check(editor.string.isEmpty && preferences.effectivePaperStartPosition == .bottom,
              "Roll adds no blank characters and honors the chosen Bottom preference")
        insert("A native paper roll.")
        let beforeReturn = scroll.contentView.bounds.minY
        recordedOffsets.removeAll()
        insert("\n")
        settle(0.25)
        let afterReturn = scroll.contentView.bounds.minY
        check(afterReturn > beforeReturn + 10, "Return feeds the real document upward by a line")
        checkBottomBand("Roll settles the active caret at the fixed band after Return")
        let intermediate = recordedOffsets.filter { $0 > beforeReturn + 0.5 && $0 < afterReturn - 0.5 }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            check(intermediate.isEmpty, "Reduce Motion skips intermediate paper-feed frames")
        } else {
            check(Set(intermediate.map { Int(($0 * 10).rounded()) }).count >= 2,
                  "Roll publishes multiple actual native scroll positions during a line feed")
        }
        checkScrollCallback("Roll surface offset matches the final native clip origin")
        edit { editor.deleteBackward(nil) }
        settle(0.25)
        check(editor.string == "A native paper roll." && abs(scroll.contentView.bounds.minY - beforeReturn) < 1,
              "deleting Return rolls back without changing any other characters")
        checkBottomBand("backward feed restores the original writing band")
        if window.probeUndoManager.canUndo {
            window.probeUndoManager.undo()
            settle(0.25)
            check(editor.string == "A native paper roll.\n", "Roll keeps native undo for line deletion")
            checkBottomBand("native undo restores the Roll band")
        }

        let longText = (1...30).map { "Native roll line \($0): नमस्ते 世界." }.joined(separator: "\n")
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        insert(longText)
        settle(0.25)
        check(editor.string == "A native paper roll.\n" + longText && text == editor.string,
              "large Unicode insertion preserves every line in Roll")
        checkBottomBand("large insertion snaps to the final line without a long animation")
        checkRollProjection()
        window.probeUndoManager.beginUndoGrouping()
        editor.insertText("\n", replacementRange: NSRange(location: NSNotFound, length: 0))
        editor.breakUndoCoalescing()
        window.probeUndoManager.endUndoGrouping()
        settle(0.04)
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        let interruptedOrigin = max(0, scroll.contentView.bounds.minY - 60)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: interruptedOrigin))
        scroll.reflectScrolledClipView(scroll.contentView)
        settle(0.25)
        check(abs(scroll.contentView.bounds.minY - interruptedOrigin) <= 1,
              "selecting earlier text interrupts an in-progress Roll animation without snapping back")
        let originalText = editor.string
        let selection = NSRange(location: 4, length: 6)
        editor.setSelectedRange(selection)
        settle()
        preferences.paperMotion = .sheet
        refresh()
        resize(height: PaperFeedLayout.editorHeight(paperHeight: 708, position: .bottom, motion: .sheet))
        check(editor.selectedRange() == selection && editor.string == originalText,
              "switching Roll off preserves native selection and exact text")
        check(preferences.effectivePaperStartPosition == .bottom,
              "switching Roll off retains the chosen Bottom layout")
        preferences.paperMotion = .roll
        refresh()
        resize(width: 420, height: 150)
        check(editor.selectedRange() == selection && editor.string == originalText,
              "small Roll viewport and rewrap preserve selection and content")
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        insert("\n")
        settle(0.25)
        checkBottomBand("resized Roll resumes at its fixed native writing band")

        let clip = scroll.contentView
        let readOrigin = max(0, clip.bounds.minY - 70)
        clip.scroll(to: NSPoint(x: 0, y: readOrigin))
        scroll.reflectScrolledClipView(clip)
        settle(0.25)
        check(abs(clip.bounds.minY - readOrigin) <= 1, "manual reading position is retained in Roll")
        insert("x")
        settle(0.25)
        checkBottomBand("typing after reading returns Roll to the real insertion line")

        let beforeComposition = editor.string
        window.probeUndoManager.beginUndoGrouping()
        editor.setMarkedText("に", selectedRange: NSRange(location: 1, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        settle(0.25)
        let markedInset = editor.textContainerInset
        preferences.paperMotion = .sheet
        preferences.paperStartPosition = .top
        refresh()
        settle()
        check(editor.hasMarkedText() && editor.textContainerInset == markedInset,
              "motion preference changes defer native layout during composition")
        editor.insertText("日本語", replacementRange: NSRange(location: NSNotFound, length: 0))
        editor.breakUndoCoalescing()
        window.probeUndoManager.endUndoGrouping()
        settle(0.25)
        check(!editor.hasMarkedText() && editor.string == beforeComposition + "日本語",
              "composition commit preserves all text when leaving Roll")
        check(latestCaret?.startPosition == .top, "deferred Sheet position applies after composition commits")
        checkRollTopPosition()
    }

    private func checkRollTopPosition() {
        print("Paper roll Top/Bottom independence checks:")
        preferences.paperMotion = .roll
        preferences.paperStartPosition = .top
        pageID = UUID()
        text = ""
        refresh()
        resize(height: PaperFeedLayout.editorHeight(paperHeight: 708, position: .top, motion: .roll))
        settle(0.25)
        let firstCaret = caretBottom()
        check(latestCaret?.startPosition == .top && firstCaret >= 68 && firstCaret < 150,
              "Roll Top begins at the projected upper margin instead of the Bottom band",
              detail: "caret \(firstCaret)")
        check(editor.textContainerInset.height == 68 && editor.string.isEmpty,
              "Roll Top uses native upper padding and adds no characters")
        insert("The first line stays near the top.")
        insert("\n")
        settle(0.25)
        let secondCaret = caretBottom()
        check(secondCaret > firstCaret + 10 && abs(scroll.contentView.bounds.minY) <= 1,
              "Roll Top advances new lines downward before paper feed is needed")

        let beforeSwitch = editor.string
        let selection = NSRange(location: 4, length: 5)
        editor.setSelectedRange(selection)
        mode(.bottom, height: PaperFeedLayout.editorHeight(paperHeight: 708, position: .bottom, motion: .roll))
        settle(0.25)
        check(editor.string == beforeSwitch && editor.selectedRange() == selection,
              "switching Roll Top to Bottom preserves native text and a nonempty selection")
        checkBottomBand("Roll Bottom moves that same selected line to the lower band")
        mode(.top, height: PaperFeedLayout.editorHeight(paperHeight: 708, position: .top, motion: .roll))
        settle(0.25)
        check(editor.string == beforeSwitch && editor.selectedRange() == selection && caretBottom() < 180,
              "switching Roll Bottom to Top restores the upper layout without altering selection")

        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        let lines = (1...30).map { "Top roll line \($0): नमस्ते 世界." }.joined(separator: "\n")
        insert(lines)
        settle(0.25)
        let limit = PaperFeedLayout.caretLimit(viewportHeight: scroll.contentView.bounds.height, position: .top)
        check(editor.string == beforeSwitch + lines && text == editor.string,
              "Roll Top keeps Unicode multiline input unchanged as the page fills")
        check(scroll.contentView.bounds.minY > 100 && abs(caretBottom() - limit) <= 3,
              "Roll Top feeds upward after reaching the same lower writing band")
        let beforeReturn = scroll.contentView.bounds.minY
        recordedOffsets.removeAll()
        insert("\n")
        settle(0.25)
        let afterReturn = scroll.contentView.bounds.minY
        check(afterReturn > beforeReturn + 10 && abs(caretBottom() - limit) <= 3,
              "Roll Top keeps subsequent Returns above the mechanism")
        let intermediate = recordedOffsets.filter { $0 > beforeReturn + 0.5 && $0 < afterReturn - 0.5 }
        check(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? intermediate.isEmpty : intermediate.count >= 2,
              "Roll Top uses the same Reduce Motion-aware native feed animation")
        checkScrollCallback("Roll Top publishes the actual native offset to its paper surface")
        editor.setSelectedRange(NSRange(location: 0, length: (editor.string as NSString).length))
        edit { editor.deleteBackward(nil) }
        settle(0.25)
        check(editor.string.isEmpty && text.isEmpty && caretBottom() < 150
              && abs(scroll.contentView.bounds.minY) <= 1,
              "deleting Roll Top back to empty restores the upper start without stale scrolling")
    }

    private func checkRollProjection() {
        guard let manager = editor.layoutManager as? InkLayoutManager else {
            check(false, "Roll uses the production native ink layout manager")
            return
        }
        let clip = scroll.contentView
        let bend = PaperRollProjection(width: clip.bounds.width, viewportHeight: clip.bounds.height).bendHeight
        let source = editor.string as NSString
        var samples = 0
        for line in 1...30 {
            let match = source.range(of: "Native roll line \(line):")
            guard match.location != NSNotFound else { continue }
            let index = match.location + 7
            let range = NSRange(location: index, length: 0)
            let rawScreen = editor.rawFirstRect(forCharacterRange: range, actualRange: nil)
            let raw = editor.convert(window.convertFromScreen(rawScreen), from: nil)
            let top = raw.minY - clip.bounds.minY
            guard top > -bend + 30, top + raw.height < bend - 20 else { continue }
            let screen = editor.firstRect(forCharacterRange: range, actualRange: nil)
            let projected = editor.convert(window.convertFromScreen(screen), from: nil)
            check(projected.height < raw.height && projected.minY > raw.minY,
                  "Roll compresses a real native caret rectangle on curved line \(line)")
            let point = NSPoint(x: projected.minX + 1, y: projected.midY)
            let insertion = editor.characterIndexForInsertion(at: point)
            check(insertion == index, "native insertion hit testing reaches curved line \(line)",
                  detail: "hit \(insertion), expected \(index), raw \(raw), projected \(projected)")
            let native = manager.unprojectedPoint(point)
            check(native.y >= raw.minY - 1 && native.y <= raw.maxY + 1,
                  "projected line \(line) maps back to its real TextKit line")
            for marker in ["नमस्ते", "世界"] {
                let searchRange = NSRange(location: match.location, length: source.length - match.location)
                let script = source.range(of: marker, options: [], range: searchRange)
                guard script.location != NSNotFound else { continue }
                let scriptScreen = editor.rawFirstRect(forCharacterRange: NSRange(location: script.location, length: 0),
                                                       actualRange: nil)
                let scriptRect = editor.convert(window.convertFromScreen(scriptScreen), from: nil)
                let rawPoint = NSPoint(x: scriptRect.minX + 1, y: scriptRect.midY)
                manager.paperRollEnabled = false
                let nativeIndex = editor.characterIndexForInsertion(at: rawPoint)
                manager.paperRollEnabled = true
                let projectedPoint = manager.projectedRect(NSRect(origin: rawPoint, size: .zero)).origin
                check(editor.characterIndexForInsertion(at: projectedPoint) == nativeIndex,
                      "\(marker) hit testing keeps native character boundaries on curved line \(line)")
            }
            samples += 1
            if samples == 3 { break }
        }
        check(samples == 3, "projection checks exercised three visible curved native lines")
    }

    private func checkFocusWidthTransitions() {
        print("Focus-width reflow checks (same native editor, Sheet/Roll and Top/Bottom):")
        let normalWidth = DeskLayout.paperWidth(windowWidth: 1080, focusMode: false, widerFocusPaper: true)
        let focusWidth = DeskLayout.paperWidth(windowWidth: 1080, focusMode: true, widerFocusPaper: true)
        for motion in [PaperMotion.sheet, .roll] {
            for position in [PaperStartPosition.top, .bottom] {
                preferences.paperMotion = motion
                preferences.paperStartPosition = position
                preferences.paperEmbossing = .monogram
                preferences.paperTexture = .cotton
                pageID = UUID()
                text = "A quiet native page.\n" + String(repeating: "Ink, paper and generous margins. ", count: 26)
                refresh()
                let height = PaperFeedLayout.editorHeight(paperHeight: 708, position: position, motion: motion)
                resize(width: normalWidth, height: height)
                let original = editor.string
                let selection = NSRange(location: (original as NSString).length - 22, length: 8)
                editor.setSelectedRange(selection)
                settle()
                let label = "\(motion.rawValue)/\(position.rawValue)"
                for width in [focusWidth, normalWidth] {
                    resize(width: width, height: height)
                    check(editor.string == original && text == original && editor.selectedRange() == selection,
                          "\(label) width \(Int(width)) preserves words and a nonempty native selection")
                    check(abs(scroll.contentView.bounds.width - width) <= 1
                          && abs(scroll.contentView.bounds.height - height) <= 1,
                          "\(label) focus changes only the native viewport width")
                    let caret = caretBottom()
                    check(caret >= 0 && caret <= height + 3,
                          "\(label) selected line remains visible after width \(Int(width))",
                          detail: "caret \(caret), height \(height)")
                    check(preferences.paperEmbossing == .monogram && preferences.paperTexture == .cotton
                          && preferences.paperMotion == motion && preferences.paperStartPosition == position,
                          "\(label) focus reflow preserves paper and embossing choices")
                }

                editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
                let beforeEdit = editor.string
                insert(" A wider thought.")
                resize(width: focusWidth, height: height)
                resize(width: normalWidth, height: height)
                check(window.probeUndoManager.canUndo, "\(label) focus transitions retain native undo")
                if window.probeUndoManager.canUndo {
                    window.probeUndoManager.undo()
                    settle()
                    check(editor.string == beforeEdit && text == beforeEdit,
                          "\(label) undo after focus transitions restores exact text")
                }

                editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
                let beforeComposition = editor.string
                window.probeUndoManager.beginUndoGrouping()
                editor.setMarkedText("に", selectedRange: NSRange(location: 1, length: 0),
                                     replacementRange: NSRange(location: NSNotFound, length: 0))
                settle()
                let marked = editor.markedRange()
                resize(width: focusWidth, height: height)
                check(editor.hasMarkedText() && editor.markedRange() == marked
                      && editor.string == beforeComposition + "に",
                      "\(label) widening keeps native marked text intact")
                resize(width: normalWidth, height: height)
                check(editor.hasMarkedText() && editor.markedRange() == marked,
                      "\(label) restoring width keeps the same composition range")
                editor.insertText("日本語", replacementRange: NSRange(location: NSNotFound, length: 0))
                editor.breakUndoCoalescing()
                window.probeUndoManager.endUndoGrouping()
                settle()
                check(!editor.hasMarkedText() && editor.string == beforeComposition + "日本語"
                      && text == editor.string,
                      "\(label) composition commits exactly after focus reflow")
                check(window.probeUndoManager.canUndo, "\(label) composition still registers native undo")
                if window.probeUndoManager.canUndo {
                    window.probeUndoManager.undo()
                    settle()
                    check(editor.string == beforeComposition && text == beforeComposition,
                          "\(label) undo restores pre-composition text after focus reflow")
                }
            }
        }
    }

    private func checkEndOfWritingScroll() {
        print("End-of-writing checks (native clip constraints, without wheel-event synthesis):")
        func endLimit() -> CGFloat {
            let end = NSRange(location: (editor.string as NSString).length, length: 0)
            let raw = editor.rawFirstRect(forCharacterRange: end, actualRange: nil)
            let rect = scroll.contentView.convert(window.convertFromScreen(raw), from: nil)
            return max(0, rect.maxY - PaperFeedLayout.caretLimit(
                viewportHeight: scroll.contentView.bounds.height, position: preferences.paperStartPosition))
        }
        func checkLimit(_ label: String, expectedLimit: CGFloat? = nil) {
            let clip = scroll.contentView
            var proposed = clip.bounds
            proposed.origin.y = 1_000_000
            let constrained = clip.constrainBoundsRect(proposed)
            let original = editor.string
            let selection = editor.selectedRange()
            clip.scroll(to: constrained.origin)
            scroll.reflectScrolledClipView(clip)
            settle(0.25)
            // Reveal the requested end before asking the input-method API for
            // its screen rectangle. While reading away from it, AppKit may
            // report a fallback rectangle for that offscreen insertion point.
            let expected = expectedLimit ?? endLimit()
            check(abs(constrained.minY - expected) <= 1,
                  "\(label): scrolling stops when the last actual line reaches the writing band",
                  detail: "native limit \(constrained.minY), actual end limit \(expected), inset \(editor.textContainerInset)")
            check(abs(clip.bounds.minY - expected) <= 1 && editor.string == original && editor.selectedRange() == selection,
                  "\(label): end-scroll leaves text/selection unchanged and reveals no trailing blank space")
        }
        let samples = ["", "One line.", "One line.\n",
                       String(repeating: "Native wrapping preserves words. ", count: 14),
                       (1...30).map { "Line \($0): a real written line." }.joined(separator: "\n")]
        for motion in [PaperMotion.sheet, .roll] {
            for position in [PaperStartPosition.top, .bottom] {
                preferences.paperMotion = motion
                preferences.paperStartPosition = position
                preferences.writingFont = .courier
                preferences.fontSize = 20
                let height = PaperFeedLayout.editorHeight(paperHeight: 708, position: position, motion: motion)
                for (index, sample) in samples.enumerated() {
                    pageID = UUID()
                    text = sample
                    refresh()
                    resize(width: 720, height: height)
                    settle(0.25)
                    checkLimit("\(motion.rawValue)/\(position.rawValue) sample \(index)")
                    if index == 1 {
                        let before = scroll.contentView.bounds.minY
                        insert("x")
                        settle(0.25)
                        check(abs(scroll.contentView.bounds.minY - before) <= 1,
                              "\(motion.rawValue)/\(position.rawValue): a character on the same line does not feed paper")
                        checkLimit("\(motion.rawValue)/\(position.rawValue) same-line insertion")
                    }
                }
                let clip = scroll.contentView
                let earlier = max(0, clip.bounds.minY - 120)
                clip.scroll(to: NSPoint(x: 0, y: earlier))
                scroll.reflectScrolledClipView(clip)
                settle(0.25)
                check(abs(clip.bounds.minY - earlier) <= 1,
                      "\(motion.rawValue)/\(position.rawValue): earlier writing remains freely scrollable with caret at end")
                resize(width: 420, height: height - 80)
                checkLimit("\(motion.rawValue)/\(position.rawValue) narrower/shorter viewport")
                resize(width: 720, height: height)
                checkLimit("\(motion.rawValue)/\(position.rawValue) restored viewport")
                let beforeDelete = editor.string
                let beforeDeleteLimit = endLimit()
                editor.setSelectedRange(NSRange(location: 0, length: (beforeDelete as NSString).length))
                edit { editor.deleteBackward(nil) }
                settle(0.25)
                checkLimit("\(motion.rawValue)/\(position.rawValue) deleted to empty")
                window.probeUndoManager.undo()
                settle(0.25)
                check(editor.string == beforeDelete, "\(motion.rawValue)/\(position.rawValue): native undo restores deleted writing")
                checkLimit("\(motion.rawValue)/\(position.rawValue) restored by undo", expectedLimit: beforeDeleteLimit)
                editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
                let beforeComposition = editor.string
                edit {
                    editor.setMarkedText("に", selectedRange: NSRange(location: 1, length: 0),
                                         replacementRange: NSRange(location: NSNotFound, length: 0))
                }
                check(editor.hasMarkedText(), "\(motion.rawValue)/\(position.rawValue): end-scroll constraint preserves native marked text")
                insert("日本語")
                settle(0.25)
                check(!editor.hasMarkedText() && editor.string == beforeComposition + "日本語",
                      "\(motion.rawValue)/\(position.rawValue): composition commits exact text")
                checkLimit("\(motion.rawValue)/\(position.rawValue) composition commit")
            }
        }
    }

    func run() throws -> Bool {
        defer {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        try checkMigration()
        print("Native checks (actual PaperEditor, isolated in-memory letter):")
        settle(0.3)
        guard let mountedEditor = descendant(InkTextView.self, in: host),
              let mountedScroll = descendant(NSScrollView.self, in: host) else {
            throw ProbeError(description: "SwiftUI did not mount the actual native editor; native checks did not run.")
        }
        editor = mountedEditor
        scroll = mountedScroll
        if CommandLine.arguments.contains("--scroll-end-only") {
            checkEndOfWritingScroll()
            print("\(checkCount - failures.count)/\(checkCount) standalone checks passed.")
            return failures.isEmpty
        }
        check(window.makeFirstResponder(editor), "native editor can become first responder")
        settle()
        check(abs(scroll.contentView.bounds.height - 640) <= 1, "Top native viewport has requested height")
        let topCaret = caretBottom()
        check(topCaret >= 68 && topCaret < 150, "empty Top letter starts near the upper margin",
              detail: "caret bottom \(topCaret)")
        check(editor.string.isEmpty && text.isEmpty, "Top layout adds no text")

        checkTopContinuousFeed()

        mode(.bottom, height: 536)
        check(abs(scroll.contentView.bounds.height - 536) <= 1, "Bottom uses the shorter native viewport")
        checkBottomBand("empty Bottom letter starts at the lower writing band")
        check(caretBottom() > topCaret + 250, "Top and Bottom have visibly distinct native starting positions")
        check(editor.string.isEmpty && text.isEmpty, "Bottom padding adds no blank lines")

        let lines = (1...14).map { "Line \($0): a quiet native writing test." }.joined(separator: "\n")
        insert(lines)
        check(editor.string == lines && text == lines && changeCount > 0,
              "multiline native insertion reaches model callback unchanged")
        check(editor.selectedRange() == NSRange(location: (lines as NSString).length, length: 0),
              "native insertion preserves the UTF-16 caret position")
        checkBottomBand("multiline insertion feeds the caret to the lower band")
        check(scroll.contentView.bounds.minY > 200, "paper scrolls upward as native lines accumulate")

        let unicode = "\nCafe\u{301} 👩🏽‍💻 — नमस्ते 世界\n"
        insert(unicode)
        let beforeDelete = lines + unicode
        check(editor.string == beforeDelete && text == beforeDelete,
              "programmatic multiline Unicode insertion preserves exact characters")
        checkBottomBand("Unicode insertion preserves the writing band")
        edit { editor.deleteBackward(nil) }
        check(editor.string == String(beforeDelete.dropLast()), "native backward delete removes the final newline")
        checkBottomBand("deleting a newline feeds the previous line back down")
        check(window.probeUndoManager.canUndo, "native text editing registered undo")
        if window.probeUndoManager.canUndo {
            window.probeUndoManager.undo()
            settle()
            check(editor.string == beforeDelete && text == beforeDelete,
                  "native undo restores deleted text through the model callback")
            checkBottomBand("undo restores the lower writing band")
        }

        let selection = NSRange(location: 0, length: 4)
        editor.setSelectedRange(selection)
        settle()
        mode(.top, height: 640)
        check(editor.selectedRange() == selection && editor.string == beforeDelete && text == beforeDelete,
              "switching to Top preserves native selection and exact text")
        mode(.bottom, height: 536)
        check(editor.selectedRange() == selection && editor.string == beforeDelete && text == beforeDelete,
              "switching back to Bottom preserves native selection and exact text")

        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        insert("Reading checks")
        let clip = scroll.contentView
        let readingOrigin = max(0, clip.bounds.minY - 150)
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: readingOrigin))
        scroll.reflectScrolledClipView(clip)
        settle()
        check(abs(clip.bounds.minY - readingOrigin) <= 1, "manual native scroll is not snapped back")
        checkScrollCallback("Bottom manual scrolling keeps the paper-surface callback synchronized")
        check(caretBottom() > clip.bounds.height + 20, "manual reading scroll can leave the caret offscreen")
        resize(height: 400)
        check(caretBottom() > clip.bounds.height + 20, "resize preserves reading away from an offscreen caret")

        insert(".")
        checkBottomBand("editing resumes paper feed after a manual reading scroll")
        let textBeforeResize = editor.string
        let selectionBeforeResize = editor.selectedRange()
        resize(height: 600)
        checkBottomBand("larger viewport keeps a visible insertion line at the Bottom band")
        resize(height: 360)
        checkBottomBand("smaller viewport keeps a visible insertion line at the Bottom band")
        check(editor.string == textBeforeResize && editor.selectedRange() == selectionBeforeResize,
              "height changes preserve text and native selection")

        insert("\n" + String(repeating: "Words wrap on real paper. ", count: 8))
        let beforeWrap = editor.string
        let wideHeight = usedHeight()
        resize(width: 420, height: 430)
        check(usedHeight() > wideHeight + 20, "narrowing the viewport causes native line wrapping")
        check(editor.string == beforeWrap && text == beforeWrap, "native wrapping adds no characters")
        checkBottomBand("width resize keeps the active wrapped line at the Bottom band")
        resize(height: 536)
        checkBottomBand("restoring width keeps the active line at the Bottom band")

        let middle = (editor.string as NSString).range(of: "Line 7:").location
        guard middle != NSNotFound else { throw ProbeError(description: "Middle-edit fixture text was unexpectedly lost.") }
        let expectedMiddle = NSMutableString(string: editor.string)
        expectedMiddle.insert("Revised ", at: middle)
        editor.setSelectedRange(NSRange(location: middle, length: 0))
        insert("Revised ")
        check(editor.string == expectedMiddle as String && text == expectedMiddle as String,
              "middle-document insertion retains all following text")
        checkBottomBand("editing an earlier paragraph feeds that actual native line to the band")

        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        let beforeComposition = editor.string
        let insetBeforeComposition = editor.textContainerInset
        window.probeUndoManager.beginUndoGrouping()
        editor.setMarkedText("に", selectedRange: NSRange(location: 1, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        settle()
        check(editor.hasMarkedText() && editor.markedRange().length == 1,
              "programmatic marked text remains native composition")
        check(editor.textContainerInset == insetBeforeComposition,
              "composition does not alter the native text-container inset")
        editor.insertText("日本語", replacementRange: NSRange(location: NSNotFound, length: 0))
        editor.breakUndoCoalescing()
        window.probeUndoManager.endUndoGrouping()
        settle()
        let committed = beforeComposition + "日本語"
        check(!editor.hasMarkedText() && editor.string == committed && text == committed,
              "programmatic commit replaces marked text without losing surrounding content")
        check(editor.selectedRange() == NSRange(location: (committed as NSString).length, length: 0),
              "composition commit preserves the native UTF-16 insertion range")
        checkBottomBand("paper feed resumes after programmatic composition commit")

        pageID = UUID()
        text = "Loaded letter\n" + String(repeating: "A stored line.\n", count: 18)
        refresh()
        settle()
        check(editor.string == text && editor.selectedRange() == NSRange(location: (text as NSString).length, length: 0),
              "loading another in-memory page selects its actual end")
        checkBottomBand("loading existing text places its final line at the Bottom band")
        check(latestCaret != nil && abs((latestCaret?.bottom ?? 0) - caretBottom()) <= 1,
              "capsule callback matches the native caret after paper feed")

        checkFontSwitching()
        checkRollMotion()
        checkFocusWidthTransitions()
        checkEndOfWritingScroll()
        try checkUnbrokenTyping()
        try checkFormatting()
        try checkMarkdownTyping()
        try checkHeadingMarkers()
        try checkArrowNavigation()

        print("\(checkCount - failures.count)/\(checkCount) standalone checks passed.")
        print("Not exercised: real OS input methods, hardware keyboard events, menu/clipboard actions, saved files, audio or visual appearance.")
        return failures.isEmpty
    }
}

@main
private struct PaperFeedCheckMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let success: Bool
        do {
            success = try PaperFeedProbe().run()
        } catch {
            print("FAIL: \(error)")
            success = false
        }
        exit(success ? 0 : 1)
    }
}
