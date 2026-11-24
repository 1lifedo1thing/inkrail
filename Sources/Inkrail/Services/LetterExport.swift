import AppKit
import UniformTypeIdentifiers
import InkrailCore

@MainActor
enum LetterExport {
    static func saveText(_ page: Page, markdown: Bool) throws {
        let type = markdown ? (UTType(filenameExtension: "md") ?? .plainText) : .plainText
        guard let url = destination(for: page, type: type, suffix: markdown ? "md" : "txt") else { return }
        let content = markdown ? page.markdownText : page.plainText
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    static func savePDF(_ page: Page, preferences: WritingPreferences, paperSize: CGSize) throws {
        guard let url = destination(for: page, type: .pdf, suffix: "pdf") else { return }
        let data = try LetterPDFExport.data(for: page, preferences: preferences, paperSize: paperSize)
        try data.write(to: url, options: .atomic)
    }

    private static func destination(for page: Page, type: UTType, suffix: String) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = page.exportName + "." + suffix
        panel.title = "Keep a copy of your letter"
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }
}
