import AppKit
import SwiftUI
import InkrailCore

extension Bundle {
    static let module = Bundle(url: URL(fileURLWithPath: CommandLine.arguments[1])
        .appendingPathComponent("FixtureResources.bundle"))!
}

@MainActor
private final class ActiveSettingsWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
}

private struct PopupFailure: Error, CustomStringConvertible {
    let description: String
}

@MainActor
private final class PopupValues: ObservableObject {
    @Published var texture: PaperTexture = .classic
    @Published var mark: PaperEmbossing = .botanical
    @Published var rail: RailFinish = .steel
    @Published var deskFinish: DeskFinish = .charcoal
    @Published var deskAccent: DeskAccent = .none
    @Published var longLabel = "American Typewriter"
    @Published var controlsEnabled = true
}

@MainActor
private struct PopupGallery: View {
    @ObservedObject var values: PopupValues
    var hostName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Native dropdowns · \(hostName) host")
                .font(.system(size: 13, weight: .medium))
            row("Texture") {
                SettingsPopUp(title: "Texture", selection: $values.texture,
                              choices: PaperTexture.allCases, label: { $0.label })
            }
            row("Mark") {
                SettingsPopUp(title: "Mark", selection: $values.mark,
                              choices: PaperEmbossing.allCases, label: { $0.label })
            }
            row("Rail") {
                SettingsPopUp(title: "Rail", selection: $values.rail,
                              choices: RailFinish.allCases, label: { $0.label })
            }
            row("Long label") {
                SettingsPopUp(title: "Long label", selection: $values.longLabel,
                              choices: ["American Typewriter", "Courier"], label: { $0 })
            }
            row("Desk finish") {
                SettingsPopUp(title: "Desk finish", selection: $values.deskFinish,
                              choices: DeskFinish.allCases, label: { $0.label })
            }
            row("Desk objects") {
                SettingsPopUp(title: "Desk objects", selection: $values.deskAccent,
                              choices: DeskAccent.allCases, label: { $0.label })
            }
            Text("Isolated native controls · no saved preferences")
                .font(.system(size: 10)).foregroundColor(DeskPalette.mutedInk)
        }
        .foregroundColor(DeskPalette.ink)
        .padding(24)
        .frame(width: 420, height: 340)
        .background(DeskPalette.paper)
        .disabled(!values.controlsEnabled)
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title).font(.system(size: 12)).frame(width: 100, alignment: .leading)
            Spacer(minLength: 0)
            content().frame(width: 220, height: 26)
        }
    }
}

@main
@MainActor
private enum SettingsPopupCheck {
    static var checks = 0
    static var themeFailures: [String] = []
    static let output = URL(fileURLWithPath: CommandLine.arguments[1])

    static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        try inspect(host: .aqua, name: "light")
        try inspect(host: .darkAqua, name: "dark")
        try inspectDone(host: .aqua, name: "light")
        try inspectDone(host: .darkAqua, name: "dark")
        if !themeFailures.isEmpty {
            themeFailures.forEach { print("FAIL \($0)") }
            exit(1)
        }
        print("PASS \(checks) native settings checks: popup contrast, olive accents, bindings and Done Return action in light/dark hosts.")
        print("These are isolated native views. Interactive menu opening/highlighting, real keyboard navigation and VoiceOver were not exercised.")
    }

    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw PopupFailure(description: message) }
        checks += 1
    }

    static func descendants<T: NSView>(_ type: T.Type, in root: NSView) -> [T] {
        var result = (root as? T).map { [$0] } ?? []
        for child in root.subviews { result += descendants(type, in: child) }
        return result
    }

    static func settle(_ host: NSView) {
        let deadline = Date(timeIntervalSinceNow: 0.2)
        repeat {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        } while Date() < deadline
    }

    static func capture(_ view: NSView, name: String) throws -> NSBitmapImageRep {
        let size = view.bounds.size
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            throw PopupFailure(description: "Cannot allocate \(name)")
        }
        bitmap.size = size
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw PopupFailure(description: "Cannot encode \(name)")
        }
        try png.write(to: output.appendingPathComponent(name + ".png"))
        return bitmap
    }

    static func inspect(host appearance: NSAppearance.Name, name: String) throws {
        let values = PopupValues()
        let window = ActiveSettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 340),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: PopupGallery(values: values, hostName: name)
            .environment(\.controlActiveState, .active))
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: 420, height: 340)
        host.appearance = NSAppearance(named: appearance)
        window.contentView = host
        settle(host)
        try require(host.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == appearance,
                    "\(name): parent does not have the requested appearance")
        let buttons = descendants(NSPopUpButton.self, in: host)
        try require(buttons.count == 6, "\(name): expected six production popups")
        let expectedTitles = ["Texture": PaperTexture.allCases.map(\.label),
                              "Mark": PaperEmbossing.allCases.map(\.label),
                              "Rail": RailFinish.allCases.map(\.label),
                              "Long label": ["American Typewriter", "Courier"],
                              "Desk finish": DeskFinish.allCases.map(\.label),
                              "Desk objects": DeskAccent.allCases.map(\.label)]
        let initial = ["Texture": "Classic", "Mark": "Botanical", "Rail": "Steel", "Long label": "American Typewriter",
                       "Desk finish": DeskFinish.charcoal.label, "Desk objects": DeskAccent.none.label]
        let gallery = try capture(host, name: "settings-popups-\(name)")
        for button in buttons {
            guard let title = button.accessibilityLabel(), let expected = expectedTitles[title] else {
                throw PopupFailure(description: "\(name): popup has no known accessible name")
            }
            try require(button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua,
                        "\(name)/\(title): native popup inherits dark appearance")
            try require(button.itemTitles == expected, "\(name)/\(title): native menu titles differ")
            try require(button.titleOfSelectedItem == initial[title], "\(name)/\(title): selected title differs")
            try require(button.menu?.items.allSatisfy { ($0.attributedTitle?.length ?? 0) == 0 } == true,
                        "\(name)/\(title): forced attributed text overrides native menu highlight colors")
            let slug = title.lowercased().replacingOccurrences(of: " ", with: "-")
            // A standalone native control cache omits its layer-backed title.
            // Crop its pixels from the fully composited NSHostingView instead.
            let rect = button.convert(button.bounds, to: host)
            let pixelRect = CGRect(x: rect.minX * 2,
                y: (host.isFlipped ? rect.minY : host.bounds.height - rect.maxY) * 2,
                width: rect.width * 2, height: rect.height * 2)
            guard let image = gallery.cgImage?.cropping(to: pixelRect) else {
                throw PopupFailure(description: "Cannot crop \(name)/\(title)")
            }
            let bitmap = NSBitmapImageRep(cgImage: image)
            bitmap.size = rect.size
            if let png = bitmap.representation(using: .png, properties: [:]) {
                try png.write(to: output.appendingPathComponent("\(name)-\(slug).png"))
            }
            try checkTitlePixels(bitmap, title: "\(name)/\(title)")
            checkThemePixels(bitmap, in: CGRect(x: bitmap.size.width - 26, y: 3,
                width: 22, height: bitmap.size.height - 6), title: "\(name)/\(title) arrow")
            let textWidth = (button.titleOfSelectedItem! as NSString)
                .size(withAttributes: [.font: button.font ?? NSFont.systemFont(ofSize: 12)]).width
            // Modern NSPopUpButtonCell reports an empty titleRect for its
            // layer-rendered title. Reserve the observed 12pt leading inset
            // and a generous 32pt arrow/trailing area instead.
            try require(textWidth + 2 <= button.bounds.width - 44,
                        "\(name)/\(title): selected label exceeds the available title strip")
            try require(window.makeFirstResponder(button) && window.firstResponder === button,
                        "\(name)/\(title): popup cannot receive native keyboard focus")
            window.makeFirstResponder(nil)
        }
        for (label, title) in [("Texture", "Cotton"), ("Mark", "Sunburst"), ("Rail", "Charcoal"),
                               ("Desk finish", DeskFinish.leather.label), ("Desk objects", DeskAccent.brassLamps.label)] {
            let button = buttons.first { $0.accessibilityLabel() == label }!
            button.selectItem(withTitle: title)
            try require(button.sendAction(button.action, to: button.target), "\(name)/\(label): action was not delivered")
        }
        settle(host)
        try require(values.texture == .cotton && values.mark == .sunburst && values.rail == .charcoal,
                    "\(name): native actions did not update the SwiftUI bindings")
        try require(values.deskFinish == .leather && values.deskAccent == .brassLamps,
                    "\(name): native desk actions did not update the SwiftUI bindings")
        values.texture = .laid
        values.mark = .monogram
        values.rail = .brass
        values.deskFinish = .walnut
        values.deskAccent = .linenLamps
        settle(host)
        try require(buttons.first { $0.accessibilityLabel() == "Texture" }?.titleOfSelectedItem == "Laid"
                    && buttons.first { $0.accessibilityLabel() == "Mark" }?.titleOfSelectedItem == "Monogram"
                    && buttons.first { $0.accessibilityLabel() == "Rail" }?.titleOfSelectedItem == "Brass",
                    "\(name): external binding changes did not update selected native titles")
        try require(buttons.first { $0.accessibilityLabel() == "Desk finish" }?.titleOfSelectedItem == DeskFinish.walnut.label
                    && buttons.first { $0.accessibilityLabel() == "Desk objects" }?.titleOfSelectedItem == DeskAccent.linenLamps.label,
                    "\(name): external desk bindings did not update selected native titles")
        _ = try capture(host, name: "settings-popups-\(name)-changed")
        values.controlsEnabled = false
        settle(host)
        try require(buttons.allSatisfy { !$0.isEnabled }, "\(name): disabled environment did not reach native popup controls")
        _ = try capture(host, name: "settings-popups-\(name)-disabled")
    }

    // Require actual coloured paint rather than merely the absence of blue.
    // Sampling excludes paper, grey disabled chrome and dark neutral text.
    static func checkThemePixels(_ bitmap: NSBitmapImageRep, in rect: CGRect, title: String) {
        let scale = Double(bitmap.pixelsWide) / bitmap.size.width
        var blue = 0, olive = 0
        for y in Int(rect.minY * scale)..<Int(rect.maxY * scale) {
            for x in Int(rect.minX * scale)..<Int(rect.maxX * scale) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      color.alphaComponent > 0.95 else { continue }
                let r = color.redComponent, g = color.greenComponent, b = color.blueComponent
                if b > r + 0.12 && b > g + 0.07 { blue += 1 }
                if g > r + 0.03 && r > b + 0.03 { olive += 1 }
            }
        }
        checks += 2
        if blue > 6 { themeFailures.append("\(title): contains \(blue) system-blue pixels") }
        if olive < 20 { themeFailures.append("\(title): missing visible olive accent (\(olive) pixels)") }
        print("THEME \(title): blue \(blue), olive \(olive)")
    }

    static func inspectDone(host appearance: NSAppearance.Name, name: String) throws {
        var closeCount = 0
        let window = ActiveSettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 740),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: StudioSettingsView(preferences: .constant(WritingPreferences()),
            previewSound: {}, stopSoundPreview: {}, close: { closeCount += 1 })
            .environment(\.controlActiveState, .active))
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: 680, height: 740)
        window.contentView = host
        settle(host)
        let panel = try capture(host, name: "settings-panel-\(name)")
        let buttons = descendants(NSButton.self, in: host)
        let doneRect = CGRect(x: 590, y: 23, width: 62, height: 30)
        checkThemePixels(panel, in: doneRect, title: "\(name)/Done")
        if let crop = panel.cgImage?.cropping(to: CGRect(x: doneRect.minX * 2, y: doneRect.minY * 2,
                width: doneRect.width * 2, height: doneRect.height * 2)) {
            try NSBitmapImageRep(cgImage: crop).representation(using: .png, properties: [:])?
                .write(to: output.appendingPathComponent("\(name)-done.png"))
        }
        if let done = buttons.first(where: { $0.title == "Done" }) {
            done.performClick(nil)
            settle(host)
            try require(closeCount == 1, "\(name): Done did not call close once")
            print("PASS \(name)/Done native click")
        }
        guard let enter = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\r",
            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36) else {
            throw PopupFailure(description: "Cannot construct Return key-equivalent check")
        }
        let beforeReturn = closeCount
        let handled = host.performKeyEquivalent(with: enter)
        settle(host)
        try require(handled && closeCount == beforeReturn + 1, "\(name): Return did not activate Done exactly once")
        print("PASS \(name)/Done: programmatic Return invokes close once")
    }

    static func checkTitlePixels(_ bitmap: NSBitmapImageRep, title: String) throws {
        // Interior title strip only: exclude the border, corner antialiasing
        // and right-hand arrow, which could otherwise conceal white title ink.
        let scale = Double(bitmap.pixelsWide) / bitmap.size.width
        var dark = 0
        var light = 0
        var darkest = 1.0
        var lightest = 0.0
        for y in Int(6 * scale)..<Int((bitmap.size.height - 6) * scale) {
            for x in Int(10 * scale)..<Int((bitmap.size.width - 32) * scale) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), color.alphaComponent > 0.95 else { continue }
                func linear(_ channel: CGFloat) -> Double {
                    let value = Double(channel)
                    return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
                }
                let luminance = 0.2126 * linear(color.redComponent)
                    + 0.7152 * linear(color.greenComponent) + 0.0722 * linear(color.blueComponent)
                if luminance < 0.25 { dark += 1; darkest = min(darkest, luminance) }
                if luminance > 0.65 { light += 1; lightest = max(lightest, luminance) }
            }
        }
        try require(dark > 30 && light > 150, "\(title): title bitmap lacks dark ink on a light interior (\(dark), \(light))")
        let contrast = (lightest + 0.05) / (darkest + 0.05)
        try require(contrast >= 4.5, "\(title): rendered title contrast is only \(contrast)")
        print("PASS \(title): \(dark) dark title pixels, measured darkest-ink/light-interior contrast \(String(format: "%.1f", contrast)):1")
    }
}
