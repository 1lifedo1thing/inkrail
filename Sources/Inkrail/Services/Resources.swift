import Foundation
import ImageIO

/// Works both from `swift run` / Xcode and in the locally built .app bundle.
enum InkrailResources {
    static let bundle: Bundle = {
        if let resources = Bundle.main.resourceURL {
            let nested = resources.appendingPathComponent("Inkrail_Inkrail.bundle")
            if let bundle = Bundle(url: nested) { return bundle }
        }
        return Bundle.module
    }()

    static func artwork(_ name: String) -> CGImage? {
        guard let url = bundle.url(forResource: name, withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
