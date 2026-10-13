import Foundation
import PerchAppCore
import PerchCore
import Testing

@Suite struct ChimeTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func session(_ status: SessionStatus, id: String = "s1", source: String = "claude-code") -> Session {
        var s = Session(id: id, source: source, title: id, startedAt: t0)
        s.status = status
        return s
    }

    @Test func eachPulsingStateHasItsSound() {
        #expect(ChimeSound(status: .waiting) == .needsYou)
        #expect(ChimeSound(status: .failed) == .failed)
        #expect(ChimeSound(status: .done) == .done)
        #expect(ChimeSound(status: .running) == nil)
        #expect(ChimeSound(status: .idle) == nil)
        #expect(ChimeSound.needsYou.urgency > ChimeSound.failed.urgency)
        #expect(ChimeSound.failed.urgency > ChimeSound.done.urgency)
    }

    @Test func enteringNeedsYouFailedOrDonePlays() {
        for (status, sound) in [(SessionStatus.waiting, ChimeSound.needsYou), (.failed, .failed), (.done, .done)] {
            var chime = Chime()
            #expect(chime.sound(from: session(.running), to: session(status), now: t0) == sound)
        }
        var chime = Chime()
        #expect(chime.sound(from: nil, to: session(.waiting), now: t0) == .needsYou)
    }

    @Test func runningIdleRemovedHiddenAndUnchangedAreSilent() {
        var chime = Chime()
        #expect(chime.sound(from: session(.waiting), to: session(.running), now: t0) == nil)
        #expect(chime.sound(from: session(.done), to: session(.idle), now: t0) == nil)
        #expect(chime.sound(from: session(.running), to: nil, now: t0) == nil)
        #expect(chime.sound(from: nil, to: session(.waiting, source: "hermes"), now: t0) == nil)
        #expect(chime.sound(from: session(.waiting), to: session(.waiting), now: t0) == nil)
    }

    @Test func theMasterSwitchAndEachStateCanBeTurnedOff() {
        var off = Chime(settings: ChimeSettings(enabled: false))
        #expect(off.sound(from: nil, to: session(.waiting), now: t0) == nil)

        var noDone = Chime(settings: ChimeSettings(sounds: [.needsYou, .failed]))
        #expect(noDone.sound(from: nil, to: session(.done, id: "a"), now: t0) == nil)
        #expect(noDone.sound(from: nil, to: session(.failed, id: "b"), now: t0) == .failed)
    }

    @Test func soundsCloseTogetherCoalesceKeepingTheMoreUrgent() {
        var chime = Chime()
        #expect(chime.sound(from: nil, to: session(.done, id: "a"), now: t0) == .done)
        // Another finish half a second later: already heard one.
        #expect(chime.sound(from: nil, to: session(.done, id: "b"), now: t0 + 0.5) == nil)
        // Something more urgent still gets through, and then sets the bar.
        #expect(chime.sound(from: nil, to: session(.waiting, id: "c"), now: t0 + 0.6) == .needsYou)
        #expect(chime.sound(from: nil, to: session(.failed, id: "d"), now: t0 + 0.9) == nil)
        // Past the window, anything plays again.
        #expect(chime.sound(from: nil, to: session(.done, id: "e"), now: t0 + 1.7) == .done)
    }

    @Test func aFlappingSessionPlaysOncePerCooldown() {
        var chime = Chime()
        #expect(chime.sound(from: session(.running), to: session(.waiting), now: t0) == .needsYou)
        #expect(chime.sound(from: session(.running), to: session(.waiting), now: t0 + 5) == nil)
        // A different sound for the same session isn't held back.
        #expect(chime.sound(from: session(.running), to: session(.done), now: t0 + 6) == .done)
        #expect(chime.sound(from: session(.running), to: session(.waiting), now: t0 + 10.5) == .needsYou)
    }

    @Test func settingsRoundTripThroughUserDefaults() throws {
        let suite = "perch-chime-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(ChimeSettings(defaults: defaults) == ChimeSettings())

        let changed = ChimeSettings(enabled: false, sounds: [.failed], volume: 0.3)
        changed.save(to: defaults)
        #expect(ChimeSettings(defaults: defaults) == changed)
        #expect(defaults.bool(forKey: "ChimeNeedsYou") == false)
        #expect(defaults.bool(forKey: "ChimeFailed") == true)
    }

    @Test func settingsToggleOneSound() {
        var settings = ChimeSettings()
        settings.set(.done, on: false)
        #expect(!settings.plays(.done))
        #expect(settings.plays(.needsYou))
        settings.enabled = false
        #expect(!settings.plays(.needsYou))
    }
}
