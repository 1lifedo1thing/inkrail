import AppKit
import SwiftUI
import InkrailCore

enum StudioSection: String, CaseIterable, Identifiable {
    case paper = "Paper", type = "Type", machine = "Machine", desk = "Desk", sound = "Sound", light = "Light", storage = "Storage"
    var id: String { rawValue }
}

/// The settings UI accepts a binding so previews and validation use the same
/// controls without creating AppModel or touching saved letters/preferences.
@MainActor
struct StudioSettingsView: View {
    @Binding var preferences: WritingPreferences
    var previewSound: () -> Void
    var stopSoundPreview: () -> Void
    var close: () -> Void
    var storagePath = "~/Library/Application Support/Inkrail"
    var storageAvailable = true
    var storageMessage: String? = nil
    var changeStorageLocation: () -> Void = {}
    var showStorageFolder: () -> Void = {}
    @InkrailState var section: StudioSection = .paper

    var body: some View {
        VStack(spacing: 0) {
            header
            Picker("Settings section", selection: $section) {
                ForEach(StudioSection.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 30).padding(.bottom, 20)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    switch section {
                    case .paper: paperSettings
                    case .type: typeSettings
                    case .machine: machineSettings
                    case .desk: deskSettings
                    case .sound: soundSettings
                    case .light: lightSettings
                    case .storage: storageSettings
                    }
                }
                .padding(.horizontal, 30).padding(.top, 4).padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            footer
        }
        .foregroundColor(DeskPalette.ink)
        .tint(DeskPalette.accent)
        .background(DeskPalette.paper)
        .frame(width: 680, height: 740)
        .preferredColorScheme(.light)
        .onChange(of: section) { _ in stopSoundPreview() }
        .onChange(of: preferences.soundEnabled) { _ in stopSoundPreview() }
        .onChange(of: preferences.typewriterSound) { _ in stopSoundPreview() }
        .onChange(of: preferences.soundVolume) { _ in stopSoundPreview() }
        .onDisappear { stopSoundPreview() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Make it yours.").font(.custom("Courier", size: 24))
                Text("A little character. A quieter desk.")
                    .font(.system(size: 12)).foregroundColor(DeskPalette.mutedInk)
            }
            Spacer()
            Button("Done", action: close)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(SettingsDoneButtonStyle())
                .controlSize(.regular)
        }
        .padding(.horizontal, 30).padding(.top, 26).padding(.bottom, 24)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.45)
            HStack {
                Text(section == .storage ? "Your letters · Your chosen folder" : "Saved on this Mac · Applies to your writing desk")
                Spacer()
                Text("Made with ❤︎ by Aaryan Verma")
                    .accessibilityLabel("Made with love by Aaryan Verma")
            }
            .font(.system(size: 10)).foregroundColor(DeskPalette.mutedInk)
            .padding(.horizontal, 30).padding(.vertical, 16)
        }
    }

    private var paperSettings: some View {
        Group {
            PaperCustomizationPreview(preferences: preferences)
            card("Page layout") {
                labeled("Paper motion") {
                    Picker("Paper motion", selection: $preferences.paperMotion) {
                        ForEach(PaperMotion.allCases) { Text($0.label).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 240)
                }
                labeled("Start writing") {
                    Picker("Start writing", selection: $preferences.paperStartPosition) {
                        ForEach(PaperStartPosition.allCases) { Text($0.label).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 220)
                }
                note(preferences.paperStartPosition == .top
                     ? "Start near the top. The paper feeds upward when the writing reaches the lower band."
                     : "Start at the lower writing line. Each new line feeds the paper upward.")
                toggle("Wide margins", isOn: $preferences.wideMargins)
            }
            card("Paper surface", subtitle: "Choose the feel of your sheet.") {
                labeled("Paper colour") {
                    HStack(spacing: 20) {
                        ForEach(PaperKind.allCases, id: \.self) { paper in
                            colorChoice(paper.label, color: paper.color, selected: preferences.paper == paper) {
                                preferences.paper = paper
                            }
                        }
                    }
                }
                menu("Texture", selection: $preferences.paperTexture, cases: PaperTexture.allCases, label: { $0.label })
                if preferences.paperTexture != .smooth {
                    control("Texture detail", value: $preferences.textureStrength, range: 0...1, percent: true)
                }
                toggle("Curved upper corners", isOn: $preferences.curvedPaper)
            }
            card("Embossing", subtitle: "A quiet impression pressed into the paper.") {
                menu("Mark", selection: $preferences.paperEmbossing, cases: PaperEmbossing.allCases, label: { $0.label })
                if preferences.paperEmbossing != .none {
                    control("Relief", value: $preferences.embossingDepth, range: 0...1, percent: true)
                }
                toggle("Botanical margins", isOn: $preferences.garden)
            }
        }
    }

    private var typeSettings: some View {
        Group {
            InkWritingPreview(preferences: preferences)
                .frame(height: 116)
                .padding(16)
                .background(preferences.paper.color)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(DeskPalette.ink.opacity(0.13), lineWidth: 0.6))
                .allowsHitTesting(false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Typeface and ink preview")
                .accessibilityValue("\(preferences.writingFont.label), \(preferences.wornInk ? "worn ribbon" : "even ink")")
            card("Typeface") {
                menu("Writing font", selection: $preferences.writingFont, cases: WritingFont.allCases, label: { $0.label })
                control("Type size", value: $preferences.fontSize, range: 15...28, suffix: "pt", step: 1)
            }
            card("Ribbon & ink") {
                toggle("Worn ribbon", isOn: $preferences.wornInk)
                if preferences.wornInk {
                    control("Ink buildup", value: $preferences.inkBuildup, range: 0...1, percent: true)
                    note("Uneven strikes leave some letters darker and thicker, others faint.")
                }
                control("Ink darkness", value: $preferences.inkStrength, range: 0.35...1, percent: true)
                labeled("Ribbon colour") {
                    HStack(spacing: 20) {
                        ForEach(RibbonColor.allCases, id: \.self) { ribbon in
                            colorChoice(ribbon.label, color: ribbon.color, selected: preferences.ribbon == ribbon) {
                                preferences.ribbon = ribbon
                            }
                        }
                    }
                }
            }
            note("Fonts and paper styling stay on your desk. Text exports contain your words.")
        }
    }

    private var machineSettings: some View {
        Group {
            ZStack {
                RailView(finish: preferences.effectiveRailFinish, style: preferences.mechanismStyle)
                CapsuleView(finish: preferences.capsule, style: preferences.mechanismStyle,
                            lampOn: preferences.nightMode, lampWarmth: preferences.lampWarmth,
                            lampIntensity: preferences.lampIntensity)
            }.frame(height: 108).padding(.horizontal, 16)
            card("Slider styles", subtitle: "The same little machine. A different character.") {
                MechanismStylePicker(preferences: $preferences)
            }
            card("Finishes") {
                if preferences.mechanismStyle == .classic {
                    labeled("Capsule colour") {
                        HStack(spacing: 17) {
                            ForEach(CapsuleFinish.allCases, id: \.self) { finish in
                                colorChoice(finish.label, color: finish.color, selected: preferences.capsule == finish) {
                                    preferences.capsule = finish
                                }
                            }
                        }
                    }
                } else {
                    toggle("Match rail to style", isOn: $preferences.matchRailToStyle)
                }
                if preferences.mechanismStyle == .classic || !preferences.matchRailToStyle {
                    menu("Rail finish", selection: $preferences.rail, cases: RailFinish.allCases, label: { $0.label })
                } else {
                    labeled("Rail finish") { Text(preferences.effectiveRailFinish.label).font(.system(size: 12)) }
                }
            }
        }
    }

    private var deskSettings: some View {
        Group {
            DeskAppearancePreview(preferences: preferences)
            card("Around the paper") {
                HStack(spacing: 12) {
                    deskScene("Leather study", detail: "Leather · bronze lamps", finish: .leather, accent: .brassLamps)
                    deskScene("Walnut study", detail: "Walnut · bronze lamps", finish: .walnut, accent: .brassLamps)
                    deskScene("Warm oak", detail: "Honey oak · linen lamps", finish: .oak, accent: .linenLamps)
                }
                menu("Desk finish", selection: $preferences.deskFinish, cases: DeskFinish.allCases, label: { $0.label })
                menu("Desk objects", selection: $preferences.deskAccent, cases: DeskAccent.allCases, label: { $0.label })
                toggle("Wider paper in Focus Mode", isOn: $preferences.widerFocusPaper)
                note("Desk scenes appear outside Focus Mode. Narrow windows tuck objects away. Your paper, embossing and roll settings stay as you chose them.")
            }
        }
    }

    private func deskScene(_ title: String, detail: String, finish: DeskFinish, accent: DeskAccent) -> some View {
        let selected = preferences.deskFinish == finish && preferences.deskAccent == accent
        return Button {
            preferences.deskFinish = finish
            preferences.deskAccent = accent
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(title).font(.system(size: 12, weight: .medium))
                    Spacer(minLength: 6)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(Color(hex: 0x738168))
                }
                Text(detail).font(.system(size: 10)).foregroundColor(DeskPalette.mutedInk)
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(selected ? 0.60 : 0.18)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(DeskPalette.ink.opacity(selected ? 0.45 : 0.10), lineWidth: selected ? 1 : 0.5))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(detail)")
        .accessibilityValue(selected ? "Selected" : "Not selected")
    }

    private var soundSettings: some View {
        Group {
            card("Typewriter sounds", subtitle: "The margin bell rings about seven character widths before the end of the line.") {
                toggle("Mechanical sounds", isOn: $preferences.soundEnabled)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(TypewriterSound.allCases, id: \.self) { sound in
                        soundChoice(sound)
                    }
                }
                .disabled(!preferences.soundEnabled)
            }
            card("Listening level") {
                control("Volume", value: $preferences.soundVolume, range: 0...1, percent: true)
                    .disabled(!preferences.soundEnabled)
                HStack {
                    Button(action: previewSound) {
                        Label("Preview sound", systemImage: "play.fill")
                    }
                    .disabled(!preferences.soundEnabled || preferences.soundVolume == 0)
                    .controlSize(.large)
                    Spacer()
                    Text("Keys, space bar, bell and return")
                        .font(.system(size: 11)).foregroundColor(DeskPalette.mutedInk)
                }
            }
            note("Preview plays only when you press the button. Mute stops the sounds immediately.")
        }
    }

    private var lightSettings: some View {
        Group {
            NightLampPreview(preferences: preferences)
            card("Night writing", subtitle: "A soft pool of light around the next sentence.") {
                toggle("Night writing", isOn: $preferences.nightMode)
                control("Lamp intensity", value: $preferences.lampIntensity, range: 0.25...1, percent: true)
                    .disabled(!preferences.nightMode)
                VStack(spacing: 6) {
                    control("Warmth", value: $preferences.lampWarmth, range: 0...1, percent: true)
                        .disabled(!preferences.nightMode)
                    HStack {
                        Text("Cool white")
                        Spacer()
                        Text("Amber")
                    }
                    .font(.system(size: 10)).foregroundColor(DeskPalette.mutedInk)
                    .padding(.leading, 148).padding(.trailing, 54)
                }
            }
            note("You can also click the capsule on your writing desk to toggle its lamp.")
        }
    }

    private var storageSettings: some View {
        Group {
            card("A home for your letters", subtitle: "Choose where Inkrail keeps your writing.") {
                Text("Letters folder").font(.system(size: 12, weight: .medium))
                Text(storagePath)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 6).fill(DeskPalette.paper))
                    .accessibilityLabel("Letters folder: \(storagePath)")
                HStack(spacing: 14) {
                    Button("Change Location…", action: changeStorageLocation)
                        .buttonStyle(SettingsDoneButtonStyle())
                        .disabled(!storageAvailable)
                    Button("Show in Finder", action: showStorageFolder)
                        .buttonStyle(.plain)
                        .font(.system(size: 12)).foregroundColor(DeskPalette.accent)
                }
                note("Choose a new or empty folder. Your letters, recently deleted letters and backups are copied there before future saves switch to the new location.")
                note("Your previous folder stays intact as a safety copy. It will no longer receive changes.")
            }
            if !storageAvailable {
                card("Letters folder unavailable") {
                    note("Reconnect the drive or put the folder back, then reopen Inkrail. Export any unsaved writing before closing the app.")
                }
            }
            if let storageMessage {
                card("Storage update") { note(storageMessage) }
            }
            note("Keep a separate backup of your letters folder. Inkrail does not sync changes between folders or devices.")
        }
    }

    private func card<Content: View>(_ title: String, subtitle: String? = nil,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.custom("Courier", size: 17))
                if let subtitle { note(subtitle) }
            }
            Divider().opacity(0.45)
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.30)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(DeskPalette.ink.opacity(0.11), lineWidth: 0.6))
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 18) {
            Text(title).font(.system(size: 12)).frame(minWidth: 112, alignment: .leading)
            Spacer(minLength: 0)
            content()
        }
    }

    private func menu<T: Hashable>(_ title: String, selection: Binding<T>, cases: [T], label: @escaping (T) -> String) -> some View {
        labeled(title) {
            SettingsPopUp(title: title, selection: selection, choices: cases, label: label)
                .frame(width: 220, height: 26)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).lineSpacing(3)
            .foregroundColor(DeskPalette.mutedInk).fixedSize(horizontal: false, vertical: true)
    }

    private func soundChoice(_ sound: TypewriterSound) -> some View {
        let selected = preferences.typewriterSound == sound
        return Button { preferences.typewriterSound = sound } label: {
            HStack(spacing: 10) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18)).foregroundColor(Color(hex: 0x738168))
                VStack(alignment: .leading, spacing: 5) {
                    Text(sound.label).font(.system(size: 13, weight: .medium))
                    Text(sound.subtitle).font(.system(size: 11)).foregroundColor(DeskPalette.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(selected ? 0.60 : 0.18)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(DeskPalette.ink.opacity(selected ? 0.45 : 0.10), lineWidth: selected ? 1 : 0.5))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(sound.label), \(sound.subtitle)")
        .accessibilityValue(selected ? "Selected" : "Not selected")
    }

    private func colorChoice(_ name: String, color: Color, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Circle().fill(color)
                    .overlay(Circle().stroke(Color.black.opacity(0.20), lineWidth: 0.8))
                    .overlay(Circle().stroke(selected ? DeskPalette.ink.opacity(0.70) : .clear, lineWidth: 1).padding(-4))
                    .frame(width: 26, height: 26)
                Text(name).font(.system(size: 9))
            }.padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityValue(selected ? "Selected" : "Not selected")
    }

    private func toggle(_ label: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) { Text(label).font(.system(size: 12)) }
            .toggleStyle(.switch).controlSize(.small)
    }

    private func control(_ name: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String = "", step: Double = 0.01, percent: Bool = false) -> some View {
        HStack(spacing: 16) {
            Text(name).font(.system(size: 12)).frame(width: 132, alignment: .leading)
            Slider(value: value, in: range, step: step).accessibilityLabel(name)
            Text(percent ? "\(Int(value.wrappedValue * 100))%" : "\(Int(value.wrappedValue))\(suffix)")
                .font(.system(size: 11)).monospacedDigit().frame(width: 38, alignment: .trailing)
        }
    }
}

/// Explicit artwork keeps the default-action button olive even when AppKit
/// chooses the system accent for a native default bezel. SwiftUI retains the
/// button action, Return shortcut and accessibility semantics.
private struct SettingsDoneButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 11).padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: 5)
                    .fill(DeskPalette.accent)
                    .overlay {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(LinearGradient(colors: [.black.opacity(0.04), .black.opacity(0.24)],
                                                 startPoint: .top, endPoint: .bottom))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(DeskPalette.ink.opacity(focused ? 0.75 : 0.25), lineWidth: focused ? 2 : 0.6)
            }
            .brightness(configuration.isPressed ? -0.12 : 0)
            .opacity(enabled ? 1 : 0.45)
    }
}

/// A read-only sample drawn by the same native layout manager as the editor.
/// SwiftUI Text would show the font but omit its uneven pressure and overprints.
@MainActor
private struct InkWritingPreview: NSViewRepresentable {
    var preferences: WritingPreferences

    func makeNSView(context: Context) -> InkSampleView { InkSampleView() }

    func updateNSView(_ view: InkSampleView, context: Context) {
        view.update(preferences)
    }

    final class InkSampleView: NSView {
        private let storage = NSTextStorage()
        private let inkLayout = InkLayoutManager()
        private let container = NSTextContainer(size: .zero)
        override var isFlipped: Bool { true }

        init() {
            super.init(frame: .zero)
            storage.addLayoutManager(inkLayout)
            inkLayout.addTextContainer(container)
            container.lineFragmentPadding = 0
            setAccessibilityElement(false)
        }

        required init?(coder: NSCoder) { return nil }

        func update(_ preferences: WritingPreferences) {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = preferences.fontSize * 0.34
            storage.setAttributedString(NSAttributedString(
                string: "Some keys leave more ink.\nA few letters linger on the page.",
                attributes: [.font: preferences.writingFont.nsFont(size: preferences.fontSize),
                             .foregroundColor: preferences.ribbon.nsColor.withAlphaComponent(preferences.inkStrength),
                             .paragraphStyle: paragraph, .ligature: 0]))
            inkLayout.wornInk = preferences.wornInk
            inkLayout.inkBuildup = preferences.inkBuildup
            needsDisplay = true
        }

        override func draw(_ dirtyRect: NSRect) {
            container.containerSize = NSSize(width: max(1, bounds.width), height: .greatestFiniteMagnitude)
            inkLayout.ensureLayout(for: container)
            let range = inkLayout.glyphRange(for: container)
            let height = inkLayout.usedRect(for: container).height
            inkLayout.drawGlyphs(forGlyphRange: range, at: NSPoint(x: 0, y: max(0, (bounds.height - height) / 2)))
        }
    }
}

/// Draw only the closed popup. AppKit still owns the menu, selection, focus,
/// keyboard navigation and accessibility; menu items keep their native ink.
/// A rounded system popup ignores SwiftUI tint (and, on some SDKs, bezelColor).
@MainActor
private final class SettingsPopUpCell: NSPopUpButtonCell {
    private func bezelRect(_ frame: NSRect) -> NSRect { frame.insetBy(dx: 1, dy: 3) }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        let rect = bezelRect(cellFrame)
        let bezel = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        let ink = NSColor(DeskPalette.ink)
        let paper = NSColor(DeskPalette.paper)
        let field = paper.blended(withFraction: isHighlighted ? 0.16 : 0.72, of: .white) ?? paper
        field.setFill()
        bezel.fill()
        ink.withAlphaComponent(isEnabled ? 0.23 : 0.12).setStroke()
        bezel.lineWidth = 0.7
        bezel.stroke()

        let arrowRect = NSRect(x: rect.maxX - 21, y: rect.minY + 2, width: 18, height: rect.height - 4)
        let arrowBezel = NSBezierPath(roundedRect: arrowRect, xRadius: 3, yRadius: 3)
        let accent = isEnabled ? NSColor(DeskPalette.accent) : ink.withAlphaComponent(0.24)
        let top = accent.blended(withFraction: isHighlighted ? 0.18 : 0.04, of: .black) ?? accent
        let bottom = accent.blended(withFraction: isHighlighted ? 0.36 : 0.24, of: .black) ?? accent
        NSGradient(starting: top, ending: bottom)?.draw(in: arrowBezel, angle: controlView.isFlipped ? 90 : -90)

        // Two small chevrons make this recognizably a native-style popup.
        let arrows = NSBezierPath()
        for direction in [-1.0, 1.0] {
            let y = arrowRect.midY + direction * 3.7
            arrows.move(to: NSPoint(x: arrowRect.midX - 2.6, y: y - direction * 1.5))
            arrows.line(to: NSPoint(x: arrowRect.midX, y: y + direction * 1.1))
            arrows.line(to: NSPoint(x: arrowRect.midX + 2.6, y: y - direction * 1.5))
        }
        NSColor.white.withAlphaComponent(isEnabled ? 1 : 0.65).setStroke()
        arrows.lineWidth = 1.4
        arrows.lineCapStyle = .round
        arrows.lineJoinStyle = .round
        arrows.stroke()

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 12),
            .foregroundColor: ink.withAlphaComponent(isEnabled ? 1 : 0.45),
            .paragraphStyle: paragraph
        ]
        let text = (titleOfSelectedItem ?? "") as NSString
        let height = text.size(withAttributes: attributes).height
        text.draw(in: NSRect(x: rect.minX + 8, y: rect.midY - height / 2,
                            width: max(0, arrowRect.minX - rect.minX - 15), height: height),
                  withAttributes: attributes)
    }

    override func drawFocusRingMask(withFrame cellFrame: NSRect, in controlView: NSView) {
        NSBezierPath(roundedRect: bezelRect(cellFrame), xRadius: 5, yRadius: 5).fill()
    }

    override func focusRingMaskBounds(forFrame cellFrame: NSRect, in controlView: NSView) -> NSRect {
        bezelRect(cellFrame)
    }
}

/// Settings stay on light paper even in a dark host. Only the collapsed cell
/// has custom artwork; the popup remains a real AppKit control and menu.
@MainActor
struct SettingsPopUp<Value: Hashable>: NSViewRepresentable {
    var title: String
    @Binding var selection: Value
    var choices: [Value]
    var label: (Value) -> String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.cell = SettingsPopUpCell(textCell: "", pullsDown: false)
        button.appearance = NSAppearance(named: .aqua)
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.font = .systemFont(ofSize: 12)
        button.setAccessibilityLabel(title)
        button.target = context.coordinator
        button.action = #selector(Coordinator.choose(_:))
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        button.isEnabled = context.environment.isEnabled
        let titles = choices.map(label)
        if button.itemTitles != titles {
            button.removeAllItems()
            button.addItems(withTitles: titles)
        }
        if let index = choices.firstIndex(of: selection) { button.selectItem(at: index) }
        button.setAccessibilityLabel(title)
        button.needsDisplay = true
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: SettingsPopUp
        init(_ parent: SettingsPopUp) { self.parent = parent }

        @objc func choose(_ sender: NSPopUpButton) {
            let index = sender.indexOfSelectedItem
            guard parent.choices.indices.contains(index) else { return }
            parent.selection = parent.choices[index]
        }
    }
}
