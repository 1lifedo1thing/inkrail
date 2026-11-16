import AppKit
import SwiftUI
import InkrailCore

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255,
                  green: Double((hex >> 8) & 255) / 255,
                  blue: Double(hex & 255) / 255, opacity: opacity)
    }
}
extension PaperKind {
    var color: Color {
        switch self {
        case .ivory: return Color(hex: 0xEEECD9)
        case .cream: return Color(hex: 0xE5D7B7)
        case .white: return Color(hex: 0xF3F1E9)
        }
    }
}
extension CapsuleFinish {
    var color: Color {
        switch self {
        case .porcelain: return Color(hex: 0xE5E2D6)
        case .sage: return Color(hex: 0x86977C)
        case .cobalt: return Color(hex: 0x3D609C)
        case .terracotta: return Color(hex: 0xAD6548)
        case .graphite: return Color(hex: 0x454C4A)
        }
    }
}
extension RibbonColor {
    var nsColor: NSColor {
        switch self {
        case .carbon: return NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.15, alpha: 1)
        case .midnight: return NSColor(calibratedRed: 0.13, green: 0.24, blue: 0.34, alpha: 1)
        case .oxblood: return NSColor(calibratedRed: 0.35, green: 0.12, blue: 0.14, alpha: 1)
        }
    }
    var color: Color { Color(nsColor: nsColor) }
}

enum DeskPalette {
    static let background = Color(hex: 0x1A1C1B)
    static let ink = Color(hex: 0x363B32)
    static let mutedInk = Color(hex: 0x7C7F6D)
    static let paper = Color(hex: 0xEEECD9)
    static let accent = Color(hex: 0x738168)
}

@MainActor
struct QuietButton: View {
    private static let side: CGFloat = 34
    let symbol: String
    let label: String
    var onDark = false
    var active = false
    var themedHoverLabel = false
    var action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @InkrailState private var hovered = false

    var body: some View {
        if themedHoverLabel {
            control
                .overlay(alignment: .topTrailing) {
                    if hovered {
                        DeskHoverLabel(text: label, onDark: onDark)
                            .offset(y: Self.side + 6)
                            .transition(.opacity)
                    }
                }
                .zIndex(hovered ? 1 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
        } else {
            control.help(label)
        }
    }

    private var control: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .regular))
                .frame(width: Self.side, height: Self.side)
                .foregroundColor(onDark ? Color(hex: 0xB8BAAA) : DeskPalette.ink.opacity(0.75))
                .background(Circle().fill((onDark ? Color.white : Color.black).opacity(hovered || active ? 0.08 : 0)))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel(label)
    }
}

/// A noninteractive label below the paper controls. The paper-stage host keeps
/// this overlay outside its clipping mask so the label remains fully visible.
struct DeskHoverLabel: View {
    let text: String
    var onDark = false

    var body: some View {
        Text(text)
            .font(.custom("Courier", size: 11))
            .foregroundColor(onDark ? DeskPalette.paper : DeskPalette.ink)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 6).fill(onDark ? DeskPalette.ink : DeskPalette.paper))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .stroke(onDark ? DeskPalette.accent : DeskPalette.ink.opacity(0.25), lineWidth: 0.7))
            .shadow(color: .black.opacity(onDark ? 0.28 : 0.16), radius: 4, y: 2)
            .fixedSize()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
