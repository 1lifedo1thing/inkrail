import XCTest
@testable import InkrailCore

final class CustomizationTests: XCTestCase {
    private func decode(_ json: String) throws -> WritingPreferences {
        try JSONDecoder().decode(WritingPreferences.self, from: Data(json.utf8))
    }

    func testNewDefaultsRetainTheOriginalPaperFontAndSound() {
        let preferences = WritingPreferences()
        XCTAssertEqual(preferences.paperTexture, .classic)
        XCTAssertEqual(preferences.textureStrength, 0.55)
        XCTAssertEqual(preferences.paperEmbossing, .none)
        XCTAssertEqual(preferences.embossingDepth, 0.45)
        XCTAssertEqual(preferences.writingFont, .courier)
        XCTAssertEqual(preferences.typewriterSound, .classic)
        XCTAssertEqual(preferences.paper, .ivory)
        XCTAssertEqual(preferences.fontSize, 20)
        XCTAssertEqual(preferences.soundVolume, 0.30)
    }

    func testLiteralLegacyPreferencesPreserveEveryExistingField() throws {
        // Actual pre-customization schema, including the v0.1.4 paper-start key.
        let legacy = """
        {"mechanismStyle":"walnut","matchRailToStyle":false,
         "paper":"cream","paperStartPosition":"bottom","capsule":"cobalt",
         "rail":"brass","ribbon":"oxblood","fontSize":24,"inkStrength":0.73,
         "wornInk":false,"wideMargins":false,"curvedPaper":false,"garden":true,
         "soundEnabled":false,"soundVolume":0.17,"nightMode":true,
         "lampIntensity":0.49,"lampWarmth":0.91}
        """
        var expected = WritingPreferences()
        expected.mechanismStyle = .walnut
        expected.matchRailToStyle = false
        expected.paper = .cream
        expected.paperStartPosition = .bottom
        expected.capsule = .cobalt
        expected.rail = .brass
        expected.ribbon = .oxblood
        expected.fontSize = 24
        expected.inkStrength = 0.73
        expected.wornInk = false
        expected.wideMargins = false
        expected.curvedPaper = false
        expected.garden = true
        expected.soundEnabled = false
        expected.soundVolume = 0.17
        expected.nightMode = true
        expected.lampIntensity = 0.49
        expected.lampWarmth = 0.91
        XCTAssertEqual(try decode(legacy), expected)
    }

    func testNullCustomizationFieldsUseDefaultsWithoutResettingExistingValues() throws {
        let preferences = try decode("""
        {"paperTexture":null,"textureStrength":null,"paperEmbossing":null,
         "embossingDepth":null,"writingFont":null,"typewriterSound":null,
         "paperStartPosition":"bottom","mechanismStyle":"midnight",
         "matchRailToStyle":false,"lampWarmth":0.23,"soundEnabled":false}
        """)
        var expected = WritingPreferences()
        expected.paperStartPosition = .bottom
        expected.mechanismStyle = .midnight
        expected.matchRailToStyle = false
        expected.lampWarmth = 0.23
        expected.soundEnabled = false
        XCTAssertEqual(preferences, expected)
    }

    func testUnknownChoicesFallBackIndependently() throws {
        let preferences = try decode("""
        {"paperTexture":"future-grain","paperEmbossing":"future-seal",
         "writingFont":"future-font","typewriterSound":"future-sound",
         "textureStrength":0.77,"embossingDepth":0.27,"paper":"white",
         "fontSize":26,"soundVolume":0,"lampWarmth":0.12}
        """)
        XCTAssertEqual(preferences.paperTexture, .classic)
        XCTAssertEqual(preferences.paperEmbossing, .none)
        XCTAssertEqual(preferences.writingFont, .courier)
        XCTAssertEqual(preferences.typewriterSound, .classic)
        XCTAssertEqual(preferences.textureStrength, 0.77)
        XCTAssertEqual(preferences.embossingDepth, 0.27)
        XCTAssertEqual(preferences.paper, .white)
        XCTAssertEqual(preferences.fontSize, 26)
        XCTAssertEqual(preferences.soundVolume, 0)
        XCTAssertEqual(preferences.lampWarmth, 0.12)
    }

    func testMachineIdentifiersRoundTrip() throws {
        let sounds: [(TypewriterSound, String)] = [
            (.classic, "classic"), (.soft, "soft"), (.royal, "royal"),
            (.vintage, "vintage"), (.portable, "portable"), (.electric, "electric")
        ]
        XCTAssertEqual(Set(TypewriterSound.allCases), Set(sounds.map { $0.0 }))
        for (sound, identifier) in sounds {
            XCTAssertEqual(sound.rawValue, identifier)
            let literal = Data("\"\(identifier)\"".utf8)
            XCTAssertEqual(try JSONDecoder().decode(TypewriterSound.self, from: literal), sound)
            XCTAssertEqual(try JSONEncoder().encode(sound), literal)
        }
    }

    func testLegacySoundPreferencesMapToMachinesAndPreserveOtherChoices() throws {
        let legacy: [(String, TypewriterSound)] = [
            ("classic", .classic), ("soft", .soft), ("crisp", .vintage),
            ("portable", .portable), ("office", .royal), ("electric", .electric)
        ]
        for (identifier, sound) in legacy {
            let preferences = try decode("""
            {"typewriterSound":"\(identifier)","soundEnabled":false,"soundVolume":0.17,
             "paper":"cream","paperMotion":"roll","paperStartPosition":"bottom",
             "paperTexture":"cotton","writingFont":"georgia","mechanismStyle":"walnut",
             "matchRailToStyle":false,"rail":"brass","nightMode":true,"lampWarmth":0.91}
            """)
            var expected = WritingPreferences()
            expected.typewriterSound = sound
            expected.soundEnabled = false
            expected.soundVolume = 0.17
            expected.paper = .cream
            expected.paperMotion = .roll
            expected.paperStartPosition = .bottom
            expected.paperTexture = .cotton
            expected.writingFont = .georgia
            expected.mechanismStyle = .walnut
            expected.matchRailToStyle = false
            expected.rail = .brass
            expected.nightMode = true
            expected.lampWarmth = 0.91
            XCTAssertEqual(preferences, expected)
            let saved = try JSONEncoder().encode(preferences)
            let record = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [String: Any])
            XCTAssertEqual(record["typewriterSound"] as? String, sound.rawValue)
        }
    }

    func testRemovedUnknownAndMissingSoundsKeepMuteAndUnrelatedPreferences() throws {
        for soundField in ["", "\"typewriterSound\":null,",
                           "\"typewriterSound\":\"recorded\",",
                           "\"typewriterSound\":\"future-sound\","] {
            let preferences = try decode("""
            {\(soundField)"soundEnabled":false,"soundVolume":0,
             "paper":"white","writingFont":"menlo","lampWarmth":0.12}
            """)
            var expected = WritingPreferences()
            expected.soundEnabled = false
            expected.soundVolume = 0
            expected.paper = .white
            expected.writingFont = .menlo
            expected.lampWarmth = 0.12
            XCTAssertEqual(preferences, expected)
        }
    }

    func testAllCustomizationCombinationsRoundTripWithStableIdentifiers() throws {
        for texture in PaperTexture.allCases {
            for embossing in PaperEmbossing.allCases {
                for font in WritingFont.allCases {
                    for sound in TypewriterSound.allCases {
                        var preferences = WritingPreferences()
                        preferences.paperTexture = texture
                        preferences.textureStrength = 0.71
                        preferences.paperEmbossing = embossing
                        preferences.embossingDepth = 0.32
                        preferences.writingFont = font
                        preferences.typewriterSound = sound
                        preferences.paperStartPosition = .bottom
                        preferences.mechanismStyle = .champagne
                        preferences.lampWarmth = 0.19
                        let bytes = try JSONEncoder().encode(preferences)
                        let record = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
                        XCTAssertEqual(record["paperTexture"] as? String, texture.rawValue)
                        XCTAssertEqual(record["paperEmbossing"] as? String, embossing.rawValue)
                        XCTAssertEqual(record["writingFont"] as? String, font.rawValue)
                        XCTAssertEqual(record["typewriterSound"] as? String, sound.rawValue)
                        XCTAssertEqual(try JSONDecoder().decode(WritingPreferences.self, from: bytes), preferences)
                    }
                }
            }
        }
    }

    func testTextureAndEmbossingAmountsClampButPreserveZero() throws {
        let clamped = try decode("""
        {"paperTexture":"cotton","textureStrength":-2,
         "paperEmbossing":"sunburst","embossingDepth":7,"writingFont":"georgia"}
        """)
        XCTAssertEqual(clamped.textureStrength, 0)
        XCTAssertEqual(clamped.embossingDepth, 1)
        XCTAssertEqual(clamped.paperTexture, .cotton)
        XCTAssertEqual(clamped.paperEmbossing, .sunburst)
        XCTAssertEqual(clamped.writingFont, .georgia)
        let zero = try decode("{\"textureStrength\":0,\"embossingDepth\":0}")
        XCTAssertEqual(zero.textureStrength, 0)
        XCTAssertEqual(zero.embossingDepth, 0)
        let reverse = try decode("{\"textureStrength\":4,\"embossingDepth\":-1}")
        XCTAssertEqual(reverse.textureStrength, 1)
        XCTAssertEqual(reverse.embossingDepth, 0)
    }

    func testNonfiniteAmountsUseDefaults() {
        for value in [Double.nan, .infinity, -.infinity] {
            var preferences = WritingPreferences()
            preferences.textureStrength = value
            preferences.embossingDepth = value
            preferences.paperTexture = .laid
            preferences.paperEmbossing = .botanical
            preferences.clamp()
            XCTAssertEqual(preferences.textureStrength, 0.55)
            XCTAssertEqual(preferences.embossingDepth, 0.45)
            XCTAssertEqual(preferences.paperTexture, .laid)
            XCTAssertEqual(preferences.paperEmbossing, .botanical)
        }
    }

    func testMalformedCustomizationFieldTypesAreRejected() {
        for json in [
            "{\"paperTexture\":7}", "{\"paperEmbossing\":false}",
            "{\"writingFont\":[]}", "{\"typewriterSound\":{}}",
            "{\"textureStrength\":\"strong\"}", "{\"embossingDepth\":true}"
        ] {
            XCTAssertThrowsError(try decode(json), json)
        }
    }
}
