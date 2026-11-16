import AppKit
import SwiftUI
import InkrailCore

// Supply the same original grain without SwiftPM's generated bundle accessor.
extension Bundle {
    static let module = Bundle(url: URL(fileURLWithPath: CommandLine.arguments[1])
        .appendingPathComponent("FixtureResources.bundle"))!
}

@MainActor
private struct LampScene: View {
    var preferences: WritingPreferences
    var headX: CGFloat = 360
    var railY: CGFloat = 550
    let size = CGSize(width: 720, height: 660)

    var body: some View {
        ZStack(alignment: .topLeading) {
            LitPaperSurface(size: size, headX: headX, railY: railY, preferences: preferences)
            Text(railY < 250 ? "Dear June," : "Dear June,\n\nA little room for wonder.\nSlow down.\nFind your next sentence.")
                .font(.custom("Courier", size: 20))
                .lineSpacing(5)
                .foregroundColor(preferences.ribbon.color)
                .padding(.leading, 76)
                .padding(.top, railY < 250 ? railY - 80 : railY - 198)
            if preferences.nightMode {
                NightLighting(size: size, headX: headX, railY: railY, preferences: preferences)
            }
            RailView(finish: preferences.effectiveRailFinish, style: preferences.mechanismStyle)
                .frame(width: size.width + 4)
                .position(x: size.width / 2, y: railY)
                .brightness(preferences.nightMode ? -0.22 : 0)
            CapsuleView(finish: preferences.capsule, style: preferences.mechanismStyle,
                        lampOn: preferences.nightMode, lampWarmth: preferences.lampWarmth,
                        lampIntensity: preferences.lampIntensity)
                .position(x: headX, y: railY)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(PaperOutline())
        .background(DeskPalette.background)
    }
}

@main
@MainActor
enum NightLampCheck {
    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        let count = try checkLampProfile()
        var p = WritingPreferences()
        p.nightMode = true
        p.mechanismStyle = .midnight
        var renders = 0
        for warmth in [0.0, 0.65, 1.0] {
            p.lampWarmth = warmth
            try render(LampScene(preferences: p), name: "warmth-\(Int(warmth * 100))", to: output)
            renders += 1
        }
        p.lampWarmth = 0.65
        p.lampIntensity = 0.25
        try render(LampScene(preferences: p), name: "intensity-25", to: output)
        p.lampIntensity = 1
        try render(LampScene(preferences: p), name: "intensity-100", to: output)
        renders += 2
        p.lampIntensity = 0.82
        for (name, x, y) in [("top-left", 64.0, 150.0), ("bottom-right", 656.0, 550.0)] {
            try render(LampScene(preferences: p, headX: x, railY: y), name: name, to: output)
            renders += 1
        }
        for paper in PaperKind.allCases {
            p.paper = paper
            try render(NightLampPreview(preferences: p).frame(width: 340),
                       name: "preview-\(paper.rawValue)", to: output)
            renders += 1
        }
        p.paper = .ivory
        let stylePreview = VStack(spacing: 12) {
            ForEach(MechanismStyle.allCases, id: \.self) { style in
                HStack(spacing: 12) {
                    ForEach([0.0, 0.65, 1.0], id: \.self) { warmth in
                        NightLampPreview(preferences: preferences(style: style, warmth: warmth))
                            .frame(width: 340)
                    }
                }
            }
        }.padding(12).background(DeskPalette.background)
        try render(stylePreview, name: "styles-and-warmth", to: output)
        p.nightMode = false
        try render(LampScene(preferences: p), name: "lamp-off", to: output)
        renders += 2
        try checkRenderedLight(in: output)
        print("Passed \(count) lamp profile check groups and 4 rendered-light checks; wrote \(renders) production SwiftUI component renders to \(output.path).")
        print("These are isolated renders, not running-app screenshots or native text-entry tests.")
    }

    static func checkRenderedLight(in output: URL) throws {
        func sample(_ name: String, x: Int, y: Int) throws -> NSColor {
            let data = try Data(contentsOf: output.appendingPathComponent(name + ".png"))
            guard let bitmap = NSBitmapImageRep(data: data),
                  let color = bitmap.colorAt(x: x * 2, y: y * 2)?.usingColorSpace(.deviceRGB) else {
                throw NSError(domain: "NightLampCheck", code: 2)
            }
            return color
        }
        func require(_ condition: Bool, _ message: String) throws {
            if !condition {
                throw NSError(domain: "NightLampCheck", code: 3,
                              userInfo: [NSLocalizedDescriptionKey: message])
            }
            print("PASS: \(message)")
        }
        // Sample bare paper beside the stem, clear of fixture text and housing.
        let cool = try sample("warmth-0", x: 375, y: 516)
        let warm = try sample("warmth-100", x: 375, y: 516)
        try require(cool.blueComponent - warm.blueComponent > 0.15
                    && cool.greenComponent - warm.greenComponent > 0.05,
                    "Rendered paper preserves a visible cool-to-amber warmth range")
        for (x, y) in [(375, 516), (400, 380)] {
            let dim = try sample("intensity-25", x: x, y: y)
            let bright = try sample("intensity-100", x: x, y: y)
            try require(bright.redComponent - dim.redComponent > 0.05,
                        "Intensity brightens \(y == 516 ? "near" : "far") paper illumination")
        }
        let belowDim = try sample("intensity-25", x: 400, y: 610)
        let belowBright = try sample("intensity-100", x: 400, y: 610)
        try require(abs(belowDim.redComponent - belowBright.redComponent) < 0.005,
                    "Rendered lamp leaves paper below the housing dark")
    }

    static func preferences(style: MechanismStyle, warmth: Double) -> WritingPreferences {
        var p = WritingPreferences()
        p.nightMode = true
        p.mechanismStyle = style
        p.lampWarmth = warmth
        return p
    }

    static func render<V: View>(_ view: V, name: String, to output: URL) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw NSError(domain: "NightLampCheck", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Could not render \(name)"])
        }
        try png.write(to: output.appendingPathComponent(name + ".png"))
    }
}
