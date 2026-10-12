import AppKit
import PerchAppCore

/// Plays the mascot's chimes (#35): the clips bundled in Contents/Resources/Sounds (packaging/sounds), or a system
/// sound when there is no bundle (`swift run PerchApp`).
@MainActor
final class ChimePlayer {
    private var sounds: [ChimeSound: NSSound] = [:]

    init() {
        for sound in ChimeSound.allCases { sounds[sound] = Self.load(sound) }
    }

    func play(_ sound: ChimeSound, volume: Float) {
        guard let player = sounds[sound] else { return }
        player.stop()  // a new chime cuts the same one short instead of being dropped
        player.volume = volume
        player.play()
    }

    private static func load(_ sound: ChimeSound) -> NSSound? {
        if let url = Bundle.main.url(forResource: sound.resourceName, withExtension: "wav", subdirectory: "Sounds"),
           let clip = NSSound(contentsOf: url, byReference: true) {
            return clip
        }
        return NSSound(named: sound.systemFallback)?.copy() as? NSSound
    }
}
