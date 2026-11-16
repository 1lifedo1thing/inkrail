import AppKit
import SwiftUI
import InkrailCore

/// Original model geometry is rasterized by scripts/render-desk-lamps.sh.
/// The app only composites cached images: no live 3D engine, timers or shaders.
/// Emission is a separate depth-tested mask tinted with the shared lamp colour.
struct DeskLampArtwork: View {
    var linen: Bool
    var appearance: LampAppearance

    private var light: Color {
        let rgb = appearance.lightRGB
        return Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
    }

    var body: some View {
        ZStack {
            if let body = DeskLampImages.body(linen: linen) {
                Image(decorative: body, scale: 3)
                    .resizable()
                    .interpolation(.high)
            }
            if let emitter = DeskLampImages.emitter(linen: linen) {
                light.opacity(appearance.emitterOpacity)
                    .mask(Image(decorative: emitter, scale: 3).resizable().interpolation(.high))
                    .shadow(color: light.opacity(0.72 * appearance.intensity), radius: 2.2)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private enum DeskLampImages {
    private static let brassBody = load("desk-lamp-brass-body")
    private static let brassEmitter = load("desk-lamp-brass-emitter")
    private static let linenBody = load("desk-lamp-linen-body")
    private static let linenEmitter = load("desk-lamp-linen-emitter")

    static func body(linen: Bool) -> CGImage? { linen ? linenBody : brassBody }
    static func emitter(linen: Bool) -> CGImage? { linen ? linenEmitter : brassEmitter }

    private static func load(_ name: String) -> CGImage? {
        guard let url = InkrailResources.bundle.url(forResource: name, withExtension: "png"),
              let source = NSImage(contentsOf: url) else { return nil }
        return source.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
