import SwiftUI
import InkrailCore

/// All these layers are noninteractive material rendering. The lamp source,
/// desk pool and paper highlight share DeskSceneLayout's window coordinates.
@MainActor
struct DeskLightPools: View {
    var scene: DeskSceneLayout
    var appearance: LampAppearance

    var body: some View {
        if scene.isVisible {
            appearance.lightColor
                .opacity(0.82 * appearance.intensity)
                .mask {
                    ZStack(alignment: .topLeading) {
                        pool(right: false)
                        pool(right: true)
                    }
                    .frame(width: scene.windowWidth, height: scene.windowHeight)
                }
                // Brightens the actual material, revealing its grain instead
                // of placing an opaque, milky cone over the desktop texture.
                .blendMode(.colorDodge)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private func pool(right: Bool) -> some View {
        if let mask = Self.masks[scene.linen] {
            let scale = scene.lampScale
            Image(decorative: mask, scale: 1)
                .resizable()
                .interpolation(.high)
                .frame(width: 640 * scale, height: 440 * scale)
                .scaleEffect(x: right ? -1 : 1, y: 1)
                .position(x: (right ? scene.rightEmitterX : scene.leftEmitterX) + (right ? -70 : 70) * scale,
                          y: scene.emitterY + 180 * scale)
        }
    }

    private static let masks: [Bool: CGImage] = {
        var masks: [Bool: CGImage] = [:]
        for linen in [false, true] {
        let width = 640, height = 440
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let value = DeskSceneLayout.desktopLight(x: Double(x) + 0.5 - 250,
                                                         y: Double(y) + 0.5 - 40, linen: linen)
                let alpha = UInt8((value * 255).rounded())
                let offset = (y * width + x) * 4
                for channel in 0..<4 { pixels[offset + channel] = alpha }
            }
        }
        masks[linen] = deskMaskImage(pixels, width: width, height: height)
        }
        return masks
    }()
}

/// Shadows belong to the tabletop plane. The warm source lights the inward
/// side of each foot; its opposite side has a soft cast shadow plus a much
/// tighter contact shadow. The paper's existing shadow is drawn above this.
struct DeskLampShadows: View {
    var scene: DeskSceneLayout

    var body: some View {
        Canvas { context, _ in
            guard scene.isVisible else { return }
            for right in [false, true] {
                let x = right ? scene.windowWidth - scene.leftFootX : scene.leftFootX
                let s = scene.lampScale
                let sign = right ? 1.0 : -1.0
                var shadow = context
                shadow.translateBy(x: x, y: scene.footY)
                shadow.scaleBy(x: s, y: s)
                var cast = shadow
                cast.addFilter(.blur(radius: 8))
                cast.fill(Path(ellipseIn: CGRect(x: -45 + sign * 24, y: -2, width: 90, height: 29)),
                          with: .color(.black.opacity(0.50)))
                var column = Path()
                column.move(to: CGPoint(x: 0, y: -6))
                column.addQuadCurve(to: CGPoint(x: sign * 94, y: 16),
                                    control: CGPoint(x: sign * 55, y: -7))
                cast.stroke(column, with: .color(.black.opacity(0.20)), lineWidth: 10)
                var contact = shadow
                contact.addFilter(.blur(radius: 1.8))
                contact.fill(Path(ellipseIn: CGRect(x: -37, y: -9, width: 74, height: 22)),
                             with: .color(.black.opacity(0.62)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Composite the decorative surface and its light in one graphics context.
/// This avoids SwiftUI isolating the blend behind a mask/layer boundary. Only
/// paper decoration is rasterized: NSTextView remains a separate native view.
@MainActor
struct DeskLitPaperMaterial: View {
    var scene: DeskSceneLayout
    var size: CGSize
    var preferences: WritingPreferences
    var feedOffset: CGFloat = 0

    var body: some View {
        Canvas { context, _ in
            guard let paper = context.resolveSymbol(id: 0),
                  let mask = DeskPaperLightMask.image(scene: scene, height: Int(ceil(size.height))) else { return }
            let lamp = LampAppearance(warmth: preferences.lampWarmth, intensity: preferences.lampIntensity)
            context.drawLayer { material in
                material.draw(paper, at: .zero, anchor: .topLeading)
                var light = material
                light.blendMode = .screen
                light.opacity = 0.90 * lamp.intensity
                light.addFilter(.colorMultiply(lamp.lightColor))
                // Draw the raster alpha field directly, not a resolved view
                // symbol whose own layer can isolate the blend operation.
                let image = Image(decorative: mask, scale: 1)
                light.draw(image, in: CGRect(x: 0, y: 0, width: DeskSceneLayout.paperReach, height: size.height))
                light.translateBy(x: size.width, y: 0)
                light.scaleBy(x: -1, y: 1)
                light.draw(image, in: CGRect(x: 0, y: 0, width: DeskSceneLayout.paperReach, height: size.height))
            }
        } symbols: {
            PaperSurface(preferences: preferences, feedOffset: feedOffset)
                .frame(width: size.width, height: size.height).tag(0)
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The same field removes part of the night veil, so the light reveals the
/// existing paper fibre/curvature instead of painting a flat luminous stripe.
@MainActor
struct DeskPaperLightMask: View {
    var scene: DeskSceneLayout
    var size: CGSize

    private struct Key: Hashable { var scene: DeskSceneLayout; var height: Int }
    private static var cache: [Key: CGImage] = [:]

    var body: some View {
        if scene.isVisible, let mask = Self.image(scene: scene, height: Int(ceil(size.height))) {
            HStack(spacing: 0) {
                Image(decorative: mask, scale: 1).resizable().interpolation(.high)
                    .frame(width: DeskSceneLayout.paperReach)
                Spacer(minLength: 0)
                Image(decorative: mask, scale: 1).resizable().interpolation(.high)
                    .scaleEffect(x: -1, y: 1)
                    .frame(width: DeskSceneLayout.paperReach)
            }
            .frame(width: size.width, height: size.height)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    static func image(scene: DeskSceneLayout, height: Int) -> CGImage? {
        guard height > 0 else { return nil }
        let key = Key(scene: scene, height: height)
        if let image = cache[key] { return image }
        let width = Int(DeskSceneLayout.paperReach)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let value = scene.paperLight(distance: Double(x) + 0.5,
                                             sceneY: scene.paperTop + Double(y) + 0.5)
                let alpha = UInt8((value * 255).rounded())
                let offset = (y * width + x) * 4
                for channel in 0..<4 { pixels[offset + channel] = alpha }
            }
        }
        guard let image = deskMaskImage(pixels, width: width, height: height) else { return nil }
        if cache.count >= 6 { cache.removeAll(keepingCapacity: true) }
        cache[key] = image
        return image
    }
}

private func deskMaskImage(_ pixels: [UInt8], width: Int, height: Int) -> CGImage? {
    guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
    return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                   bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                   provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
}
