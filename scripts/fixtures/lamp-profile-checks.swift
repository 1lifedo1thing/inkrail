import Foundation
import InkrailCore

private struct LampProfileCheckFailure: Error, CustomStringConvertible {
    let description: String
}

/// Numerically checks the production core types without depending on XCTest.
/// The returned count is the number of named check groups, not pixel samples.
func checkLampProfile() throws -> Int {
    var count = 0
    func require(_ condition: @autoclosure () -> Bool, _ detail: String) throws {
        guard condition() else { throw LampProfileCheckFailure(description: detail) }
    }
    func close(_ lhs: Double, _ rhs: Double, tolerance: Double = 1e-12) -> Bool {
        abs(lhs - rhs) <= tolerance
    }
    func check(_ label: String, _ body: () throws -> Void) throws {
        try body()
        count += 1
        print("PASS: \(label)")
    }

    try check("Lamp is strongest at the slit") {
        let source = LampBeamProfile.illumination(x: 0, rise: 0)
        try require(close(source, 1), "Slit brightness must be 1")
        for (x, rise) in [(0.0, 35.0), (25.0, 0.0), (0.0, -5.0)] {
            try require(source > LampBeamProfile.illumination(x: x, rise: rise),
                        "An off-source sample is as bright as the slit: x=\(x), rise=\(rise)")
        }
    }

    try check("Centre illumination fades upward") {
        var previous = LampBeamProfile.illumination(x: 0, rise: 0)
        for rise in stride(from: 4.0, through: LampBeamProfile.sourceY, by: 4) {
            let value = LampBeamProfile.illumination(x: 0, rise: rise)
            try require(value <= previous, "Centre illumination increased at rise \(rise)")
            previous = value
        }
        try require(previous == 0, "Top edge must be transparent")
    }

    try check("The fan widens away from the slit") {
        func relativeShoulder(_ rise: Double) -> Double {
            LampBeamProfile.illumination(x: 60, rise: rise)
                / LampBeamProfile.illumination(x: 0, rise: rise)
        }
        let near = relativeShoulder(20)
        let middle = relativeShoulder(100)
        let far = relativeShoulder(200)
        try require(near < 0.30, "The fan is too wide beside the slit")
        try require(middle > 0.5, "The fan does not widen enough above the slit")
        try require(near < middle && middle < far, "Relative penumbra does not widen with height")
    }

    try check("Little light spills below the slit") {
        let above = LampBeamProfile.illumination(x: 0, rise: 14)
        let below = LampBeamProfile.illumination(x: 0, rise: -14)
        try require(above > 0.9, "Expected a bright field just above the slit")
        try require(below < 0.02 && below < above * 0.03, "Excessive centre spill below the slit")
        try require(LampBeamProfile.illumination(x: 30, rise: -14) < 0.01,
                    "Excessive lateral spill below the slit")
    }

    try check("Bitmap borders fade to transparent without seams") {
        let side = Double(LampBeamProfile.width) / 2
        let bottom = LampBeamProfile.sourceY - Double(LampBeamProfile.height)
        for rise in stride(from: bottom, through: LampBeamProfile.sourceY, by: 8) {
            try require(LampBeamProfile.illumination(x: -side, rise: rise) == 0
                        && LampBeamProfile.illumination(x: side, rise: rise) == 0,
                        "Nontransparent side border at rise \(rise)")
            try require(LampBeamProfile.illumination(x: side - 1, rise: rise) < 0.001,
                        "Abrupt side-border cutoff at rise \(rise)")
        }
        for x in stride(from: -side, through: side, by: 8) {
            try require(LampBeamProfile.illumination(x: x, rise: LampBeamProfile.sourceY) == 0
                        && LampBeamProfile.illumination(x: x, rise: bottom) == 0,
                        "Nontransparent top/bottom border at x \(x)")
            try require(LampBeamProfile.illumination(x: x, rise: LampBeamProfile.sourceY - 1) < 0.001
                        && LampBeamProfile.illumination(x: x, rise: bottom + 1) < 0.001,
                        "Abrupt top/bottom border cutoff at x \(x)")
        }
    }

    try check("Profile samples are symmetric, finite and bounded") {
        for rise in stride(from: -30.0, through: 450, by: 10) {
            for x in stride(from: 0.0, through: 380, by: 10) {
                let value = LampBeamProfile.illumination(x: x, rise: rise)
                try require(value.isFinite && (0...1).contains(value),
                            "Invalid illumination at x=\(x), rise=\(rise)")
                try require(close(value, LampBeamProfile.illumination(x: -x, rise: rise)),
                            "Asymmetric illumination at x=\(x), rise=\(rise)")
            }
        }
    }

    try check("Invalid and out-of-bounds coordinates emit no light") {
        for value in [Double.nan, Double.infinity, -Double.infinity] {
            try require(LampBeamProfile.illumination(x: value, rise: 70) == 0
                        && LampBeamProfile.illumination(x: 0, rise: value) == 0,
                        "Nonfinite coordinate produced illumination")
        }
        for (x, rise) in [(Double.greatestFiniteMagnitude, 0.0),
                          (0.0, Double.greatestFiniteMagnitude),
                          (0.0, -Double.greatestFiniteMagnitude)] {
            try require(LampBeamProfile.illumination(x: x, rise: rise) == 0,
                        "Out-of-bounds coordinate produced illumination")
        }
    }

    try check("Warmth retains cool-white, warm-white and amber endpoints") {
        let samples: [(Double, LampRGB)] = [
            (0, LampRGB(red: 0.92, green: 0.96, blue: 1)),
            (0.5, LampRGB(red: 1, green: 0.86, blue: 0.65)),
            (1, LampRGB(red: 1, green: 0.64, blue: 0.30))
        ]
        for (warmth, expected) in samples {
            let light = LampAppearance(warmth: warmth, intensity: 0.82).lightRGB
            try require(close(light.red, expected.red) && close(light.green, expected.green)
                        && close(light.blue, expected.blue), "Warmth endpoint changed at \(warmth)")
        }
    }

    try check("The complete warmth range progresses smoothly toward amber") {
        var previous = LampAppearance(warmth: 0, intensity: 1).lightRGB
        for step in 1...100 {
            let light = LampAppearance(warmth: Double(step) / 100, intensity: 1).lightRGB
            try require(light.red >= previous.red && light.green < previous.green && light.blue < previous.blue,
                        "Warmth progression reversed at step \(step)")
            try require([light.red, light.green, light.blue].allSatisfy { $0.isFinite && (0...1).contains($0) },
                        "Warmth produced an invalid colour at step \(step)")
            previous = light
        }
        let below = LampAppearance(warmth: 0.5 - 1e-6, intensity: 1).lightRGB
        let above = LampAppearance(warmth: 0.5 + 1e-6, intensity: 1).lightRGB
        try require(close(below.red, above.red, tolerance: 2e-6)
                    && close(below.green, above.green, tolerance: 2e-6)
                    && close(below.blue, above.blue, tolerance: 2e-6),
                    "Colour is discontinuous at the midpoint")
    }

    try check("Intensity and warmth remain independent") {
        for warmth in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let dim = LampAppearance(warmth: warmth, intensity: 0.25)
            let bright = LampAppearance(warmth: warmth, intensity: 1)
            try require(dim.lightRGB == bright.lightRGB && dim.paperTintOpacity == bright.paperTintOpacity,
                        "Intensity changed colour or paper-tint strength at warmth \(warmth)")
            try require(dim.emitterOpacity < bright.emitterOpacity
                        && dim.emitterGlowOpacity < bright.emitterGlowOpacity,
                        "Emitter did not brighten with intensity at warmth \(warmth)")
        }
        let cool = LampAppearance(warmth: 0, intensity: 0.6)
        let warm = LampAppearance(warmth: 1, intensity: 0.6)
        try require(cool.intensity == warm.intensity && cool.emitterOpacity == warm.emitterOpacity
                    && cool.emitterGlowOpacity == warm.emitterGlowOpacity,
                    "Warmth changed emitter brightness or intensity")
    }
    return count
}
