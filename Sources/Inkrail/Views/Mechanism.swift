import SwiftUI
import InkrailCore

@MainActor
struct RailView: View {
    var finish: RailFinish
    var style: MechanismStyle = .classic

    private var colors: [Color] {
        switch finish {
        case .steel: return [Color(hex: 0x252B29), Color(hex: 0xA5AAA1), Color(hex: 0x6A746D), Color(hex: 0x27322E), Color(hex: 0x151C19)]
        case .brass: return [Color(hex: 0x514532), Color(hex: 0xCEBB84), Color(hex: 0xAA915D), Color(hex: 0x5B4B2E), Color(hex: 0x30291C)]
        case .charcoal: return [Color(hex: 0x1E2221), Color(hex: 0x59605B), Color(hex: 0x343B36), Color(hex: 0x161D19)]
        }
    }

    var body: some View {
        ZStack {
            Capsule().fill(Color.black.opacity(0.25)).frame(height: 15).offset(y: 6).blur(radius: 5)
            Capsule().fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)).frame(height: 17)
            Rectangle().fill(Color.white.opacity(0.25)).frame(height: 1).offset(y: -4)
                .padding(.horizontal, 17)
            if style != .classic {
                Rectangle().fill(Color.black.opacity(0.35)).frame(height: 1).offset(y: 3)
                    .padding(.horizontal, 18)
            }
            HStack {
                endCap
                Spacer(minLength: 0)
                endCap
            }
        }
        .frame(height: 30)
        .accessibilityHidden(true)
    }

    private var endCap: some View {
        RoundedRectangle(cornerRadius: style == .classic ? 3 : 4)
            .fill(LinearGradient(colors: [Color(hex: 0x60665D), Color(hex: 0x282E29), Color(hex: 0x121713)], startPoint: .leading, endPoint: .trailing))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.10), lineWidth: 0.6))
            .overlay {
                if style != .classic {
                    Rectangle().fill(Color(hex: style.material.trim).opacity(0.75))
                        .frame(width: 1, height: 16)
                }
            }
            .frame(width: 16, height: 25)
    }
}

@MainActor
struct CapsuleView: View {
    var finish: CapsuleFinish
    var style: MechanismStyle = .classic
    var striking = false
    var lampOn = false
    var lampWarmth: Double = 0.65
    var lampIntensity: Double = 0.82

    private var lamp: LampAppearance {
        LampAppearance(warmth: lampWarmth, intensity: lampIntensity)
    }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Ellipse().fill(Color.black.opacity(0.28))
                .frame(width: 100, height: 12).offset(y: 26).blur(radius: 6)
            // Exposed hammer and stem: the active character sits immediately above.
            RoundedRectangle(cornerRadius: 1)
                .fill(LinearGradient(colors: [Color(hex: 0x313B32), Color(hex: 0x8A9080), Color(hex: 0x252E28)], startPoint: .leading, endPoint: .trailing))
                .frame(width: 5, height: 30)
                .offset(y: -31 + (striking && !reduceMotion ? -4 : 0))
            RoundedRectangle(cornerRadius: 1)
                .fill(LinearGradient(colors: [Color(hex: 0x919582), Color(hex: 0x2A332C)], startPoint: .top, endPoint: .bottom))
                .frame(width: 23, height: 5)
                .shadow(color: .black.opacity(0.22), radius: 1, y: 2)
                .offset(y: -46 + (striking && !reduceMotion ? -4 : 0))
            if style == .classic {
                classicHousing
            } else {
                StyledCapsuleHousing(style: style, lampOn: lampOn)
            }
            if lampOn {
                Capsule().fill(lamp.lightColor.opacity(lamp.emitterOpacity))
                    .frame(width: 22, height: 3)
                    .shadow(color: lamp.lightColor.opacity(lamp.emitterGlowOpacity), radius: 4)
                    .blur(radius: 1).offset(y: LampBeamProfile.emitterOffsetY)
            }
        }
        .frame(width: 116, height: 100)
        // Keep the housing, shadow and hardware in one compositing layer.
        // The native Button host can otherwise drop the shadowed housing near
        // the paper's clipped left edge while still drawing the stem and dots.
        .compositingGroup()
        .animation(reduceMotion ? nil : .spring(response: 0.13, dampingFraction: 0.5), value: striking)
        .accessibilityHidden(true)
    }

    private var classicHousing: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22)
                .fill(finish.color)
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .fill(LinearGradient(stops: [
                            .init(color: .white.opacity(0.50), location: 0),
                            .init(color: .white.opacity(0.06), location: 0.30),
                            .init(color: .clear, location: 0.52),
                            .init(color: .black.opacity(0.13), location: 0.83),
                            .init(color: .black.opacity(0.25), location: 1)
                        ], startPoint: .top, endPoint: .bottom))
                )
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color(hex: 0x343B30).opacity(0.26), lineWidth: 0.8))
                .frame(width: 110, height: 46)
                .shadow(color: .black.opacity(0.28), radius: 3, y: 4)
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.35))
                .frame(width: 72, height: 2).blur(radius: 1).offset(y: -17)
            HStack(spacing: 7) {
                Circle().fill(lampOn ? Color(hex: 0xB9CF7D) : Color(hex: 0x8BA474))
                    .shadow(color: lampOn ? Color(hex: 0xB9CF7D).opacity(0.8) : .clear, radius: 4)
                Circle().fill(Color(hex: 0x916D5D))
                Circle().fill(Color(hex: 0x51564A))
            }
            .frame(width: 29, height: 4)
            .offset(x: -25, y: 0)
        }
    }
}
