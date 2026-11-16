/// Display colours, not a calibrated Kelvin/black-body simulation.
/// Kept outside SwiftUI so the slider mapping can be regression-tested.
public struct LampRGB: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    fileprivate func interpolated(to other: LampRGB, fraction: Double) -> LampRGB {
        LampRGB(red: red + (other.red - red) * fraction,
                green: green + (other.green - green) * fraction,
                blue: blue + (other.blue - blue) * fraction)
    }
}

public struct LampAppearance: Equatable, Sendable {
    public let warmth: Double
    public let intensity: Double

    public init(warmth: Double, intensity: Double) {
        self.warmth = min(1, max(0, warmth.isFinite ? warmth : 0.65))
        self.intensity = min(1, max(0.25, intensity.isFinite ? intensity : 0.82))
    }

    /// Slightly cool white -> warm white -> amber. Warmth changes RGB,
    /// not merely the opacity of the same yellow colour.
    public var lightRGB: LampRGB {
        let cool = LampRGB(red: 0.92, green: 0.96, blue: 1.00)
        let middle = LampRGB(red: 1.00, green: 0.86, blue: 0.65)
        let amber = LampRGB(red: 1.00, green: 0.64, blue: 0.30)
        if warmth <= 0.5 {
            return cool.interpolated(to: middle, fraction: warmth * 2)
        }
        return middle.interpolated(to: amber, fraction: (warmth - 0.5) * 2)
    }

    /// Independent of warmth and intensity. Spatial falloff comes from the
    /// shared light field; the dimming overlay controls overall illumination.
    public var paperTintOpacity: Double { 0.78 }
    public var emitterOpacity: Double { 0.55 + intensity * 0.45 }
    public var emitterGlowOpacity: Double { 0.20 + intensity * 0.40 }
}
