import AppKit

extension Bundle {
    static let module = Bundle(url: URL(fileURLWithPath: CommandLine.arguments[1])
        .appendingPathComponent("FixtureResources.bundle"))!
}

@main
@MainActor
private enum AppIconCheck {
    private static var checks = 0

    static func main() {
        do { try run() }
        catch {
            fputs("FAIL: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func run() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        let appURL = URL(fileURLWithPath: CommandLine.arguments[2])
        let app = try require(Bundle(url: appURL), "Built app bundle opens")
        let empty = try require(Bundle(url: output.appendingPathComponent("Empty.bundle")), "Empty fixture bundle opens")
        let declaredIcon = app.object(forInfoDictionaryKey: "CFBundleIconFile") as? String
        try check(declaredIcon == "AppIcon" || declaredIcon == "AppIcon.icns", "Info.plist declares the packaged icon")

        let bundled = try require(InkrailAppIcon.image(applicationBundle: app, resources: empty), "Packaged ICNS decodes without a PNG fallback")
        let pixelWidths = Set(bundled.representations.map(\.pixelsWide))
        try check([16, 32, 64, 128, 256, 512, 1024].allSatisfy(pixelWidths.contains), "ICNS has small and Retina representations")

        let fallback = try require(InkrailAppIcon.image(applicationBundle: empty, resources: .module), "SwiftPM PNG fallback decodes without an app bundle")
        try check(fallback.representations.contains { $0.pixelsWide == 1024 && $0.pixelsHigh == 1024 }, "Runtime fallback retains the original resolution")
        try check(InkrailAppIcon.image(applicationBundle: empty, resources: empty) == nil, "Missing assets do not install a generic replacement")

        let packagedResources = try require(Bundle(url: appURL.appendingPathComponent("Contents/Resources/Inkrail_Inkrail.bundle")), "Packaged resource bundle opens")
        let packagedPNG = try require(packagedResources.url(forResource: "AppIcon", withExtension: "png"), "Bundled PNG exists for runtime fallback")
        let sourcePNG = try require(Bundle.module.url(forResource: "AppIcon", withExtension: "png"), "Source PNG exists")
        try check(try Data(contentsOf: packagedPNG) == Data(contentsOf: sourcePNG), "Bundle uses the unchanged original icon artwork")

        InkrailAppIcon.install()
        let installed = try require(NSApplication.shared.applicationIconImage, "Native application icon was assigned")
        try check(matchesArtwork(installed, fallback), "NSApplication returns the original runtime icon artwork")
        print("PASS \(checks) app icon checks: packaged ICNS sizes, SwiftPM fallback, unchanged artwork, and native application icon assignment.")
    }

    private static func require<T>(_ value: T?, _ description: String) throws -> T {
        try check(value != nil, description)
        return value!
    }

    private static func matchesArtwork(_ actual: NSImage, _ expected: NSImage) -> Bool {
        guard actual.size == expected.size,
              let actualData = actual.tiffRepresentation, let expectedData = expected.tiffRepresentation,
              let a = NSBitmapImageRep(data: actualData), let b = NSBitmapImageRep(data: expectedData) else { return false }
        // AppKit can return a 2x raster for the same logical icon on a Retina display.
        var error = 0.0
        var samples = 0
        for y in stride(from: 0, to: b.pixelsHigh, by: 16) {
            for x in stride(from: 0, to: b.pixelsWide, by: 16) {
                let ax = x * a.pixelsWide / b.pixelsWide
                let ay = y * a.pixelsHigh / b.pixelsHigh
                guard let ac = a.colorAt(x: ax, y: ay)?.usingColorSpace(.sRGB),
                      let bc = b.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return false }
                let av = [ac.alphaComponent, ac.redComponent * ac.alphaComponent,
                          ac.greenComponent * ac.alphaComponent, ac.blueComponent * ac.alphaComponent]
                let bv = [bc.alphaComponent, bc.redComponent * bc.alphaComponent,
                          bc.greenComponent * bc.alphaComponent, bc.blueComponent * bc.alphaComponent]
                error += zip(av, bv).map { abs($0 - $1) }.reduce(0, +)
                samples += av.count
            }
        }
        return samples > 0 && error / Double(samples) < 0.01
    }

    private static func check(_ success: Bool, _ description: String) throws {
        guard success else { throw NSError(domain: "AppIconCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: description]) }
        checks += 1
    }
}
