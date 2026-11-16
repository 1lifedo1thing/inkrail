import Foundation

private struct DeskPreferenceFailure: Error, CustomStringConvertible {
    let description: String
}

@main
enum DeskPreferenceCheck {
    static var assertions = 0
    static var groups = 0

    static func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw DeskPreferenceFailure(description: message) }
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
        try checkLegacyPreferences()
        try checkExistingDeskPreferences()
        try checkExistingLampPreferences()
        try checkIndependentFallbacks()
        try checkStableChoices()
        try checkWidths()
        print("Passed \(groups) Foundation desk groups (\(assertions) assertions).")
        print("No user data/preferences, UI, text input or XCTest are involved.")
    }

    static func checkLegacyPreferences() throws {
        let defaults = WritingPreferences()
        try require(defaults.deskFinish == .charcoal && defaults.deskAccent == .none
                    && defaults.widerFocusPaper, "Desk defaults changed")
        // Complete literal schema from before the desk additions, never encoded
        // by the new model. Includes the recent font, ink and sound preferences.
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
        try require(try decode(record) == expected, "Legacy fields were reset by desk migration")
        passed("quiet desk defaults and complete literal legacy preference preservation")
    }

    static func checkIndependentFallbacks() throws {
        for fields in ["", "\"deskFinish\":null,\"deskAccent\":null,\"widerFocusPaper\":null,",
                       "\"deskFinish\":\"future-finish\",\"deskAccent\":\"future-accent\","] {
            let actual = try decode("{\(fields)\"paperMotion\":\"roll\",\"paperEmbossing\":\"sunburst\",\"inkBuildup\":0.82}")
            var expected = WritingPreferences()
            expected.paperMotion = .roll
            expected.paperEmbossing = .sunburst
            expected.inkBuildup = 0.82
            try require(actual == expected, "Missing/null/unknown desk fields changed paper or ink")
        }
        let selected = try decode("{\"deskFinish\":\"future\",\"deskAccent\":\"sprig\",\"widerFocusPaper\":false}")
        try require(selected.deskFinish == .charcoal && selected.deskAccent == .sprig
                    && !selected.widerFocusPaper, "Unknown finish reset accent or focus choice")
        let reverse = try decode("{\"deskFinish\":\"linen\",\"deskAccent\":\"future\",\"widerFocusPaper\":false}")
        try require(reverse.deskFinish == .linen && reverse.deskAccent == .none
                    && !reverse.widerFocusPaper, "Unknown accent reset finish or focus choice")
        for record in ["{\"deskFinish\":7}", "{\"deskAccent\":[]}",
                       "{\"widerFocusPaper\":\"yes\"}"] {
            var rejected = false
            do { _ = try decode(record) } catch { rejected = true }
            try require(rejected, "Malformed desk field was silently accepted")
        }
        passed("independent missing/null/unknown fallbacks and malformed-value rejection")
    }

    static func checkStableChoices() throws {
        let finishes = ["charcoal", "walnut", "felt", "linen", "oak", "leather"]
        let accents = ["none", "sprig", "paperclip", "envelope", "brassLamps", "linenLamps"]
        try require(DeskFinish.allCases.map(\.rawValue) == finishes, "Persisted finish IDs changed")
        try require(DeskAccent.allCases.map(\.rawValue) == accents, "Persisted accent IDs changed")
        for finish in DeskFinish.allCases {
            let literal = Data("\"\(finish.rawValue)\"".utf8)
            try require(try JSONDecoder().decode(DeskFinish.self, from: literal) == finish,
                        "Finish literal did not decode")
            try require(try JSONEncoder().encode(finish) == literal && finish.id == finish.rawValue,
                        "Finish ID did not persist")
            for accent in DeskAccent.allCases {
                let accentLiteral = Data("\"\(accent.rawValue)\"".utf8)
                try require(try JSONDecoder().decode(DeskAccent.self, from: accentLiteral) == accent,
                            "Accent literal did not decode")
                try require(try JSONEncoder().encode(accent) == accentLiteral && accent.id == accent.rawValue,
                            "Accent ID did not persist")
                for wider in [false, true] {
                    var preferences = WritingPreferences()
                    preferences.deskFinish = finish
                    preferences.deskAccent = accent
                    preferences.widerFocusPaper = wider
                    preferences.paperMotion = .roll
                    preferences.paperEmbossing = .botanical
                    preferences.inkBuildup = 0.68
                    let encoded = try JSONEncoder().encode(preferences)
                    let record = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
                    try require(record?["deskFinish"] as? String == finish.rawValue
                                && record?["deskAccent"] as? String == accent.rawValue
                                && record?["widerFocusPaper"] as? Bool == wider,
                                "Desk fields were omitted or stored under unstable names")
                    try require(try JSONDecoder().decode(WritingPreferences.self, from: encoded) == preferences,
                                "Desk combination failed to round-trip")
                }
            }
        }
        passed("stable IDs and all \(finishes.count * accents.count * 2) finish/accent/focus combinations round-trip")
    }

    static func checkExistingDeskPreferences() throws {
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
        try require(try decode(record) == expected, "Existing desk or unrelated preferences were reset by lamp additions")
        passed("literal existing desk record keeps its finish, accent, focus opt-out and unrelated preferences")
    }

    static func checkWidths() throws {
        try require(DeskLayout.paperWidth(windowWidth: 1080, focusMode: false, widerFocusPaper: true) == 720,
                    "Regular paper width changed")
        let focused = DeskLayout.paperWidth(windowWidth: 1080, focusMode: true, widerFocusPaper: true)
        try require(focused == 960 && (1080 - focused) / 2 == 60, "Focus does not leave a 60pt border")
        try require(DeskLayout.paperWidth(windowWidth: 1080, focusMode: true, widerFocusPaper: false) == 720,
                    "Disabling wider focus does not retain regular paper")
        for focus in [false, true] {
            try require(DeskLayout.paperWidth(windowWidth: 660, focusMode: focus, widerFocusPaper: true) == 556,
                        "Narrow window inset changed")
        }
        try require(DeskLayout.paperWidth(windowWidth: 3840, focusMode: true, widerFocusPaper: true) == 960,
                    "Large windows create unbounded writing lines")
        for width in stride(from: 1.0, through: 5000, by: 7) {
            let normal = DeskLayout.paperWidth(windowWidth: width, focusMode: false, widerFocusPaper: true)
            let focus = DeskLayout.paperWidth(windowWidth: width, focusMode: true, widerFocusPaper: true)
            try require(normal.isFinite && focus.isFinite && normal >= 1 && focus <= width,
                        "Paper width escaped a finite drawable viewport")
            try require(normal <= focus && normal <= 720 && focus <= 960,
                        "Focus shrinks the sheet or exceeds its cap")
            try require(DeskLayout.paperWidth(windowWidth: width, focusMode: true, widerFocusPaper: false) == normal,
                        "Wider focus off disagrees with the standard width")
        }
        for invalid in [Double.nan, .infinity, -.infinity, -200, 0, 0.5] {
            try require(DeskLayout.paperWidth(windowWidth: invalid, focusMode: true, widerFocusPaper: true) == 1,
                        "Invalid/subpoint window did not produce a safe drawable fallback")
        }
        let normalRoll = PaperRollProjection(width: 720, viewportHeight: 536)
        let focusedRoll = PaperRollProjection(width: 960, viewportHeight: 536)
        for y in stride(from: -180.0, through: 700, by: 5) {
            try require(normalRoll.projectY(y) == focusedRoll.projectY(y)
                        && normalRoll.horizontalScale(at: y) == focusedRoll.horizontalScale(at: y),
                        "Wider focus changed the roll bend or compression")
        }
        passed("720/960pt focus widths, narrow/invalid bounds and unchanged vertical roll projection")
    }

    static func checkExistingLampPreferences() throws {
        // Literal pre-leather schema, not a record emitted by today's encoder.
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
        try require(actual == expected, "Bronze lamp material or leather addition reset existing preferences")
        let saved = try JSONSerialization.jsonObject(with: JSONEncoder().encode(actual)) as? [String: Any]
        try require(saved?["deskAccent"] as? String == "brassLamps"
                    && saved?["deskFinish"] as? String == "walnut",
                    "Bronze display label changed a saved desk ID")
        passed("literal brassLamps record survives bronze material and leather addition with the original saved ID")
    }
}
