import SwiftUI
import ImageIO
import InkrailCore

/// Original surface details, drawn once and tiled at a fixed physical scale.
/// Neither caret movement nor a SwiftUI render generates new noise.
@MainActor
struct PaperTextureLayer: View {
    var preferences: WritingPreferences

    var body: some View {
        switch preferences.paperTexture {
        case .classic:
            tile(PaperTextureTiles.classic, scale: 1,
                 opacity: 0.35 * preferences.textureStrength / 0.55)
        case .smooth:
            Color.clear
        case .laid:
            tile(PaperTextureTiles.laid, opacity: preferences.textureStrength)
        case .cotton:
            ZStack {
                tile(PaperTextureTiles.classic, scale: 1, opacity: preferences.textureStrength * 0.22)
                tile(PaperTextureTiles.cotton, opacity: preferences.textureStrength)
            }
        }
    }

    @ViewBuilder
    private func tile(_ image: CGImage?, scale: CGFloat = 2, opacity: Double) -> some View {
        if let image {
            Image(decorative: image, scale: scale)
                .resizable(resizingMode: .tile)
                .opacity(opacity)
        }
    }
}

private enum PaperTextureTiles {
    // Decode the standalone bundle resource directly. Name-based SwiftUI Image
    // lookup can omit loose PNG resources when rendering outside an asset
    // catalogue; the same cached pixels now serve the app and its previews.
    static let classic: CGImage? = {
        guard let url = InkrailResources.bundle.url(forResource: "paper-grain", withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }()
    static let laid = makeTile(laid: true)
    static let cotton = makeTile(laid: false)

    private static func makeTile(laid: Bool) -> CGImage? {
        let pixels = 512
        guard let context = CGContext(data: nil, width: pixels, height: pixels,
                                      bitsPerComponent: 8, bytesPerRow: pixels * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: 2, y: 2)
        context.setLineCap(.round)
        if laid {
            // Fine wire impressions with a slower, nearly invisible chain line.
            // Integer periods meet at the tile boundary without a hard seam.
            for row in 0..<80 {
                let y = CGFloat(row) * 3.2 + 1
                context.beginPath()
                context.move(to: CGPoint(x: 0, y: y))
                for step in 1...32 {
                    let x = CGFloat(step) * 8
                    let bend = sin(Double(step) * .pi / 8) * 0.17
                    context.addLine(to: CGPoint(x: x, y: y + bend))
                }
                context.setStrokeColor(CGColor(red: 0.40, green: 0.35, blue: 0.24,
                                               alpha: row % 5 == 0 ? 0.18 : 0.11))
                context.setLineWidth(0.42)
                context.strokePath()
                context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.19))
                context.fill(CGRect(x: 0, y: y + 0.6, width: 256, height: 0.35))
            }
            for column in 0..<8 {
                context.setFillColor(CGColor(red: 0.48, green: 0.43, blue: 0.30, alpha: 0.06))
                context.fill(CGRect(x: CGFloat(column) * 32 + 9, y: 0, width: 0.55, height: 256))
            }
        }

        let count = laid ? 180 : 510
        for index in 0..<count {
            // A fixed integer hash creates an original repeatable fibre pattern.
            // This is evaluated only for the two cached tiles above.
            let x = coordinate(index, salt: 17) * 256
            let y = coordinate(index, salt: 83) * 256
            let variation = coordinate(index, salt: 149)
            let alpha = laid ? 0.10 : 0.12 + variation * 0.25
            context.setFillColor(CGColor(red: 0.37, green: 0.31, blue: 0.20, alpha: alpha))
            let radius = 0.17 + variation * 0.35
            context.fillEllipse(in: CGRect(x: x, y: y, width: radius * 2, height: radius * 1.3))
            if index % 4 == 0 {
                let length = 1.8 + coordinate(index, salt: 257) * 4.5
                let angle = coordinate(index, salt: 311) * .pi
                context.beginPath()
                context.move(to: CGPoint(x: x, y: y))
                context.addQuadCurve(to: CGPoint(x: x + cos(angle) * length, y: y + sin(angle) * length),
                                     control: CGPoint(x: x + length * 0.25, y: y - length * 0.20))
                context.setStrokeColor(CGColor(red: 0.45, green: 0.40, blue: 0.27, alpha: alpha * 0.55))
                context.setLineWidth(0.27)
                context.strokePath()
            }
        }
        return context.makeImage()
    }

    private static func coordinate(_ index: Int, salt: UInt32) -> CGFloat {
        var value = UInt32(index) &* 747_796_405 &+ salt &* 2_891_336_453
        value = (value ^ (value >> 16)) &* 2_246_822_519
        value ^= value >> 13
        return CGFloat(value & 0x00FF_FFFF) / CGFloat(0x0100_0000)
    }
}

/// Pressed relief rather than a coloured stamp: the upper groove catches a
/// little shadow and its lower edge catches light. The paper remains visible.
@MainActor
struct PaperEmbossingMark: View {
    var style: PaperEmbossing
    var depth: Double

    var body: some View {
        let motif = EmbossingMotif(style: style)
        let amount = min(1, max(0, depth))
        ZStack {
            motif.stroke(Color(hex: 0x665F45).opacity(amount * 0.34),
                         style: StrokeStyle(lineWidth: 1.15, lineCap: .round, lineJoin: .round))
                .offset(x: -0.5, y: -0.65)
            motif.stroke(Color.white.opacity(amount * 0.86),
                         style: StrokeStyle(lineWidth: 1.15, lineCap: .round, lineJoin: .round))
                .offset(x: 0.5, y: 0.65)
            motif.stroke(Color(hex: 0x8B8268).opacity(amount * 0.08), lineWidth: 0.45)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct EmbossingMotif: Shape {
    var style: PaperEmbossing

    func path(in rect: CGRect) -> Path {
        var p = Path()
        switch style {
        case .none:
            break
        case .botanical:
            p.addEllipse(in: CGRect(x: 12, y: 8, width: 76, height: 84))
            p.move(to: CGPoint(x: 49, y: 78))
            p.addCurve(to: CGPoint(x: 49, y: 31), control1: CGPoint(x: 56, y: 63), control2: CGPoint(x: 43, y: 45))
            p.move(to: CGPoint(x: 51, y: 65))
            p.addQuadCurve(to: CGPoint(x: 32, y: 48), control: CGPoint(x: 41, y: 54))
            p.move(to: CGPoint(x: 49, y: 57))
            p.addQuadCurve(to: CGPoint(x: 68, y: 40), control: CGPoint(x: 58, y: 51))
            leaf(&p, from: CGPoint(x: 48, y: 69), to: CGPoint(x: 28, y: 61), bend: 7)
            leaf(&p, from: CGPoint(x: 52, y: 66), to: CGPoint(x: 70, y: 57), bend: -6)
            leaf(&p, from: CGPoint(x: 47, y: 51), to: CGPoint(x: 36, y: 35), bend: 6)
            flower(&p, center: CGPoint(x: 49, y: 29), radius: 5)
            flower(&p, center: CGPoint(x: 30, y: 46), radius: 3.5)
            flower(&p, center: CGPoint(x: 69, y: 38), radius: 4)
        case .monogram:
            p.addRoundedRect(in: CGRect(x: 14, y: 14, width: 72, height: 72), cornerSize: CGSize(width: 16, height: 16))
            p.move(to: CGPoint(x: 29, y: 32)); p.addLine(to: CGPoint(x: 44, y: 32))
            p.move(to: CGPoint(x: 36.5, y: 32)); p.addLine(to: CGPoint(x: 36.5, y: 67))
            p.move(to: CGPoint(x: 29, y: 67)); p.addLine(to: CGPoint(x: 44, y: 67))
            p.move(to: CGPoint(x: 53, y: 68)); p.addLine(to: CGPoint(x: 53, y: 32))
            p.addLine(to: CGPoint(x: 62, y: 32))
            p.addCurve(to: CGPoint(x: 62, y: 51), control1: CGPoint(x: 78, y: 32), control2: CGPoint(x: 78, y: 51))
            p.addLine(to: CGPoint(x: 53, y: 51))
            p.move(to: CGPoint(x: 61, y: 51)); p.addLine(to: CGPoint(x: 73, y: 68))
        case .sunburst:
            p.addEllipse(in: CGRect(x: 11, y: 11, width: 78, height: 78))
            p.addEllipse(in: CGRect(x: 34, y: 34, width: 32, height: 32))
            for ray in 0..<20 {
                let angle = Double(ray) * .pi / 10
                let outer = ray % 2 == 0 ? 34.0 : 28.0
                p.move(to: CGPoint(x: 50 + cos(angle) * 21, y: 50 + sin(angle) * 21))
                p.addLine(to: CGPoint(x: 50 + cos(angle) * outer, y: 50 + sin(angle) * outer))
            }
        }
        let side = min(rect.width, rect.height)
        return p.applying(CGAffineTransform(scaleX: side / 100, y: side / 100)
            .concatenating(CGAffineTransform(translationX: rect.midX - side / 2,
                                           y: rect.midY - side / 2)))
    }

    private func leaf(_ p: inout Path, from start: CGPoint, to end: CGPoint, bend: CGFloat) {
        let middle = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        p.move(to: start)
        p.addQuadCurve(to: end, control: CGPoint(x: middle.x + bend, y: middle.y - 5))
        p.addQuadCurve(to: start, control: CGPoint(x: middle.x - bend, y: middle.y + 4))
    }

    private func flower(_ p: inout Path, center: CGPoint, radius: CGFloat) {
        for petal in 0..<5 {
            let angle = Double(petal) * .pi * 2 / 5 - .pi / 2
            p.addEllipse(in: CGRect(x: center.x + cos(angle) * radius - radius * 0.60,
                                   y: center.y + sin(angle) * radius - radius * 0.65,
                                   width: radius * 1.20, height: radius * 1.30))
        }
        p.addEllipse(in: CGRect(x: center.x - 1.4, y: center.y - 1.4, width: 2.8, height: 2.8))
    }
}

/// Shared settings preview of the real paper surface and the installed font.
@MainActor
struct PaperCustomizationPreview: View {
    var preferences: WritingPreferences

    var body: some View {
        GeometryReader { geometry in
            let rollRailY: CGFloat = preferences.paperStartPosition == .top ? 128 : 158
            ZStack(alignment: .topLeading) {
                PaperSurface(preferences: preferences)
                Text(preferences.paperMotion == .roll
                     ? "The paper rises.\nThe next line waits."
                     : "The rain is soft.\nA little room to write.")
                    .font(preferences.writingFont.font(size: geometry.size.width > 500
                                                      ? preferences.fontSize : min(22, preferences.fontSize)))
                    .lineSpacing(7)
                    .foregroundColor(preferences.ribbon.color.opacity(preferences.inkStrength))
                    .frame(width: max(1, geometry.size.width - 154), alignment: .leading)
                    .padding(.leading, preferences.paperMotion == .roll ? 50 : 30)
                    .padding(.top, preferences.paperMotion == .roll ? rollRailY - 104 : 67)
                if preferences.paperMotion == .roll {
                    RailView(finish: preferences.effectiveRailFinish, style: preferences.mechanismStyle)
                        .position(x: geometry.size.width / 2, y: rollRailY)
                    CapsuleView(finish: preferences.capsule, style: preferences.mechanismStyle,
                                lampOn: preferences.nightMode, lampWarmth: preferences.lampWarmth,
                                lampIntensity: preferences.lampIntensity)
                        .position(x: geometry.size.width * 0.52, y: rollRailY)
                }
            }
        }
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(DeskPalette.ink.opacity(0.13), lineWidth: 0.6))
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Paper and type preview")
        .accessibilityValue("\(preferences.paperMotion.label), \(preferences.paper.label), \(preferences.paperTexture.label), \(preferences.paperEmbossing.label), \(preferences.writingFont.label)")
    }
}
