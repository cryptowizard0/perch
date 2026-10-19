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

    /// A region of the canvas (and the margin around it), same letters as `art`.
    func art(_ cells: [Mascot.Cell], x: Range<Int>, y: Range<Int>) -> [String] {
        var grid = Array(repeating: Array(repeating: Character("."), count: x.count), count: y.count)
        for cell in cells where x.contains(cell.x) && y.contains(cell.y) {
            grid[cell.y - y.lowerBound][cell.x - x.lowerBound] = switch cell.ink { case .body: "#"; case .white: "w"; case .dark: "o"; case .faint: "z"; case .confetti0, .confetti1, .confetti2: "c" }
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
        for mood in [Mascot.Mood.idle, .asleep, .failed, .done] {
            var kinds = Set<Mascot.Quirk>(), offsets = Set<Int>()
            var time = 0.0
            for _ in 0..<60 {
                let next = Mascot.nextQuirk(after: time, in: mood)!
                #expect(next.start > time)
                #expect(next.start - time <= 2 * Mascot.quirkPeriod)
                kinds.insert(next.quirk)
                offsets.insert(Int(next.start.truncatingRemainder(dividingBy: Mascot.quirkPeriod)))
                time = next.start + next.quirk.duration
            }
            #expect(kinds == Set(mood.quirks), "\(mood)")
            #expect(offsets.count > 20, "\(mood)")
            // A quirk always ends before the next one starts.
            let first = Mascot.nextQuirk(after: 1_000_000, in: mood)!
            #expect(Mascot.nextQuirk(after: first.start, in: mood)!.start - first.start > first.quirk.duration, "\(mood)")
        }
    }

    /// Each mood draws from its own set, at the same moments; Running and Needs you have none.
    @Test func eachMoodHasItsOwnQuirks() {
        #expect(Mascot.Mood.idle.quirks == [.yawn, .lookAround, .bubble])
        #expect(Mascot.Mood.asleep.quirks == [.yawn, .lookAround, .bubble])
        #expect(Mascot.Mood.failed.quirks == [.sigh, .rubHead])
        #expect(Mascot.Mood.done.quirks == [.sway, .hum])
        #expect(Mascot.Mood.running.quirks.isEmpty && Mascot.Mood.waiting.quirks.isEmpty)
        #expect(Set(Mascot.Mood.allCases.flatMap(\.quirks)) == Set(Mascot.Quirk.allCases))
        #expect(Mascot.nextQuirk(after: 0, in: .running) == nil && Mascot.nextQuirk(after: 0, in: .waiting) == nil)
        for time in stride(from: 0.0, to: 50 * Mascot.quirkPeriod, by: 97) {
            let idle = Mascot.nextQuirk(after: time, in: .idle)!
            #expect(Mascot.nextQuirk(after: time, in: .failed)!.start == idle.start)
            #expect(Mascot.nextQuirk(after: time, in: .done)!.start == idle.start)
            #expect(Mascot.nextQuirk(after: time, in: .asleep)! == idle)
        }
    }

    /// Idle and asleep keep the schedule they had before Failed and Done got quirks (#59): these are main's.
    @Test func idleQuirksAreUnchanged() {
        var time = 812_000_000.0, played: [String] = []
        for _ in 0..<6 {
            let next = Mascot.nextQuirk(after: time, in: .idle)!
            played.append("\(next.quirk) \(Int(next.start))")
            time = next.start
        }
        #expect(played == [
            "yawn 812000014", "bubble 812000251", "lookAround 812000487",
            "bubble 812000672", "yawn 812000909", "lookAround 812001274",
        ])
    }

    @Test func quirksPlayOnlyInTheirMoodThenItGoesBack() {
        for mood in Mascot.Mood.allCases {
            for quirk in Mascot.Quirk.allCases {
                let mid = Mascot.QuirkPlay(quirk, age: 1.0)
                let time = mood == .idle ? 0.5 : 0
                if mood.quirks.contains(quirk) {
                    #expect(Mascot.frame(mood, time: time, quirk: mid) != Mascot.frame(mood, time: time), "\(mood) \(quirk)")
                } else {
                    #expect(Mascot.frame(mood, time: time, quirk: mid) == Mascot.frame(mood, time: time), "\(mood) \(quirk)")
                }
                let over = Mascot.QuirkPlay(quirk, age: quirk.duration)
                #expect(over.isOver)
                #expect(Mascot.frame(mood, time: 0, quirk: over) == Mascot.frame(mood, time: 0))
            }
        }
        // A reaction wins over a quirk.
        let reacting = Mascot.frame(.idle, time: 0, reaction: .init(mood: .done, age: 0.1), quirk: .init(.yawn, age: 1))
        #expect(reacting == Mascot.frame(.idle, time: 0, reaction: .init(mood: .done, age: 0.1)))
        let failing = Mascot.frame(.failed, time: 0, reaction: .init(mood: .failed, age: 0.9), quirk: .init(.sigh, age: 1))
        #expect(failing == Mascot.frame(.failed, time: 0, reaction: .init(mood: .failed, age: 0.9)))
    }

    /// Failed's sigh: sunk a point, the antenna flopped right over, a wisp of smoke off its tip.
    @Test func failedSighs() {
        #expect(art(Mascot.frame(.failed, time: 0, quirk: .init(.sigh, age: 1.2)), x: 0..<15, y: 1..<17) == [
            "...............",
            "...........z...",
            "..........z....",
            "...............",
            "........##.....",
            "....#######....",
            "...#########...",
            "..####www####..",
            "..###wowow###..",
            "..###wwoww###..",
            "..###wowow###..",
            ".#####www#####.",
            ".#############.",
            "...###ooo###...",
            "...##o###o##...",
            "....##...##....",
        ])
        // Back up before it ends.
        #expect(Mascot.frame(.failed, time: 0, quirk: .init(.sigh, age: 2.3)) == Mascot.still(.failed))
    }

    /// Failed rubs its head: the right arm over the top, the hand going back and forth twice.
    @Test func failedRubsItsHead() {
        #expect(art(Mascot.frame(.failed, time: 0, quirk: .init(.rubHead, age: 0.4)), x: 0..<15, y: 3..<16) == [
            "...............",
            ".......##.#....",
            "....########...",
            "...##########..",
            "..####www#####.",
            "..###wowow####.",
            "..###wwoww###..",
            "..###wowow###..",
            ".#####www####..",
            ".############..",
            "...###ooo###...",
            "...##o###o##...",
            "....##...##....",
        ])
        let top = { (age: Double) in self.art(Mascot.frame(.failed, time: 0, quirk: .init(.rubHead, age: age)), x: 0..<15, y: 4..<5)[0] }
        #expect([0.4, 0.8, 1.2, 1.6].map(top) == [".......##.#....", ".......####....", ".......##.#....", ".......####...."])
    }

    /// Done sways left and right, the antenna trailing; mid-sway it blinks, the "^" squeezed flatter.
    @Test func doneSways() {
        #expect(art(Mascot.frame(.done, time: 0, quirk: .init(.sway, age: 0.1)), x: 0..<15, y: 3..<16) == [
            ".......#.......",
            "......#........",
            "...#######.....",
            "..#########....",
            ".###########...",
            ".#####o#####...",
            ".####o#o####...",
            ".###o###o###...",
            "#############..",
            "#############..",
            "..##o###o##....",
            "..###ooo###....",
            "...##...##.....",
        ])
        #expect(art(Mascot.frame(.done, time: 0, quirk: .init(.sway, age: 1.1)), x: 0..<15, y: 3..<16) == [
            ".......#.......",
            "........#......",
            ".....#######...",
            "....#########..",
            "...###########.",
            "...###########.",
            "...####ooo####.",
            "...###o###o###.",
            "..#############",
            "..#############",
            "....##o###o##..",
            "....###ooo###..",
            ".....##...##...",
        ])
        let blinks = stride(from: 0.0, to: Mascot.Quirk.sway.duration, by: 0.05).filter {
            art(Mascot.frame(.done, time: 0, quirk: .init(.sway, age: $0)), x: 0..<15, y: 9..<10)[0].contains("ooo")
        }
        #expect(blinks.first! >= 0.9 && blinks.last! < 1.3, "blinks once, mid-sway")
    }

    /// Done hums: a faint ♪ rises and drifts off to the right, like Idle's "z".
    @Test func doneHums() {
        #expect(art(Mascot.frame(.done, time: 0, quirk: .init(.hum, age: 1.4)), x: 0..<20, y: 2..<16) == [
            ".................zz.",
            ".......#.........z..",
            ".......#........zz..",
            "....#######.....zz..",
            "...#########........",
            "..###########.......",
            "..#####o#####.......",
            "..####o#o####.......",
            "..###o###o###.......",
            ".#############......",
            ".#############......",
            "...####o####........",
            "...#########........",
            "....##...##.........",
        ])
        let tops = [0.4, 0.9, 1.4, 1.9].map { age in
            Mascot.frame(.done, time: 0, quirk: .init(.hum, age: age)).filter { $0.ink == .faint }.map(\.y).min()!
        }
        #expect(tops == tops.sorted(by: >) && Set(tops).count == 4)
        #expect(Mascot.frame(.done, time: 0, quirk: .init(.hum, age: 2.5)).allSatisfy { $0.ink != .faint })
    }

    /// The signal never weakens: Failed keeps its X eye and Done its happy eye (or its squeezed blink) in every
    /// quirk frame, and no quirk brings in another colour.
    @Test func failedAndDoneKeepTheirEyesThroughQuirks() {
        let cross = ["#www#", "wowow", "wwoww", "wowow", "#www#"]
        let happy = [["#####", "##o##", "#o#o#", "o###o", "#####"], ["#####", "#####", "#ooo#", "o###o", "#####"]]
        /// The 5 × 5 eye wherever the quirk has moved the sprite (a point or two either way).
        func eyes(_ cells: [Mascot.Cell]) -> [[String]] {
            (-2...2).flatMap { dx in (-2...2).map { dy in art(cells, x: (5 + dx)..<(10 + dx), y: (7 + dy)..<(12 + dy)) } }
        }
        let inks: Set<Mascot.Ink> = [.body, .white, .dark, .faint]
        for (mood, wanted) in [(Mascot.Mood.failed, [cross]), (.done, happy)] {
            for quirk in mood.quirks {
                for age in stride(from: 0.0, to: quirk.duration, by: 0.05) {
                    let cells = Mascot.frame(mood, time: 0, quirk: .init(quirk, age: age))
                    #expect(eyes(cells).contains { wanted.contains($0) }, "\(quirk) at \(age)")
                    #expect(Set(cells.map(\.ink)).isSubset(of: inks), "\(quirk) at \(age)")
                    if mood == .done { #expect(!art(cells, x: 0..<15, y: 7..<12).joined().contains("w"), "\(quirk) at \(age)") }
                }
            }
        }
    }

    /// Nothing is scheduled with Reduce Motion or with perchd offline.
    @Test func reducedMotionAndOfflinePlayNoQuirks() {
        for mood in Mascot.Mood.allCases {
            #expect(Mascot.quirks(mood, online: true, reduceMotion: false) == mood.quirks)
            #expect(Mascot.quirks(mood, online: true, reduceMotion: true).isEmpty)
            #expect(Mascot.quirks(mood, online: false, reduceMotion: false).isEmpty)
        }
    }

    /// Failed and Done stand still between quirks and redraw only while one plays.
    @Test func failedAndDoneRedrawOnlyWhileAQuirkPlays() {
        for mood in [Mascot.Mood.failed, .done] {
            #expect(Mascot.fps(mood, reacting: false, quirking: false) == 0)
            #expect(Mascot.fps(mood, reacting: false, quirking: true) == Mascot.reactionFPS)
        }
        #expect(Mascot.fps(.running, reacting: false, quirking: false) == Mascot.Mood.running.fps)
        #expect(Mascot.fps(.waiting, reacting: true, quirking: false) == Mascot.reactionFPS)
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

/// Time in the state (#60, #61).
extension MascotTests {
    /// Below 10 minutes a running turn looks as it always has; from 10 minutes a drop hangs by its head.
    @Test func aLongRunSweats() {
        for time in times {
            #expect(Mascot.frame(.running, time: 1000 + time, since: 1000 + time - 599) == Mascot.frame(.running, time: 1000 + time),
                    "\(time)")
        }
        let sweating = Mascot.frame(.running, time: 600.5, since: 0.5)
        #expect(art(sweating, x: 0..<16, y: 3..<16) == [
            ".......#........",
            ".......#........",
            "....#######..w..",
            "...#########.w..",
            "..####www####...",
            "..###wwwww###...",
            "..###wwoww###...",
            "..###wwwww###...",
            ".#####www#####..",
            ".#############..",
            "...###ooo###....",
            "...#########....",
            "....##...##.....",
        ])
        // The drop is all that's new: same eye, same colours, still trotting.
        #expect(Set(sweating).subtracting(Mascot.frame(.running, time: 600.5)) == [
            Mascot.Cell(x: 13, y: 5, ink: .white), Mascot.Cell(x: 13, y: 6, ink: .white),
        ])
        let hop = Mascot.frame(.running, time: 600.3, since: 0)
        #expect(hop.map(\.y).min()! < sweating.map(\.y).min()!)
    }

    /// Reduce Motion: the plain still frame, no drop.
    @Test func reducedMotionNeverSweats() {
        #expect(Mascot.still(.running) == Mascot.frame(.running, time: 0))
        #expect(!Mascot.still(.running).contains { $0.x == 13 && $0.y == 5 })
    }

    /// Every `wipePeriod` it lifts its right hand to its brow and wipes the drop away; then a new one forms.
    @Test func aLongRunWipesItsForehead() {
        let start = 6000.0
        func at(_ offset: Double) -> [String] { art(Mascot.frame(.running, time: start + offset, since: 0), x: 0..<16, y: 3..<16) }
        #expect(at(2.1) == [
            ".......#........",
            ".......#........",
            "....#######.....",
            "...##########...",
            "..####www#####..",
            "..###wwwww####..",
            "..###wwoww###...",
            "..###wwwww###...",
            ".#####www####...",
            ".############...",
            "...###ooo###....",
            "...#########....",
            "....##...##.....",
        ])
        let drop = { (offset: Double) in Mascot.frame(.running, time: start + offset, since: 0).contains { $0.x == 13 && $0.ink == .white } }
        let hand = { (offset: Double) in
            Mascot.frame(.running, time: start + offset, since: 0).contains { $0.x == 13 && $0.y < 10 && $0.ink == .body }
        }
        // Before: the drop. During the wipe: the hand, back and forth across the brow. After: neither, then a new drop.
        #expect(drop(1.9) && !hand(1.9))
        let wiping = stride(from: 2.0, to: 3.0, by: 0.05).map { start + $0 }
        #expect(wiping.allSatisfy { !drop($0 - start) && hand($0 - start) })
        #expect(Set(wiping.map { Mascot.frame(.running, time: $0, since: 0).filter { $0.ink == .body && $0.x >= 11 && $0.y <= 6 } }).count > 1)
        #expect(!drop(3.3) && !hand(3.3))
        #expect(drop(3.7) && !hand(3.7))
        // Every period, for as long as it runs (48 s: whole wipes and whole glance cycles).
        #expect(at(2.1) == art(Mascot.frame(.running, time: start + 2.1 + 10 * 48, since: 0), x: 0..<16, y: 3..<16))
        #expect(at(2.1) == art(Mascot.frame(.running, time: start + 2.1 - 112 * 48, since: 0), x: 0..<16, y: 3..<16))
    }
}

/// Needs you escalates (#61).
extension MascotTests {
    func waiting(_ waited: Double) -> [String] { art(Mascot.frame(.waiting, time: waited, since: 0), x: 0..<16, y: 2..<17) }

    /// Leaning in to knock: the wide eye (24 white cells; the upward eye has 20, plus the tip).
    func knocking(_ waited: Double) -> Bool {
        Mascot.frame(.waiting, time: waited, since: 0).filter { $0.ink == .white }.count >= 24
    }

    /// Both arms in the same place: waving together, not taking turns.
    func armsTogether(_ waited: Double) -> Bool {
        let cells = Mascot.frame(.waiting, time: waited, since: 0).filter { $0.ink == .body }
        return Set(cells.filter { $0.x == 1 }.map(\.y)) == Set(cells.filter { $0.x == 13 }.map(\.y))
    }

    var quarter: [Double] { [0.05, 0.3, 0.55, 0.8] }

    @Test func needsYouLevelsGoByTheLongestWait() {
        // Under a minute: today's look, arms taking turns.
        for x in stride(from: 0.0, to: 1, by: 0.05) {
            #expect(Mascot.frame(.waiting, time: 59 + x, since: 0) == Mascot.frame(.waiting, time: 59 + x), "\(x)")
        }
        #expect(quarter.allSatisfy { !armsTogether(59 + $0) })
        // From a minute: both arms together, and a hop every few seconds.
        #expect(quarter.allSatisfy { armsTogether(60 + $0) && armsTogether(299 + $0) })
        #expect(waiting(62.1) == [
            ".......#........",
            "....#######.....",
            "...#########....",
            ".#####www#####..",
            ".####wwoww####..",
            "..###wwwww###...",
            "..###wwwww###...",
            "..####www####...",
            "..###########...",
            "...###ooo###....",
            "...###ooo###....",
            ".....#...#......",
            "................",
            "................",
            "................",
        ])
        #expect(Mascot.frame(.waiting, time: 62.1, since: 0).map(\.y).min()! < Mascot.frame(.waiting, time: 61.1, since: 0).map(\.y).min()!)
        // The tip flashes faster: on and off every quarter second instead of every half.
        let tip = { (time: Double, since: Double?) in Mascot.frame(.waiting, time: time, since: since).contains { $0.x == 7 && $0.ink == .white && $0.y < 5 } }
        #expect([0.1, 0.35, 0.6, 0.85].map { tip(120 + $0, 0) } == [false, true, false, true])
        #expect([0.1, 0.35, 0.6, 0.85].map { tip(120 + $0, nil) } == [false, false, true, true])
        // From five minutes, a knock.
        #expect(!stride(from: 0.0, to: 300, by: 0.05).contains(where: knocking))
        #expect(knocking(300) && knocking(300.1))
    }

    /// It leans in, eye wide, and knocks three times, a glint at its hand on each.
    @Test func fromFiveMinutesItKnocksOnTheGlass() {
        #expect(waiting(300.3) == [
            "................",
            "................",
            ".......w........",
            ".......#........",
            "....#######.....",
            "...#########....",
            "..###wwwww####w.",
            "..###wwwww####..",
            "..###wwoww###...",
            "..###wwwww###...",
            ".####wwwww###...",
            ".############...",
            "...###ooo###....",
            "...###ooo###....",
            "....##...##.....",
        ])
        let glint = { (waited: Double) in Mascot.frame(.waiting, time: waited, since: 0).contains { $0.x == 14 && $0.ink == .white } }
        let samples = stride(from: 300.0, to: 300 + Mascot.knockPeriod, by: 0.05).map(glint)
        let knocks = zip(samples, [false] + samples).filter { $0 && !$1 }.count
        #expect(knocks == 3)
        // Then back to waving until the next one.
        #expect(!knocking(302) && !knocking(307.9) && knocking(308.1))
        // It sinks a point to lean in.
        #expect(Mascot.frame(.waiting, time: 300.1, since: 0).map(\.y).max()! > Mascot.frame(.waiting, time: 61.1, since: 0).map(\.y).max()!)
    }

    /// Five minutes is the top: at 30 and 120 minutes it's the same cycle, every 8 s, nothing new.
    @Test func theKnockNeverChangesAfterFiveMinutes() {
        for x in stride(from: 0.0, to: Mascot.knockPeriod, by: 0.05) {
            let five = Mascot.frame(.waiting, time: 300 + x, since: 0)
            #expect(five == Mascot.frame(.waiting, time: 300 + 188 * Mascot.knockPeriod + x, since: 0), "\(x)")
            #expect(five == Mascot.frame(.waiting, time: 300 + 863 * Mascot.knockPeriod + x, since: 0), "\(x)")
        }
    }

    /// The signal never weakens: orange body, never another colour, in every frame of every level.
    @Test func needsYouStaysOrangeAtEveryLevel() {
        let inks: Set<Mascot.Ink> = [.body, .white, .dark]
        for waited in stride(from: 0.0, to: 320, by: 0.1) {
            let cells = Mascot.frame(.waiting, time: waited, since: 0)
            #expect(Set(cells.map(\.ink)).isSubset(of: inks) && cells.filter { $0.ink == .body }.count > 60, "\(waited)")
        }
    }

    /// The entry reaction still plays first; Reduce Motion is the still frame.
    @Test func theEntryReactionStillComesFirst() {
        for age in stride(from: 0.0, to: Mascot.Mood.waiting.reactionDuration!, by: 0.1) {
            let reaction = Mascot.Reaction(mood: .waiting, age: age)
            #expect(Mascot.frame(.waiting, time: 400, since: 0, reaction: reaction) == Mascot.frame(.waiting, time: 400, reaction: reaction))
        }
        #expect(Mascot.still(.waiting) == Mascot.frame(.waiting, time: 0))
    }
}

/// Bow and scratch (#62).
extension MascotTests {
    func answered(_ answer: Mascot.Answer, _ age: Double, _ mood: Mascot.Mood = .running, time: Double = 0) -> [Mascot.Cell] {
        Mascot.frame(mood, time: time, answer: .init(answer, age: age))
    }

    /// Allow: it leans forward, eye down, antenna tipped towards you, holds, and comes back up.
    @Test func allowBows() {
        #expect(art(answered(.bow, 0.5), x: 0..<15, y: 3..<17) == [
            "...............",
            "...............",
            ".......#.......",
            "....#######....",
            "...#########...",
            "..####www####..",
            "..###wwwww###..",
            "..###wwwww###..",
            "..###wwoww###..",
            ".#####www#####.",
            ".#############.",
            "...###ooo###...",
            "...#########...",
            "....##...##....",
        ])
        #expect(answered(.bow, 1.0) == Mascot.still(.running))
        #expect(answered(.bow, Mascot.Answer.bow.duration) == Mascot.frame(.running, time: 0))
    }

    /// Deny: the left hand up behind its head, scratching, its eye glancing away, a small embarrassed mouth.
    @Test func denyScratchesItsHead() {
        #expect(art(answered(.scratch, 0.3), x: 0..<15, y: 3..<16) == [
            ".......#.......",
            ".......#.......",
            "..#.#######....",
            "..##########...",
            ".#####www####..",
            ".####wwwww###..",
            "..###wwwow###..",
            "..###wwwww###..",
            "..####www#####.",
            "..############.",
            "...####o####...",
            "...#########...",
            "....##...##....",
        ])
        let hand = { (age: Double) in self.art(self.answered(.scratch, age), x: 0..<15, y: 5..<6)[0] }
        #expect([0.3, 0.4, 0.5, 0.7].map(hand) == ["..#.#######....", "...########....", "..#.#######....", "...########...."])
        #expect(answered(.scratch, 1.3) != Mascot.still(.running))
        #expect(answered(.scratch, Mascot.Answer.scratch.duration) == Mascot.frame(.running, time: 0))
    }

    /// They play over the mood's loop, in its colour (no other inks), and Failed keeps its X eye.
    @Test func answersOverrideTheLoopButNotTheSignal() {
        for mood in Mascot.Mood.allCases {
            for answer in Mascot.Answer.allCases {
                for age in stride(from: 0.0, to: answer.duration, by: 0.05) {
                    let cells = answered(answer, age, mood, time: 600.3)
                    #expect(Set(cells.map(\.ink)).isSubset(of: [.body, .white, .dark]), "\(mood) \(answer) \(age)")
                    if mood == .failed {
                        #expect(cells.contains { $0.ink == .dark && $0.x == 6 && $0.y == 8 + (answer == .bow && age < 0.95 ? 1 : 0) },
                                "\(answer) \(age)")
                    }
                }
            }
        }
        // A sweating run bows without its drop or trot, then goes back to them.
        #expect(Mascot.frame(.running, time: 600.3, since: 0, answer: .init(.bow, age: 0.5)) == answered(.bow, 0.5))
        // A quirk waits; the entry reaction wins.
        #expect(Mascot.frame(.done, time: 0, answer: .init(.bow, age: 0.5), quirk: .init(.sway, age: 1)) == answered(.bow, 0.5, .done))
        let reaction = Mascot.Reaction(mood: .waiting, age: 0.2)
        #expect(Mascot.frame(.running, time: 0, reaction: reaction, answer: .init(.bow, age: 0.5)) == Mascot.frame(.running, time: 0, reaction: reaction))
    }
}
