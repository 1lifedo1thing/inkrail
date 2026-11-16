import AVFoundation
import Foundation
import InkrailCore

enum StrokeKind { case key, space, carriage, erase }

/// Original synthesized samples, loaded only when a sound style is needed.
/// At most six banks of six samples × five voices are retained. Preview
/// players are separate, bounded to four, and never start without a request.
/// No microphone, runtime downloads, or continuous audio engine.
@MainActor
final class SoundEngine {
    static let shared = SoundEngine()
    private static let sampleNames = ["key-1", "key-2", "key-3", "space", "return", "erase"]
    private final class VoiceBank {
        var voices: [String: [AVAudioPlayer]] = [:]
        var offsets: [String: Int] = [:]
    }
    private var banks: [TypewriterSound: VoiceBank] = [:]
    private var previewPlayers: [AVAudioPlayer] = []
    private var previewTask: Task<Void, Never>?
    private var previewGeneration: UInt = 0

    /// Preparing a style never plays audio. Classic keeps the original filenames.
    @discardableResult
    func prepare(style: TypewriterSound = .classic) -> Bool {
        if let bank = banks[style] { return bank.voices.count == Self.sampleNames.count }
        let bank = VoiceBank()
        for name in Self.sampleNames {
            let pool = (0..<5).compactMap { _ in makePlayer(sample: name, style: style) }
            if !pool.isEmpty { bank.voices[name] = pool }
        }
        banks[style] = bank
        return bank.voices.count == Self.sampleNames.count
    }

    /// The caller gates typing sounds with the user's soundEnabled preference.
    /// New typing also ends an unfinished settings preview.
    @discardableResult
    func play(_ kind: StrokeKind, volume: Double, style: TypewriterSound = .classic) -> Bool {
        stopPreview()
        let gain = safeVolume(volume)
        guard gain > 0 else { return false }
        prepare(style: style)
        guard let bank = banks[style] else { return false }
        let name: String
        switch kind {
        case .key: name = "key-\(Int.random(in: 1...3))"
        case .space: name = "space"
        case .carriage: name = "return"
        case .erase: name = "erase"
        }
        guard let pool = bank.voices[name], !pool.isEmpty else { return false }
        let index = (bank.offsets[name] ?? 0) % pool.count
        bank.offsets[name] = (index + 1) % pool.count
        let player = pool[index]
        player.currentTime = 0
        player.volume = gain
        return player.play()
    }

    /// Explicit, short key/key/space/return preview at the requested volume.
    /// The UI must gate this with soundEnabled and call stopAll on mute/style
    /// changes. Dismissing settings calls stopPreview. Cancellation and a
    /// generation check prevent a sleeping task from starting another sample.
    @discardableResult
    func preview(style: TypewriterSound, volume: Double) -> Bool {
        stopPreview()
        let gain = safeVolume(volume)
        guard gain > 0 else { return false }
        for name in ["key-1", "key-2", "space", "return"] {
            guard let player = makePlayer(sample: name, style: style) else {
                stopPreview()
                return false
            }
            player.volume = gain
            previewPlayers.append(player)
        }
        let generation = previewGeneration
        previewTask = Task { @MainActor [weak self] in
            // Intervals, not repeating timers. The whole preview lasts < 1.2s.
            for (index, delay) in [UInt64(0), 120_000_000, 170_000_000, 240_000_000].enumerated() {
                if delay > 0 {
                    do { try await Task.sleep(nanoseconds: delay) } catch { return }
                }
                guard !Task.isCancelled, let self,
                      self.previewGeneration == generation,
                      self.previewPlayers.indices.contains(index) else { return }
                self.previewPlayers[index].play()
            }
            do { try await Task.sleep(nanoseconds: 600_000_000) } catch { return }
            guard !Task.isCancelled, let self, self.previewGeneration == generation else { return }
            self.previewPlayers.removeAll()
            self.previewTask = nil
        }
        return true
    }

    func stopPreview() {
        previewGeneration &+= 1
        previewTask?.cancel()
        previewTask = nil
        for player in previewPlayers { player.stop() }
        previewPlayers.removeAll()
    }

    /// Use on mute or style changes to stop both preview and existing tails.
    func stopAll() {
        stopPreview()
        for bank in banks.values {
            for pool in bank.voices.values {
                for player in pool {
                    player.stop()
                    player.currentTime = 0
                }
            }
        }
    }

    private func safeVolume(_ volume: Double) -> Float {
        Float(volume.isFinite ? min(1, max(0, volume)) : 0)
    }

    private func makePlayer(sample: String, style: TypewriterSound) -> AVAudioPlayer? {
        let resource = style == .classic ? sample : "\(style.rawValue)-\(sample)"
        guard let url = InkrailResources.bundle.url(forResource: resource, withExtension: "wav"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.prepareToPlay()
        return player
    }
}
