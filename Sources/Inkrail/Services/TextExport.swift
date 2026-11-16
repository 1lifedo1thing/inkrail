import AppKit
import UniformTypeIdentifiers
import InkrailCore

@MainActor
enum TextExport {
    static func save(_ page: Page, markdown: Bool) throws {
        let panel = NSSavePanel()
        let type = markdown ? (UTType(filenameExtension: "md") ?? .plainText) : .plainText
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = page.exportName + (markdown ? ".md" : ".txt")
        panel.title = "Keep a copy of your letter"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try page.text.write(to: url, atomically: true, encoding: .utf8)
    }
}
