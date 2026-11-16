import Foundation

/// Original continuous light field for the capsule's upward-facing slit.
/// This describes spatial illumination only; LampAppearance owns its colour.
public enum LampBeamProfile {
    public static let width = 720
    public static let height = 440
    public static let sourceY = 416.0
    public static let emitterOffsetY = -22.0

    /// x is the horizontal distance from the emitter; rise is the distance
    /// upward from its slit. Negative rise is below the slit. Returns 0...1.
    public static func illumination(x: Double, rise: Double) -> Double {
        guard x.isFinite, rise.isFinite else { return 0 }
        let halfWidth = Double(width) / 2
        let lowerMargin = Double(height) - sourceY
        let distance = abs(x)
        guard distance < halfWidth, rise < sourceY, rise > -lowerMargin else { return 0 }

        let upward = max(0, rise)
        let spread = 22 + upward * 1.35
        let horizontal = exp(-pow(distance / spread, 2.6) * 1.2)
        let vertical = exp(-pow(upward / 135, 1.5))
        let main = horizontal * vertical

        // A faint broad bounce softens the fan's shoulders without forming
        // a hard cone outline or an equally bright circular halo.
        let bounce = 0.10 * exp(-pow(x / 160, 2) - pow((rise - 70) / 170, 2))
        let combined = 1 - (1 - main) * (1 - bounce)
        let belowSlit = exp(-pow(max(0, -rise) / 7, 2))

        // Smoothly reach transparent pixels at the cached bitmap's borders.
        // The cubic taper has zero slope at both ends, avoiding a visible seam.
        let sideFade = fade(distance, from: halfWidth - 48, to: halfWidth)
        let upperFade = fade(rise, from: sourceY - 48, to: sourceY)
        let lowerFade = fade(-rise, from: lowerMargin - 12, to: lowerMargin)
        return min(1, max(0, combined * belowSlit * sideFade * upperFade * lowerFade))
    }

    private static func fade(_ value: Double, from start: Double, to end: Double) -> Double {
        let t = min(1, max(0, (value - start) / (end - start)))
        return 1 - t * t * (3 - 2 * t)
    }
}
