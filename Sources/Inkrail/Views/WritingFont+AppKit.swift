import AppKit
import SwiftUI
import InkrailCore

@MainActor
extension WritingFont {
    /// Resolve only locally installed faces. No font files are bundled,
    /// registered or downloaded. A missing optional face uses a system fallback.
    func nsFont(size: Double) -> NSFont {
        let pointSize = size.isFinite ? max(1, size) : 20
        let names: [String]
        switch self {
        case .courier: names = ["Courier"]
        case .americanTypewriter: names = ["AmericanTypewriter"]
        case .menlo: names = ["Menlo-Regular"]
        case .georgia: names = ["Georgia"]
        case .courierNew: names = ["CourierNewPSMT", "Courier New", "Courier"]
        case .typewriterLight: names = ["AmericanTypewriter-Light", "AmericanTypewriter"]
        case .typewriterCondensed: names = ["AmericanTypewriter-Condensed", "AmericanTypewriter"]
        case .monaco: names = ["Monaco", "Menlo-Regular"]
        }
        for name in names {
            if let installed = NSFont(name: name, size: pointSize) { return installed }
        }
        if self == .georgia {
            let system = NSFont.systemFont(ofSize: pointSize, weight: .regular)
            if let descriptor = system.fontDescriptor.withDesign(.serif),
               let serif = NSFont(descriptor: descriptor, size: pointSize) {
                return serif
            }
            return system
        }
        return NSFont(name: "Courier", size: pointSize)
            ?? NSFont.monospacedSystemFont(ofSize: pointSize, weight: .regular)
    }

    /// Use the exact resolved AppKit face for SwiftUI previews and placeholders.
    func font(size: Double) -> Font {
        Font(nsFont(size: size))
    }
}
