import SwiftUI
import InkrailCore

struct PaperOutline: Shape {
    var curved = true
    var feedOffset: CGFloat = 0

    static func curlDepth(width: CGFloat) -> CGFloat { min(104, max(56, width * 0.13)) }

    // Long, tangent shoulders turn into the face of the sheet instead of a
    // rounded-rectangle corner. A very shallow crown softens the upper lip.
    func upperEdge(in rect: CGRect) -> Path {
        let depth = Self.curlDepth(width: rect.width)
        let inset = min(64, max(22, rect.width * 0.09))
        let lift = min(depth, max(0, feedOffset.isFinite ? feedOffset : 0))
        let top = rect.minY - lift
        let left = rect.minX
        let right = rect.maxX
        var edge = Path()
        edge.move(to: CGPoint(x: left, y: top + depth))
        edge.addCurve(to: CGPoint(x: left + inset, y: top + 4),
                      control1: CGPoint(x: left, y: top + depth * 0.48),
                      control2: CGPoint(x: left + inset * 0.42, y: top + 4))
        edge.addCurve(to: CGPoint(x: right - inset, y: top + 4),
                      control1: CGPoint(x: left + rect.width * 0.34, y: top - 1),
                      control2: CGPoint(x: left + rect.width * 0.66, y: top - 1))
        edge.addCurve(to: CGPoint(x: right, y: top + depth),
                      control1: CGPoint(x: right - inset * 0.42, y: top + 4),
                      control2: CGPoint(x: right, y: top + depth * 0.48))
        return edge
    }

    func path(in rect: CGRect) -> Path {
        guard curved else { return Path(roundedRect: rect, cornerRadius: 3) }
        var path = upperEdge(in: rect)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct PaperLip: Shape {
    var feedOffset: CGFloat
    func path(in rect: CGRect) -> Path { PaperOutline(feedOffset: feedOffset).upperEdge(in: rect) }
}

@MainActor
struct PaperSurface: View {
    var preferences: WritingPreferences
    var feedOffset: CGFloat = 0

    private var feed: CGFloat { max(0, feedOffset.isFinite ? feedOffset : 0) }
    private var rolling: Bool { preferences.paperMotion == .roll }

    var body: some View {
        ZStack {
            preferences.paper.color
            LinearGradient(stops: [
                .init(color: .white.opacity(0.05), location: 0),
                .init(color: .white.opacity(0.22), location: 0.43),
                .init(color: Color(hex: 0x918766).opacity(0.08), location: 1)
            ], startPoint: .topLeading, endPoint: .bottomTrailing)
            GeometryReader { geometry in
                // 1280 is a whole number of both the original 640pt grain
                // and the new 256pt tiles. Keep a bounded surface even for a
                // long letter; the native scroll view owns its exact motion.
                if rolling {
                    RolledPaperTexture(preferences: preferences, feed: feed)
                } else {
                    PaperTextureLayer(preferences: preferences)
                        .frame(width: geometry.size.width, height: geometry.size.height + 1280)
                        .offset(y: -feed.truncatingRemainder(dividingBy: 1280))
                }
            }.clipped()
            if preferences.paperEmbossing != .none && feed < (rolling ? 310 : 130) {
                GeometryReader { geometry in
                    let projection = PaperRollProjection(width: geometry.size.width,
                        viewportHeight: PaperFeedLayout.editorHeight(paperHeight: geometry.size.height,
                            position: preferences.effectivePaperStartPosition, motion: .roll))
                    let markY = 77 - feed
                    let markX = max(60, geometry.size.width - 77)
                    PaperEmbossingMark(style: preferences.paperEmbossing, depth: preferences.embossingDepth)
                        .frame(width: 96, height: 96)
                        .scaleEffect(x: rolling ? projection.horizontalScale(at: markY) : 1,
                                     y: rolling ? max(0.02, (projection.projectY(markY + 48)
                                         - projection.projectY(markY - 48)) / 96) : 1)
                        .position(x: rolling ? projection.projectX(markX, at: markY) : markX,
                                  y: rolling ? projection.projectY(markY) : markY)
                }
            }
            if preferences.curvedPaper {
                HStack(spacing: 0) {
                    LinearGradient(colors: [.black.opacity(0.12), .white.opacity(0.07), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 28)
                    Spacer(minLength: 0)
                    LinearGradient(colors: [.clear, .white.opacity(0.05), .black.opacity(0.11)], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 28)
                }
                GeometryReader { geometry in
                    let depth = PaperOutline.curlDepth(width: geometry.size.width)
                    LinearGradient(stops: [
                        .init(color: Color(hex: 0x756D54).opacity(0.18), location: 0),
                        .init(color: .white.opacity(0.28), location: 0.12),
                        .init(color: .white.opacity(0.12), location: 0.38),
                        .init(color: .clear, location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                    .frame(height: depth * 1.65)
                    .offset(y: rolling ? 0 : -feed)
                    PaperLip(feedOffset: rolling ? 0 : feed)
                        .stroke(.white.opacity(0.46), lineWidth: 1)
                        .offset(y: 0.7)
                        .blur(radius: 0.5)
                }
            }
        }
        .clipShape(PaperOutline(curved: preferences.curvedPaper, feedOffset: rolling ? 0 : feed))
        .clipped()
        .animation(nil, value: feedOffset)
        .accessibilityHidden(true)
    }
}

/// Project decorative grain through the same curve as the native ink. Canvas
/// resolves one texture symbol, then draws thin bands from it. Only this
/// decoration is rasterized; editable text stays in the AppKit text system.
@MainActor
private struct RolledPaperTexture: View {
    var preferences: WritingPreferences
    var feed: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let projection = PaperRollProjection(width: size.width,
                viewportHeight: PaperFeedLayout.editorHeight(paperHeight: size.height,
                    position: preferences.effectivePaperStartPosition, motion: .roll))
            let extra = projection.bendHeight
            let phase = (feed + 1280 - extra).truncatingRemainder(dividingBy: 1280)
            Canvas { context, canvasSize in
                guard let texture = context.resolveSymbol(id: 0) else { return }
                // Below the curved portion a single draw is sufficient.
                for y in stride(from: 0.0, to: extra, by: 2) {
                    let bottom = min(extra, y + 2)
                    let sourceTop = projection.unprojectY(y)
                    let sourceBottom = projection.unprojectY(bottom)
                    let scaleY = (bottom - y) / max(0.001, sourceBottom - sourceTop)
                    let scaleX = projection.horizontalScale(at: (sourceTop + sourceBottom) / 2)
                    var band = context
                    band.clip(to: Path(CGRect(x: 0, y: y, width: canvasSize.width, height: bottom - y)))
                    band.translateBy(x: canvasSize.width * (1 - scaleX) / 2,
                                     y: y - (sourceTop + extra) * scaleY)
                    band.scaleBy(x: scaleX, y: scaleY)
                    band.draw(texture, at: .zero, anchor: .topLeading)
                }
                var flat = context
                flat.clip(to: Path(CGRect(x: 0, y: extra, width: canvasSize.width,
                                         height: max(0, canvasSize.height - extra))))
                flat.draw(texture, at: CGPoint(x: 0, y: -extra), anchor: .topLeading)
            } symbols: {
                PaperTextureLayer(preferences: preferences)
                    .frame(width: size.width, height: size.height + 1280 + extra * 2)
                    .offset(y: -phase)
                    .frame(width: size.width, height: size.height + extra * 2, alignment: .top)
                    .clipped().tag(0)
            }
        }
    }
}

// A continuous, original light field rather than a blurred triangle. Generate
// its alpha once; caret motion only moves the cached image, and sliders never
// regenerate pixels. The same field drives paper tint and darkness removal.
private struct LampFootprint: View {
    var headX: CGFloat
    var railY: CGFloat

    private static let mask: CGImage? = {
        let width = LampBeamProfile.width
        let height = LampBeamProfile.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let alpha = UInt8((LampBeamProfile.illumination(
                    x: Double(x) + 0.5 - Double(width) / 2,
                    rise: LampBeamProfile.sourceY - Double(y) - 0.5
                ) * 255).rounded())
                let offset = (y * width + x) * 4
                // Premultiplied white, so the image can be used as an alpha mask.
                for channel in 0..<4 { pixels[offset + channel] = alpha }
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8,
                       bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true,
                       intent: .defaultIntent)
    }()

    var body: some View {
        if let mask = Self.mask {
            Image(decorative: mask, scale: 1)
                .interpolation(.high)
                .frame(width: CGFloat(LampBeamProfile.width), height: CGFloat(LampBeamProfile.height))
                .position(x: headX,
                          y: railY + LampBeamProfile.emitterOffsetY
                            - LampBeamProfile.sourceY + Double(LampBeamProfile.height) / 2)
        }
    }
}

extension LampAppearance {
    var lightColor: Color {
        let rgb = lightRGB
        return Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
    }
}

/// Tint ONLY the paper, beneath the native editor. Multiplication preserves
/// grain and doesn't paint a milky coloured overlay over the ink. Keep this
/// compositing group off the AppKit editor: it contains SwiftUI surfaces only.
@MainActor
struct LitPaperSurface: View {
    var size: CGSize
    var headX: CGFloat
    var railY: CGFloat
    var preferences: WritingPreferences
    var feedOffset: CGFloat = 0
    var deskScene: DeskSceneLayout? = nil

    var body: some View {
        let lamp = LampAppearance(warmth: preferences.lampWarmth, intensity: preferences.lampIntensity)
        ZStack {
            if let scene = deskScene, scene.isVisible {
                DeskLitPaperMaterial(scene: scene, size: size, preferences: preferences,
                                     feedOffset: feedOffset)
            } else {
                PaperSurface(preferences: preferences, feedOffset: feedOffset)
            }
            if preferences.nightMode {
                lamp.lightColor
                    .opacity(lamp.paperTintOpacity)
                    .frame(width: size.width, height: size.height)
                    .mask(LampFootprint(headX: headX, railY: railY))
                    .blendMode(.multiply)
            }
        }
        .frame(width: size.width, height: size.height)
        .compositingGroup()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

@MainActor
struct NightLighting: View {
    var size: CGSize
    var headX: CGFloat
    var railY: CGFloat
    var preferences: WritingPreferences
    var deskScene: DeskSceneLayout? = nil

    var body: some View {
        let lamp = LampAppearance(warmth: preferences.lampWarmth, intensity: preferences.lampIntensity)
        ZStack {
            Color.black.opacity(0.80)
            LampFootprint(headX: headX, railY: railY)
                .opacity(lamp.intensity)
                .blendMode(.destinationOut)
            if let scene = deskScene, scene.isVisible {
                DeskPaperLightMask(scene: scene, size: size)
                    .opacity(lamp.intensity * 0.92)
                    .blendMode(.destinationOut)
            }
        }
        .compositingGroup()
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The settings sheet covers the desk. Reuse the actual paper, mask and lamp
/// here so a warmth adjustment can be inspected without dismissing the sheet.
@MainActor
struct NightLampPreview: View {
    var preferences: WritingPreferences

    var body: some View {
        GeometryReader { geometry in
            let headX = geometry.size.width * 0.55
            let railY = geometry.size.height - 42
            ZStack(alignment: .topLeading) {
                LitPaperSurface(size: geometry.size, headX: headX, railY: railY, preferences: preferences)
                Text("A little light.\nA quieter desk.")
                    .font(preferences.writingFont.font(size: 14))
                    .lineSpacing(6)
                    .foregroundColor(preferences.ribbon.color)
                    .position(x: headX, y: 61)
                if preferences.nightMode {
                    NightLighting(size: geometry.size, headX: headX, railY: railY, preferences: preferences)
                }
                RailView(finish: preferences.effectiveRailFinish, style: preferences.mechanismStyle)
                    .frame(width: geometry.size.width + 4)
                    .position(x: geometry.size.width / 2, y: railY)
                    .brightness(preferences.nightMode ? -0.22 : 0)
                CapsuleView(finish: preferences.capsule, style: preferences.mechanismStyle, lampOn: preferences.nightMode,
                            lampWarmth: preferences.lampWarmth, lampIntensity: preferences.lampIntensity)
                    .position(x: headX, y: railY)
            }
        }
        .frame(height: 178)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(DeskPalette.ink.opacity(0.15), lineWidth: 0.5))
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Night lamp preview")
        .accessibilityValue(preferences.nightMode ? "Warmth \(Int(preferences.lampWarmth * 100)) percent" : "Lamp off")
    }
}

/// Original, deliberately restrained vector botanicals. No Platen artwork.
@MainActor
struct MarginGarden: View {
    var body: some View {
        Canvas { context, size in
            for side in 0..<2 {
                let edge: CGFloat = side == 0 ? 13 : size.width - 13
                let sign: CGFloat = side == 0 ? 1 : -1
                var stem = Path()
                stem.move(to: CGPoint(x: edge, y: 32))
                for i in 1...28 {
                    let x = edge + sin(CGFloat(i) * 0.8) * 7
                    let y = CGFloat(i) * size.height / 28
                    stem.addLine(to: CGPoint(x: x, y: y))
                }
                context.stroke(stem, with: .color(Color(hex: 0x65724B).opacity(0.65)), lineWidth: 1.1)
                for i in 1...25 {
                    let y = CGFloat(i) * (size.height - 30) / 26 + 13
                    let x = edge + sin(CGFloat(i) * 0.8) * 7
                    let length: CGFloat = 12 + CGFloat(i % 4) * 2
                    let direction = i % 2 == 0 ? sign : -sign * 0.55
                    var leaf = Path()
                    leaf.move(to: CGPoint(x: x, y: y))
                    leaf.addQuadCurve(to: CGPoint(x: x + direction * length, y: y - 17), control: CGPoint(x: x + direction * (length + 7), y: y - 1))
                    leaf.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: x + direction * 2, y: y - 19))
                    context.fill(leaf, with: .linearGradient(Gradient(colors: [Color(hex: 0x7C8B55), Color(hex: 0x3C5940)]), startPoint: CGPoint(x: x, y: y - 18), endPoint: CGPoint(x: x + length, y: y)))
                    if i % 6 == 2 {
                        let flowerX = x + sign * 15
                        for petal in 0..<5 {
                            let angle = CGFloat(petal) * .pi * 2 / 5
                            let rect = CGRect(x: flowerX + cos(angle) * 4 - 3, y: y + sin(angle) * 4 - 3, width: 6, height: 7)
                            context.fill(Path(ellipseIn: rect), with: .color(Color(hex: side == 0 ? 0xA99BB2 : 0xDFD9BD)))
                        }
                        context.fill(Path(ellipseIn: CGRect(x: flowerX - 1.5, y: y - 1.5, width: 3, height: 3)), with: .color(Color(hex: 0xB8A064)))
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
