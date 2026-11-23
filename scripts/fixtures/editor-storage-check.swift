import AppKit
import InkrailCore
import SwiftUI

@MainActor private struct LibraryEditor: View {
    @ObservedObject var model: AppModel
    var snapshot: Page?

    var body: some View {
        if let page = snapshot ?? model.selectedPage {
            PaperEditor(page: page, currentPage: { model.selectedPage },
                        preferences: model.preferences, onChange: { model.edit($0, text: $1, formatting: $2) },
                        onCaret: { _ in }, onStroke: { _ in }, onConnect: { model.editor = $0 })
        }
    }
}

/// Verify committed files before SwiftUI has a chance to redraw between a menu action
/// and the next native keystroke. Uses a private window and a disposable library.
@MainActor func checkEditorStorage(_ check: (Bool, String) -> Void) throws {
    struct Failure: Error, CustomStringConvertible { let description: String }
    func findEditor(in view: NSView) -> InkTextView? {
        if let text = view as? InkTextView { return text }
        return view.subviews.lazy.compactMap { findEditor(in: $0) }.first
    }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("Inkrail-editor-storage-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let model = AppModel(defaults: MemoryDefaults(), defaultRootURL: root, schedulesAutosave: false)
    let source = model.selectedID!
    model.edit(source, text: "Old draft")
    model.createPage(text: "Styled letter")
    let destination = model.selectedID!
    let bold = TextFormatRun(location: 0, length: 6, emphasis: .bold)
    model.edit(destination, text: "Styled letter", formatting: [bold])
    model.select(source)

    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.contentView = nil; window.close() }
    let host = NSHostingView(rootView: LibraryEditor(model: model))
    let originalSnapshot = model.selectedPage
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15))
    guard let editor = findEditor(in: host), window.makeFirstResponder(editor) else {
        throw Failure(description: "The native library editor did not mount.")
    }

    let selection = NSRange(location: NSNotFound, length: 0)
    editor.setSelectedRange(NSRange(location: 0, length: 3))
    editor.setMarkedText("新的", selectedRange: NSRange(location: 2, length: 0), replacementRange: selection)
    model.select(destination)
    editor.insertText("!", replacementRange: selection)
    model.createPage()
    let newID = model.selectedID!
    editor.insertText("x", replacementRange: selection)
    host.rootView = LibraryEditor(model: model, snapshot: originalSnapshot)
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
    check(editor.string == "x", "queued SwiftUI updates keep the most recent letter and keystroke")
    check(model.saveNow(), "rapid page changes save successfully")
    let repo = try PageRepository(rootURL: root)
    let pages = try repo.load().pages
    check(pages.first { $0.id == source }?.text == "新的 draft",
              "changing letters preserves the pending input-method replacement in the original file")
    let saved = pages.first { $0.id == destination }
    check(saved?.text == "Styled letter!" && saved?.formatting == [bold],
              "the very next keystroke preserves the destination body and formatting")
    check(pages.first { $0.id == newID }?.text == "x",
              "the first keystroke after New Letter starts with an empty buffer")

    editor.setSelectedRange(NSRange(location: 0, length: 1))
    editor.setMarkedText("に", selectedRange: NSRange(location: 1, length: 0), replacementRange: selection)
    model.moveToTrash(newID)
    check(try repo.load(inTrash: true).pages.first { $0.id == newID }?.text == "に",
              "moving the selected letter to trash includes its pending composition")
}
