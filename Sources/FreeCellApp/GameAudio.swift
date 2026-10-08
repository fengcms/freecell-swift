import AVFoundation
import Foundation
import OSLog
import FreeCellPresentation

@MainActor
final class GameAudio {
    private var music: AVAudioPlayer?
    private var effect: AVAudioPlayer?
    private let logger = Logger(subsystem: "local.fungleo.FreeCell", category: "Audio")
    init() {
        music = load("background", extension: "mp3")
        music?.numberOfLoops = -1
        music?.volume = 0.18
        effect = load("move", extension: "wav")
        effect?.volume = 0.40
    }
    private func load(_ name: String, extension type: String) -> AVAudioPlayer? {
        guard let url = GameResources.bundle.url(forResource: name, withExtension: type, subdirectory: "Audio") else {
            logger.error("Missing audio resource: \(name)"); return nil
        }
        do { let player = try AVAudioPlayer(contentsOf: url); player.prepareToPlay(); return player }
        catch { logger.error("Cannot decode audio: \(name)"); return nil }
    }
    func update(preferences: GamePreferences, active: Bool, paused: Bool) {
        if preferences.backgroundMusic && active && !paused {
            if music?.isPlaying != true { music?.play() }
        } else { music?.pause() }
        if !preferences.moveSound || !active || paused { effect?.stop() }
    }
    func playMove(preferences: GamePreferences, active: Bool, paused: Bool) {
        guard preferences.moveSound && active && !paused else { return }
        effect?.currentTime = 0
        effect?.play()
    }
}
