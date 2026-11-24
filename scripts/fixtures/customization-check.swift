import AppKit
import SwiftUI
import ImageIO
import InkrailCore

// The production resource lookup remains unchanged; only the generated SwiftPM
// accessor is supplied by this isolated fixture.
extension Bundle {
    static let module = Bundle(url: URL(fileURLWithPath: CommandLine.arguments[1])
        .appendingPathComponent("FixtureResources.bundle"))!
}

private struct CustomizationCheckFailure: Error, CustomStringConvertible {
    let description: String
}

@MainActor
private struct PaperGallery: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(PaperTexture.allCases) { texture in
                HStack(spacing: 14) {
                    ForEach(PaperEmbossing.allCases) { embossing in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(texture.label) · \(embossing.label)")
                                .font(.system(size: 12)).foregroundColor(.white.opacity(0.8))
                            PaperCustomizationPreview(preferences: preferences(texture, embossing))
                                .frame(width: 320)
                        }
                    }
                }
            }
        }.padding(20).background(DeskPalette.background)
    }

    private func preferences(_ texture: PaperTexture, _ embossing: PaperEmbossing) -> WritingPreferences {
        var p = WritingPreferences()
        p.paperTexture = texture
        p.paperEmbossing = embossing
        p.textureStrength = 0.8
        p.embossingDepth = 0.75
        p.writingFont = .americanTypewriter
        p.fontSize = 16
        return p
    }
}

@MainActor
private struct FontGallery: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(WritingFont.allCases) { font in
                VStack(alignment: .leading, spacing: 8) {
                    Text(font.label).font(.system(size: 13)).foregroundColor(.white.opacity(0.8))
                    PaperCustomizationPreview(preferences: preferences(font)).frame(width: 560)
                }
            }
        }.padding(20).background(DeskPalette.background)
    }

    private func preferences(_ font: WritingFont) -> WritingPreferences {
        var p = WritingPreferences()
        p.paperTexture = .cotton
        p.paperEmbossing = .botanical
        p.writingFont = font
        p.embossingDepth = 0.7
        p.textureStrength = 0.75
        return p
    }
}

@MainActor
private struct FedLampScene: View {
    var preferences: WritingPreferences

    var body: some View {
        let size = CGSize(width: 560, height: 420)
        let headX: CGFloat = 330
        let railY: CGFloat = 330
        ZStack(alignment: .topLeading) {
            LitPaperSurface(size: size, headX: headX, railY: railY,
                            preferences: preferences, feedOffset: 180)
            Text("The paper rises.\nThe next line waits.")
                .font(preferences.writingFont.font(size: 20))
                .foregroundColor(preferences.ribbon.color)
                .lineSpacing(7)
                .padding(.leading, 76).padding(.top, 220)
            NightLighting(size: size, headX: headX, railY: railY, preferences: preferences, feedOffset: 180)
            RailView(finish: preferences.effectiveRailFinish, style: preferences.mechanismStyle)
                .frame(width: size.width + 4).position(x: size.width / 2, y: railY)
                .brightness(-0.22)
            CapsuleView(finish: preferences.capsule, style: preferences.mechanismStyle,
                        lampOn: true, lampWarmth: preferences.lampWarmth, lampIntensity: preferences.lampIntensity)
                .position(x: headX, y: railY)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(PaperOutline(curved: preferences.curvedPaper, feedOffset: 180))
    }
}

@main
@MainActor
enum CustomizationCheck {
    static var renders = 0
    static var groups = 0
    static let output = URL(fileURLWithPath: CommandLine.arguments[1])

    static func main() throws {
        if CommandLine.arguments.contains("--settings-only") {
            // Keep a stalled native drawing call from blocking the check runner.
            DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
                fputs("Native settings capture timed out.\n", stderr)
                exit(1)
            }
            let app = NSApplication.shared
            app.setActivationPolicy(.prohibited)
            var p = WritingPreferences()
            p.paperTexture = .cotton
            p.paperEmbossing = .botanical
            p.embossingDepth = 0.7
            p.writingFont = .americanTypewriter
            p.typewriterSound = .soft
            p.nightMode = true
            for section in StudioSection.allCases {
                try renderSettings(preferences: p, section: section)
            }
            p.nightMode = false
            p.deskFinish = .walnut
            p.deskAccent = .brassLamps
            try renderSettings(preferences: p, section: .desk, suffix: "-walnut-study")
            p.deskFinish = .oak
            p.deskAccent = .linenLamps
            try renderSettings(preferences: p, section: .desk, suffix: "-warm-oak")
            p.deskFinish = .leather
            p.deskAccent = .brassLamps
            try renderSettings(preferences: p, section: .desk, suffix: "-leather-study")
            print("Rendered \(StudioSection.allCases.count + 3) isolated native settings views; numerical checks not run in this mode.")
            return
        }
        try checkLegacyPreferences()
        try checkNewPreferenceValues()
        try checkFontResolution()
        try checkPaperResource()
        try checkPaperRendering()
        try checkDefaultEmbossingVisibility()
        try checkPaperFeedRendering()
        try checkPaperRollRendering()
        var preferences = WritingPreferences()
        preferences.paperMotion = .sheet
        preferences.paperTexture = .cotton
        preferences.paperEmbossing = .botanical
        preferences.embossingDepth = 0.7
        preferences.writingFont = .americanTypewriter
        preferences.typewriterSound = .soft
        preferences.nightMode = true
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        for section in StudioSection.allCases {
            try renderSettings(preferences: preferences, section: section)
        }
        preferences.paperMotion = .roll
        try renderSettings(preferences: preferences, section: .paper, suffix: "-roll")
        try render(PaperGallery(), name: "paper-and-embossing-gallery")
        try render(FontGallery(), name: "font-gallery")
        print("Passed \(groups) customization check groups; wrote \(renders) production SwiftUI component renders to \(output.path).")
        print("These are isolated renders, not running-app screenshots, control interactions, native typing or audio tests.")
    }

    static func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw CustomizationCheckFailure(description: message) }
    }

    static func passed(_ message: String) {
        groups += 1
        print("PASS: \(message)")
    }

    static func decode(_ json: String) throws -> WritingPreferences {
        try JSONDecoder().decode(WritingPreferences.self, from: Data(json.utf8))
    }

    static func checkLegacyPreferences() throws {
        // Literal v0.1.4 record, not a round-trip produced by the new encoder.
        let legacy = """
        {"mechanismStyle":"walnut","matchRailToStyle":false,
         "paper":"cream","paperStartPosition":"bottom","capsule":"cobalt",
         "rail":"brass","ribbon":"oxblood","fontSize":24,"inkStrength":0.73,
         "wornInk":false,"wideMargins":false,"curvedPaper":false,"garden":true,
         "soundEnabled":false,"soundVolume":0.17,"nightMode":true,
         "lampIntensity":0.49,"lampWarmth":0.91}
        """
        var expected = WritingPreferences()
        expected.mechanismStyle = .walnut
        expected.matchRailToStyle = false
        expected.paper = .cream
        expected.paperStartPosition = .bottom
        expected.capsule = .cobalt
        expected.rail = .brass
        expected.ribbon = .oxblood
        expected.fontSize = 24
        expected.inkStrength = 0.73
        expected.wornInk = false
        expected.wideMargins = false
        expected.curvedPaper = false
        expected.garden = true
        expected.soundEnabled = false
        expected.soundVolume = 0.17
        expected.nightMode = true
        expected.lampIntensity = 0.49
        expected.lampWarmth = 0.91
        let migrated = try decode(legacy)
        try require(migrated == expected, "Legacy values changed during customization migration")
        try require(migrated.paperTexture == .classic && migrated.textureStrength == 0.70
                    && migrated.paperEmbossing == .makerMark && migrated.embossingDepth == 0.70
                    && migrated.writingFont == .courier && migrated.typewriterSound == .classic,
                    "Missing surface, typeface and sound settings should use their defaults")
        passed("Literal legacy preferences preserve every saved field and apply defaults for missing fields")
    }

    static func checkNewPreferenceValues() throws {
        let defaults = WritingPreferences()
        try require(defaults.paperMotion == .roll && defaults.paperStartPosition == .bottom
                    && defaults.paperTexture == .classic && defaults.textureStrength == 0.70
                    && defaults.paperEmbossing == .makerMark && defaults.embossingDepth == 0.70,
                    "Incorrect default paper layout or surface")
        try require(defaults.mechanismStyle == .walnut && defaults.matchRailToStyle
                    && defaults.effectiveRailFinish == .brass && defaults.soundVolume == 0.55
                    && !defaults.nightMode && defaults.lampIntensity == 0.85 && defaults.lampWarmth == 0.55,
                    "Incorrect default mechanism, volume or lighting")
        passed("Fresh paper, mechanism, sound and light settings")

        for texture in PaperTexture.allCases {
            for embossing in PaperEmbossing.allCases {
                for font in WritingFont.allCases {
                    for sound in TypewriterSound.allCases {
                        var p = WritingPreferences()
                        p.paperTexture = texture
                        p.paperEmbossing = embossing
                        p.writingFont = font
                        p.typewriterSound = sound
                        p.textureStrength = 0.71
                        p.embossingDepth = 0.32
                        p.lampWarmth = 0.19
                        let bytes = try JSONEncoder().encode(p)
                        let decoded = try JSONDecoder().decode(WritingPreferences.self, from: bytes)
                        try require(decoded == p, "Customization combination failed to round-trip")
                    }
                }
            }
        }
        let future = try decode("""
        {"paperTexture":"future","paperEmbossing":"future","writingFont":"future",
         "typewriterSound":"future","textureStrength":0.77,"embossingDepth":0.27,
         "paper":"white","lampWarmth":0.12,"soundVolume":0}
        """)
        try require(future.paperTexture == .classic && future.paperEmbossing == .makerMark
                    && future.writingFont == .courier && future.typewriterSound == .classic
                    && future.textureStrength == 0.77 && future.embossingDepth == 0.27
                    && future.paper == .white && future.lampWarmth == 0.12 && future.soundVolume == 0,
                    "Unknown options reset unrelated settings")
        let clamped = try decode("{\"textureStrength\":-1,\"embossingDepth\":2}")
        try require(clamped.textureStrength == 0 && clamped.embossingDepth == 1, "Detail amounts are not clamped")
        for value in [Double.nan, .infinity, -.infinity] {
            var p = WritingPreferences()
            p.textureStrength = value
            p.embossingDepth = value
            p.clamp()
            try require(p.textureStrength == 0.70 && p.embossingDepth == 0.70, "Nonfinite detail values lack defaults")
        }
        let combinationCount = PaperTexture.allCases.count * PaperEmbossing.allCases.count
            * WritingFont.allCases.count * TypewriterSound.allCases.count
        passed("\(combinationCount) customization combinations persist; unknown options and invalid amounts remain safe")
    }

    static func checkFontResolution() throws {
        for font in WritingFont.allCases {
            let resolved = font.nsFont(size: 20)
            try require(resolved.pointSize == 20 && resolved.ascender > 0 && resolved.descender < 0,
                        "Invalid local font metrics for \(font.label)")
            print("FONT: \(font.label) → \(resolved.fontName), \(resolved.pointSize) pt")
        }
        passed("All \(WritingFont.allCases.count) typeface choices resolve to local AppKit fonts at the requested size")
    }

    static func checkPaperResource() throws {
        guard let url = InkrailResources.bundle.url(forResource: "paper-grain", withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CustomizationCheckFailure(description: "Original paper-grain resource is missing or cannot be decoded")
        }
        try require(image.width == 640 && image.height == 640, "Original paper-grain resource has unexpected dimensions")
        let bitmap = NSBitmapImageRep(cgImage: image)
        var visible = 0
        for y in stride(from: 0, to: image.height, by: 8) {
            for x in stride(from: 0, to: image.width, by: 8) {
                if let color = bitmap.colorAt(x: x, y: y), color.alphaComponent > 0.01 { visible += 1 }
            }
        }
        try require(visible > 100, "Original paper grain is fully transparent or lacks surface detail")
        passed("The original 640-point grain resolves from the bundle and contains visible detail")
    }

    static func checkPaperRendering() throws {
        var p = WritingPreferences()
        p.paperMotion = .sheet
        p.paperTexture = .smooth
        p.paperEmbossing = .none
        let plain = try renderPaper(p, name: "surface-smooth")
        var activeTextures: [PaperTexture: CGImage] = [:]
        for texture in PaperTexture.allCases {
            p.paperTexture = texture
            p.textureStrength = 0
            let zero = try renderPaper(p, name: "texture-\(texture.rawValue)-zero")
            try require(try difference(plain, zero).changed == 0,
                        "Texture detail at zero still changes the paper: \(texture.label)")
            p.textureStrength = 1
            activeTextures[texture] = try renderPaper(p, name: "texture-\(texture.rawValue)-full")
        }
        passed("Every texture at zero detail matches the smooth paper")
        for texture in [PaperTexture.classic, .laid, .cotton] {
            guard let image = activeTextures[texture] else { throw CustomizationCheckFailure(description: "Missing texture render") }
            try require(try difference(plain, image).changed > 100,
                        "Selected texture produces no visible surface detail: \(texture.label)")
        }
        if let laid = activeTextures[.laid], let cotton = activeTextures[.cotton] {
            try require(try difference(laid, cotton).changed > 100, "Laid and Cotton render the same surface")
        }
        passed("Classic, Laid and Cotton visibly change the paper, and the new textures are distinct")

        p.paperTexture = .smooth
        var reliefImages: [PaperEmbossing: CGImage] = [:]
        for mark in PaperEmbossing.allCases where mark != .none {
            p.paperEmbossing = mark
            p.embossingDepth = 0
            let zero = try renderPaper(p, name: "emboss-\(mark.rawValue)-zero")
            try require(try difference(plain, zero).changed == 0,
                        "Zero relief leaves a visible embossing: \(mark.label)")
            p.embossingDepth = 0.75
            reliefImages[mark] = try renderPaper(p, name: "emboss-\(mark.rawValue)-full")
        }
        passed("Every embossed mark disappears completely at zero relief")
        // Points within a generous upper-right stamp box; image scale is 2x.
        let stampBounds = CGRect(x: 425 * 2, y: 15 * 2, width: 120 * 2, height: 130 * 2)
        for (mark, image) in reliefImages {
            let delta = try difference(plain, image, region: stampBounds)
            try require(delta.changed > 40 && delta.outside == 0,
                        "\(mark.label) must alter only the upper-right stamp area (inside \(delta.changed), outside \(delta.outside))")
        }
        passed("All embossed marks create local relief without altering the rest of the sheet")
    }

    static func checkDefaultEmbossingVisibility() throws {
        let size = CGSize(width: 560, height: 420)
        // Pixel coordinates for the upper-right corner in the 2x render.
        let stampBounds = CGRect(x: 425 * 2, y: 15 * 2, width: 120 * 2, height: 130 * 2)
        var preferences = WritingPreferences()
        preferences.paperMotion = .sheet
        for night in [false, true] {
            preferences.nightMode = night
            let appearance = night ? "night" : "day"
            func sheet(_ mark: PaperEmbossing) throws -> CGImage {
                var paper = preferences
                paper.paperEmbossing = mark
                let view = ZStack {
                    LitPaperSurface(size: size, headX: 76, railY: 332, preferences: paper)
                    if night {
                        NightLighting(size: size, headX: 76, railY: 332, preferences: paper)
                    }
                }.frame(width: size.width, height: size.height)
                return try render(view, name: "emboss-default-\(appearance)-\(mark.rawValue)")
            }
            let plain = try sheet(.none)
            for mark in PaperEmbossing.allCases where mark != .none {
                // Sample one pixel per point. A few antialiased edges are insufficient
                // to make the motif legible at the normal desk zoom.
                let stamp = try sheet(mark)
                let delta = try difference(plain, stamp, region: stampBounds, minimumDelta: (night ? 9.0 : 24.0) / 255)
                try require(delta.changed > 120, "\(mark.label) relief is too faint at the default depth in \(appearance) light")
                try require(delta.outside == 0, "\(mark.label) changed the surrounding paper in \(appearance) light")
            }
        }
        passed("All four embossings have visible relief on textured paper by day and by night at the default depth")
    }

    static func checkPaperFeedRendering() throws {
        var p = WritingPreferences()
        p.paperMotion = .sheet
        p.paperTexture = .cotton
        p.textureStrength = 0.8
        p.embossingDepth = 0.75
        var marked: [Int: CGImage] = [:]
        var unmarked: [Int: CGImage] = [:]
        for feed in [0, 20, 180] {
            p.paperEmbossing = .botanical
            marked[feed] = try renderPaper(p, feedOffset: CGFloat(feed), name: "paper-feed-\(feed)")
            p.paperEmbossing = .none
            unmarked[feed] = try renderPaper(p, feedOffset: CGFloat(feed), name: "paper-feed-\(feed)-unmarked")
        }
        guard let mark0 = marked[0], let mark20 = marked[20], let mark180 = marked[180],
              let plain0 = unmarked[0], let plain20 = unmarked[20], let plain180 = unmarked[180] else {
            throw CustomizationCheckFailure(description: "Missing paper-feed renders")
        }
        let first = try reliefCentroid(mark0, plain0)
        let shifted = try reliefCentroid(mark20, plain20)
        try require(abs((first - shifted) - 20) < 1.25,
                    "Embossing did not rise with the paper: centroid shift \(first - shifted) pt")
        passed("Embossed relief rises 20 points with the paper instead of remaining fixed")
        try require(try difference(mark180, plain180).changed == 0,
                    "Embossing remains visible after its paper region has rolled away")
        passed("The embossed mark leaves the visible paper after sufficient feed")

        p.paperEmbossing = .botanical
        let fedEdge = try renderPaper(p, feedOffset: PaperOutline.curlDepth(width: 560), name: "paper-feed-full-curl")
        let before = NSBitmapImageRep(cgImage: mark0)
        let after = NSBitmapImageRep(cgImage: fedEdge)
        for x in [2, 557] {
            guard let firstCorner = before.colorAt(x: x * 2, y: 2 * 2),
                  let fedCorner = after.colorAt(x: x * 2, y: 2 * 2) else {
                throw CustomizationCheckFailure(description: "Could not sample paper corners")
            }
            try require(firstCorner.alphaComponent < 0.01 && fedCorner.alphaComponent > 0.99,
                        "The curved top corner remains pinned after the paper rises")
        }
        passed("Both curved upper shoulders feed out after their full curl depth")
        p.nightMode = true
        p.writingFont = .americanTypewriter
        try render(FedLampScene(preferences: p), name: "paper-feed-180-night")
    }

    static func checkPaperRollRendering() throws {
        var p = WritingPreferences()
        p.paperMotion = .roll
        p.paperTexture = .smooth
        p.paperEmbossing = .none
        let initial = try renderPaper(p, name: "roll-smooth-start")
        let fed = try renderPaper(p, feedOffset: 180, name: "roll-smooth-fed")
        try require(try difference(initial, fed).changed == 0,
                    "Rolling a smooth sheet moves its fixed outline or shading")
        let a = NSBitmapImageRep(cgImage: initial)
        let b = NSBitmapImageRep(cgImage: fed)
        for point in [(2, 2), (40, 20), (560, 20), (1118, 2)] {
            try require(abs((a.colorAt(x: point.0, y: point.1)?.alphaComponent ?? -1)
                            - (b.colorAt(x: point.0, y: point.1)?.alphaComponent ?? -2)) < 0.02,
                        "Paper roll upper-edge clipping changed during feed")
        }
        passed("Paper roll keeps its curved silhouette and top lighting fixed during feed")
        p.paperTexture = .laid
        let grain0 = try renderPaper(p, name: "roll-grain-start")
        let grain20 = try renderPaper(p, feedOffset: 20, name: "roll-grain-fed")
        let repeated = try renderPaper(p, feedOffset: 20, name: "roll-grain-repeat")
        try require(try difference(grain0, grain20).changed > 100,
                    "Rolled texture does not move with native feed")
        try require(try difference(grain20, repeated).changed == 0,
                    "Rolled texture changes on an identical render")
        passed("Rolled grain moves with the paper and remains deterministic")
        p.paperEmbossing = .botanical
        p.embossingDepth = 0.8
        _ = try renderPaper(p, name: "roll-emboss-start")
        _ = try renderPaper(p, feedOffset: 90, name: "roll-emboss-lip")
    }

    /// Measure the output difference from an otherwise identical unmarked
    /// sheet, isolating the relief from the texture and moving paper outline.
    static func reliefCentroid(_ marked: CGImage, _ plain: CGImage) throws -> Double {
        let a = NSBitmapImageRep(cgImage: marked)
        let b = NSBitmapImageRep(cgImage: plain)
        var weightedY = 0.0
        var total = 0.0
        for y in 0..<(145 * 2) {
            for x in (425 * 2)..<(545 * 2) {
                guard let c = a.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      let d = b.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    throw CustomizationCheckFailure(description: "Could not sample relief")
                }
                let weight = Double(abs(c.redComponent - d.redComponent)
                                    + abs(c.greenComponent - d.greenComponent)
                                    + abs(c.blueComponent - d.blueComponent))
                weightedY += Double(y) * weight
                total += weight
            }
        }
        try require(total > 1, "No visible embossed relief found")
        return weightedY / total / 2
    }

    static func renderPaper(_ p: WritingPreferences, feedOffset: CGFloat = 0, name: String) throws -> CGImage {
        try render(PaperSurface(preferences: p, feedOffset: feedOffset).frame(width: 560, height: 280), name: name)
    }

    /// ImageRenderer cannot draw AppKit-backed Pickers/ScrollViews. Host the real
    /// settings in an isolated, unshown NSWindow and cache its native view tree.
    /// This is an offscreen component render, never a system screen capture.
    static func renderSettings(preferences: WritingPreferences, section: StudioSection, suffix: String = "") throws {
        let size = CGSize(width: 680, height: 740)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let view = StudioSettingsView(preferences: .constant(preferences), previewSound: {},
                                      stopSoundPreview: {}, close: {}, section: section)
        let host = NSHostingView(rootView: view)
        host.sizingOptions = []
        host.frame = CGRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        window.contentView = host
        let deadline = Date(timeIntervalSinceNow: 0.25)
        repeat {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        } while Date() < deadline
        host.layoutSubtreeIfNeeded()
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                           pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                           isPlanar: false, colorSpaceName: .deviceRGB,
                                           bytesPerRow: 0, bitsPerPixel: 0) else {
            throw CustomizationCheckFailure(description: "Could not allocate the native settings render")
        }
        bitmap.size = size
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CustomizationCheckFailure(description: "Could not encode \(section.rawValue) settings render")
        }
        try png.write(to: output.appendingPathComponent("settings-\(section.rawValue.lowercased())\(suffix).png"))
        renders += 1
    }

    /// Compare sampled output pixels, not a duplicate of the texture algorithm.
    static func difference(_ lhs: CGImage, _ rhs: CGImage, region: CGRect? = nil,
                           minimumDelta: CGFloat = 2.1 / 255) throws -> (changed: Int, outside: Int) {
        try require(lhs.width == rhs.width && lhs.height == rhs.height, "Render dimensions changed")
        let a = NSBitmapImageRep(cgImage: lhs)
        let b = NSBitmapImageRep(cgImage: rhs)
        var changed = 0
        var outside = 0
        for y in stride(from: 0, to: lhs.height, by: 2) {
            for x in stride(from: 0, to: lhs.width, by: 2) {
                guard let c = a.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      let d = b.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    throw CustomizationCheckFailure(description: "Could not read render pixels")
                }
                // Independent native renders can differ by a couple of 8-bit
                // levels from display dithering. Transparent antialiased edges
                // also amplify unpremultiplication error; compare opaque paper.
                guard c.alphaComponent > 0.99 && d.alphaComponent > 0.99 else { continue }
                let delta = max(max(abs(c.redComponent - d.redComponent),
                                    abs(c.greenComponent - d.greenComponent)),
                                max(abs(c.blueComponent - d.blueComponent),
                                    abs(c.alphaComponent - d.alphaComponent)))
                if delta > minimumDelta {
                    if let region, !region.contains(CGPoint(x: x, y: y)) { outside += 1 }
                    else { changed += 1 }
                }
            }
        }
        return (changed, outside)
    }

    @discardableResult
    static func render<V: View>(_ view: V, name: String) throws -> CGImage {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw CustomizationCheckFailure(description: "Could not render \(name)")
        }
        try png.write(to: output.appendingPathComponent(name + ".png"))
        renders += 1
        return image
    }
}
