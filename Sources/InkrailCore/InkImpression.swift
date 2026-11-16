import Foundation

/// Drawing-only variation for a single, already shaped ASCII character.
/// Stable integer mixing keeps the same passage still across redraws and launches.
/// These values never change glyph advances, stored text or font attributes.
public struct InkImpression: Equatable, Sendable {
    public let opacity: Double
    public let offsetX: Double
    public let offsetY: Double
    public let spread: Double
    public let spreadOpacity: Double

    public init(characterIndex: Int, codeUnit: UInt16, buildup: Double, pointSize: Double) {
        let amount = min(1, max(0, buildup.isFinite ? buildup : 0.55))
        let size = min(144, max(1, pointSize.isFinite ? pointSize : 20)) / 20
        var hash = UInt64(truncatingIfNeeded: characterIndex) &* 0x9E3779B97F4A7C15
            &+ UInt64(codeUnit) &* 0xBF58476D1CE4E5B9
        hash = (hash ^ (hash >> 30)) &* 0xBF58476D1CE4E5B9
        hash = (hash ^ (hash >> 27)) &* 0x94D049BB133111EB
        hash ^= hash >> 31
        let pressure = Double((hash >> 12) % 101) / 100
        let baseOpacity = 0.82 + pressure * 0.18
        let strike = hash % 100
        let heavy = strike < 24
        let dry = strike >= 24 && strike < 42
        opacity = heavy ? baseOpacity + (1 - baseOpacity) * amount
            : baseOpacity - (dry ? (0.22 + pressure * 0.12) * amount : 0)
        offsetX = (Double((hash >> 24) % 7) - 3) * 0.035 * amount * size
        offsetY = (Double((hash >> 8) % 7) - 3) * (0.065 + 0.035 * amount) * size
        spread = heavy ? (0.46 + pressure * 0.24) * amount * size : 0
        spreadOpacity = heavy ? 0.30 + 0.28 * amount : 0
    }
}
