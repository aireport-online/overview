import AVFoundation

enum SoundEffect: String, CaseIterable {
    case scanStart = "scan-start"
    case scanComplete = "scan-complete"
    case zoomIn = "zoom-in"
    case zoomOut = "zoom-out"
    case select
    case trash
}

/// Plays the short interface sounds. Silent when sounds are switched off in
/// the app, or when "Play user interface sound effects" is off in System
/// Settings.
@MainActor
final class SoundPlayer {
    static let shared = SoundPlayer()

    private var players: [SoundEffect: AVAudioPlayer] = [:]

    private init() {
        for effect in SoundEffect.allCases {
            guard let url = Assets.url(effect.rawValue, "wav", subdirectory: "Sounds"),
                  let player = try? AVAudioPlayer(contentsOf: url)
            else { continue }
            player.prepareToPlay()
            players[effect] = player
        }
    }

    /// The sounds that were found in the app bundle.
    var loaded: [SoundEffect] {
        SoundEffect.allCases.filter { players[$0] != nil }
    }

    func play(_ effect: SoundEffect, volume: Float = 0.6) {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "soundEnabled") as? Bool ?? true,
              defaults.object(forKey: "com.apple.sound.uiaudio.enabled") as? Bool ?? true,
              let player = players[effect]
        else { return }
        player.volume = volume
        player.currentTime = 0
        player.play()
    }
}
