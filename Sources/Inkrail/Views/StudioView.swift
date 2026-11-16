import SwiftUI
import InkrailCore

@MainActor
struct StudioView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        StudioSettingsView(preferences: $model.preferences,
                           previewSound: {
                               guard model.preferences.soundEnabled, model.preferences.soundVolume > 0 else { return }
                               SoundEngine.shared.preview(style: model.preferences.typewriterSound,
                                                          volume: model.preferences.soundVolume)
                           },
                           stopSoundPreview: { SoundEngine.shared.stopPreview() },
                           close: { dismiss() },
                           storagePath: model.rootURL.path,
                           storageAvailable: model.storageAvailable,
                           storageMessage: model.storageMessage,
                           changeStorageLocation: { model.chooseStorageLocation() },
                           showStorageFolder: { model.revealStorage() })
    }
}

