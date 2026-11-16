import XCTest
@testable import InkrailCore

final class InkImpressionTests: XCTestCase {
    func testRedrawOrderDoesNotChangeAnImpression() {
        let passage = Array("The rusty keys leave a little ink behind. 0123456789".utf16)
        let first = passage.enumerated().map {
            InkImpression(characterIndex: $0.offset, codeUnit: $0.element, buildup: 0.55, pointSize: 20)
        }
        for index in passage.indices.reversed() {
            XCTAssertEqual(first[index], InkImpression(characterIndex: index,
                codeUnit: passage[index], buildup: 0.55, pointSize: 20))
        }
    }

    func testRepeatedLettersHaveOccasionalHeavyAndDryStrikes() {
        let values = (0..<512).map {
            InkImpression(characterIndex: $0, codeUnit: 101, buildup: 1, pointSize: 20)
        }
        let heavy = values.filter { $0.spread > 0 }.count
        XCTAssertGreaterThan(heavy, 40)
        XCTAssertLessThan(heavy, 205)
        XCTAssertTrue(values.contains { $0.opacity < 0.75 })
        XCTAssertTrue(values.contains { $0.opacity > 0.9 && $0.spread == 0 })
    }

    func testBuildupBroadensOnlyHeavyStrikesAndZeroRemovesSpread() {
        for index in 0..<256 {
            let zero = InkImpression(characterIndex: index, codeUnit: 97, buildup: 0, pointSize: 20)
            let low = InkImpression(characterIndex: index, codeUnit: 97, buildup: 0.2, pointSize: 20)
            let high = InkImpression(characterIndex: index, codeUnit: 97, buildup: 1, pointSize: 20)
            XCTAssertEqual(zero.spread, 0)
            if high.spread > 0 {
                XCTAssertGreaterThan(high.spread, low.spread)
                XCTAssertGreaterThan(low.spread, 0)
                XCTAssertGreaterThanOrEqual(high.opacity, low.opacity)
            } else {
                XCTAssertEqual(low.spread, 0)
            }
        }
    }

    func testExtremeInputsStayFiniteAndClamped() {
        let amounts: [Double] = [-100, 0, 0.55, 1, 100, .nan, .infinity, -.infinity]
        let sizes: [Double] = [-100, 0, 1, 20, 144, 1e12, .nan, .infinity, -.infinity]
        for index in [Int.min, -1, 0, 7, 101, Int.max] {
            for amount in amounts {
                for size in sizes {
                    let value = InkImpression(characterIndex: index, codeUnit: 87,
                                              buildup: amount, pointSize: size)
                    XCTAssertTrue([value.opacity, value.offsetX, value.offsetY,
                                   value.spread, value.spreadOpacity].allSatisfy(\.isFinite))
                    XCTAssertTrue((0...1).contains(value.opacity))
                    XCTAssertTrue((0...1).contains(value.spreadOpacity))
                    XCTAssertTrue((0...6).contains(value.spread))
                    XCTAssertLessThanOrEqual(abs(value.offsetX), 1)
                    XCTAssertLessThanOrEqual(abs(value.offsetY), 3)
                }
            }
        }
        for invalid in [Double.nan, .infinity, -.infinity] {
            XCTAssertEqual(InkImpression(characterIndex: 27, codeUnit: 101, buildup: invalid, pointSize: 20),
                           InkImpression(characterIndex: 27, codeUnit: 101, buildup: 0.55, pointSize: 20))
            XCTAssertEqual(InkImpression(characterIndex: 27, codeUnit: 101, buildup: 0.55, pointSize: invalid),
                           InkImpression(characterIndex: 27, codeUnit: 101, buildup: 0.55, pointSize: 20))
        }
        XCTAssertEqual(InkImpression(characterIndex: 27, codeUnit: 101, buildup: -2, pointSize: 20),
                       InkImpression(characterIndex: 27, codeUnit: 101, buildup: 0, pointSize: 20))
        XCTAssertEqual(InkImpression(characterIndex: 27, codeUnit: 101, buildup: 8, pointSize: 20),
                       InkImpression(characterIndex: 27, codeUnit: 101, buildup: 1, pointSize: 20))
    }

    func testLiteralLegacyRecordKeepsCleanInkAndOtherChoices() throws {
        XCTAssertEqual(WritingPreferences().inkBuildup, 0.55)
        let legacy = """
        {"writingFont":"americanTypewriter","fontSize":24,"inkStrength":0.73,
         "wornInk":false,"ribbon":"oxblood","paper":"cream","paperMotion":"roll",
         "paperStartPosition":"bottom","typewriterSound":"electric","soundEnabled":false,
         "soundVolume":0.17,"mechanismStyle":"walnut","nightMode":true,"lampWarmth":0.91}
        """
        let actual = try JSONDecoder().decode(WritingPreferences.self, from: Data(legacy.utf8))
        var expected = WritingPreferences()
        expected.writingFont = .americanTypewriter
        expected.fontSize = 24
        expected.inkStrength = 0.73
        expected.wornInk = false
        expected.ribbon = .oxblood
        expected.paper = .cream
        expected.paperMotion = .roll
        expected.paperStartPosition = .bottom
        expected.typewriterSound = .electric
        expected.soundEnabled = false
        expected.soundVolume = 0.17
        expected.mechanismStyle = .walnut
        expected.nightMode = true
        expected.lampWarmth = 0.91
        XCTAssertEqual(actual, expected)
        XCTAssertEqual(actual.inkBuildup, 0.55)
    }

    func testBuildupNullClampAndRoundTripPreserveZero() throws {
        for (literal, value) in [("null", 0.55), ("-5", 0), ("0", 0), ("0.83", 0.83), ("8", 1)] {
            let record = "{\"inkBuildup\":\(literal),\"wornInk\":false,\"writingFont\":\"monaco\"}"
            let preferences = try JSONDecoder().decode(WritingPreferences.self, from: Data(record.utf8))
            XCTAssertEqual(preferences.inkBuildup, value)
            XCTAssertFalse(preferences.wornInk)
            XCTAssertEqual(preferences.writingFont, .monaco)
            let saved = try JSONEncoder().encode(preferences)
            XCTAssertEqual(try JSONDecoder().decode(WritingPreferences.self, from: saved), preferences)
        }
        for invalid in [Double.nan, .infinity, -.infinity] {
            var preferences = WritingPreferences()
            preferences.inkBuildup = invalid
            preferences.wornInk = false
            preferences.clamp()
            XCTAssertEqual(preferences.inkBuildup, 0.55)
            XCTAssertFalse(preferences.wornInk)
        }
        for bad in ["\"heavy\"", "true", "[]", "{}"] {
            XCTAssertThrowsError(try JSONDecoder().decode(WritingPreferences.self,
                from: Data("{\"inkBuildup\":\(bad)}".utf8)))
        }
    }
}
