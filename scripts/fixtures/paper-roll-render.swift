import AppKit
import SwiftUI
import InkrailCore

// These declarations satisfy the editor's app-level interfaces without loading
// AppModel, a user's documents/preferences, or SoundEngine.
enum StrokeKind { case key, space, carriage, erase, navigation }
extension Notification.Name {
    static let inkrailFocusEditor = Notification.Name("Inkrail.FocusEditor")
}
extension Bundle {
    static let module = Bundle(url: URL(fileURLWithPath: CommandLine.arguments[1])
        .appendingPathComponent("FixtureResources.bundle"))!
}

private struct RenderFailure: Error, CustomStringConvertible {
    let description: String
}

@MainActor
private final class RenderObservation {
    var caret: CaretPosition?
}

/// Mirrors the current desk's placement around the actual production editor,
/// paper and mechanism. The fixture footer identifies these as component
/// captures. Input and caret changes are ordinary SwiftUI state callbacks.
@MainActor
private struct NativeRollScene: View {
    let preferences: WritingPreferences
    let observation: RenderObservation
    private let pageID = UUID()
    @InkrailState private var text: String
    @InkrailState private var caret = CaretPosition()

    init(preferences: WritingPreferences, sample: String, observation: RenderObservation) {
        self.preferences = preferences
        self.observation = observation
        _text = InkrailState(initialValue: sample)
    }

    var body: some View {
        GeometryReader { geometry in
            let width = min(720.0, geometry.size.width - 104)
            let height = max(440.0, geometry.size.height - 112)
            ZStack {
                DeskPalette.background
                RadialGradient(colors: [Color(hex: 0x3B3C30).opacity(0.18), .clear],
                               center: .center, startRadius: 100, endRadius: 700)
                VStack(spacing: 0) {
                    Text("INKRAIL")
                        .font(.custom("Courier", size: 10)).tracking(3.6)
                        .foregroundColor(Color(hex: 0x8C8F7E).opacity(0.65))
                        .frame(height: 58)
                    paper(width: width, height: height)
                        .frame(width: width, height: height)
                        .shadow(color: .black.opacity(0.4), radius: 25, y: 14)
                    Text("ISOLATED NATIVE COMPONENT RENDER")
                        .font(.custom("Courier", size: 9)).tracking(1)
                        .foregroundColor(Color(hex: 0x969A88).opacity(0.65))
                        .frame(height: 48)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .preferredColorScheme(.light)
    }

    private func paper(width: CGFloat, height: CGFloat) -> some View {
        let start = preferences.effectivePaperStartPosition
        let rolling = preferences.paperMotion == .roll
        let editorHeight = PaperFeedLayout.editorHeight(paperHeight: height, position: start,
                                                       motion: preferences.paperMotion)
        let headX = min(width - 64, max(64, caret.x))
        let railY = caret.railCenterY(paperHeight: height, editorHeight: editorHeight,
                                      position: start, hasText: !text.isEmpty)
        let size = CGSize(width: width, height: height)
        return ZStack(alignment: .topLeading) {
            LitPaperSurface(size: size, headX: headX, railY: railY, preferences: preferences,
                            feedOffset: caret.scrollOffset)
            PaperEditor(pageID: pageID, text: text, preferences: preferences,
                        onChange: { value, _ in text = value },
                        onCaret: { caret = $0; observation.caret = $0 },
                        onStroke: { _ in })
                .frame(width: width, height: editorHeight)
            if preferences.nightMode {
                NightLighting(size: size, headX: headX, railY: railY, preferences: preferences)
            }
            RailView(finish: preferences.effectiveRailFinish, style: preferences.mechanismStyle)
                .frame(width: width + 4)
                .position(x: width / 2, y: railY)
                .brightness(preferences.nightMode ? -0.22 : 0)
                .allowsHitTesting(false)
            CapsuleView(finish: preferences.capsule, style: preferences.mechanismStyle,
                        lampOn: preferences.nightMode, lampWarmth: preferences.lampWarmth,
                        lampIntensity: preferences.lampIntensity)
                .position(x: headX, y: railY)
                .allowsHitTesting(false)
        }
        .clipShape(PaperOutline(curved: preferences.curvedPaper,
                                feedOffset: rolling ? 0 : caret.scrollOffset))
        .clipped()
        .animation(nil, value: caret.scrollOffset)
    }
}

@main
@MainActor
private enum PaperRollRender {
    static let output = URL(fileURLWithPath: CommandLine.arguments[1])
    static let sample = """
    An afternoon at the little writing desk.
    The windows are open to a quiet street.
    A cup cools beside a folded letter.
    Every line leaves its small impression.
    The paper climbs and the light stays near.
    We make a little room for another thought.
    Some sentences arrive all at once.
    Others need the space between the keys.
    Nothing has to be finished by sundown.
    Outside, the rain begins again.
    Each drop finds a different way to fall.
    The last page waits beneath this one.
    The machine keeps its patient rhythm.
    The paper carries the words over its curve.
    Yesterday becomes a thinner line above.
    Here is the place for the next sentence.
    """

    static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        var roll = WritingPreferences()
        roll.paperMotion = .roll
        roll.paperStartPosition = .bottom
        roll.soundEnabled = false
        roll.paperEmbossing = .botanical
        var sheet = roll
        sheet.paperMotion = .sheet
        var night = roll
        night.nightMode = true
        night.lampIntensity = 0.8
        night.lampWarmth = 0.72
        let standard = CGSize(width: 1080, height: 820)
        try render(roll, size: standard, text: sample, name: "roll-day-1080x820")
        try render(sheet, size: standard, text: sample, name: "sheet-control-1080x820")
        try render(night, size: standard, text: sample, name: "roll-night-1080x820")
        try render(roll, size: CGSize(width: 660, height: 580), text: sample, name: "roll-minimum-660x580")
        try render(roll, size: standard, text: "A quiet page.\nA place to begin.", name: "roll-start-1080x820")
        var top = roll
        top.paperStartPosition = .top
        try render(top, size: standard, text: "A quiet page.\nA place to begin.", name: "roll-top-start-1080x820")
        try render(top, size: standard, text: sample, name: "roll-top-long-1080x820")
        var square = roll
        square.curvedPaper = false
        try render(square, size: standard, text: sample, name: "roll-square-corners-1080x820")
        print("PASS eight isolated native component renders. These are not running-app screenshots or motion/IME tests.")
        print("Output: \(output.path)")
    }

    static func descendant<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for child in view.subviews {
            if let match = descendant(type, in: child) { return match }
        }
        return nil
    }

    static func render(_ preferences: WritingPreferences, size: CGSize, text: String, name: String) throws {
        let observation = RenderObservation()
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: NativeRollScene(preferences: preferences, sample: text,
                                                         observation: observation))
        host.sizingOptions = []
        host.frame = CGRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        window.contentView = host
        let deadline = Date(timeIntervalSinceNow: 0.65)
        repeat {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        } while Date() < deadline
        host.layoutSubtreeIfNeeded()
        guard let editor = descendant(InkTextView.self, in: host),
              let manager = editor.layoutManager as? InkLayoutManager,
              let caret = observation.caret,
              let scroll = editor.enclosingScrollView else {
            throw RenderFailure(description: "\(name): native editor did not mount/report its caret")
        }
        guard editor.string == text, manager.paperRollEnabled == (preferences.paperMotion == .roll) else {
            throw RenderFailure(description: "\(name): native text or projection does not match the scene")
        }
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                           pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                           isPlanar: false, colorSpaceName: .deviceRGB,
                                           bytesPerRow: 0, bitsPerPixel: 0) else {
            throw RenderFailure(description: "Could not allocate \(name)")
        }
        bitmap.size = size
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw RenderFailure(description: "Could not encode \(name)")
        }
        try png.write(to: output.appendingPathComponent("\(name).png"))
        let metadata: [String: Any] = [
            "kind": "isolated native component render; not a running-app screenshot",
            "width": size.width, "height": size.height,
            "paperMotion": preferences.paperMotion.rawValue,
            "paperStartPosition": preferences.paperStartPosition.rawValue,
            "nativeTextUTF16Length": (editor.string as NSString).length,
            "nativeScrollOffset": scroll.contentView.bounds.minY,
            "nativeViewportHeight": scroll.contentView.bounds.height,
            "reportedCaret": ["x": caret.x, "top": caret.top, "bottom": caret.bottom,
                               "scrollOffset": caret.scrollOffset]
        ]
        try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("\(name).json"))
        print("PASS \(name): native text and caret mounted, PNG saved")
    }
}
