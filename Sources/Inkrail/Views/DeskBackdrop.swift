import SwiftUI
import InkrailCore

/// Decorative desk only. It never participates in paper layout or text input.
/// The normal charcoal path retains the original colour and soft radial light.
@MainActor
struct DeskBackdrop: View {
    var finish: DeskFinish
    var accent: DeskAccent
    var paperWidth: CGFloat
    var focusMode: Bool
    var nightMode: Bool
    var lampWarmth: Double = 0.65
    var lampIntensity: Double = 0.82

    private var visibleFinish: DeskFinish { focusMode ? .charcoal : finish }

    var body: some View {
        GeometryReader { geometry in
        let scene = DeskSceneLayout(windowWidth: geometry.size.width, windowHeight: geometry.size.height,
                                    paperWidth: paperWidth, accent: accent,
                                    enabled: !focusMode && (accent == .brassLamps || accent == .linenLamps))
        let lamp = LampAppearance(warmth: lampWarmth, intensity: lampIntensity)
        ZStack {
            baseColour(visibleFinish).ignoresSafeArea()
            if visibleFinish != .charcoal {
                DeskMaterialTexture(finish: visibleFinish, pairedLighting: scene.isVisible)
                // Paired sources need the same ambient level at mirrored
                // positions: color-dodge lighting amplifies a diagonal shade
                // into visibly different left/right light colours.
                LinearGradient(colors: [.white.opacity(0.025), .clear, .black.opacity(0.16)],
                               startPoint: scene.isVisible ? .top : .topLeading,
                               endPoint: scene.isVisible ? .bottom : .bottomTrailing)
                if nightMode { Color.black.opacity(0.16) }
            }
            RadialGradient(colors: [Color(hex: 0x3B3C30).opacity(0.18), .clear],
                           center: .center, startRadius: 100, endRadius: 700)
                .ignoresSafeArea()
            if scene.isVisible {
                DeskLightPools(scene: scene, appearance: lamp)
            }
            if visibleFinish == .leather {
                DeskLeatherSurface(strength: 0.40)
                RadialGradient(colors: [.clear, .black.opacity(0.32)], center: .center,
                               startRadius: min(geometry.size.width, geometry.size.height) * 0.28,
                               endRadius: max(geometry.size.width, geometry.size.height) * 0.67)
            }
            if !focusMode {
                if accent == .brassLamps || accent == .linenLamps {
                    DeskLampShadows(scene: scene)
                    DeskTwinLamps(linen: accent == .linenLamps, paperWidth: paperWidth,
                                  appearance: lamp,
                                  nightMode: nightMode)
                } else if accent != .none {
                    DeskEdgeAccent(accent: accent, paperWidth: paperWidth)
                        .brightness(nightMode ? -0.14 : 0)
                }
            }
        }
        .compositingGroup()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func baseColour(_ finish: DeskFinish) -> Color {
        switch finish {
        case .charcoal: return DeskPalette.background
        case .walnut: return Color(hex: 0x3D332B)
        case .oak: return Color(hex: 0x72614B)
        case .felt: return Color(hex: 0x28332E)
        case .linen: return Color(hex: 0x38362F)
        case .leather: return Color(hex: 0x3B2B20)
        }
    }
}

/// Fixed formulas, with no random generator, external texture or animation.
/// All marks are subdued so the lighter paper remains the visual centre.
private struct DeskMaterialTexture: View {
    var finish: DeskFinish
    var pairedLighting: Bool

    var body: some View {
        Canvas { context, size in
            switch finish {
            case .charcoal, .leather: break
            case .walnut, .oak:
                drawWood(in: &context, size: size, oak: finish == .oak)
            case .felt:
                for row in stride(from: 0, through: Int(size.height) + 12, by: 12) {
                    for column in stride(from: 0, through: Int(size.width) + 15, by: 15) {
                        let phase = Double((row * 31 + column * 17) % 97)
                        let x = Double(column) + sin(phase) * 3
                        let y = Double(row) + cos(phase * 0.7) * 3
                        var fibre = Path()
                        fibre.move(to: CGPoint(x: x, y: y))
                        fibre.addLine(to: CGPoint(x: x + 2.5 + sin(phase * 0.4), y: y + cos(phase) * 2))
                        context.stroke(fibre, with: .color(Color(hex: 0xA1B09A).opacity(0.065)), lineWidth: 0.7)
                    }
                }
            case .linen:
                for x in stride(from: 0.0, through: size.width, by: 5) {
                    var warp = Path()
                    warp.move(to: CGPoint(x: x, y: 0))
                    warp.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(warp, with: .color(Color(hex: 0xBEB69E).opacity(0.045)), lineWidth: 0.7)
                }
                for y in stride(from: 0.0, through: size.height, by: 5) {
                    var weft = Path()
                    weft.move(to: CGPoint(x: 0, y: y))
                    weft.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(weft, with: .color(.black.opacity(0.075)), lineWidth: 0.8)
                }
            }
        }
    }

    private func drawWood(in context: inout GraphicsContext, size: CGSize, oak: Bool) {
        let pale = Color(hex: oak ? 0xBAAB8D : 0x9A8670)
        let dark = Color(hex: oak ? 0x40362A : 0x1E1A16)
        // Long, interrupted fibres follow one coherent grain field. Smooth
        // hash noise replaces repeating sine bands and drawn-on knot rings.
        // The coordinates belong to the desk, so resizing never reseeds them.
        for index in 0...Int(size.height / 2.1) + 24 {
            let row = Double(index) * 2.1 - 24 + sample(index, 3) * 1.25
            let lightFibre = sample(index, 19) > 0.68
            let opacity = 0.025 + sample(index, 43) * (oak ? 0.085 : 0.065)
            var fibre = Path()
            var connected = false
            for x in stride(from: 0.0, through: size.width + 8, by: 8) {
                let flow = grainFlow(x: x, y: row)
                let point = CGPoint(x: x, y: row + flow)
                let continuous = noise(x: x / 86, y: row / 3.7, seed: 71) > 0.28
                if continuous && connected { fibre.addLine(to: point) }
                else { fibre.move(to: point) }
                connected = continuous
            }
            context.stroke(fibre, with: .color((lightFibre ? pale : dark).opacity(opacity)),
                           lineWidth: 0.35 + sample(index, 83) * 0.65)
        }
        // Open pores are short, irregular marks aligned with the fibres.
        // Their very low contrast supplies material detail without striping.
        for rowIndex in -1...Int(size.height / 16) + 1 {
            for column in 0...Int(size.width / 26) {
                let index = column + rowIndex * 4099
                let x = Double(column) * 26 + sample(index, 107) * 26
                let row = Double(rowIndex) * 16 + sample(index, 131) * 16
                let length = 1.5 + pow(sample(index, 151), 3) * (oak ? 19 : 11)
                var pore = Path()
                pore.move(to: CGPoint(x: x, y: row + grainFlow(x: x, y: row)))
                pore.addLine(to: CGPoint(x: x + length, y: row + grainFlow(x: x + length, y: row)))
                context.stroke(pore, with: .color(dark.opacity(0.025 + sample(index, 173) * 0.075)),
                               style: StrokeStyle(lineWidth: 0.4 + sample(index, 191) * 0.6, lineCap: .round))
            }
        }
        // Keep this broad reflection level across paired light pools too.
        // The original diagonal remains for desks without visible lamps.
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
            Gradient(stops: [.init(color: pale.opacity(0.055), location: 0),
                             .init(color: .clear, location: 0.44),
                             .init(color: .black.opacity(0.14), location: 1)]),
            startPoint: .zero,
            endPoint: CGPoint(x: pairedLighting ? 0 : size.width * 0.35, y: size.height)))
    }

    private func grainFlow(x: Double, y: Double) -> Double {
        (noise(x: x / 390, y: y / 155, seed: 11) - 0.5) * 24
            + (noise(x: x / 150, y: y / 65, seed: 29) - 0.5) * 5
            + (noise(x: x / 45, y: y / 24, seed: 47) - 0.5) * 0.8
    }

    private func sample(_ index: Int, _ seed: Int) -> Double {
        var value = UInt64(bitPattern: Int64(index)) &* 0x9E3779B185EBCA87 &+ UInt64(seed)
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return Double((value ^ (value >> 31)) & 0xFFFF) / 65535
    }

    private func noise(x: Double, y: Double, seed: Int) -> Double {
        let column = Int(floor(x)), row = Int(floor(y))
        let dx = x - floor(x), dy = y - floor(y)
        let u = dx * dx * (3 - 2 * dx), v = dy * dy * (3 - 2 * dy)
        let a = sample(column + row * 4099, seed)
        let b = sample(column + 1 + row * 4099, seed)
        let c = sample(column + (row + 1) * 4099, seed)
        let d = sample(column + 1 + (row + 1) * 4099, seed)
        return (a + (b - a) * u) * (1 - v) + (c + (d - c) * u) * v
    }
}

/// Both fixtures share the same world coordinates as their light pools and
/// the paper-edge grazing field. The right-hand fixture faces inward.
private struct DeskTwinLamps: View {
    var linen: Bool
    var paperWidth: CGFloat
    var appearance: LampAppearance
    var nightMode: Bool

    var body: some View {
        GeometryReader { geometry in
            let layout = DeskSceneLayout(windowWidth: geometry.size.width,
                                         windowHeight: geometry.size.height,
                                         paperWidth: paperWidth,
                                         accent: linen ? .linenLamps : .brassLamps)
            if layout.isVisible {
                ZStack(alignment: .topLeading) {
                    DeskLampArtwork(linen: linen, appearance: appearance)
                        .frame(width: DeskSceneLayout.lampWidth * layout.lampScale,
                               height: DeskSceneLayout.lampHeight * layout.lampScale)
                        .offset(x: layout.leftLampX, y: layout.lampTop)
                    DeskLampArtwork(linen: linen, appearance: appearance)
                        .frame(width: DeskSceneLayout.lampWidth * layout.lampScale,
                               height: DeskSceneLayout.lampHeight * layout.lampScale)
                        .scaleEffect(x: -1, y: 1)
                        .offset(x: layout.rightLampX, y: layout.lampTop)
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            }
        }
    }
}

/// The clip excludes the paper plus its shadow. Small windows simply omit
/// objects; decorations never shrink into unreadable marks or cover writing.
private struct DeskEdgeAccent: View {
    var accent: DeskAccent
    var paperWidth: CGFloat

    var body: some View {
        Canvas { context, size in
            let gutter = max(0, (size.width - paperWidth) / 2)
            guard gutter >= 156, size.height >= 400 else { return }
            var safeArea = Path(CGRect(x: 12, y: 70, width: max(0, gutter - 46), height: max(0, size.height - 100)))
            safeArea.addRect(CGRect(x: size.width - gutter + 34, y: 70,
                                    width: max(0, gutter - 46), height: max(0, size.height - 100)))
            context.clip(to: safeArea)
            // Centre inside the usable gutter, accounting for its larger
            // paper-shadow exclusion. The whole envelope fits before showing.
            let left = min((gutter - 22) / 2, 128)
            let right = size.width - left
            switch accent {
            case .none, .brassLamps, .linenLamps: break
            case .sprig:
                context.translateBy(x: left, y: size.height * 0.66)
                context.rotate(by: .degrees(-13))
                drawSprig(in: &context)
            case .paperclip:
                context.translateBy(x: right, y: size.height * 0.34)
                context.rotate(by: .degrees(19))
                drawPaperclip(in: &context)
            case .envelope:
                context.translateBy(x: left, y: size.height * 0.73)
                context.rotate(by: .degrees(-9))
                drawEnvelope(in: &context)
            }
        }
    }

    private func drawSprig(in context: inout GraphicsContext) {
        var stem = Path()
        stem.move(to: CGPoint(x: -12, y: 84))
        stem.addCurve(to: CGPoint(x: 8, y: -83), control1: CGPoint(x: 20, y: 26), control2: CGPoint(x: -14, y: -23))
        context.drawLayer { branch in
            branch.addFilter(.shadow(color: .black.opacity(0.35), radius: 1.2, x: 1.2, y: 2))
            branch.stroke(stem, with: .linearGradient(
                Gradient(colors: [Color(hex: 0x787764), Color(hex: 0x4D4F40), Color(hex: 0x807360)]),
                startPoint: CGPoint(x: -2, y: -83), endPoint: CGPoint(x: 8, y: 84)),
                style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        }
        // Individual, slightly curled leaves; no repeated mirrored leaf icon.
        let leaves: [(Double, Double, Double, Double, Double)] = [
            (4, -67, -12, -91, 7), (0, -51, 27, -76, 11),
            (-1, -32, -29, -56, 12), (1, -14, 31, -37, 10),
            (5, 5, -27, -13, 13), (8, 27, 34, 2, 12),
            (6, 47, -24, 31, 11), (2, 63, 25, 47, 8)
        ]
        for (index, values) in leaves.enumerated() {
            let (x, y, tipX, tipY, width) = values
            let base = CGPoint(x: x, y: y), tip = CGPoint(x: tipX, y: tipY)
            let mid = CGPoint(x: (x + tipX) / 2, y: (y + tipY) / 2)
            let side = tipX < x ? -1.0 : 1.0
            var leaf = Path()
            leaf.move(to: base)
            leaf.addCurve(to: tip, control1: CGPoint(x: mid.x + side * width, y: y + 2),
                          control2: CGPoint(x: tipX + side * 3, y: tipY + 9))
            leaf.addCurve(to: base, control1: CGPoint(x: mid.x - side * width * 0.5, y: tipY - 5),
                          control2: CGPoint(x: x - side * 3, y: y - 8))
            let pale = Color(hex: index.isMultiple(of: 3) ? 0x81806A : 0x767E6D)
            let dark = Color(hex: index.isMultiple(of: 3) ? 0x464A3D : 0x3D4C41)
            context.drawLayer { blade in
                blade.addFilter(.shadow(color: .black.opacity(0.35), radius: 1.6, x: 1.4, y: 2.8))
                blade.fill(leaf, with: .linearGradient(Gradient(stops: [
                    .init(color: pale, location: 0), .init(color: pale.opacity(0.92), location: 0.42),
                    .init(color: dark, location: 1)]),
                    startPoint: CGPoint(x: mid.x - 9, y: mid.y - 8),
                    endPoint: CGPoint(x: mid.x + 8, y: mid.y + 9)))
            }
            var vein = Path()
            vein.move(to: base)
            vein.addQuadCurve(to: tip, control: CGPoint(x: mid.x + side * 2, y: mid.y + 2))
            context.stroke(vein, with: .color(Color(hex: 0xB4AD8C).opacity(0.17)), lineWidth: 0.45)
        }
    }

    private func drawPaperclip(in context: inout GraphicsContext) {
        var wire = Path()
        wire.move(to: CGPoint(x: 8, y: 18))
        wire.addLine(to: CGPoint(x: 8, y: -27))
        wire.addCurve(to: CGPoint(x: -8, y: -27), control1: CGPoint(x: 8, y: -38), control2: CGPoint(x: -8, y: -38))
        wire.addLine(to: CGPoint(x: -8, y: 30))
        wire.addCurve(to: CGPoint(x: 16, y: 30), control1: CGPoint(x: -8, y: 46), control2: CGPoint(x: 16, y: 46))
        wire.addLine(to: CGPoint(x: 16, y: -28))
        wire.addCurve(to: CGPoint(x: -16, y: -28), control1: CGPoint(x: 16, y: -50), control2: CGPoint(x: -16, y: -50))
        wire.addLine(to: CGPoint(x: -16, y: 20))
        context.drawLayer { shadow in
            shadow.addFilter(.shadow(color: .black.opacity(0.4), radius: 1.2, x: 1.2, y: 1.8))
            shadow.stroke(wire, with: .color(Color(hex: 0x48473E)), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
        }
        context.stroke(wire, with: .linearGradient(Gradient(colors: [Color(hex: 0xA49E8D), Color(hex: 0x69685E), Color(hex: 0x8F897A)]),
                                                    startPoint: CGPoint(x: -20, y: -45), endPoint: CGPoint(x: 20, y: 45)),
                       style: StrokeStyle(lineWidth: 1.65, lineCap: .round))
        var glint = context
        glint.translateBy(x: -0.35, y: -0.35)
        glint.stroke(wire, with: .linearGradient(Gradient(colors: [Color(hex: 0xDED8C7).opacity(0.45),
            .clear, Color(hex: 0xDED8C7).opacity(0.16)]),
            startPoint: CGPoint(x: -14, y: -40), endPoint: CGPoint(x: 14, y: 35)),
            style: StrokeStyle(lineWidth: 0.45, lineCap: .round))
    }

    private func drawEnvelope(in context: inout GraphicsContext) {
        let rect = CGRect(x: -47, y: -33, width: 94, height: 66)
        let paper = Path(roundedRect: rect, cornerRadius: 0.8)
        context.drawLayer { shadow in
            shadow.addFilter(.shadow(color: .black.opacity(0.28), radius: 3, x: 1, y: 3))
            shadow.fill(paper, with: .color(Color(hex: 0x70695A)))
        }
        context.fill(paper, with: .linearGradient(Gradient(colors: [Color(hex: 0xACA591), Color(hex: 0x928A77)]),
                                                  startPoint: CGPoint(x: -47, y: -33), endPoint: CGPoint(x: 47, y: 33)))
        var bottomFold = Path()
        bottomFold.move(to: CGPoint(x: -47, y: 33))
        bottomFold.addLine(to: CGPoint(x: -4, y: -1))
        bottomFold.addQuadCurve(to: CGPoint(x: 4, y: -1), control: CGPoint(x: 0, y: -4))
        bottomFold.addLine(to: CGPoint(x: 47, y: 33))
        bottomFold.closeSubpath()
        context.drawLayer { fold in
            fold.addFilter(.shadow(color: .black.opacity(0.16), radius: 0.6, x: 0, y: -0.4))
            fold.fill(bottomFold, with: .linearGradient(
                Gradient(colors: [Color(hex: 0xA69E8A), Color(hex: 0xAAA18D)]),
                startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: 33)))
        }
        var flap = Path()
        flap.move(to: CGPoint(x: -47, y: -33))
        flap.addLine(to: CGPoint(x: -5, y: 6))
        flap.addQuadCurve(to: CGPoint(x: 5, y: 6), control: CGPoint(x: 0, y: 10))
        flap.addLine(to: CGPoint(x: 47, y: -33))
        flap.closeSubpath()
        context.drawLayer { fold in
            fold.addFilter(.shadow(color: .black.opacity(0.24), radius: 0.7, x: 0, y: 0.8))
            fold.fill(flap, with: .linearGradient(
                Gradient(colors: [Color(hex: 0xB5AD99), Color(hex: 0xAAA18D), Color(hex: 0xA29883)]),
                startPoint: CGPoint(x: 0, y: -33), endPoint: CGPoint(x: 0, y: 9)))
        }
        var fibres = context
        fibres.clip(to: paper)
        for index in 0..<280 {
            let x = Double((index * 37) % 937) / 10 - 47
            let y = Double((index * 71) % 659) / 10 - 33
            fibres.fill(Path(CGRect(x: x, y: y, width: index.isMultiple(of: 3) ? 1.4 : 0.5, height: 0.35)),
                        with: .color(index.isMultiple(of: 2) ? .white.opacity(0.06) : .black.opacity(0.045)))
        }
        var edge = Path()
        edge.move(to: CGPoint(x: -46.5, y: 32))
        edge.addLine(to: CGPoint(x: -46.5, y: -32.5))
        edge.addLine(to: CGPoint(x: 46.5, y: -32.5))
        context.stroke(edge, with: .color(Color(hex: 0xD7CFB8).opacity(0.22)), lineWidth: 0.45)
    }
}

/// A small view of the same desk and real paper treatment, without editor
/// state. Paper/embossing dimensions are laid out at normal size before scaling.
@MainActor
struct DeskAppearancePreview: View {
    var preferences: WritingPreferences

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / 1080
            let sceneHeight = geometry.size.height / max(0.01, scale)
            let paperSize = CGSize(width: 720, height: max(180, sceneHeight - 42))
            let scene = DeskSceneLayout(windowWidth: 1080, windowHeight: sceneHeight, paperWidth: 720,
                                        paperTop: 26, accent: preferences.deskAccent,
                                        enabled: preferences.deskAccent == .brassLamps || preferences.deskAccent == .linenLamps)
            ZStack(alignment: .top) {
                DeskBackdrop(finish: preferences.deskFinish, accent: preferences.deskAccent,
                             paperWidth: 720, focusMode: false, nightMode: preferences.nightMode,
                             lampWarmth: preferences.lampWarmth, lampIntensity: preferences.lampIntensity)
                ZStack {
                    if scene.isVisible {
                        DeskLitPaperMaterial(scene: scene, size: paperSize, preferences: preferences)
                    } else {
                        PaperSurface(preferences: preferences)
                    }
                    if preferences.nightMode {
                        // This preview has no capsule. Reveal only the desk
                        // sources, rather than inventing an unmounted light.
                        ZStack {
                            Color.black.opacity(0.80)
                            DeskPaperLightMask(scene: scene, size: paperSize)
                                .opacity(LampAppearance(warmth: preferences.lampWarmth,
                                                        intensity: preferences.lampIntensity).intensity * 0.92)
                                .blendMode(.destinationOut)
                        }.compositingGroup()
                    }
                }
                    .compositingGroup()
                    .frame(width: paperSize.width, height: paperSize.height)
                    .clipShape(PaperOutline(curved: preferences.curvedPaper))
                    .shadow(color: .black.opacity(0.40), radius: 25, y: 14)
                    .padding(.top, 26)
            }
            .frame(width: 1080, height: sceneHeight)
            .scaleEffect(scale, anchor: .topLeading)
        }
        .frame(height: 236)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(DeskPalette.ink.opacity(0.13), lineWidth: 0.6))
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Desk finish and accent preview")
        .accessibilityValue("\(preferences.deskFinish.label), \(preferences.deskAccent.label)")
    }
}
