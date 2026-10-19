import PerchAppCore
import PerchCore
import Testing

@Suite struct MascotTests {
    /// The sprite part of a frame (13 × 13 at the canvas origin) as `#` body, `w` white, `o` dark, `z` faint.
    func art(_ cells: [Mascot.Cell]) -> [String] {
        var grid = Array(repeating: Array(repeating: Character("."), count: 13), count: 13)
        for cell in cells {
            let x = cell.x - 1, y = cell.y - 3
            guard (0..<13).contains(x), (0..<13).contains(y) else { continue }
            grid[y][x] = switch cell.ink { case .body: "#"; case .white: "w"; case .dark: "o"; case .faint: "z"; case .confetti0, .confetti1, .confetti2: "c" }
        }
        return grid.map { String($0) }
    }

    /// Every 0.1 s over the longest loop (4 s), plus some frame boundaries.
    let times: [Double] = (0..<42).map { Double($0) * 0.1 } + [0.25, 0.75, 3.6, 3.99]

    @Test func atRestItIsTheCyclopsFromTheIssue() {
        #expect(art(Mascot.still(.running)) == [
            "......#......",
            "......#......",
            "...#######...",
            "..#########..",
            ".####www####.",
            ".###wwwww###.",
            ".###wwoww###.",
            ".###wwwww###.",
            "#####www#####",
            "#############",
            "..###ooo###..",
            "..#########..",
            "...##...##...",
        ])
    }

    @Test func theSignalPicksTheMood() {
        #expect(Mascot.Mood(signal: .running) == .running)
        #expect(Mascot.Mood(signal: .waiting) == .waiting)
        #expect(Mascot.Mood(signal: .failed) == .failed)
        #expect(Mascot.Mood(signal: .done) == .done)
        #expect(Mascot.Mood(signal: .idle) == .idle)
        #expect(Mascot.Mood(signal: nil) == .asleep)
        #expect(Mascot.Mood(signal: .waiting, online: false) == .asleep)
    }

    @Test func everyMoodLooksDifferent() {
        let looks = Mascot.Mood.allCases.map { Mascot.still($0) }
        #expect(Set(looks).count == looks.count)
    }

    var reactions: [Mascot.Reaction] {
        [Mascot.Mood.waiting, .failed, .done].flatMap { mood in
            stride(from: 0.0, to: mood.reactionDuration!, by: 1 / Mascot.reactionFPS).map { Mascot.Reaction(mood: mood, age: $0) }
        }
    }

    var quirks: [Mascot.QuirkPlay] {
        Mascot.Quirk.allCases.flatMap { quirk in
            stride(from: 0.0, to: quirk.duration, by: 0.05).map { Mascot.QuirkPlay(quirk, age: $0) }
        }
    }

    /// Only Idle's "z" may leave the canvas, and only to the right, up to `overflowWidth`.
    @Test func everyFrameStaysOnTheCanvas() {
        var offCanvas: [String] = []
        for mood in Mascot.Mood.allCases {
            for time in times {
                let cells = Mascot.frame(mood, time: time)
                let fits = !cells.isEmpty && Set(cells.map { [$0.x, $0.y] }).count == cells.count && cells.allSatisfy {
                    (0..<Mascot.height).contains($0.y) && (0..<($0.ink == .faint ? Mascot.overflowWidth : Mascot.width)).contains($0.x)
                }
                if !fits { offCanvas.append("\(mood) t=\(time)") }
            }
        }
        #expect(offCanvas.isEmpty, "\(offCanvas.prefix(5))")
    }

    /// Reactions and quirks may use `margin` all round the canvas, no more.
    @Test func reactionsAndQuirksStayWithinTheMargin() {
        let m = Mascot.margin
        func fits(_ cells: [Mascot.Cell]) -> Bool {
            !cells.isEmpty && Set(cells.map { [$0.x, $0.y] }).count == cells.count && cells.allSatisfy {
                (-m..<(Mascot.height + m)).contains($0.y) && (-m..<(Mascot.width + m)).contains($0.x)
            }
        }
        var outside: [String] = []
        for mood in Mascot.Mood.allCases {
            for reaction in reactions where !fits(Mascot.frame(mood, time: 0.3, reaction: reaction)) {
                outside.append("\(mood) \(reaction)")
            }
            for quirk in quirks where !fits(Mascot.frame(mood, time: 0.3, quirk: quirk)) {
                outside.append("\(mood) \(quirk)")
            }
        }
        #expect(outside.isEmpty, "\(outside.prefix(5))")
    }

    /// The first beat stays timed to the chime; then each reaction has a second act.
    @Test func reactionsHaveASecondAct() {
        let exclaim = Mascot.frame(.waiting, time: 0, reaction: .init(mood: .waiting, age: 1.0))
        #expect(exclaim.contains { $0.ink == .white && $0.x == 12 && $0.y == 2 })
        #expect(!Mascot.frame(.waiting, time: 0, reaction: .init(mood: .waiting, age: 0.3)).contains { $0.x == 12 && $0.y == 2 })

        // On its side: the frown stands upright on its right, the antenna sticks out on its left, a row lower.
        let fallen = Mascot.frame(.failed, time: 0, reaction: .init(mood: .failed, age: 0.9))
        let frown = fallen.filter { $0.ink == .dark && $0.x > 10 }
        #expect(Set(frown.map(\.x)).count == 2 && frown.count == 5)
        #expect(fallen.contains { $0.ink == .body && $0.x == 2 && $0.y == 10 })
        #expect(Mascot.frame(.failed, time: 0, reaction: .init(mood: .failed, age: 1.4)) != Mascot.still(.failed))
        #expect(Mascot.frame(.failed, time: 0, reaction: .init(mood: .failed, age: 1.0)).contains { $0.ink == .faint })
        #expect(Mascot.frame(.failed, time: 0, reaction: .init(mood: .failed, age: 0.3)).allSatisfy { $0.ink != .faint })

        let confetti: Set<Mascot.Ink> = [.confetti0, .confetti1, .confetti2]
        #expect(Mascot.frame(.done, time: 0, reaction: .init(mood: .done, age: 0.9)).contains { confetti.contains($0.ink) })
        #expect(!Mascot.frame(.done, time: 0, reaction: .init(mood: .done, age: 0.3)).contains { confetti.contains($0.ink) })
    }

    @Test func quirksComeOncePerPeriodAtScrambledMomentsAndKinds() {
        var kinds = Set<Mascot.Quirk>(), offsets = Set<Int>()
        var time = 0.0
        for _ in 0..<60 {
            let next = Mascot.nextQuirk(after: time)
            #expect(next.start > time)
            #expect(next.start - time <= 2 * Mascot.quirkPeriod)
            kinds.insert(next.quirk)
            offsets.insert(Int(next.start.truncatingRemainder(dividingBy: Mascot.quirkPeriod)))
            time = next.start + next.quirk.duration
        }
        #expect(kinds == Set(Mascot.Quirk.allCases))
        #expect(offsets.count > 20)
        // A quirk always ends before the next one starts.
        let first = Mascot.nextQuirk(after: 1_000_000)
        #expect(Mascot.nextQuirk(after: first.start).start - first.start > first.quirk.duration)
    }

    @Test func quirksPlayOnlyAsleepOrIdleThenItSleepsAgain() {
        for quirk in Mascot.Quirk.allCases {
            let mid = Mascot.QuirkPlay(quirk, age: 1.0)
            #expect(Mascot.frame(.asleep, time: 0, quirk: mid) != Mascot.frame(.asleep, time: 0), "\(quirk)")
            #expect(Mascot.frame(.idle, time: 0.5, quirk: mid) != Mascot.frame(.idle, time: 0.5), "\(quirk)")
            #expect(Mascot.frame(.running, time: 0.5, quirk: mid) == Mascot.frame(.running, time: 0.5), "\(quirk)")
            #expect(Mascot.frame(.done, time: 0, quirk: mid) == Mascot.frame(.done, time: 0), "\(quirk)")
            let over = Mascot.QuirkPlay(quirk, age: quirk.duration)
            #expect(over.isOver)
            #expect(Mascot.frame(.asleep, time: 0, quirk: over) == Mascot.frame(.asleep, time: 0))
        }
        // A reaction wins over a quirk.
        let reacting = Mascot.frame(.idle, time: 0, reaction: .init(mood: .done, age: 0.1), quirk: .init(.yawn, age: 1))
        #expect(reacting == Mascot.frame(.idle, time: 0, reaction: .init(mood: .done, age: 0.1)))
    }

    @Test func stillMoodsHaveOneFrameAndNeverRedraw() {
        for mood in [Mascot.Mood.failed, .done, .asleep] {
            #expect(mood.fps == 0)
            #expect(Set(times.map { Mascot.frame(mood, time: $0) }).count == 1, "\(mood)")
        }
        for mood in [Mascot.Mood.running, .waiting, .idle] {
            #expect(mood.fps > 0)
            #expect(Set(times.map { Mascot.frame(mood, time: $0) }).count > 1, "\(mood)")
        }
    }

    /// Running trots (feet, hop), scans with its pupil and blinks.
    @Test func runningTrotsAndLooksAround() {
        let rest = Mascot.frame(.running, time: 0.5), hop = Mascot.frame(.running, time: 0.3)
        #expect(hop.map(\.y).min()! < rest.map(\.y).min()!)
        #expect(art(Mascot.frame(.running, time: 0.85))[6] == ".###wwwow###.")
        #expect(art(Mascot.frame(.running, time: 2.5))[6] == ".###wowww###.")
        #expect(art(Mascot.frame(.running, time: 3.65))[6] == ".####ooo####.")
    }

    /// Redrawn at 5 fps (or a little slower: the display rounds the interval up to its refresh), Running must catch
    /// a blink every 4 s cycle whatever the sampling phase, or it may never blink at all.
    @Test func runningBlinksWhateverTheFramePhase() {
        for interval in [1 / Mascot.Mood.running.fps, 13.0 / 60, 25.0 / 120] {
            for phase in stride(from: 0.0, to: interval, by: 0.005) {
                let samples = stride(from: phase, to: 4, by: interval)
                // The open eye is white; a blink is the only frame without white.
                let blinked = samples.contains { !Mascot.frame(.running, time: $0).contains { $0.ink == .white } }
                #expect(blinked, "interval \(interval), phase \(phase)")
            }
        }
    }

    /// Needs you waves one arm, then the other, and flashes its antenna tip.
    @Test func needsYouWavesAndFlashes() {
        let a = art(Mascot.frame(.waiting, time: 0.1)), b = art(Mascot.frame(.waiting, time: 0.3))
        #expect(a[4].last == "#" && a[4].first == ".")
        #expect(b[4].first == "#" && b[4].last == ".")
        #expect(art(Mascot.frame(.waiting, time: 0.1))[0] == "......#......")
        #expect(art(Mascot.frame(.waiting, time: 0.6))[0] == "......w......")
    }

    @Test func idleZDriftsUp() {
        let zTops = (0..<3).map { step in
            Mascot.frame(.idle, time: Double(step) + 0.5).filter { $0.ink == .faint }.map(\.y).min()!
        }
        #expect(zTops[0] > zTops[1] && zTops[1] > zTops[2])
        #expect(Mascot.frame(.idle, time: 3.5) == Mascot.frame(.idle, time: 0.5))
        #expect(Mascot.frame(.asleep, time: 0.5).allSatisfy { $0.ink != .faint })
    }

    @Test func onlyNeedsYouFailedAndDoneReact() {
        #expect(Mascot.Mood.allCases.filter { $0.reactionDuration != nil } == [.waiting, .failed, .done])
    }

    @Test func aReactionMovesThenEnds() {
        for mood in [Mascot.Mood.waiting, .failed, .done] {
            let duration = mood.reactionDuration!
            let early = Mascot.frame(mood, time: 0, reaction: .init(mood: mood, age: 0.05))
            #expect(early != Mascot.frame(mood, time: 0), "\(mood)")
            let over = Mascot.Reaction(mood: mood, age: duration)
            #expect(over.isOver)
            #expect(Mascot.frame(mood, time: 0, reaction: over) == Mascot.frame(mood, time: 0), "\(mood)")
        }
    }

    /// A session finishing while another needs you hops in Done's look, then goes back.
    @Test func aReactionPlaysItsOwnMood() {
        let reacting = Mascot.frame(.waiting, time: 0, reaction: .init(mood: .done, age: 0.05))
        #expect(art(reacting) != art(Mascot.frame(.waiting, time: 0)))
        #expect(Set(reacting.map(\.ink)).contains(.white))
        let doneEye = art(Mascot.frame(.done, time: 0, reaction: .init(mood: .done, age: 0.05)))
        #expect(art(reacting) == doneEye)
        #expect(Mascot.frame(.waiting, time: 0, reaction: .init(mood: .done, age: 2)) == Mascot.frame(.waiting, time: 0))
    }

    @Test func reducedMotionIsTheFirstFrame() {
        for mood in Mascot.Mood.allCases {
            #expect(Mascot.still(mood) == Mascot.frame(mood, time: 0, reaction: nil))
        }
    }
}
