import SwiftUI
import InkrailCore

/// Original procedural finishes: no downloaded textures, font files or shaders.
@MainActor
struct StyledCapsuleHousing: View {
    var style: MechanismStyle
    var lampOn: Bool

    private var material: MechanismMaterial { style.material }
    private var shell: RoundedRectangle {
        RoundedRectangle(cornerRadius: CGFloat(material.cornerRadius), style: .continuous)
    }
    private var trim: Color { Color(hex: material.trim) }

    var body: some View {
        ZStack {
            shell.fill(LinearGradient(colors: material.bodyColors.map { Color(hex: $0) },
                                      startPoint: .top, endPoint: .bottom))
            MechanismTextureView(texture: material.texture)
                .clipShape(shell)
            shell.stroke(Color.black.opacity(style == .porcelain ? 0.18 : 0.45), lineWidth: 0.8)
            shell.inset(by: 1)
                .stroke(LinearGradient(colors: [.white.opacity(0.65), .white.opacity(0.04), .black.opacity(0.22)],
                                       startPoint: .top, endPoint: .bottom), lineWidth: 0.7)
            details
            // A small, recessed slit when the lamp is off. The emitting light is
            // drawn by CapsuleView using the same LampAppearance for every style.
            Capsule().fill(Color.black.opacity(0.5))
                .frame(width: 26, height: 4).offset(y: -21.5)
        }
        .frame(width: CGFloat(MechanismMaterial.housingWidth), height: CGFloat(MechanismMaterial.housingHeight))
        .shadow(color: .black.opacity(0.28), radius: 3, y: 4)
    }

    @ViewBuilder
    private var details: some View {
        switch style {
        case .classic:
            EmptyView() // Classic is rendered by the original housing.
        case .brushedSteel:
            HStack {
                GripRibs(color: trim)
                Spacer()
                GripRibs(color: trim)
            }.padding(.horizontal, 9)
            Capsule().fill(Color(hex: 0x4A5550)).frame(width: 30, height: 10)
                .overlay(Capsule().stroke(.white.opacity(0.35), lineWidth: 0.6))
            statusDot.offset(x: -7)
            Rectangle().fill(Color(hex: 0xBFC7BE).opacity(0.75)).frame(width: 9, height: 0.8).offset(x: 5)
        case .champagne:
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(trim.opacity(0.45), lineWidth: 0.6).padding(4)
            HStack(spacing: 0) {
                decoLines
                Spacer(minLength: 36)
                decoLines
            }.padding(.horizontal, 15)
            RoundedRectangle(cornerRadius: 3).fill(Color(hex: 0x4C5145)).frame(width: 25, height: 14)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color(hex: 0xF8E9C5).opacity(0.7), lineWidth: 0.7))
            DiamondMark().stroke(Color(hex: 0xEDDCAD), lineWidth: 0.7).frame(width: 6, height: 7)
        case .walnut:
            RoundedRectangle(cornerRadius: 3)
                .fill(LinearGradient(colors: [Color(hex: 0xE0CA99), trim, Color(hex: 0xAA8B51)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 44, height: 18)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(.black.opacity(0.4), lineWidth: 0.6))
            Text("INKRAIL").font(.custom("Courier", size: 5.5)).tracking(1.1)
                .foregroundColor(Color(hex: 0x59462B))
            ScrewHead(color: trim).offset(x: -44)
            ScrewHead(color: trim).offset(x: 44)
        case .porcelain:
            Capsule().fill(trim).frame(width: 31, height: 11)
                .overlay(Capsule().stroke(.black.opacity(0.16), lineWidth: 0.6))
                .offset(y: 2)
            Circle().fill(Color(hex: 0xECEBDD)).frame(width: 3, height: 3).offset(x: -6, y: 2)
            Rectangle().fill(Color(hex: 0xE5E3D0).opacity(0.75)).frame(width: 9, height: 0.7).offset(x: 4, y: 2)
            Capsule().fill(.white.opacity(0.65)).frame(width: 56, height: 2).blur(radius: 1).offset(y: -14)
        case .midnight:
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(trim.opacity(0.4), lineWidth: 0.55).padding(4)
            Rectangle().fill(trim.opacity(0.8)).frame(width: 57, height: 0.6).offset(y: 10)
            HStack(spacing: 4) {
                Circle().fill(trim).frame(width: 3, height: 3)
                Text("IR").font(.custom("Courier", size: 6)).tracking(1.7).foregroundColor(trim)
            }.offset(y: -2)
        case .roseQuartz:
            Capsule().stroke(trim.opacity(0.38), lineWidth: 0.6).padding(4)
            Capsule().fill(Color(hex: 0xF6E8DB).opacity(0.92)).frame(width: 30, height: 15)
                .overlay(Capsule().stroke(trim.opacity(0.6), lineWidth: 0.65))
            DiamondMark().fill(trim).frame(width: 5, height: 7)
            Circle().fill(trim.opacity(0.65)).frame(width: 2, height: 2).offset(x: -8)
            Circle().fill(trim.opacity(0.65)).frame(width: 2, height: 2).offset(x: 8)
            Capsule().fill(.white.opacity(0.65)).frame(width: 37, height: 1.5)
                .blur(radius: 0.7).rotationEffect(.degrees(-7)).offset(x: -20, y: -13)
        case .seaGlass:
            Capsule().stroke(trim.opacity(0.48), lineWidth: 1).padding(4)
            Capsule().stroke(Color(hex: 0x2F655E).opacity(0.30), lineWidth: 0.55).padding(6)
            WaveMark().stroke(Color(hex: 0xF0F7E9).opacity(0.90),
                              style: StrokeStyle(lineWidth: 0.9, lineCap: .round))
                .frame(width: 25, height: 8).offset(y: 2)
            Ellipse().fill(.white.opacity(0.27)).frame(width: 36, height: 4)
                .blur(radius: 1.6).offset(x: -24, y: -12)
        case .lavender:
            HStack {
                enamelWings
                Spacer(minLength: 28)
                enamelWings
            }.padding(.horizontal, 13)
            Capsule().fill(Color(hex: 0x655476)).frame(width: 29, height: 12)
                .overlay(Capsule().stroke(trim.opacity(0.9), lineWidth: 0.7))
            HStack(spacing: 3) {
                Circle().fill(trim.opacity(0.7)).frame(width: 2, height: 2)
                DiamondMark().fill(trim).frame(width: 4, height: 5)
                Circle().fill(trim.opacity(0.7)).frame(width: 2, height: 2)
            }
            Capsule().fill(.white.opacity(0.6)).frame(width: 46, height: 1.5)
                .blur(radius: 0.8).offset(y: -14)
        case .racingGreen:
            HStack(spacing: 3) {
                Rectangle().fill(Color(hex: 0xEAE3C9)).frame(width: 5)
                Rectangle().fill(Color(hex: 0xEAE3C9).opacity(0.85)).frame(width: 2)
            }.frame(height: 44).offset(x: -33)
            RoundedRectangle(cornerRadius: 5).fill(Color(hex: 0x142F23)).frame(width: 28, height: 16)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(trim.opacity(0.9), lineWidth: 0.85))
                .offset(x: 8)
            Text("IR").font(.custom("Courier-Bold", size: 7)).tracking(1.2)
                .foregroundColor(Color(hex: 0xEBE3C6)).offset(x: 8)
            GripRibs(color: trim).offset(x: 43)
        case .copper:
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(trim.opacity(0.78), lineWidth: 1.1).padding(3.5)
            RoundedRectangle(cornerRadius: 4).fill(Color(hex: 0x36534B)).frame(width: 38, height: 17)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: 0xEDC39B), lineWidth: 0.7))
            Text("INKRAIL").font(.custom("Courier", size: 5)).tracking(0.65)
                .foregroundColor(Color(hex: 0xF1CEAC))
            ScrewHead(color: Color(hex: 0xDDB088)).offset(x: -44)
            ScrewHead(color: Color(hex: 0xDDB088)).offset(x: 44)
        case .wildflower:
            WildflowerEnamel().clipShape(shell)
            Capsule().fill(Color(hex: 0x536B50)).frame(width: 25, height: 12)
                .overlay(Capsule().stroke(Color(hex: 0xF7EDCD).opacity(0.9), lineWidth: 0.7))
            DiamondMark().fill(Color(hex: 0xE7D8A9)).frame(width: 4, height: 5)
            Capsule().stroke(Color(hex: 0x8D976C).opacity(0.38), lineWidth: 0.6).padding(3.5)
        }
    }

    private var statusDot: some View {
        Circle().fill(lampOn ? Color(hex: 0xC8D5A2) : Color(hex: 0x91A681))
            .frame(width: 3, height: 3)
    }

    private var decoLines: some View {
        VStack(spacing: 3) {
            ForEach(0..<3) { _ in
                Rectangle().fill(trim.opacity(0.65)).frame(height: 0.7)
                    .shadow(color: .white.opacity(0.4), radius: 0, y: 1)
            }
        }.frame(width: 17)
    }

    private var enamelWings: some View {
        VStack(spacing: 2.5) {
            Capsule().fill(trim.opacity(0.65)).frame(width: 15, height: 0.8)
            Capsule().fill(trim.opacity(0.65)).frame(width: 20, height: 0.8)
            Capsule().fill(trim.opacity(0.65)).frame(width: 15, height: 0.8)
        }
    }
}

private struct WaveMark: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            for row in 0..<2 {
                let y = rect.minY + CGFloat(row) * rect.height * 0.55 + 1
                path.move(to: CGPoint(x: rect.minX, y: y))
                path.addCurve(to: CGPoint(x: rect.maxX, y: y),
                              control1: CGPoint(x: rect.width * 0.35, y: y - 5),
                              control2: CGPoint(x: rect.width * 0.65, y: y + 5))
            }
        }
    }
}

/// Tiny hand-drawn enamel sprigs. Their coordinates and colours are fixed;
/// there is no random-on-render decoration or external flower artwork.
private struct WildflowerEnamel: View {
    var body: some View {
        Canvas { context, _ in
            let blooms: [(CGFloat, CGFloat, CGFloat, UInt32)] = [
                (14, 16, 3.0, 0xB97670), (27, 32, 2.6, 0xBC9752),
                (36, 12, 2.7, 0x8D7B9D), (76, 30, 3.0, 0xB97670),
                (87, 12, 2.6, 0xBC9752), (98, 26, 2.6, 0x8D7B9D)
            ]
            for (x, y, radius, color) in blooms {
                var stem = Path()
                stem.move(to: CGPoint(x: x - 3, y: min(42, y + 12)))
                stem.addQuadCurve(to: CGPoint(x: x, y: y),
                                  control: CGPoint(x: x + 3, y: y + 6))
                context.stroke(stem, with: .color(Color(hex: 0x607856).opacity(0.85)), lineWidth: 0.6)
                let leaf = CGRect(x: x - 5, y: y + 5, width: 5, height: 2)
                context.fill(Path(ellipseIn: leaf), with: .color(Color(hex: 0x798A5E)))
                for petal in 0..<5 {
                    let angle = Double(petal) * .pi * 2 / 5
                    let rect = CGRect(x: x + CGFloat(cos(angle)) * radius - 1.7,
                                      y: y + CGFloat(sin(angle)) * radius - 2,
                                      width: 3.4, height: 4)
                    context.fill(Path(ellipseIn: rect), with: .color(Color(hex: color)))
                }
                context.fill(Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)),
                             with: .color(Color(hex: 0xEEE1AE)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct DiamondMark: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.closeSubpath()
        }
    }
}

private struct GripRibs: View {
    var color: Color
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3) { _ in
                Capsule().fill(color.opacity(0.5)).frame(width: 0.8, height: 18)
                    .shadow(color: .white.opacity(0.45), radius: 0, x: 1)
            }
        }
    }
}

private struct ScrewHead: View {
    var color: Color
    var body: some View {
        Circle().fill(color)
            .overlay(Circle().stroke(.black.opacity(0.45), lineWidth: 0.5))
            .overlay(Rectangle().fill(.black.opacity(0.45)).frame(width: 3, height: 0.6).rotationEffect(.degrees(-25)))
            .frame(width: 4.5, height: 4.5)
    }
}

/// Deterministic patterns stay fixed on the housing while typing. No timer,
/// random-per-frame noise, TimelineView or continuously running animation.
private struct MechanismTextureView: View {
    var texture: MechanismTexture

    var body: some View {
        Canvas { context, size in
            switch texture {
            case .none:
                break
            case .brushed:
                for index in 0..<30 {
                    let y = CGFloat(index) * size.height / 30 + 0.3
                    var line = Path()
                    line.move(to: CGPoint(x: 0, y: y))
                    line.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(line, with: .color(index.isMultiple(of: 3) ? .white.opacity(0.16) : .black.opacity(0.07)), lineWidth: 0.35)
                }
            case .wood:
                for row in 0..<13 {
                    var grain = Path()
                    for point in 0...32 {
                        let x = CGFloat(point) * size.width / 32
                        let wave = sin(Double(point) * 0.22 + Double(row) * 0.72) * 1.8
                        let y = CGFloat(row) * size.height / 12 + CGFloat(wave)
                        if point == 0 { grain.move(to: CGPoint(x: x, y: y)) }
                        else { grain.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    context.stroke(grain, with: .color(row.isMultiple(of: 3) ? .white.opacity(0.10) : .black.opacity(0.23)), lineWidth: row.isMultiple(of: 2) ? 0.55 : 0.3)
                }
            case .ceramic, .matte:
                let opacity = texture == .ceramic ? 0.075 : 0.045
                for index in 0..<95 {
                    let x = CGFloat((index * 47 + 13) % 109) / 109 * size.width
                    let y = CGFloat((index * 23 + 7) % 43) / 43 * size.height
                    let dot = CGRect(x: x, y: y, width: 0.7, height: 0.7)
                    context.fill(Path(ellipseIn: dot), with: .color(texture == .ceramic ? .black.opacity(opacity) : .white.opacity(opacity)))
                }
            case .mineral:
                for vein in 0..<7 {
                    var line = Path()
                    let x = CGFloat(vein) * 23 - 18
                    line.move(to: CGPoint(x: x, y: -3))
                    line.addCurve(to: CGPoint(x: x + 37, y: size.height + 3),
                                  control1: CGPoint(x: x + 32, y: size.height * 0.30),
                                  control2: CGPoint(x: x + 4, y: size.height * 0.68))
                    context.stroke(line, with: .color(.white.opacity(vein.isMultiple(of: 2) ? 0.25 : 0.12)),
                                   lineWidth: vein.isMultiple(of: 2) ? 1.4 : 0.7)
                }
            case .frosted:
                for index in 0..<150 {
                    let x = CGFloat((index * 37 + 11) % 113) / 113 * size.width
                    let y = CGFloat((index * 19 + 5) % 47) / 47 * size.height
                    let diameter = index.isMultiple(of: 4) ? 1.2 : 0.5
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: diameter, height: diameter)),
                                 with: .color(.white.opacity(0.14)))
                }
            case .enamel:
                var sheen = Path()
                sheen.move(to: CGPoint(x: 6, y: 0))
                sheen.addLine(to: CGPoint(x: 30, y: 0))
                sheen.addLine(to: CGPoint(x: 65, y: size.height))
                sheen.addLine(to: CGPoint(x: 48, y: size.height))
                sheen.closeSubpath()
                context.fill(sheen, with: .linearGradient(Gradient(colors: [.white.opacity(0.16), .clear]),
                                                        startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            case .hammered:
                for index in 0..<54 {
                    let x = CGFloat((index * 31 + 7) % 107)
                    let y = CGFloat((index * 17 + 3) % 43)
                    let diameter: CGFloat = 2.4 + CGFloat(index % 3) * 0.6
                    let mark = Path(ellipseIn: CGRect(x: x, y: y, width: diameter, height: diameter * 0.65))
                    context.fill(mark, with: .color(.black.opacity(0.055)))
                    context.stroke(mark, with: .color(.white.opacity(0.13)), lineWidth: 0.4)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
