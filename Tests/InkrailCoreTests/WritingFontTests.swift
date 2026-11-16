import XCTest
@testable import InkrailCore

final class WritingFontTests: XCTestCase {
    func testEightFontChoicesHaveStablePersistedIdentifiers() throws {
        let choices: [(WritingFont, String)] = [
            (.courier, "courier"), (.americanTypewriter, "americanTypewriter"),
            (.menlo, "menlo"), (.georgia, "georgia"), (.courierNew, "courierNew"),
            (.typewriterLight, "typewriterLight"),
            (.typewriterCondensed, "typewriterCondensed"), (.monaco, "monaco")
        ]
        XCTAssertEqual(Set(WritingFont.allCases), Set(choices.map { $0.0 }))
        for (font, identifier) in choices {
            let literal = Data("\"\(identifier)\"".utf8)
            XCTAssertEqual(font.rawValue, identifier)
            XCTAssertEqual(font.id, identifier)
            XCTAssertEqual(try JSONDecoder().decode(WritingFont.self, from: literal), font)
            XCTAssertEqual(try JSONEncoder().encode(font), literal)
        }
    }

    func testLiteralLegacyFontRecordsPreserveInkAndSoundChoices() throws {
        // Pre-expansion records, never produced by the new encoder.
        for font in [WritingFont.courier, .americanTypewriter, .menlo, .georgia] {
            let record = """
            {"writingFont":"\(font.rawValue)","fontSize":24,"inkStrength":0.73,
             "wornInk":false,"ribbon":"oxblood","paper":"cream",
             "paperStartPosition":"bottom","paperMotion":"roll",
             "typewriterSound":"electric","soundEnabled":false,"soundVolume":0.17}
            """
            let preferences = try JSONDecoder().decode(WritingPreferences.self, from: Data(record.utf8))
            var expected = WritingPreferences()
            expected.writingFont = font
            expected.fontSize = 24
            expected.inkStrength = 0.73
            expected.wornInk = false
            expected.ribbon = .oxblood
            expected.paper = .cream
            expected.paperStartPosition = .bottom
            expected.paperMotion = .roll
            expected.typewriterSound = .electric
            expected.soundEnabled = false
            expected.soundVolume = 0.17
            XCTAssertEqual(preferences, expected)
        }
    }

    func testMissingNullAndUnknownFontsFallBackWithoutResettingPreferences() throws {
        for field in ["", "\"writingFont\":null,", "\"writingFont\":\"future-font\","] {
            let record = """
            {\(field)"fontSize":22,"wornInk":false,"inkStrength":0.63,
             "ribbon":"midnight","soundEnabled":false,"soundVolume":0}
            """
            let preferences = try JSONDecoder().decode(WritingPreferences.self, from: Data(record.utf8))
            var expected = WritingPreferences()
            expected.fontSize = 22
            expected.wornInk = false
            expected.inkStrength = 0.63
            expected.ribbon = .midnight
            expected.soundEnabled = false
            expected.soundVolume = 0
            XCTAssertEqual(preferences, expected)
        }
    }
}
