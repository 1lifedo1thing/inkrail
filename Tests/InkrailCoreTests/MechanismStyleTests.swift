import XCTest
@testable import InkrailCore

final class MechanismStyleTests: XCTestCase {
    private func decode(_ json: String) throws -> WritingPreferences {
        try JSONDecoder().decode(WritingPreferences.self, from: Data(json.utf8))
    }

    func testDefaultWalnutStyleMatchesItsBrassRail() {
        let preferences = WritingPreferences()
        XCTAssertEqual(preferences.mechanismStyle, .walnut)
        XCTAssertTrue(preferences.matchRailToStyle)
        XCTAssertEqual(preferences.capsule, .porcelain)
        XCTAssertEqual(preferences.rail, .steel)
        XCTAssertEqual(preferences.effectiveRailFinish, .brass)
    }

    func testLegacyV012PreferencesKeepAllValues() throws {
        // Matches the old synthesized schema: neither of the two new keys exists.
        let legacy = """
        {"paper":"cream","capsule":"cobalt","rail":"brass","ribbon":"oxblood",
         "fontSize":24,"inkStrength":0.73,"wornInk":false,"wideMargins":false,
         "curvedPaper":false,"garden":true,"soundEnabled":false,"soundVolume":0.17,
         "nightMode":true,"lampIntensity":0.49,"lampWarmth":0.91}
        """
        let preferences = try decode(legacy)
        XCTAssertEqual(preferences.mechanismStyle, .walnut)
        XCTAssertTrue(preferences.matchRailToStyle)
        XCTAssertEqual(preferences.paper, .cream)
        XCTAssertEqual(preferences.capsule, .cobalt)
        XCTAssertEqual(preferences.rail, .brass)
        XCTAssertEqual(preferences.effectiveRailFinish, .brass)
        XCTAssertEqual(preferences.ribbon, .oxblood)
        XCTAssertEqual(preferences.fontSize, 24)
        XCTAssertEqual(preferences.inkStrength, 0.73)
        XCTAssertFalse(preferences.wornInk)
        XCTAssertFalse(preferences.wideMargins)
        XCTAssertFalse(preferences.curvedPaper)
        XCTAssertTrue(preferences.garden)
        XCTAssertFalse(preferences.soundEnabled)
        XCTAssertEqual(preferences.soundVolume, 0.17)
        XCTAssertTrue(preferences.nightMode)
        XCTAssertEqual(preferences.lampIntensity, 0.49)
        XCTAssertEqual(preferences.lampWarmth, 0.91)
    }

    func testMissingAndNullKeysUseDefaults() throws {
        XCTAssertEqual(try decode("{}"), WritingPreferences())
        XCTAssertEqual(try decode("{\"mechanismStyle\":null,\"matchRailToStyle\":null}"), WritingPreferences())
    }

    func testFalseAndZeroAreNotTreatedAsMissing() throws {
        let preferences = try decode("""
        {"matchRailToStyle":false,"soundEnabled":false,"soundVolume":0,"lampWarmth":0}
        """)
        XCTAssertFalse(preferences.matchRailToStyle)
        XCTAssertFalse(preferences.soundEnabled)
        XCTAssertEqual(preferences.soundVolume, 0)
        XCTAssertEqual(preferences.lampWarmth, 0)
    }

    func testEveryStyleAndRailModeRoundTrips() throws {
        for style in MechanismStyle.allCases {
            for match in [false, true] {
                var preferences = WritingPreferences()
                preferences.mechanismStyle = style
                preferences.matchRailToStyle = match
                preferences.rail = .brass
                preferences.capsule = .sage
                preferences.lampWarmth = 0.13
                let bytes = try JSONEncoder().encode(preferences)
                let result = try JSONDecoder().decode(WritingPreferences.self, from: bytes)
                XCTAssertEqual(result, preferences)
            }
        }
    }

    func testUnknownStyleDoesNotResetOtherValues() throws {
        let preferences = try decode("""
        {"mechanismStyle":"futureFinish","capsule":"terracotta","rail":"charcoal",
         "nightMode":true,"lampWarmth":0.24,"soundVolume":0.11}
        """)
        XCTAssertEqual(preferences.mechanismStyle, .walnut)
        XCTAssertEqual(preferences.capsule, .terracotta)
        XCTAssertEqual(preferences.rail, .charcoal)
        XCTAssertEqual(preferences.effectiveRailFinish, .brass)
        XCTAssertTrue(preferences.nightMode)
        XCTAssertEqual(preferences.lampWarmth, 0.24)
        XCTAssertEqual(preferences.soundVolume, 0.11)
    }

    func testIncorrectFieldTypesAreNotSilentlyAccepted() {
        XCTAssertThrowsError(try decode("{\"mechanismStyle\":7}"))
        XCTAssertThrowsError(try decode("{\"fontSize\":\"large\"}"))
    }

    func testSwitchingPreservesClassicChoicesAndLamp() {
        var preferences = WritingPreferences()
        preferences.mechanismStyle = .classic
        preferences.capsule = .cobalt
        preferences.rail = .charcoal
        preferences.lampWarmth = 0.23
        preferences.lampIntensity = 0.71
        preferences.nightMode = true
        let original = preferences
        let originalLamp = LampAppearance(warmth: preferences.lampWarmth, intensity: preferences.lampIntensity)
        for style in MechanismStyle.allCases {
            preferences.mechanismStyle = style
            XCTAssertEqual(preferences.capsule, .cobalt)
            XCTAssertEqual(preferences.rail, .charcoal)
            XCTAssertEqual(preferences.lampWarmth, original.lampWarmth)
            XCTAssertEqual(preferences.lampIntensity, original.lampIntensity)
            XCTAssertTrue(preferences.nightMode)
            let lamp = LampAppearance(warmth: preferences.lampWarmth, intensity: preferences.lampIntensity)
            XCTAssertEqual(lamp, originalLamp)
        }
        preferences.mechanismStyle = .classic
        XCTAssertEqual(preferences, original)
        XCTAssertEqual(preferences.effectiveRailFinish, .charcoal)
    }

    func testCoordinatedRailsUseExpectedMaterials() {
        let pairs: [(MechanismStyle, RailFinish)] = [
            (.brushedSteel, .steel), (.champagne, .brass), (.walnut, .brass),
            (.porcelain, .charcoal), (.midnight, .charcoal),
            (.roseQuartz, .brass), (.seaGlass, .steel), (.lavender, .steel),
            (.racingGreen, .brass), (.copper, .charcoal), (.wildflower, .brass)
        ]
        for (style, rail) in pairs {
            var preferences = WritingPreferences()
            preferences.rail = .steel
            preferences.mechanismStyle = style
            XCTAssertEqual(preferences.effectiveRailFinish, rail)
            XCTAssertEqual(preferences.rail, .steel)
        }
    }

    func testManualRailAlwaysWinsWhenMatchingOff() {
        for style in MechanismStyle.allCases {
            for rail in RailFinish.allCases {
                var preferences = WritingPreferences()
                preferences.mechanismStyle = style
                preferences.matchRailToStyle = false
                preferences.rail = rail
                XCTAssertEqual(preferences.effectiveRailFinish, rail)
            }
        }
    }

    func testMaterialsHaveValidDistinctDesignTokens() {
        XCTAssertEqual(MechanismStyle.allCases.count, 12)
        XCTAssertEqual(Set(MechanismStyle.allCases.map(\.rawValue)).count, 12)
        XCTAssertEqual(Set(MechanismStyle.allCases.map(\.label)).count, 12)
        XCTAssertEqual(MechanismMaterial.housingWidth, 110)
        XCTAssertEqual(MechanismMaterial.housingHeight, 46)
        for style in MechanismStyle.allCases {
            let material = style.material
            XCTAssertGreaterThanOrEqual(material.bodyColors.count, 3)
            XCTAssertTrue((material.bodyColors + [material.trim]).allSatisfy { $0 <= 0xFFFFFF })
            XCTAssertGreaterThan(material.cornerRadius, 0)
            XCTAssertLessThanOrEqual(material.cornerRadius, MechanismMaterial.housingHeight / 2)
            XCTAssertFalse(style.subtitle.isEmpty)
        }
        XCTAssertEqual(MechanismStyle.walnut.material.texture, .wood)
        XCTAssertEqual(MechanismStyle.porcelain.material.texture, .ceramic)
        XCTAssertNotEqual(MechanismStyle.midnight.material, MechanismStyle.brushedSteel.material)
    }

    func testOriginalStyleIdentifiersRemainFirstAndLegacyPreferencesSurvive() throws {
        XCTAssertEqual(Array(MechanismStyle.allCases.prefix(6)).map(\.rawValue),
                       ["classic", "brushedSteel", "champagne", "walnut", "porcelain", "midnight"])
        let preferences = try decode("""
        {"mechanismStyle":"midnight","matchRailToStyle":false,"capsule":"cobalt",
         "rail":"brass","paper":"cream","paperStartPosition":"bottom",
         "paperMotion":"roll","writingFont":"georgia","typewriterSound":"soft",
         "lampWarmth":0.27,"lampIntensity":0.64}
        """)
        XCTAssertEqual(preferences.mechanismStyle, .midnight)
        XCTAssertFalse(preferences.matchRailToStyle)
        XCTAssertEqual(preferences.capsule, .cobalt)
        XCTAssertEqual(preferences.effectiveRailFinish, .brass)
        XCTAssertEqual(preferences.paper, .cream)
        XCTAssertEqual(preferences.paperStartPosition, .bottom)
        XCTAssertEqual(preferences.paperMotion, .roll)
        XCTAssertEqual(preferences.writingFont, .georgia)
        XCTAssertEqual(preferences.typewriterSound, .soft)
        XCTAssertEqual(preferences.lampWarmth, 0.27)
        XCTAssertEqual(preferences.lampIntensity, 0.64)
    }

    func testDecodingClampsUnsafeNumbersWithoutDiscardingStyle() throws {
        let preferences = try decode("""
        {"mechanismStyle":"walnut","fontSize":999,"lampWarmth":-4,"lampIntensity":8,"soundVolume":-2}
        """)
        XCTAssertEqual(preferences.mechanismStyle, .walnut)
        XCTAssertEqual(preferences.fontSize, 28)
        XCTAssertEqual(preferences.lampWarmth, 0)
        XCTAssertEqual(preferences.lampIntensity, 1)
        XCTAssertEqual(preferences.soundVolume, 0)
    }
}
