import Foundation

private struct InkPreferenceFailure: Error, CustomStringConvertible {
    let description: String
}

@main
enum InkPreferenceCheck {
    static var assertions = 0
    static var groups = 0

    static func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw InkPreferenceFailure(description: message) }
        assertions += 1
    }

    static func passed(_ message: String) {
        groups += 1
        print("PASS \(message)")
    }

    static func decode(_ record: String) throws -> WritingPreferences {
        try JSONDecoder().decode(WritingPreferences.self, from: Data(record.utf8))
    }

    static func main() throws {
        try checkImpressions()
        try checkBounds()
        try checkPreferences()
        try checkFontIDs()
        print("Passed \(groups) Foundation ink/font groups (\(assertions) assertions).")
        print("No user files/preferences, UI, text input or XCTest are involved.")
    }

    static func checkImpressions() throws {
        let passage = Array("The rusty keys leave a little ink behind. 0123456789".utf16)
        let first = passage.enumerated().map {
            InkImpression(characterIndex: $0.offset, codeUnit: $0.element, buildup: 0.55, pointSize: 20)
        }
        for index in passage.indices.reversed() {
            try require(first[index] == InkImpression(characterIndex: index,
                codeUnit: passage[index], buildup: 0.55, pointSize: 20), "Impression depends on redraw order")
        }
        let repeated = (0..<512).map {
            InkImpression(characterIndex: $0, codeUnit: 101, buildup: 1, pointSize: 20)
        }
        let heavy = repeated.filter { $0.spread > 0 }.count
        try require(heavy > 40 && heavy < 205, "Heavy strikes must be occasional, not uniform")
        try require(repeated.contains { $0.opacity < 0.75 }, "No dry strikes remain")
        try require(repeated.contains { $0.opacity > 0.9 && $0.spread == 0 }, "No ordinary firm strikes remain")
        for index in 0..<256 {
            let zero = InkImpression(characterIndex: index, codeUnit: 97, buildup: 0, pointSize: 20)
            let low = InkImpression(characterIndex: index, codeUnit: 97, buildup: 0.2, pointSize: 20)
            let high = InkImpression(characterIndex: index, codeUnit: 97, buildup: 1, pointSize: 20)
            try require(zero.spread == 0, "Zero buildup still spreads ink")
            if high.spread > 0 {
                try require(high.spread > low.spread && low.spread > 0, "Buildup does not broaden a heavy strike")
                try require(high.opacity >= low.opacity, "A stronger heavy strike gets lighter")
            } else {
                try require(low.spread == 0, "Buildup changes which strikes are heavy")
            }
        }
        passed("deterministic impressions, occasional heavy/dry strikes and monotonic buildup")
    }

    static func checkBounds() throws {
        let amounts: [Double] = [-100, 0, 0.55, 1, 100, .nan, .infinity, -.infinity]
        let sizes: [Double] = [-100, 0, 1, 20, 144, 1e12, .nan, .infinity, -.infinity]
        for index in [Int.min, -1, 0, 7, 101, Int.max] {
            for amount in amounts {
                for size in sizes {
                    let value = InkImpression(characterIndex: index, codeUnit: 87,
                                              buildup: amount, pointSize: size)
                    try require([value.opacity, value.offsetX, value.offsetY, value.spread,
                                 value.spreadOpacity].allSatisfy(\.isFinite), "Nonfinite ink geometry")
                    try require((0...1).contains(value.opacity) && (0...1).contains(value.spreadOpacity),
                                "Opacity outside its drawing range")
                    try require((0...6).contains(value.spread) && abs(value.offsetX) <= 1 && abs(value.offsetY) <= 3,
                                "Extreme inputs create unbounded ink displacement")
                }
            }
        }
        for invalid in [Double.nan, .infinity, -.infinity] {
            try require(InkImpression(characterIndex: 27, codeUnit: 101, buildup: invalid, pointSize: 20)
                == InkImpression(characterIndex: 27, codeUnit: 101, buildup: 0.55, pointSize: 20),
                "Nonfinite buildup does not fall back to the default")
            try require(InkImpression(characterIndex: 27, codeUnit: 101, buildup: 0.55, pointSize: invalid)
                == InkImpression(characterIndex: 27, codeUnit: 101, buildup: 0.55, pointSize: 20),
                "Nonfinite font size does not fall back to the default")
        }
        for (outside, bound) in [(-2.0, 0.0), (8, 1)] {
            try require(InkImpression(characterIndex: 27, codeUnit: 101, buildup: outside, pointSize: 20)
                == InkImpression(characterIndex: 27, codeUnit: 101, buildup: bound, pointSize: 20),
                "Buildup is not clamped at \(bound)")
        }
        passed("finite, bounded rendering values for extreme indices, buildup and sizes")
    }

    static func checkPreferences() throws {
        try require(WritingPreferences().inkBuildup == 0.55, "Ink buildup default changed")
        let legacy = """
        {"writingFont":"americanTypewriter","fontSize":24,"inkStrength":0.73,
         "wornInk":false,"ribbon":"oxblood","paper":"cream","paperMotion":"roll",
         "paperStartPosition":"bottom","typewriterSound":"electric","soundEnabled":false,
         "soundVolume":0.17,"mechanismStyle":"walnut","nightMode":true,"lampWarmth":0.91}
        """
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
        try require(try decode(legacy) == expected, "Literal legacy record reset an existing choice")
        for (literal, value) in [("null", 0.55), ("-5", 0), ("0", 0), ("0.83", 0.83), ("8", 1)] {
            let record = "{\"inkBuildup\":\(literal),\"wornInk\":false,\"writingFont\":\"monaco\"}"
            let preferences = try decode(record)
            try require(preferences.inkBuildup == value && !preferences.wornInk
                        && preferences.writingFont == .monaco, "Buildup decoding/fallback reset saved choices")
            let saved = try JSONEncoder().encode(preferences)
            try require(try JSONDecoder().decode(WritingPreferences.self, from: saved) == preferences,
                        "Buildup does not round-trip")
        }
        for invalid in [Double.nan, .infinity, -.infinity] {
            var preferences = WritingPreferences()
            preferences.inkBuildup = invalid
            preferences.wornInk = false
            preferences.clamp()
            try require(preferences.inkBuildup == 0.55 && !preferences.wornInk,
                        "Nonfinite buildup resets the clean ink choice")
        }
        for bad in ["\"heavy\"", "true", "[]", "{}"] {
            var rejected = false
            do { _ = try decode("{\"inkBuildup\":\(bad)}") } catch { rejected = true }
            try require(rejected, "Malformed ink buildup silently accepted")
        }
        passed("legacy/null/default/clamped ink preferences and explicit zero round-trip")
    }

    static func checkFontIDs() throws {
        let choices: [(WritingFont, String)] = [
            (.courier, "courier"), (.americanTypewriter, "americanTypewriter"),
            (.menlo, "menlo"), (.georgia, "georgia"), (.courierNew, "courierNew"),
            (.typewriterLight, "typewriterLight"),
            (.typewriterCondensed, "typewriterCondensed"), (.monaco, "monaco")
        ]
        try require(Set(WritingFont.allCases) == Set(choices.map { $0.0 }), "Font catalog changed")
        for (font, identifier) in choices {
            let literal = Data("\"\(identifier)\"".utf8)
            try require(font.rawValue == identifier && font.id == identifier, "Persisted font identifier changed")
            try require(try JSONDecoder().decode(WritingFont.self, from: literal) == font,
                        "Literal font ID does not decode")
            try require(try JSONEncoder().encode(font) == literal, "Font ID does not encode")
            let record = """
            {"writingFont":"\(identifier)","fontSize":24,"inkStrength":0.73,
             "wornInk":false,"ribbon":"oxblood","typewriterSound":"electric",
             "soundEnabled":false,"soundVolume":0.17}
            """
            var expected = WritingPreferences()
            expected.writingFont = font
            expected.fontSize = 24
            expected.inkStrength = 0.73
            expected.wornInk = false
            expected.ribbon = .oxblood
            expected.typewriterSound = .electric
            expected.soundEnabled = false
            expected.soundVolume = 0.17
            let actual = try decode(record)
            try require(actual == expected, "Font preference reset ink/sound choices")
            let saved = try JSONEncoder().encode(actual)
            try require(try JSONDecoder().decode(WritingPreferences.self, from: saved) == expected,
                        "Font preference round-trip failed")
        }
        for field in ["", "\"writingFont\":null,", "\"writingFont\":\"future-font\","] {
            let record = "{\(field)\"wornInk\":false,\"inkBuildup\":0,\"soundVolume\":0}"
            var expected = WritingPreferences()
            expected.wornInk = false
            expected.inkBuildup = 0
            expected.soundVolume = 0
            try require(try decode(record) == expected, "Missing/null/future font reset explicit ink/sound values")
        }
        try require(WritingPreferences().writingFont == .courier, "Default font changed")
        passed("all eight stable font IDs, saved font records and independent fallback")
    }
}
