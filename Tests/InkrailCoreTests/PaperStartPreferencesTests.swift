import XCTest
@testable import InkrailCore

final class PaperStartPreferencesTests: XCTestCase {
    private func decode(_ json: String) throws -> WritingPreferences {
        try JSONDecoder().decode(WritingPreferences.self, from: Data(json.utf8))
    }

    func testDefaultAndMissingPositionKeepTopStartingLayout() throws {
        XCTAssertEqual(WritingPreferences().paperStartPosition, .top)
        XCTAssertEqual(try decode("{}").paperStartPosition, .top)
        XCTAssertEqual(PaperStartPosition.allCases.map(\.id), ["top", "bottom"])
    }

    func testLegacyV013RecordPreservesEveryExistingPreference() throws {
        // Literal pre-feature schema: no paperStartPosition key exists.
        let legacy = """
        {"mechanismStyle":"walnut","matchRailToStyle":false,
         "paper":"cream","capsule":"cobalt","rail":"brass","ribbon":"oxblood",
         "fontSize":24,"inkStrength":0.73,"wornInk":false,"wideMargins":false,
         "curvedPaper":false,"garden":true,"soundEnabled":false,"soundVolume":0.17,
         "nightMode":true,"lampIntensity":0.49,"lampWarmth":0.91}
        """
        var expected = WritingPreferences()
        expected.mechanismStyle = .walnut
        expected.matchRailToStyle = false
        expected.paper = .cream
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

    func testNullPositionUsesTopWithoutResettingOtherPreferences() throws {
        let preferences = try decode("""
        {"paperStartPosition":null,"mechanismStyle":"champagne",
         "matchRailToStyle":false,"soundVolume":0,"nightMode":true}
        """)
        XCTAssertEqual(preferences.paperStartPosition, .top)
        XCTAssertEqual(preferences.mechanismStyle, .champagne)
        XCTAssertFalse(preferences.matchRailToStyle)
        XCTAssertEqual(preferences.soundVolume, 0)
        XCTAssertTrue(preferences.nightMode)
    }

    func testUnknownPositionUsesTopWithoutResettingOtherPreferences() throws {
        let preferences = try decode("""
        {"paperStartPosition":"futurePosition","paper":"white",
         "capsule":"sage","rail":"charcoal","lampWarmth":0.13}
        """)
        XCTAssertEqual(preferences.paperStartPosition, .top)
        XCTAssertEqual(preferences.paper, .white)
        XCTAssertEqual(preferences.capsule, .sage)
        XCTAssertEqual(preferences.rail, .charcoal)
        XCTAssertEqual(preferences.lampWarmth, 0.13)
    }

    func testBothPositionsRoundTripWithStablePersistedIdentifiers() throws {
        for position in PaperStartPosition.allCases {
            var preferences = WritingPreferences()
            preferences.paperStartPosition = position
            preferences.mechanismStyle = .midnight
            preferences.matchRailToStyle = false
            preferences.rail = .brass
            preferences.wideMargins = false
            preferences.lampWarmth = 0.19
            let data = try JSONEncoder().encode(preferences)
            let record = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(record["paperStartPosition"] as? String, position.rawValue)
            XCTAssertEqual(try JSONDecoder().decode(WritingPreferences.self, from: data), preferences)
        }
    }

    func testMalformedPositionTypesAreRejected() {
        XCTAssertThrowsError(try decode("{\"paperStartPosition\":7}"))
        XCTAssertThrowsError(try decode("{\"paperStartPosition\":false}"))
        XCTAssertThrowsError(try decode("{\"paperStartPosition\":[]}"))
    }

    func testLiteralRollPreferencesKeepTopAndBottomIndependentOfMotion() throws {
        for position in PaperStartPosition.allCases {
            let preferences = try decode("""
            {"paperMotion":"roll","paperStartPosition":"\(position.rawValue)",
             "mechanismStyle":"walnut","fontSize":24,"lampWarmth":0.19}
            """)
            XCTAssertEqual(preferences.paperMotion, .roll)
            XCTAssertEqual(preferences.effectivePaperStartPosition, position)
            XCTAssertEqual(preferences.mechanismStyle, .walnut)
            XCTAssertEqual(preferences.fontSize, 24)
            XCTAssertEqual(preferences.lampWarmth, 0.19)
            var changed = preferences
            changed.paperMotion = .sheet
            XCTAssertEqual(changed.effectivePaperStartPosition, position)
        }
    }
}
