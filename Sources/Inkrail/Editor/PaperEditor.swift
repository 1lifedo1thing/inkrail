import AppKit
import SwiftUI
import InkrailCore

struct CaretPosition: Equatable {
    var x: CGFloat = 78
    var top: CGFloat = 68
    var bottom: CGFloat = 104
    var scrollOffset: CGFloat = 0
    var visible = true
    var startPosition: PaperStartPosition?
}

final class InkTextView: NSTextView {
    var onStroke: ((StrokeKind) -> Void)?
    var onLayout: (() -> Void)?
    var onCompositionEnd: (() -> Void)?
    var onWillEdit: (() -> Void)?
    var onInteraction: (() -> Void)?
    private(set) var performingNativeEdit = false

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let wasComposing = hasMarkedText()
        let inserted = (insertString as? String) ?? (insertString as? NSAttributedString)?.string ?? ""
        onWillEdit?()
        performingNativeEdit = true
        defer { performingNativeEdit = false }
        super.insertText(insertString, replacementRange: replacementRange)
        // AppKit handles input methods; never reinterpret raw key codes as text.
        (layoutManager as? InkLayoutManager)?.composing = hasMarkedText()
        if wasComposing && !hasMarkedText() { onCompositionEnd?() }
        guard !inserted.isEmpty else { return }
        if inserted.contains("\n") && inserted.count <= 2 { onStroke?(.carriage) }
        else if inserted == " " { onStroke?(.space) }
        else if inserted.count <= 4 || wasComposing { onStroke?(.key) }
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
        super.setFrameSize(newSize)
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
    var preferences: WritingPreferences
    var onChange: (String) -> Void
    var onCaret: (CaretPosition) -> Void
    var onStroke: (StrokeKind) -> Void

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
        storage.addLayoutManager(manager)
        let container = NSTextContainer(containerSize: NSSize(width: 640, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.heightTracksTextView = false
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        let editor = InkTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 480), textContainer: container)
        editor.isEditable = true
        editor.isSelectable = true
        editor.isRichText = false
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
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PaperEditor
        weak var editor: InkTextView?
        weak var scroll: NSScrollView?
        private var loadedID: UUID?
        private var appliedPreferences: WritingPreferences?
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
            } else if editor.string != parent.text && !editor.hasMarkedText() {
                let selection = editor.selectedRange()
                editor.string = parent.text
                editor.setSelectedRange(NSRange(location: min(selection.location, (parent.text as NSString).length), length: 0))
                textReplaced = true
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
            let selected = editor.selectedRanges
            editor.font = font
            editor.textColor = ink
            editor.insertionPointColor = ink.withAlphaComponent(0.48)
            editor.selectedTextAttributes = [
                .backgroundColor: NSColor(calibratedRed: 0.55, green: 0.59, blue: 0.44, alpha: 0.28)
            ]
            editor.defaultParagraphStyle = paragraph
            editor.typingAttributes = attributes
            editor.textStorage?.setAttributes(attributes, range: NSRange(location: 0, length: (editor.string as NSString).length))
            editor.selectedRanges = selected
            (editor.layoutManager as? InkLayoutManager)?.wornInk = prefs.wornInk
            (editor.layoutManager as? InkLayoutManager)?.inkBuildup = prefs.inkBuildup
            (editor.layoutManager as? InkLayoutManager)?.paperRollEnabled = prefs.paperMotion == .roll
            editor.needsDisplay = true
        }

        func textDidChange(_ notification: Notification) {
            guard !updating, let editor else { return }
            parent.onChange(editor.string)
            (editor.layoutManager as? InkLayoutManager)?.composing = editor.hasMarkedText()
            animateNextFeed = editor.performingNativeEdit && !editor.hasMarkedText()
            scheduleCaretUpdate(followCaret: true)
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
                    let animate = self.animateNextFeed && !layoutChanged
                    let origin = self.pendingFeedOrigin
                    self.animateNextFeed = false
                    self.pendingFeedOrigin = nil
                    if follow || layoutChanged { self.followInsertionPoint(animate: animate, from: origin) }
                }
                // While composing, leave the container and scrolling to AppKit.
                // The pending follow is consumed after commit/unmark.
                self.publishCaret()
                self.scheduled = false
            }
        }

        /// Insets are native layout padding, never blank lines in the letter.
        /// Bottom's leading inset anchors its first line. Its symmetric trailing
        /// padding is excluded from reading scroll by the native clip constraint.
        private func updatePaperLayout() -> Bool {
            guard let editor, let clip = scroll?.contentView,
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
            if resized || layoutPreferenceChanged {
                fitDocumentToWritingBand()
            }
            if resized && !layoutPreferenceChanged && lastCaret?.visible == false {
                var origin = oldScrollOrigin
                origin.y += inset.height - oldInset.height
                clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: origin, size: clip.bounds.size)).origin)
                scroll?.reflectScrolledClipView(clip)
            }
            // A resize must not jump away from text the user has scrolled to read.
            return layoutPreferenceChanged || (resized && lastCaret?.visible != false)
        }

        private func fitDocumentToWritingBand() {
            guard let editor, let clip = scroll?.contentView,
                  let container = editor.textContainer, let layout = editor.layoutManager else { return }
            layout.ensureLayout(for: container)
            var minimumHeight = clip.bounds.height
            if parent.preferences.effectivePaperStartPosition == .top {
                // NSTextView normally leaves only its symmetric 68-point inset
                // below the text. Top's writing band needs 108 points, otherwise
                // NSClipView clamps the final lines below the mechanism. Grow
                // only the native document extent, including an empty last line;
                // recomputing after deletion lets it shrink to the viewport again.
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
            if abs(bounded.minY - clip.bounds.minY) > 0.5 {
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

        private func publishCaret() {
            guard let clip = scroll?.contentView, let rect = caretRectInClip(projected: true) else { return }
            let bottom = clip.isFlipped ? rect.maxY - clip.bounds.minY : clip.bounds.maxY - rect.minY
            let position = CaretPosition(
                x: rect.minX - clip.bounds.minX,
                top: clip.isFlipped ? rect.minY - clip.bounds.minY : clip.bounds.maxY - rect.maxY,
                bottom: bottom,
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
