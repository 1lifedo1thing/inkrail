import AppKit
import SwiftUI
import InkrailCore

struct CaretPosition: Equatable {
    var x: CGFloat = 78
    var top: CGFloat = 68
    var bottom: CGFloat = 104
    var followingTextBottom: CGFloat?
    var scrollOffset: CGFloat = 0
    var visible = true
    var startPosition: PaperStartPosition?

    func railCenterY(paperHeight: CGFloat, editorHeight: CGFloat, position: PaperStartPosition,
                     hasText: Bool) -> CGFloat {
        if position == .bottom {
            return PaperFeedLayout.caretLimit(viewportHeight: editorHeight, position: .bottom) + 42
        }
        let writingY = min(paperHeight - 108, max(150, bottom + 42))
        // Until the first layout, a previously written page can fill the viewport.
        let textEdge = startPosition == .top ? followingTextBottom : (hasText ? editorHeight : nil)
        guard let textEdge else { return writingY }
        // The hammer reaches 53 pt above the rail at the peak of a strike.
        return max(writingY, min(textEdge, editorHeight) + 56)
    }
}

final class InkTextView: NSTextView {
    var baseAttributes: [NSAttributedString.Key: Any] = [:]
    var onStroke: ((StrokeKind) -> Void)?
    var onLayout: (() -> Void)?
    var onCompositionEnd: (() -> Void)?
    var onWillEdit: (() -> Void)?
    var onInteraction: (() -> Void)?
    private(set) var performingNativeEdit = false

    override var writablePasteboardTypes: [NSPasteboard.PasteboardType] {
        [LetterSelection.pasteboardType] + super.writablePasteboardTypes
    }

    override func writeSelection(to pasteboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        if type == LetterSelection.pasteboardType {
            guard let data = encodedSelection() else { return false }
            return pasteboard.setData(data, forType: type)
        }
        return super.writeSelection(to: pasteboard, type: type)
    }

    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] { [LetterSelection.pasteboardType, .rtf, .string] }

    override func readSelection(from pasteboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        let content: NSAttributedString?
        if type == LetterSelection.pasteboardType, let data = pasteboard.data(forType: type) {
            content = decodeSelection(data)
        } else if type == .rtf, let data = pasteboard.data(forType: type) {
            content = NSAttributedString(rtf: data, documentAttributes: nil).map(styledPaste)
        } else {
            content = nil
        }
        guard let content else { return super.readSelection(from: pasteboard, type: .string) }
        breakUndoCoalescing()
        super.insertText(content, replacementRange: selectedRange())
        return true
    }

    override func doCommand(by selector: Selector) {
        // AppKit resolves arrows, their modifiers, and the user's key bindings
        // into movement commands. Input methods keep control of marked text.
        if !hasMarkedText(), NSStringFromSelector(selector).hasPrefix("move") {
            onStroke?(.navigation)
        }
        super.doCommand(by: selector)
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let wasComposing = hasMarkedText()
        let inserted = (insertString as? String) ?? (insertString as? NSAttributedString)?.string ?? ""
        let isTyping = !inserted.isEmpty && (wasComposing || inserted.count <= 4)
        let hasLineBreak = isTyping && inserted.contains(where: \.isNewline)
        let defaultRange = wasComposing ? markedRange() : selectedRange()
        let editRange = replacementRange.location == NSNotFound ? defaultRange : replacementRange
        let previousCaret = isTyping && !hasLineBreak ? insertionRect(at: editRange.location) : nil
        onWillEdit?()
        performingNativeEdit = true
        defer { performingNativeEdit = false }
        if !wasComposing, let replacement = markdownReplacement(for: inserted, at: editRange) {
            let followingAttributes = typingAttributes
            breakUndoCoalescing()
            super.insertText(replacement.text, replacementRange: replacement.range)
            typingAttributes = followingAttributes
            breakUndoCoalescing()
        } else {
            super.insertText(insertString, replacementRange: replacementRange)
        }
        // AppKit handles input methods; never reinterpret raw key codes as text.
        (layoutManager as? InkLayoutManager)?.composing = hasMarkedText()
        if wasComposing && !hasMarkedText() { onCompositionEnd?() }
        guard isTyping else { return }
        if hasLineBreak && inserted.count <= 2 { onStroke?(.carriage) }
        else if inserted == " " { onStroke?(.space) }
        else { onStroke?(.key) }
        if let previousCaret, !hasMarkedText(), let currentCaret = insertionRect(at: selectedRange().location),
           currentCaret.midY >= previousCaret.maxY {
            onStroke?(.carriage)
        }
    }

    // A zero-length glyph range gives the insertion point in the native
    // layout, including an empty last line. Scrolling never clips this rect.
    private func insertionRect(at location: Int) -> NSRect? {
        guard let layoutManager, let textContainer, let textStorage,
              location != NSNotFound, location <= textStorage.length else { return nil }
        let glyphs = layoutManager.glyphRange(forCharacterRange: NSRange(location: location, length: 0),
                                              actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
        return rect.height > 0 ? rect : nil
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        onInteraction?()
        (layoutManager as? InkLayoutManager)?.composing = true
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
    }

    override func unmarkText() {
        super.unmarkText()
        (layoutManager as? InkLayoutManager)?.composing = false
        needsDisplay = true
        onCompositionEnd?()
    }

    override func deleteBackward(_ sender: Any?) {
        let before = string
        onWillEdit?()
        performingNativeEdit = true
        defer { performingNativeEdit = false }
        super.deleteBackward(sender)
        if before != string { onStroke?(.erase) }
    }

    override func deleteForward(_ sender: Any?) {
        let before = string
        onWillEdit?()
        performingNativeEdit = true
        defer { performingNativeEdit = false }
        super.deleteForward(sender)
        if before != string { onStroke?(.erase) }
    }

    override func setFrameSize(_ newSize: NSSize) {
        // TextKit fits the document's height as the letter grows. Its width
        // must always be the visible sheet's so widthTracksTextView wraps at
        // the paper margins, even during a native resize or caret reveal.
        var size = newSize
        if let clip = superview as? InkClipView, clip.bounds.width > 0 {
            size.width = clip.bounds.width
        }
        super.setFrameSize(size)
        onLayout?()
    }

    override func mouseDown(with event: NSEvent) {
        onInteraction?()
        super.mouseDown(with: event)
    }

    override func setNeedsDisplay(_ invalidRect: NSRect) {
        // Native caret blinking and selection changes invalidate flat TextKit
        // rectangles. Repaint the visible projection too, including ink drawn
        // over the lip from lines above the native viewport.
        let rolled = (layoutManager as? InkLayoutManager)?.paperRollEnabled == true
        super.setNeedsDisplay(rolled ? invalidRect.union(visibleRect) : invalidRect)
    }

    /// Keep the insertion caret and IME candidate anchor on the same native
    /// paper projection as glyphs. The coordinator retains access to the raw
    /// TextKit rectangle for scrolling; projected geometry must not feed back
    /// into native document layout.
    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        let drawn = (layoutManager as? InkLayoutManager)?.projectedRect(rect) ?? rect
        super.drawInsertionPoint(in: drawn, color: color, turnedOn: flag)
    }

    func rawFirstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        super.firstRect(forCharacterRange: range, actualRange: actualRange)
    }

    override func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        let original = rawFirstRect(forCharacterRange: range, actualRange: actualRange)
        guard let window, let manager = layoutManager as? InkLayoutManager, manager.paperRollEnabled else {
            return original
        }
        let local = convert(window.convertFromScreen(original), from: nil)
        return window.convertToScreen(convert(manager.projectedRect(local), to: nil))
    }
}

/// NSTextView uses a symmetric inset. Bottom's large leading inset therefore
/// also creates blank document space below the last line. Keep that native
/// layout padding, but never let it become additional readable/scrollable text.
final class InkClipView: NSClipView {
    var maximumWritingOffset: CGFloat?

    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var constrained = super.constrainBoundsRect(proposedBounds)
        constrained.origin.x = 0
        // AppKit owns scrolling while an input method is composing. The bound
        // is refreshed from the committed end insertion rectangle afterward.
        if isFlipped, (documentView as? NSTextView)?.hasMarkedText() != true,
           let maximumWritingOffset {
            constrained.origin.y = min(maximumWritingOffset, max(0, constrained.origin.y))
        }
        return constrained
    }
}

/// A real scroll view, including trackpad gestures and native selection.
/// Reading gestures interrupt the brief automatic paper feed immediately.
final class InkScrollView: NSScrollView {
    var onManualScroll: (() -> Void)?

    override func scrollWheel(with event: NSEvent) {
        onManualScroll?()
        super.scrollWheel(with: event)
    }
}

@MainActor
struct PaperEditor: NSViewRepresentable {
    var pageID: UUID
    var text: String
    var formatting: [TextFormatRun] = []
    var preferences: WritingPreferences
    var onChange: (String, [TextFormatRun]) -> Void
    var onCaret: (CaretPosition) -> Void
    var onStroke: (StrokeKind) -> Void
    var onEmphasisChange: ((TextEmphasis) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = InkScrollView()
        scroll.contentView = InkClipView()
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.verticalScrollElasticity = .none
        scroll.horizontalScrollElasticity = .none
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentView.postsBoundsChangedNotifications = true
        scroll.contentView.postsFrameChangedNotifications = true

        // Explicit TextKit 1 stack: glyph cosmetics never replace native editing.
        let storage = NSTextStorage()
        let manager = InkLayoutManager()
        manager.delegate = manager
        storage.addLayoutManager(manager)
        let container = NSTextContainer(containerSize: NSSize(width: 640, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.heightTracksTextView = false
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        let editor = InkTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 480), textContainer: container)
        editor.isEditable = true
        editor.isSelectable = true
        editor.isRichText = true
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.usesFontPanel = false
        editor.usesFindBar = true
        editor.isIncrementalSearchingEnabled = true
        editor.drawsBackground = false
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.minSize = NSSize(width: 0, height: 0)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isAutomaticLinkDetectionEnabled = false
        editor.isContinuousSpellCheckingEnabled = false
        editor.setAccessibilityLabel("Letter. Native text editor.")
        editor.delegate = context.coordinator
        storage.delegate = context.coordinator
        scroll.documentView = editor
        let coordinator = context.coordinator
        coordinator.editor = editor
        coordinator.scroll = scroll
        editor.onLayout = { [weak coordinator] in coordinator?.scheduleCaretUpdate() }
        editor.onCompositionEnd = { [weak coordinator] in coordinator?.scheduleCaretUpdate(followCaret: true) }
        editor.onWillEdit = { [weak coordinator] in coordinator?.prepareNativeEdit() }
        editor.onInteraction = { [weak coordinator] in coordinator?.interruptPaperFeed(cancelFollow: true) }
        scroll.onManualScroll = { [weak coordinator] in coordinator?.interruptPaperFeed(cancelFollow: true) }
        editor.onStroke = { [weak coordinator] kind in
            guard let coordinator else { return }
            coordinator.parent.onStroke(kind)
        }
        coordinator.observe()
        coordinator.load(self)
        DispatchQueue.main.async {
            editor.window?.makeFirstResponder(editor)
            coordinator.scheduleCaretUpdate()
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.load(self)
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.stopObserving()
        coordinator.editor?.delegate = nil
        coordinator.editor?.textStorage?.delegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var parent: PaperEditor
        weak var editor: InkTextView?
        weak var scroll: NSScrollView?
        private var loadedID: UUID?
        private var appliedPreferences: WritingPreferences?
        private var knownFormatting: [TextFormatRun] = []
        private var restoreTypingFromText = true
        private var lastEmphasis: TextEmphasis?
        private var pendingBlockRange: NSRange?
        private var tokens: [NSObjectProtocol] = []
        private var updating = false
        private var scheduled = false
        private var pendingFollowCaret = false
        private var viewportSize: NSSize?
        private var lastCaret: CaretPosition?
        private var pendingFeedOrigin: NSPoint?
        private var animateNextFeed = false
        private var feedTimer: Timer?
        private var feedOrigin = NSPoint.zero
        private var feedTarget: NSPoint?
        private var feedStartedAt: TimeInterval = 0
        // A measured visual approximation, not an exact reproduction of the
        // reference app's spring. Only active while a single line is feeding.
        private let feedDuration: TimeInterval = 0.18

        init(_ parent: PaperEditor) { self.parent = parent }
        deinit {
            feedTimer?.invalidate()
            for token in tokens { NotificationCenter.default.removeObserver(token) }
        }

        func stopObserving() {
            interruptPaperFeed()
            for token in tokens { NotificationCenter.default.removeObserver(token) }
            tokens.removeAll()
        }

        func observe() {
            tokens.append(NotificationCenter.default.addObserver(
                forName: .inkrailToggleEmphasis, object: nil, queue: .main
            ) { [weak self] notification in
                guard let flag = notification.object as? TextEmphasis else { return }
                MainActor.assumeIsolated {
                    guard let editor = self?.editor, let window = editor.window,
                          window.isKeyWindow, window.attachedSheet == nil else { return }
                    window.makeFirstResponder(editor)
                    editor.toggleEmphasis(flag)
                }
            })
            if let clip = scroll?.contentView {
                // A height-only shrink need not change the document frame or
                // scroll origin. Observe viewport frame changes as well.
                for name in [NSView.boundsDidChangeNotification, NSView.frameDidChangeNotification] {
                    tokens.append(NotificationCenter.default.addObserver(
                        forName: name, object: clip, queue: .main
                    ) { [weak self] _ in
                        Task { @MainActor in
                            self?.editor?.needsDisplay = true
                            self?.scheduleCaretUpdate()
                        }
                    })
                }
            }
            tokens.append(NotificationCenter.default.addObserver(
                forName: .inkrailFocusEditor, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let editor = self.editor else { return }
                    editor.window?.makeFirstResponder(editor)
                    self.scheduleCaretUpdate()
                }
            })
        }

        func load(_ newParent: PaperEditor) {
            if parent.pageID != newParent.pageID || parent.preferences.paperMotion != newParent.preferences.paperMotion
                || parent.preferences.paperStartPosition != newParent.preferences.paperStartPosition {
                interruptPaperFeed()
            }
            parent = newParent
            guard let editor else { return }
            updating = true
            let switched = loadedID != parent.pageID
            var textReplaced = false
            if switched {
                editor.breakUndoCoalescing()
                editor.undoManager?.removeAllActions()
                editor.string = parent.text
                editor.setSelectedRange(NSRange(location: (parent.text as NSString).length, length: 0))
                loadedID = parent.pageID
                appliedPreferences = nil
                lastCaret = nil
            } else if !editor.hasMarkedText() && !editor.string.utf8.elementsEqual(parent.text.utf8) {
                let selection = editor.selectedRange()
                editor.string = parent.text
                editor.setSelectedRange(NSRange(location: min(selection.location, (parent.text as NSString).length), length: 0))
                textReplaced = true
            }
            if switched || textReplaced || (!editor.hasMarkedText() && knownFormatting != parent.formatting) {
                knownFormatting = parent.formatting
                restoreTypingFromText = true
                appliedPreferences = nil
                lastEmphasis = nil
            }
            updating = false
            if switched {
                DispatchQueue.main.async { [weak self] in
                    guard let self, let editor = self.editor else { return }
                    editor.window?.makeFirstResponder(editor)
                    self.scheduleCaretUpdate(followCaret: true)
                }
            }
            scheduleCaretUpdate(followCaret: switched || textReplaced)
        }

        private func applyStyle(to editor: InkTextView) {
            let prefs = parent.preferences
            let font = prefs.writingFont.nsFont(size: prefs.fontSize)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = prefs.fontSize * 0.34
            paragraph.paragraphSpacing = 0
            paragraph.lineBreakMode = .byWordWrapping
            let ink = prefs.ribbon.nsColor.withAlphaComponent(prefs.inkStrength)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: ink, .paragraphStyle: paragraph, .ligature: 0
            ]
            editor.textColor = ink
            editor.insertionPointColor = ink.withAlphaComponent(0.48)
            editor.selectedTextAttributes = [
                .backgroundColor: NSColor(calibratedRed: 0.55, green: 0.59, blue: 0.44, alpha: 0.28)
            ]
            editor.defaultParagraphStyle = paragraph
            editor.applyLetterStyle(attributes, runs: knownFormatting, restoreTypingFromText: restoreTypingFromText)
            editor.refreshMarkdownBlocks()
            pendingBlockRange = nil
            restoreTypingFromText = false
            (editor.layoutManager as? InkLayoutManager)?.wornInk = prefs.wornInk
            (editor.layoutManager as? InkLayoutManager)?.inkBuildup = prefs.inkBuildup
            (editor.layoutManager as? InkLayoutManager)?.paperRollEnabled = prefs.paperMotion == .roll
            editor.needsDisplay = true
        }

        func textDidChange(_ notification: Notification) {
            guard !updating, let editor else { return }
            knownFormatting = editor.formattingRuns
            parent.onChange(editor.string, knownFormatting)
            if editor.undoManager?.isUndoing == true || editor.undoManager?.isRedoing == true {
                // Native undo can restore attributes captured with an earlier desk font.
                appliedPreferences = nil
                restoreTypingFromText = true
            }
            (editor.layoutManager as? InkLayoutManager)?.composing = editor.hasMarkedText()
            animateNextFeed = editor.performingNativeEdit && !editor.hasMarkedText()
            scheduleCaretUpdate(followCaret: true)
        }

        nonisolated func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                                     range editedRange: NSRange, changeInLength delta: Int) {
            // This storage belongs to the AppKit editor and is edited on the main thread.
            MainActor.assumeIsolated {
                guard !updating, editedRange.location != NSNotFound else { return }
                if let prior = pendingBlockRange {
                    let start = min(prior.location, editedRange.location)
                    let end = max(NSMaxRange(prior) + max(0, delta), NSMaxRange(editedRange))
                    pendingBlockRange = NSRange(location: start, length: end - start)
                } else {
                    pendingBlockRange = editedRange
                }
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !updating else { return }
            if editor?.performingNativeEdit != true {
                let undoing = editor?.undoManager?.isUndoing == true || editor?.undoManager?.isRedoing == true
                interruptPaperFeed(cancelFollow: !undoing)
            }
            // Selection and reading scrolls must not snap the paper back.
            editor?.needsDisplay = true
            scheduleCaretUpdate()
        }

        func textViewDidChangeTypingAttributes(_ notification: Notification) {
            if !updating { scheduleCaretUpdate() }
        }

        func scheduleCaretUpdate(followCaret: Bool = false) {
            pendingFollowCaret = pendingFollowCaret || followCaret
            guard !scheduled else { return }
            scheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let editor = self.editor, !editor.hasMarkedText() {
                    let follow = self.pendingFollowCaret
                    self.pendingFollowCaret = false
                    let layoutChanged = self.updatePaperLayout()
                    if let range = self.pendingBlockRange, let storage = editor.textStorage {
                        self.pendingBlockRange = nil
                        self.updating = true
                        let start = min(range.location, storage.length)
                        let end = min(NSMaxRange(range), storage.length)
                        editor.refreshMarkdownBlocks(in: NSRange(location: start, length: end - start))
                        self.updating = false
                    }
                    let animate = self.animateNextFeed && !layoutChanged
                    let origin = self.pendingFeedOrigin
                    self.animateNextFeed = false
                    self.pendingFeedOrigin = nil
                    if follow || layoutChanged { self.followInsertionPoint(animate: animate, from: origin) }
                }
                // While composing, leave the container and scrolling to AppKit.
                // The pending follow is consumed after commit/unmark.
                self.publishCaret()
                if let editor = self.editor, let onEmphasisChange = self.parent.onEmphasisChange {
                    let emphasis = editor.activeEmphasis
                    if emphasis != self.lastEmphasis {
                        self.lastEmphasis = emphasis
                        onEmphasisChange(emphasis)
                    }
                }
                self.scheduled = false
            }
        }

        /// Insets are native layout padding, never blank lines in the letter.
        /// Bottom's leading inset anchors its first line. Its symmetric trailing
        /// padding is excluded from reading scroll by the native clip constraint.
        private func updatePaperLayout() -> Bool {
            guard let editor, let container = editor.textContainer, let clip = scroll?.contentView,
                  clip.bounds.width > 0, clip.bounds.height > 0 else { return false }
            let prefs = parent.preferences
            let previous = appliedPreferences
            let styleChanged = previous != prefs
            let layoutPreferenceChanged = previous?.paperStartPosition != prefs.paperStartPosition
                || previous?.paperMotion != prefs.paperMotion
                || previous?.fontSize != prefs.fontSize || previous?.wideMargins != prefs.wideMargins
                || previous?.writingFont != prefs.writingFont
            if styleChanged {
                updating = true
                applyStyle(to: editor)
                appliedPreferences = prefs
                updating = false
            }
            let resized = viewportSize != clip.bounds.size
            if resized || layoutPreferenceChanged { interruptPaperFeed() }
            viewportSize = clip.bounds.size
            let oldInset = editor.textContainerInset
            let oldScrollOrigin = clip.bounds.origin
            let font = editor.font ?? prefs.writingFont.nsFont(size: prefs.fontSize)
            let lineHeight = editor.layoutManager?.defaultLineHeight(for: font) ?? prefs.fontSize * 1.2
            let inset = NSSize(
                width: prefs.wideMargins ? 76 : 46,
                height: PaperFeedLayout.topInset(viewportHeight: clip.bounds.height,
                                               lineHeight: lineHeight, position: prefs.effectivePaperStartPosition)
            )
            if editor.textContainerInset != inset { editor.textContainerInset = inset }
            // An existing TextKit container can still carry its previous line
            // width after the viewport or the paper margins have changed.
            let writingWidth = max(1, clip.bounds.width - 2 * inset.width)
            let needsReflow = container.containerSize.width != writingWidth
            if needsReflow { container.containerSize.width = writingWidth }
            if resized || layoutPreferenceChanged || needsReflow {
                fitDocumentToWritingBand()
            }
            if resized && !layoutPreferenceChanged && lastCaret?.visible == false {
                var origin = oldScrollOrigin
                origin.y += inset.height - oldInset.height
                clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: origin, size: clip.bounds.size)).origin)
                scroll?.reflectScrolledClipView(clip)
            }
            // A resize must not jump away from text the user has scrolled to read.
            return layoutPreferenceChanged || ((resized || needsReflow) && lastCaret?.visible != false)
        }

        private func fitDocumentToWritingBand() {
            guard let editor, let clip = scroll?.contentView,
                  let container = editor.textContainer, let layout = editor.layoutManager else { return }
            layout.ensureLayout(for: container)
            var minimumHeight = clip.bounds.height
            if parent.preferences.effectivePaperStartPosition == .top {
                // Include an empty last line and enough trailing space to feed
                // it to the writing line. Recompute after deletion as well.
                var contentBottom = layout.usedRect(for: container).maxY
                if layout.extraLineFragmentTextContainer === container {
                    contentBottom = max(contentBottom, layout.extraLineFragmentRect.maxY)
                }
                let trailingSpace = clip.bounds.height - PaperFeedLayout.caretLimit(
                    viewportHeight: clip.bounds.height, position: .top)
                minimumHeight = max(minimumHeight, editor.textContainerOrigin.y + contentBottom + max(0, trailingSpace))
            }
            let minimum = NSSize(width: 0, height: minimumHeight)
            if editor.minSize != minimum { editor.minSize = minimum }
            editor.sizeToFit()
            updateEndOfWritingBound()
        }

        private func updateEndOfWritingBound() {
            guard let editor,
                  let clip = scroll?.contentView as? InkClipView else { return }
            // Use TextKit's zero-length end glyph range, including an empty
            // last line after Return. Unlike the input-method screen rectangle,
            // this remains valid when the end is offscreen or text is selected.
            guard let layout = editor.layoutManager, let container = editor.textContainer else { return }
            let rect = layout.boundingRect(forGlyphRange: NSRange(location: layout.numberOfGlyphs, length: 0),
                                           in: container)
            guard rect.maxY.isFinite else { return }
            clip.maximumWritingOffset = max(0, editor.textContainerOrigin.y + rect.maxY - PaperFeedLayout.caretLimit(
                viewportHeight: clip.bounds.height, position: parent.preferences.effectivePaperStartPosition))
            let bounded = clip.constrainBoundsRect(clip.bounds)
            if bounded.minX != clip.bounds.minX || abs(bounded.minY - clip.bounds.minY) > 0.5 {
                clip.scroll(to: bounded.origin)
                scroll?.reflectScrolledClipView(clip)
            }
        }

        private func caretRectInClip(projected: Bool = false) -> NSRect? {
            guard let editor, let window = editor.window, let clip = scroll?.contentView else { return nil }
            let index = min(editor.selectedRange().location, (editor.string as NSString).length)
            let range = NSRange(location: index, length: 0)
            let screen = projected
                ? editor.firstRect(forCharacterRange: range, actualRange: nil)
                : editor.rawFirstRect(forCharacterRange: range, actualRange: nil)
            guard screen.origin.x.isFinite, screen.origin.y.isFinite else { return nil }
            return clip.convert(window.convertFromScreen(screen), from: nil)
        }

        private func followInsertionPoint(animate: Bool, from origin: NSPoint?) {
            guard let editor, let scroll, !editor.hasMarkedText() else { return }
            fitDocumentToWritingBand()
            // Let AppKit reveal an offscreen insertion point first, including
            // editing earlier paragraphs, before applying our writing band.
            editor.scrollRangeToVisible(editor.selectedRange())
            let clip = scroll.contentView
            guard clip.isFlipped, let rect = caretRectInClip() else { return }
            let offset = PaperFeedLayout.desiredScrollOffset(
                caretBottom: rect.maxY, currentOffset: clip.bounds.minY,
                viewportHeight: clip.bounds.height, position: parent.preferences.effectivePaperStartPosition
            )
            var point = clip.bounds.origin
            point.y = offset
            point = clip.constrainBoundsRect(NSRect(origin: point, size: clip.bounds.size)).origin
            if animate, parent.preferences.paperMotion == .roll,
               !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let origin,
               abs(point.y - origin.y) > 0.5,
               abs(point.y - origin.y) <= max(80, parent.preferences.fontSize * 4) {
                // AppKit may already have revealed the new line. Return to the
                // pre-edit viewport and feed the actual native document from it.
                setScrollOrigin(origin)
                if feedTarget != point || feedTimer == nil { startPaperFeed(from: origin, to: point) }
                return
            }
            stopPaperFeed()
            if abs(point.y - clip.bounds.minY) > 0.5 {
                clip.scroll(to: point)
                scroll.reflectScrolledClipView(clip)
            }
        }

        func prepareNativeEdit() {
            guard parent.preferences.paperMotion == .roll, editor?.hasMarkedText() == false else { return }
            pendingFeedOrigin = scroll?.contentView.bounds.origin
        }

        func interruptPaperFeed(cancelFollow: Bool = false) {
            stopPaperFeed()
            pendingFeedOrigin = nil
            animateNextFeed = false
            if cancelFollow { pendingFollowCaret = false }
        }

        private func stopPaperFeed() {
            feedTimer?.invalidate()
            feedTimer = nil
            feedTarget = nil
        }

        private func setScrollOrigin(_ point: NSPoint) {
            guard let scroll else { return }
            let clip = scroll.contentView
            let constrained = clip.constrainBoundsRect(NSRect(origin: point, size: clip.bounds.size)).origin
            clip.scroll(to: constrained)
            scroll.reflectScrolledClipView(clip)
            editor?.needsDisplay = true
        }

        private func startPaperFeed(from origin: NSPoint, to target: NSPoint) {
            stopPaperFeed()
            feedOrigin = origin
            feedTarget = target
            feedStartedAt = ProcessInfo.processInfo.systemUptime
            let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.advancePaperFeed() }
            }
            feedTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }

        private func advancePaperFeed() {
            guard let target = feedTarget else { stopPaperFeed(); return }
            guard editor?.hasMarkedText() == false else { interruptPaperFeed(); return }
            let elapsed = ProcessInfo.processInfo.systemUptime - feedStartedAt
            let progress = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                ? 1 : min(1, max(0, elapsed / feedDuration))
            let eased = 1 - pow(1 - progress, 3)
            setScrollOrigin(NSPoint(x: target.x, y: feedOrigin.y + (target.y - feedOrigin.y) * eased))
            publishCaret()
            if progress >= 1 { stopPaperFeed() }
        }

        // The rail spans the whole page. When revising or scrolling away from
        // the insertion point, clear the full width of the remaining writing.
        private func followingTextBottom(in clip: NSClipView, caretBottom: CGFloat) -> CGFloat? {
            guard parent.preferences.effectivePaperStartPosition == .top, let editor,
                  let storage = editor.textStorage,
                  editor.selectedRange().location < storage.length || caretBottom > clip.bounds.height,
                  let layout = editor.layoutManager, let container = editor.textContainer else { return nil }
            let used = layout.usedRect(for: container)
            let bottom = editor.textContainerOrigin.y + used.maxY - clip.bounds.minY
            if bottom >= clip.bounds.height { return clip.bounds.height }
            if parent.preferences.paperMotion == .roll {
                return PaperRollProjection(width: clip.bounds.width, viewportHeight: clip.bounds.height).projectY(bottom)
            }
            return bottom
        }

        private func publishCaret() {
            guard let clip = scroll?.contentView, let rect = caretRectInClip(projected: true) else { return }
            let bottom = clip.isFlipped ? rect.maxY - clip.bounds.minY : clip.bounds.maxY - rect.minY
            let position = CaretPosition(
                x: rect.minX - clip.bounds.minX,
                top: clip.isFlipped ? rect.minY - clip.bounds.minY : clip.bounds.maxY - rect.maxY,
                bottom: bottom,
                followingTextBottom: followingTextBottom(in: clip, caretBottom: bottom),
                scrollOffset: max(0, clip.bounds.minY),
                visible: bottom >= 0 && bottom <= clip.bounds.height + 4,
                startPosition: parent.preferences.effectivePaperStartPosition
            )
            guard position != lastCaret else { return }
            lastCaret = position
            parent.onCaret(position)
        }
    }
}
