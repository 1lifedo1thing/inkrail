import XCTest
@testable import InkrailCore

final class DeskAppearanceTests: XCTestCase {
    private func decode(_ record: String) throws -> WritingPreferences {
        try JSONDecoder().decode(WritingPreferences.self, from: Data(record.utf8))
    }

    func testDefaultDeskStaysQuietAndFocusCanWiden() {
        let preferences = WritingPreferences()
        XCTAssertEqual(preferences.deskFinish, .charcoal)
        XCTAssertEqual(preferences.deskAccent, .none)
        XCTAssertTrue(preferences.widerFocusPaper)
    }

    func testLiteralLegacyRecordPreservesPaperRollEmbossingInkAndSound() throws {
        // A complete pre-desk schema, not data emitted by the current encoder.
        let record = """
        {"mechanismStyle":"walnut","matchRailToStyle":false,
         "paper":"cream","paperStartPosition":"bottom","paperMotion":"roll",
         "paperTexture":"cotton","textureStrength":0.77,
         "paperEmbossing":"monogram","embossingDepth":0.61,
         "capsule":"cobalt","rail":"brass","ribbon":"oxblood",
         "fontSize":24,"writingFont":"courierNew","inkStrength":0.73,
         "wornInk":false,"inkBuildup":0.81,"wideMargins":false,
         "curvedPaper":true,"garden":true,"soundEnabled":false,
         "soundVolume":0.17,"typewriterSound":"electric","nightMode":true,
         "lampIntensity":0.49,"lampWarmth":0.91}
        """
        var expected = WritingPreferences()
        expected.mechanismStyle = .walnut
        expected.matchRailToStyle = false
        expected.paper = .cream
        expected.paperStartPosition = .bottom
        expected.paperMotion = .roll
        expected.paperTexture = .cotton
        expected.textureStrength = 0.77
        expected.paperEmbossing = .monogram
        expected.embossingDepth = 0.61
        expected.capsule = .cobalt
        expected.rail = .brass
        expected.ribbon = .oxblood
        expected.fontSize = 24
        expected.writingFont = .courierNew
        expected.inkStrength = 0.73
        expected.wornInk = false
        expected.inkBuildup = 0.81
        expected.wideMargins = false
        expected.curvedPaper = true
        expected.garden = true
        expected.soundEnabled = false
        expected.soundVolume = 0.17
        expected.typewriterSound = .electric
        expected.nightMode = true
        expected.lampIntensity = 0.49
        expected.lampWarmth = 0.91
        XCTAssertEqual(try decode(record), expected)
    }

    func testMissingNullAndUnknownDeskFieldsFallBackIndependently() throws {
        for fields in ["", "\"deskFinish\":null,\"deskAccent\":null,\"widerFocusPaper\":null,",
                       "\"deskFinish\":\"future-finish\",\"deskAccent\":\"future-accent\","] {
            let actual = try decode("{\(fields)\"paperMotion\":\"roll\",\"paperEmbossing\":\"sunburst\",\"inkBuildup\":0.82}")
            var expected = WritingPreferences()
            expected.paperMotion = .roll
            expected.paperEmbossing = .sunburst
            expected.inkBuildup = 0.82
            XCTAssertEqual(actual, expected)
        }
        let selected = try decode("{\"deskFinish\":\"future\",\"deskAccent\":\"sprig\",\"widerFocusPaper\":false}")
        XCTAssertEqual(selected.deskFinish, .charcoal)
        XCTAssertEqual(selected.deskAccent, .sprig)
        XCTAssertFalse(selected.widerFocusPaper)
        let reverse = try decode("{\"deskFinish\":\"linen\",\"deskAccent\":\"future\",\"widerFocusPaper\":false}")
        XCTAssertEqual(reverse.deskFinish, .linen)
        XCTAssertEqual(reverse.deskAccent, .none)
        XCTAssertFalse(reverse.widerFocusPaper)
    }

    func testStableDeskIdentifiersAndEveryCombinationRoundTrip() throws {
        XCTAssertEqual(DeskFinish.allCases.map(\.rawValue), ["charcoal", "walnut", "felt", "linen", "oak", "leather"])
        XCTAssertEqual(DeskAccent.allCases.map(\.rawValue), ["none", "sprig", "paperclip", "envelope", "brassLamps", "linenLamps"])
        for finish in DeskFinish.allCases {
            XCTAssertEqual(finish.id, finish.rawValue)
            for accent in DeskAccent.allCases {
                XCTAssertEqual(accent.id, accent.rawValue)
                for wider in [false, true] {
                    var preferences = WritingPreferences()
                    preferences.deskFinish = finish
                    preferences.deskAccent = accent
                    preferences.widerFocusPaper = wider
                    preferences.paperMotion = .roll
                    preferences.paperEmbossing = .botanical
                    preferences.inkBuildup = 0.68
                    let encoded = try JSONEncoder().encode(preferences)
                    let record = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
                    XCTAssertEqual(record["deskFinish"] as? String, finish.rawValue)
                    XCTAssertEqual(record["deskAccent"] as? String, accent.rawValue)
                    XCTAssertEqual(record["widerFocusPaper"] as? Bool, wider)
                    XCTAssertEqual(try JSONDecoder().decode(WritingPreferences.self, from: encoded), preferences)
                }
            }
        }
    }

    func testLiteralExistingDeskChoiceSurvivesLampAdditions() throws {
        let record = """
        {"deskFinish":"walnut","deskAccent":"envelope","widerFocusPaper":false,
         "paperMotion":"roll","paperStartPosition":"bottom","paper":"cream",
         "paperTexture":"laid","paperEmbossing":"sunburst","embossingDepth":0.72,
         "writingFont":"typewriterLight","inkBuildup":0.86,"wornInk":false,
         "typewriterSound":"electric","soundEnabled":false,"soundVolume":0.17,
         "nightMode":true,"lampWarmth":0.23,"lampIntensity":0.54}
        """
        var expected = WritingPreferences()
        expected.deskFinish = .walnut
        expected.deskAccent = .envelope
        expected.widerFocusPaper = false
        expected.paperMotion = .roll
        expected.paperStartPosition = .bottom
        expected.paper = .cream
        expected.paperTexture = .laid
        expected.paperEmbossing = .sunburst
        expected.embossingDepth = 0.72
        expected.writingFont = .typewriterLight
        expected.inkBuildup = 0.86
        expected.wornInk = false
        expected.typewriterSound = .electric
        expected.soundEnabled = false
        expected.soundVolume = 0.17
        expected.nightMode = true
        expected.lampWarmth = 0.23
        expected.lampIntensity = 0.54
        XCTAssertEqual(try decode(record), expected)
    }

    func testMalformedDeskFieldsAreRejected() {
        for record in ["{\"deskFinish\":7}", "{\"deskAccent\":[]}",
                       "{\"widerFocusPaper\":\"yes\"}"] {
            XCTAssertThrowsError(try decode(record))
        }
    }

    func testLiteralBrassLampChoiceSurvivesBronzeMaterialAndLeatherAddition() throws {
        // A record from the green-glass lamp version: the display label and
        // material change must not rename its persisted ID or reset choices.
        let record = """
        {"deskFinish":"walnut","deskAccent":"brassLamps","widerFocusPaper":false,
         "paper":"white","paperMotion":"roll","paperStartPosition":"bottom",
         "paperEmbossing":"botanical","lampWarmth":0.73,"lampIntensity":0.68,
         "nightMode":true,"soundEnabled":false,"mechanismStyle":"copper"}
        """
        var expected = WritingPreferences()
        expected.deskFinish = .walnut
        expected.deskAccent = .brassLamps
        expected.widerFocusPaper = false
        expected.paper = .white
        expected.paperMotion = .roll
        expected.paperStartPosition = .bottom
        expected.paperEmbossing = .botanical
        expected.lampWarmth = 0.73
        expected.lampIntensity = 0.68
        expected.nightMode = true
        expected.soundEnabled = false
        expected.mechanismStyle = .copper
        let actual = try decode(record)
        XCTAssertEqual(actual, expected)
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(actual)) as? [String: Any])
        XCTAssertEqual(saved["deskAccent"] as? String, "brassLamps")
        XCTAssertEqual(saved["deskFinish"] as? String, "walnut")
    }

    func testFocusWidthsKeepAnOuterBorderAndNarrowWindowBehavior() {
        XCTAssertEqual(DeskLayout.paperWidth(windowWidth: 1080, focusMode: false, widerFocusPaper: true), 720)
        let focused = DeskLayout.paperWidth(windowWidth: 1080, focusMode: true, widerFocusPaper: true)
        XCTAssertEqual(focused, 960)
        XCTAssertEqual((1080 - focused) / 2, 60)
        XCTAssertEqual(DeskLayout.paperWidth(windowWidth: 1080, focusMode: true, widerFocusPaper: false), 720)
        for focus in [false, true] {
            XCTAssertEqual(DeskLayout.paperWidth(windowWidth: 660, focusMode: focus, widerFocusPaper: true), 556)
        }
        XCTAssertEqual(DeskLayout.paperWidth(windowWidth: 3840, focusMode: true, widerFocusPaper: true), 960)
    }

    func testPaperWidthIsFiniteBoundedAndNeverShrinksOnFocus() {
        for width in stride(from: 1.0, through: 5000, by: 7) {
            let normal = DeskLayout.paperWidth(windowWidth: width, focusMode: false, widerFocusPaper: true)
            let focus = DeskLayout.paperWidth(windowWidth: width, focusMode: true, widerFocusPaper: true)
            XCTAssertTrue(normal.isFinite && focus.isFinite)
            XCTAssertGreaterThanOrEqual(normal, 1)
            XCTAssertLessThanOrEqual(focus, width)
            XCTAssertLessThanOrEqual(normal, focus)
            XCTAssertLessThanOrEqual(normal, 720)
            XCTAssertLessThanOrEqual(focus, 960)
        }
        for invalid in [Double.nan, .infinity, -.infinity, -200, 0, 0.5] {
            XCTAssertEqual(DeskLayout.paperWidth(windowWidth: invalid, focusMode: true, widerFocusPaper: true), 1)
        }
    }
}
