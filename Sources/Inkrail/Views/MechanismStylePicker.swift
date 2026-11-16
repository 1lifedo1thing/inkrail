import SwiftUI
import InkrailCore

/// Each tile uses the real desk renderers, rather than a decorative screenshot.
@MainActor
struct MechanismStylePicker: View {
    @Binding var preferences: WritingPreferences

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(MechanismStyle.allCases, id: \.self) { style in
                choice(style)
            }
        }
    }

    private func choice(_ style: MechanismStyle) -> some View {
        let selected = preferences.mechanismStyle == style
        var preview = preferences
        preview.mechanismStyle = style

        return Button {
            // Do not overwrite the user's Classic colour or manual rail finish.
            preferences.mechanismStyle = style
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    RailView(finish: preview.effectiveRailFinish, style: style)
                        .frame(width: 154).scaleEffect(0.86)
                    CapsuleView(finish: preview.capsule, style: style,
                                lampOn: preview.nightMode, lampWarmth: preview.lampWarmth,
                                lampIntensity: preview.lampIntensity)
                        .scaleEffect(0.74)
                }
                .frame(height: 79)
                .allowsHitTesting(false)
                Text(style.label).font(.custom("Courier", size: 11)).lineLimit(1)
                Text(style.subtitle).font(.custom("Courier", size: 8.5))
                    .foregroundColor(DeskPalette.mutedInk).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 4).padding(.top, 7).padding(.bottom, 12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(selected ? 0.43 : 0.19)))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(selected ? DeskPalette.ink.opacity(0.55) : DeskPalette.ink.opacity(0.14),
                        lineWidth: selected ? 1.1 : 0.6))
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12)).foregroundColor(Color(hex: 0x718067))
                        .padding(8)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .help("\(style.label): \(style.subtitle)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(style.label), \(style.subtitle)")
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityHint("Applies this style to the moving capsule and rail. Your writing and lamp settings are unchanged.")
    }
}
