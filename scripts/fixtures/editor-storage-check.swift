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
                        onRestoreSeal: { model.setSeal($1, for: $0) },
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

    model.select(destination)
    let seal = LetterSeal(text: "Yours", shape: .oval, color: .forest)
    model.setSeal(seal, for: destination)
    editor.selectAll(nil)
    editor.setMarkedText(" ", selectedRange: NSRange(location: 1, length: 0), replacementRange: selection)
    check(model.selectedPage?.seal == seal, "provisional input-method whitespace keeps the letter seal")
    editor.insertText("Closing", replacementRange: selection)
    check(model.currentText == "Closing" && model.selectedPage?.seal == seal,
          "replacing the letter through an input method preserves the seal")
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
    editor.selectAll(nil)
    editor.breakUndoCoalescing()
    editor.deleteBackward(nil)
    editor.breakUndoCoalescing()
    check(model.currentText.isEmpty && model.selectedPage?.seal == nil, "deleting the last writing clears its seal")
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
    guard let undo = editor.undoManager, undo.canUndo else { throw Failure(description: "Deletion has no native undo") }
    undo.undo()
    check(model.currentText == "Closing" && model.selectedPage?.seal == seal, "Undo restores the writing and its original seal")
    let revised = LetterSeal(text: "Revised", shape: .scalloped, color: .plum)
    model.setSeal(revised, for: destination)
    undo.redo()
    check(model.currentText.isEmpty && model.selectedPage?.seal == nil, "Redo removes the writing and seal together")
    undo.undo()
    check(model.currentText == "Closing" && model.selectedPage?.seal == revised, "another Undo restores the most recently edited seal")
    model.setSeal(nil, for: destination)
    undo.redo()
    undo.undo()
    check(model.currentText == "Closing" && model.selectedPage?.seal == nil, "Undo honors an explicitly removed seal")
    model.setSeal(revised, for: destination)
    editor.selectAll(nil)
    editor.setMarkedText(" ", selectedRange: NSRange(location: 1, length: 0), replacementRange: selection)
    check(model.saveNow() && model.currentText == " " && model.selectedPage?.seal == nil,
          "saving a whitespace-only input-method commit removes the seal")

    model.createPage(text: "End")
    model.setSeal(seal, for: model.selectedID!)
    for _ in 0..<3 {
        editor.deleteBackward(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.04))
    }
    check(model.currentText.isEmpty && model.selectedPage?.seal == nil, "repeated Backspace clears the seal")
    undo.undo()
    check(!model.currentText.isEmpty && model.selectedPage?.seal == seal,
          "one Undo restores the last writing and seal after repeated Backspace")
}
