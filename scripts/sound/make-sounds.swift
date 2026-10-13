import Foundation

// Perch's chimes (#35): the notch mascot's voice, synthesized like a chiptune so there is no recorded or licensed audio.
// One clip per state the notch pulses for, timed to the mascot's entry reaction (`Mascot.Mood.reactionDuration`):
//   needs-you.wav  "Mrrp? Mrrp?"    two rolled-r chirps gliding up, one per hop (0.7 s)
//   failed.wav     "Uh-oh… bzzt"    two falling wobbly notes, then the bent antenna fizzling (0.5 s)
//   done.wav       "Bwip! hehe ✨"  a hop slide, a two-blip giggle, a sparkle ping (0.6 s)
// scripts/sound/make-sounds.sh writes them to packaging/sounds/; commit the .wav files.
// usage: swift make-sounds.swift <out dir>
let out = URL(fileURLWithPath: CommandLine.arguments[1])
let rate = 44_100.0

/// One sound being built: mono samples in -1…1, voices mixed in at a time offset.
struct Clip {
    var samples: [Double]

    init(seconds: Double) { samples = Array(repeating: 0, count: Int(seconds * rate)) }

    /// The monster's voice: a narrow pulse wave (nasal, "chiptune") whose pitch follows `pitch(t)` and loudness
    /// `level(t)`, `t` running 0…1 over the note. Attack and release ramps keep it from clicking.
    mutating func voice(at start: Double, length: Double, duty: Double = 0.25, gain: Double = 1,
                        pitch: (Double) -> Double, level: (Double) -> Double = { _ in 1 }) {
        let first = Int(start * rate), count = Int(length * rate)
        var phase = 0.0
        for i in 0..<count where first + i < samples.count {
            let t = Double(i) / Double(count)
            phase = (phase + pitch(t) / rate).truncatingRemainder(dividingBy: 1)
            let wave = phase < duty ? 1.0 : -1.0
            samples[first + i] += wave * gain * level(t) * ramp(i, count)
        }
    }

    /// A sine ping that rings out: the sparkle.
    mutating func ping(at start: Double, length: Double, frequency: Double, gain: Double) {
        let first = Int(start * rate), count = Int(length * rate)
        for i in 0..<count where first + i < samples.count {
            let t = Double(i) / Double(count)
            samples[first + i] += sin(2 * .pi * frequency * Double(i) / rate) * gain * pow(1 - t, 3) * ramp(i, count)
        }
    }

    /// Sample-and-hold noise, chopped: the antenna shorting out.
    mutating func fizzle(at start: Double, length: Double, gain: Double) {
        let first = Int(start * rate), count = Int(length * rate)
        var seed: UInt32 = 0x9E37_79B9  // fixed, so regenerating gives the same files
        var held = 0.0
        let hold = Int(rate / 3_000)
        for i in 0..<count where first + i < samples.count {
            if i % hold == 0 {
                seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
                held = Double(seed) / Double(UInt32.max) * 2 - 1
            }
            let t = Double(i) / Double(count)
            let chop = sin(2 * .pi * 45 * Double(i) / rate) > -0.2 ? 1.0 : 0.15
            samples[first + i] += held * gain * chop * (1 - t) * ramp(i, count)
        }
    }

    /// 4 ms in, 25 ms out.
    func ramp(_ i: Int, _ count: Int) -> Double {
        let attack = 0.004 * rate, release = 0.025 * rate
        return min(1, Double(i) / attack, Double(count - i) / release)
    }

    /// Softens the pulse wave's edges (one-pole low-pass), then scales the peak to `peak`.
    func mastered(cutoff: Double = 4_500, peak: Double = 0.7) -> [Double] {
        let a = exp(-2 * .pi * cutoff / rate)
        var y = 0.0
        let soft = samples.map { x -> Double in
            y = (1 - a) * x + a * y
            return y
        }
        let top = soft.map(abs).max() ?? 1
        return soft.map { $0 / max(top, 1e-9) * peak }
    }
}

/// Glides from `a` to `b` easing out, like a voice.
func glide(_ a: Double, _ b: Double) -> (Double) -> Double {
    { t in a + (b - a) * (1 - pow(1 - t, 2)) }
}

/// The rolled "r" at the start of a chirp: loudness fluttering at `rate` Hz for the first `until` of the note.
func trill(rate: Double, until: Double, length: Double) -> (Double) -> Double {
    { t in t < until ? 0.55 + 0.45 * sin(2 * .pi * rate * t * length) : 1 }
}

func wav(_ samples: [Double]) -> Data {
    var data = Data()
    func le<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    let bytes = UInt32(samples.count * 2)
    data.append(contentsOf: Array("RIFF".utf8)); le(36 + bytes)
    data.append(contentsOf: Array("WAVEfmt ".utf8)); le(UInt32(16)); le(UInt16(1)); le(UInt16(1))
    le(UInt32(rate)); le(UInt32(rate) * 2); le(UInt16(2)); le(UInt16(16))
    data.append(contentsOf: Array("data".utf8)); le(bytes)
    for s in samples { le(Int16((max(-1, min(1, s)) * 32_767).rounded())) }
    return data
}

// Needs you — "Mrrp? Mrrp?": the second chirp a bit higher, asking again.
var needsYou = Clip(seconds: 0.7)
for (start, from, to) in [(0.0, 470.0, 840.0), (0.30, 560.0, 1_050.0)] {
    let length = 0.22
    needsYou.voice(at: start, length: length, pitch: glide(from, to), level: trill(rate: 34, until: 0.45, length: length))
    needsYou.voice(at: start, length: length, duty: 0.5, gain: 0.25, pitch: { glide(from, to)($0) / 2 })
}

// Failed — "Uh-oh… bzzt": "uh" steady, "oh" sagging with a wobble, then the antenna fizzles out.
var failed = Clip(seconds: 0.5)
failed.voice(at: 0, length: 0.12, duty: 0.35, pitch: { _ in 392 })
failed.voice(at: 0.13, length: 0.24, duty: 0.35, pitch: { t in glide(330, 185)(t) * (1 + 0.04 * sin(2 * .pi * 9 * t * 0.24)) })
failed.voice(at: 0.13, length: 0.24, duty: 0.5, gain: 0.3, pitch: { glide(330, 185)($0) / 2 })
failed.fizzle(at: 0.37, length: 0.12, gain: 0.45)

// Done — "Bwip! hehe ✨": the hop slides up, two giggle blips, a sparkle rings over the top.
var done = Clip(seconds: 0.6)
done.voice(at: 0, length: 0.11, duty: 0.25, pitch: glide(420, 1_000))
done.voice(at: 0.14, length: 0.065, duty: 0.25, pitch: { _ in 1_175 })
done.voice(at: 0.23, length: 0.065, duty: 0.25, pitch: { _ in 1_047 })
done.ping(at: 0.30, length: 0.30, frequency: 2_637, gain: 0.5)
done.ping(at: 0.36, length: 0.24, frequency: 3_520, gain: 0.3)

try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for (name, clip) in [("needs-you", needsYou), ("failed", failed), ("done", done)] {
    try wav(clip.mastered()).write(to: out.appendingPathComponent("\(name).wav"))
    print(out.appendingPathComponent("\(name).wav").path)
}
