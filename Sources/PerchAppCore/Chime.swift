import Foundation
import PerchCore

/// The mascot's voice (#35): a short sound when a panel session enters Needs you, Failed or Done, the same changes
/// that pulse the notch (`Panel.pulses`). The clips are synthesized by scripts/sound/make-sounds.swift and timed to
/// the mascot's entry reactions.
public enum ChimeSound: String, CaseIterable, Hashable, Sendable {
    /// "Mrrp? Mrrp?"
    case needsYou
    /// "Uh-oh… bzzt"
    case failed
    /// "Bwip! hehe"
    case done

    public init?(status: SessionStatus) {
        switch status {
        case .waiting: self = .needsYou
        case .failed: self = .failed
        case .done: self = .done
        case .running, .idle: return nil
        }
    }

    /// Which sound wins when several come together.
    public var urgency: Int {
        switch self {
        case .needsYou: return 3
        case .failed: return 2
        case .done: return 1
        }
    }

    /// The clip in the bundle's Resources/Sounds (packaging/sounds in the repo).
    public var resourceName: String {
        switch self {
        case .needsYou: return "needs-you"
        case .failed: return "failed"
        case .done: return "done"
        }
    }

    /// A system sound for builds without the bundle (`swift run PerchApp`).
    public var systemFallback: String {
        switch self {
        case .needsYou: return "Glass"
        case .failed: return "Basso"
        case .done: return "Tink"
        }
    }

    /// The menu's name for it, as the notch names the state.
    public var title: String {
        switch self {
        case .needsYou: return SessionStatus.waiting.label
        case .failed: return SessionStatus.failed.label
        case .done: return SessionStatus.done.label
        }
    }

    var defaultsKey: String {
        switch self {
        case .needsYou: return "ChimeNeedsYou"
        case .failed: return "ChimeFailed"
        case .done: return "ChimeDone"
        }
    }
}

/// Whether and what the notch plays. Kept in the app's user defaults (`defaults write dev.perch.app ChimeDone -bool false`).
public struct ChimeSettings: Equatable, Sendable {
    /// The master switch ("Play Sounds").
    public var enabled: Bool
    /// The states that play, when enabled.
    public var sounds: Set<ChimeSound>
    /// 0…1. `defaults write` only.
    public var volume: Float

    public init(enabled: Bool = true, sounds: Set<ChimeSound> = Set(ChimeSound.allCases), volume: Float = 0.6) {
        self.enabled = enabled
        self.sounds = sounds
        self.volume = volume
    }

    static let enabledKey = "Chimes"
    static let volumeKey = "ChimeVolume"

    /// Missing keys take the defaults: everything on, volume 0.6.
    public init(defaults: UserDefaults) {
        let fallback = ChimeSettings()
        enabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? fallback.enabled
        sounds = Set(ChimeSound.allCases.filter { defaults.object(forKey: $0.defaultsKey) as? Bool ?? true })
        let volume = defaults.object(forKey: Self.volumeKey) as? Double ?? Double(fallback.volume)
        self.volume = Float(min(max(volume, 0), 1))
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(enabled, forKey: Self.enabledKey)
        for sound in ChimeSound.allCases { defaults.set(sounds.contains(sound), forKey: sound.defaultsKey) }
        defaults.set(Double(volume), forKey: Self.volumeKey)
    }

    public func plays(_ sound: ChimeSound) -> Bool { enabled && sounds.contains(sound) }

    public mutating func set(_ sound: ChimeSound, on: Bool) {
        if on { sounds.insert(sound) } else { sounds.remove(sound) }
    }
}

/// Decides, per session change, whether to play and what. Sounds play at once; it never waits to coalesce.
public struct Chime {
    /// Within this long after a sound, only a strictly more urgent one plays: three agents finishing together make
    /// one sound.
    public static let coalesce: TimeInterval = 1
    /// The same sound for the same session plays at most once this often (a session flapping waiting ↔ running).
    public static let cooldown: TimeInterval = 10

    public var settings: ChimeSettings
    private var last: (sound: ChimeSound, at: Date)?
    private var played: [String: Date] = [:]

    public init(settings: ChimeSettings = ChimeSettings()) {
        self.settings = settings
    }

    /// The sound for a session going from `before` to `after` (nil = removed), or nil to stay quiet.
    public mutating func sound(from before: Session?, to after: Session?, now: Date) -> ChimeSound? {
        guard Panel.pulses(from: before, to: after), let after, let sound = ChimeSound(status: after.status),
              settings.plays(sound) else { return nil }
        if let last, now.timeIntervalSince(last.at) < Self.coalesce, sound.urgency <= last.sound.urgency { return nil }
        let key = "\(after.id)\u{0}\(sound.rawValue)"
        if let at = played[key], now.timeIntervalSince(at) < Self.cooldown { return nil }
        played = played.filter { now.timeIntervalSince($0.value) < Self.cooldown }
        played[key] = now
        last = (sound, now)
        return sound
    }
}
