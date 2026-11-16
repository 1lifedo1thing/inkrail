import AVFoundation
import Foundation

// Stand in for SwiftPM's generated accessor while exercising Resources.swift
// unchanged. In packaged mode this accessor must never be reached.
extension Bundle {
    static var module: Bundle {
        precondition(CommandLine.arguments[2] == "fallback", "Packaged lookup fell back to Bundle.module")
        return Bundle(url: URL(fileURLWithPath: CommandLine.arguments[1]))!
    }
}

@main
private struct SoundCheck {
    static func main() throws {
        try checkSoundPreferences()
        let expected = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
        let bundle = InkrailResources.bundle
        precondition(bundle.bundleURL.standardizedFileURL == expected, "Resolved the wrong resource bundle")
        let available = Set((bundle.urls(forResourcesWithExtension: "wav", subdirectory: nil) ?? [])
            .map { $0.lastPathComponent })
        let expectedNames = Set(TypewriterSound.allCases.flatMap { style in
            ["key-1", "key-2", "key-3", "space", "return", "erase"].map { sample in
                "\(style == .classic ? sample : "\(style.rawValue)-\(sample)").wav"
            }
        })
        precondition(available == expectedNames, "Unexpected or missing bundled WAVs")
        var count = 0
        for style in TypewriterSound.allCases {
            for sample in ["key-1", "key-2", "key-3", "space", "return", "erase"] {
                let name = style == .classic ? sample : "\(style.rawValue)-\(sample)"
                guard let url = bundle.url(forResource: name, withExtension: "wav") else {
                    fatalError("Missing bundled sound: \(name)")
                }
                let player = try AVAudioPlayer(contentsOf: url)
                precondition(player.numberOfChannels == 1, name)
                let durations = sample == "return" ? 0.25...0.5 : 0.045...0.18
                precondition(durations.contains(player.duration), name)
                let file = try AVAudioFile(forReading: url)
                precondition(file.processingFormat.sampleRate == 44_100, name)
                let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                             frameCapacity: AVAudioFrameCount(file.length))!
                try file.read(into: buffer)
                precondition(Int64(buffer.frameLength) == file.length && file.length > 0, name)
                let values = buffer.floatChannelData![0]
                var peak: Float = 0
                for frame in 0..<Int(buffer.frameLength) {
                    precondition(values[frame].isFinite, name)
                    peak = max(peak, abs(values[frame]))
                }
                precondition(peak > 0.08 && peak < 0.90, name)
                count += 1
            }
        }
        precondition(count == 36, "Expected all six complete sound profiles")
        print("PASS \(count)/36 sounds: production \(CommandLine.arguments[2]) bundle lookup, AVAudioPlayer load, full AVAudioFile decode.")
        print("Playback and audio-device preparation were not requested; this is not a listening test.")
    }

    static func checkSoundPreferences() throws {
        let sounds: [(TypewriterSound, String)] = [
            (.classic, "classic"), (.soft, "soft"), (.crisp, "crisp"),
            (.portable, "portable"), (.office, "office"), (.electric, "electric")
        ]
        precondition(Set(TypewriterSound.allCases) == Set(sounds.map { $0.0 }), "Sound choices changed")
        for (sound, identifier) in sounds {
            precondition(sound.rawValue == identifier, "Persisted sound identifier changed")
            let literal = Data("\"\(identifier)\"".utf8)
            let decoded = try JSONDecoder().decode(TypewriterSound.self, from: literal)
            let encoded = try JSONEncoder().encode(sound)
            precondition(decoded == sound && encoded == literal, "Sound identifier does not persist")
            // A pre-expansion record for the original sounds, and the same
            // stored preference schema for the additions. No UserDefaults I/O.
            let record = """
            {"typewriterSound":"\(identifier)","soundEnabled":false,"soundVolume":0.17,
             "paper":"cream","paperMotion":"roll","paperStartPosition":"bottom",
             "paperTexture":"cotton","writingFont":"georgia","mechanismStyle":"walnut",
             "matchRailToStyle":false,"rail":"brass","nightMode":true,"lampWarmth":0.91}
            """
            let preferences = try JSONDecoder().decode(WritingPreferences.self, from: Data(record.utf8))
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
            precondition(preferences == expected, "Sound migration reset preferences: \(identifier)")
            let saved = try JSONEncoder().encode(preferences)
            let reloaded = try JSONDecoder().decode(WritingPreferences.self, from: saved)
            precondition(reloaded == expected, "Sound preference failed to round-trip: \(identifier)")
        }
        for soundField in ["", "\"typewriterSound\":null,",
                           "\"typewriterSound\":\"recorded\",",
                           "\"typewriterSound\":\"future-sound\","] {
            let record = """
            {\(soundField)"soundEnabled":false,"soundVolume":0,
             "paper":"white","writingFont":"menlo","lampWarmth":0.12}
            """
            let preferences = try JSONDecoder().decode(WritingPreferences.self, from: Data(record.utf8))
            var expected = WritingPreferences()
            expected.soundEnabled = false
            expected.soundVolume = 0
            expected.paper = .white
            expected.writingFont = .menlo
            expected.lampWarmth = 0.12
            precondition(preferences == expected, "Sound fallback reset unrelated preferences")
        }
        print("PASS six stable sound IDs, literal saved preferences, and missing/null/removed/unknown fallback; mute, volume and unrelated values preserved.")
    }
}
