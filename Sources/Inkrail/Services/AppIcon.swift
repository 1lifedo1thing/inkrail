import AppKit

/// Gives bundled launches and SwiftPM launches the same original app icon.
@MainActor
enum InkrailAppIcon {
    static func image(applicationBundle: Bundle = .main,
                      resources: Bundle = InkrailResources.bundle) -> NSImage? {
        if let url = applicationBundle.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url), icon.isValid {
            return icon
        }
        guard let url = resources.url(forResource: "AppIcon", withExtension: "png"),
              let icon = NSImage(contentsOf: url), icon.isValid else { return nil }
        return icon
    }

    static func install() {
        if let icon = image() { NSApplication.shared.applicationIconImage = icon }
    }
}
