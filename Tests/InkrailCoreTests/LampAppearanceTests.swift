import XCTest
@testable import InkrailCore

final class LampAppearanceTests: XCTestCase {
    func testNightWritingStartsOffWithDefaultIntensityAndWarmth() {
        let preferences = WritingPreferences()
        XCTAssertFalse(preferences.nightMode)
        XCTAssertEqual(preferences.lampIntensity, 0.85)
        XCTAssertEqual(preferences.lampWarmth, 0.55)
    }

    func testCoolEndpointIsNotYellow() {
        let light = LampAppearance(warmth: 0, intensity: 0.82).lightRGB
        XCTAssertEqual(light, LampRGB(red: 0.92, green: 0.96, blue: 1.0))
        XCTAssertGreaterThan(light.blue, light.red)
    }

    func testWarmEndpointIsAmber() {
        let light = LampAppearance(warmth: 1, intensity: 0.82).lightRGB
        XCTAssertEqual(light.red, 1, accuracy: 1e-12)
        XCTAssertEqual(light.green, 0.64, accuracy: 1e-12)
        XCTAssertEqual(light.blue, 0.30, accuracy: 1e-12)
    }

    func testMidpointIsWarmWhite() {
        let light = LampAppearance(warmth: 0.5, intensity: 0.82).lightRGB
        XCTAssertEqual(light.red, 1, accuracy: 1e-12)
        XCTAssertEqual(light.green, 0.86, accuracy: 1e-12)
        XCTAssertEqual(light.blue, 0.65, accuracy: 1e-12)
    }

    func testColourIsContinuousAtMidpoint() {
        let below = LampAppearance(warmth: 0.5 - 1e-6, intensity: 1).lightRGB
        let above = LampAppearance(warmth: 0.5 + 1e-6, intensity: 1).lightRGB
        XCTAssertEqual(below.red, above.red, accuracy: 2e-6)
        XCTAssertEqual(below.green, above.green, accuracy: 2e-6)
        XCTAssertEqual(below.blue, above.blue, accuracy: 2e-6)
    }

    func testEntireSliderRangeProgressivelyWarms() {
        var previous = LampAppearance(warmth: 0, intensity: 1).lightRGB
        for step in 1...100 {
            let current = LampAppearance(warmth: Double(step) / 100, intensity: 1).lightRGB
            XCTAssertGreaterThanOrEqual(current.red, previous.red)
            XCTAssertLessThan(current.green, previous.green)
            XCTAssertLessThan(current.blue, previous.blue)
            for channel in [current.red, current.green, current.blue] {
                XCTAssertTrue((0...1).contains(channel))
            }
            previous = current
        }
    }

    func testIntensityDoesNotChangeColourOrTintStrength() {
        for warmth in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let dim = LampAppearance(warmth: warmth, intensity: 0.25)
            let bright = LampAppearance(warmth: warmth, intensity: 1)
            XCTAssertEqual(dim.lightRGB, bright.lightRGB)
            XCTAssertEqual(dim.paperTintOpacity, bright.paperTintOpacity)
            XCTAssertLessThan(dim.emitterOpacity, bright.emitterOpacity)
            XCTAssertLessThan(dim.emitterGlowOpacity, bright.emitterGlowOpacity)
        }
    }

    func testWarmthDoesNotChangeIntensity() {
        XCTAssertEqual(LampAppearance(warmth: 0, intensity: 0.6).intensity,
                       LampAppearance(warmth: 1, intensity: 0.6).intensity)
        XCTAssertEqual(LampAppearance(warmth: 0, intensity: 0.6).emitterOpacity,
                       LampAppearance(warmth: 1, intensity: 0.6).emitterOpacity)
    }

    func testInvalidValuesAreClamped() {
        XCTAssertEqual(LampAppearance(warmth: -3, intensity: -3).warmth, 0)
        XCTAssertEqual(LampAppearance(warmth: 3, intensity: 3).warmth, 1)
        XCTAssertEqual(LampAppearance(warmth: -3, intensity: -3).intensity, 0.25)
        XCTAssertEqual(LampAppearance(warmth: 3, intensity: 3).intensity, 1)
        for value in [Double.nan, .infinity, -.infinity] {
            let lamp = LampAppearance(warmth: value, intensity: value)
            XCTAssertEqual(lamp.warmth, 0.55)
            XCTAssertEqual(lamp.intensity, 0.85)
        }
    }

    func testWarmthPreferenceRoundTripsAtBothEndpoints() throws {
        for value in [0.0, 0.5, 1.0] {
            var preferences = WritingPreferences()
            preferences.lampWarmth = value
            let data = try JSONEncoder().encode(preferences)
            let decoded = try JSONDecoder().decode(WritingPreferences.self, from: data)
            XCTAssertEqual(decoded.lampWarmth, value)
        }
    }

    /// An arithmetic check of the chosen multiply tint, NOT a macOS screenshot
    /// test. Check all existing papers, with a partial and full cone mask.
    func testPaperTintEndpointsHaveSubstantialChannelSeparation() {
        let cool = LampAppearance(warmth: 0, intensity: 0.82)
        let warm = LampAppearance(warmth: 1, intensity: 0.82)
        for paperBlue in [217.0 / 255, 183.0 / 255, 233.0 / 255] {
            for mask in [0.5, 1.0] {
                let alpha = cool.paperTintOpacity * mask
                let coolBlue = paperBlue * (1 - alpha + alpha * cool.lightRGB.blue)
                let warmBlue = paperBlue * (1 - alpha + alpha * warm.lightRGB.blue)
                XCTAssertGreaterThan(coolBlue - warmBlue, 0.19)
            }
        }
    }
}
