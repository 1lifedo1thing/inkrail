import InkrailCore

/// The native buffer must switch letters before AppKit handles the next input event.
@MainActor
protocol LetterEditor: AnyObject {
    func commitComposition()
    func display(_ page: Page)
}
