import PerchAppCore
import PerchCore
import SwiftUI

/// Right-click menu on the notch (a row has its own).
struct NotchMenu {
    /// "Lists…" (#70): the window that chooses and orders the Todo tab's Reminders lists.
    var lists: () -> Void
    /// "Uninstall Perch…": asks first.
    var uninstall: () -> Void
    var quit: () -> Void
}

struct NotchView: View {
    @ObservedObject var notch: NotchModel
    @ObservedObject var queue: QueueModel
    @ObservedObject var setup: SetupModel
    var gaze: GazeTracker
    var menu: NotchMenu

    var body: some View {
        ZStack(alignment: .top) {
            let notchWidth = notch.geometry?.notch?.width ?? 0
            NotchShape(hasNotch: notch.geometry?.hasNotch ?? true, expanded: notch.expanded)
                .fill(Color.black)
                // Collapsed, the window may be wider than the band while the right wing shrinks back.
                .frame(width: notch.expanded ? nil : notch.leftWing + notchWidth + notch.rightWing)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 0) {
                Group {
                    if notch.expanded {
                        TabStrip(queue: queue)
                    } else {
                        CollapsedBar(queue: queue, gaze: gaze, notchWidth: notchWidth, leftWing: notch.leftWing, rightWing: notch.rightWing)
                    }
                }
                .frame(height: notch.geometry?.bandHeight ?? NotchGeometry.capsuleHeight)
                if notch.expanded {
                    ExpandedPanel(queue: queue, setup: setup)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contextMenu {
            // Only with Reminders access (#70): without it there are no lists to choose.
            if queue.choosesLists {
                Button("Lists…", action: menu.lists)
                Divider()
            }
            // Not setup, so every build has it (#35). Turning a state on plays it.
            Menu("Sounds") {
                Toggle("Play Sounds", isOn: $queue.chimes.enabled)
                Divider()
                ForEach(ChimeSound.allCases, id: \.self) { sound in
                    Toggle(sound.title, isOn: Binding(
                        get: { queue.chimes.sounds.contains(sound) },
                        set: { on in
                            queue.chimes.set(sound, on: on)
                            if on { queue.onChime(sound) }
                        }
                    ))
                    .disabled(!queue.chimes.enabled)
                }
            }
            Menu("Display") {
                Toggle("Automatic", isOn: displayBinding(.automatic))
                Toggle("Main Display", isOn: displayBinding(.main))
                Divider()
                ForEach(DisplayMenu.displays(choice: notch.display, screens: notch.screens), id: \.title) { item in
                    Toggle(item.title, isOn: displayBinding(item.choice, checked: item.checked))
                        .disabled(!item.enabled)
                }
            }
            Divider()
            // Only an app that maintains the install (in an Applications folder, no PERCH_HOME) edits agent configs.
            if !setup.state.menu.isEmpty && !setup.uninstalling {
                Menu("Agents") {
                    ForEach(setup.state.menu, id: \.agent) { toggle in
                        Toggle(toggle.title, isOn: Binding(
                            get: { toggle.on },
                            set: { $0 ? setup.connect(toggle.agent) : setup.disconnect(toggle.agent) }
                        ))
                        .disabled(!toggle.available)
                    }
                }
                Divider()
            }
            if let login = setup.state.loginMenu, !setup.uninstalling {
                Toggle(login.title, isOn: Binding(get: { login.on }, set: { _ in setup.chooseLoginToggle() }))
            }
            if setup.state.canUninstall && !setup.uninstalling {
                Button("Uninstall Perch…", action: menu.uninstall)
                Divider()
            }
            Button("Quit Perch", action: menu.quit)
        }
    }
}

extension NotchView {
    /// A Display menu item: checked when it is the choice; choosing it again does nothing (no un-checking).
    private func displayBinding(_ choice: DisplayChoice, checked: Bool? = nil) -> Binding<Bool> {
        Binding(get: { checked ?? (notch.display == choice) }, set: { _ in notch.display = choice })
    }
}

/// The band beside the notch. Left wing: the mascot (acting out the most urgent session's state) and right next to it
/// the number of running sessions (hidden at 0), or the offline icon. Right wing: the todo icon and the open count
/// (#56; the icon alone, dimmed, at 0), or the event banner instead while one shows.
struct CollapsedBar: View {
    @ObservedObject var queue: QueueModel
    /// Where the mascot looks: the pointer nearby (#63).
    @ObservedObject var gaze: GazeTracker
    var notchWidth: CGFloat
    var leftWing: CGFloat
    var rightWing: CGFloat

    var body: some View {
        let panel = queue.panel
        HStack(spacing: 0) {
            HStack(spacing: NotchGeometry.collapsedGap) {
                MascotView(signal: panel.signal, since: panel.signalSince, online: queue.online, pulse: queue.pulse,
                           pulseStatus: queue.pulseStatus, answer: queue.answerReaction, gaze: gaze.gaze)
                    // Away on its Done run, drawn by the overlay; the running count keeps its place.
                    .opacity(queue.flight == nil ? 1 : 0)
                Group {
                    if !queue.online {
                        Image(systemName: "bolt.horizontal.circle").help(queue.offlineReason ?? "perchd is not running")
                    } else if panel.runningCount > 0 {
                        Text("\(panel.runningCount)").monospacedDigit().help("\(panel.runningCount) running")
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.leading, NotchGeometry.collapsedInset)
            .frame(width: leftWing, alignment: .leading)
            Color.clear.frame(width: notchWidth)
            ZStack(alignment: .leading) {
                if let banner = queue.banner {
                    BannerView(banner: banner, delay: scrollDelay)
                        .id(banner.id)
                        .padding(.leading, CGFloat(Banner.inset))
                        // Opened and rolled up by the Done run; on the banner itself, so it stays rolled up as it fades.
                        .mask(alignment: .leading) {
                            if let flight = queue.flight, !flight.interrupted { FlightReveal(flight: flight) } else { Rectangle() }
                        }
                        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                } else {
                    CollapsedTodos(count: queue.collapsedTodoCount)
                        .padding(.leading, NotchGeometry.collapsedInset)
                        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                }
            }
            .frame(width: rightWing, alignment: .leading)
            .clipped()
            Spacer(minLength: 0)
        }
        .overlay(alignment: .topLeading) {
            if let flight = queue.flight {
                FlightView(flight: flight, signal: panel.signal, online: queue.online)
            }
        }
    }

    /// A too-long banner waits for the Done run to finish opening it before it scrolls.
    private var scrollDelay: TimeInterval {
        guard queue.carriesBanner, let opened = queue.flight?.opened else { return Banner.scrollDelay }
        return Banner.scrollDelay + max(0, opened - Date().timeIntervalSinceReferenceDate)
    }
}

/// The right wing's todos (#56): static, never in a state's colour. White with the open count; at 0 the icon alone,
/// dimmed like an unselected tab.
struct CollapsedTodos: View {
    var count: Int

    var body: some View {
        HStack(spacing: NotchGeometry.collapsedGap) {
            Image(systemName: "checklist")
            if count > 0 {
                Text("\(count)").monospacedDigit()
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.white.opacity(count > 0 ? 0.9 : 0.4))
    }
}

/// A session state's colour; Running breathes.
struct StatusDot: View {
    var status: SessionStatus?
    var size: CGFloat = 7
    @State private var breathing = false

    var body: some View {
        Circle()
            .fill(SessionStatus.color(status))
            .frame(width: size, height: size)
            .opacity(status == .running ? (breathing ? 0.35 : 1) : 1)
            .animation(status == .running ? .easeInOut(duration: 1.4).repeatForever(autoreverses: true) : .default, value: breathing)
            .onAppear { breathing = status == .running }
            .onChange(of: status) { breathing = status == .running }
    }
}

extension SessionStatus {
    /// Needs you orange, Failed red, Running green, Done blue, Idle grey; no sessions a darker grey.
    static func color(_ status: SessionStatus?) -> Color {
        switch status {
        case .waiting: return Color(red: 1, green: 0.58, blue: 0.1)
        case .failed: return Color(red: 1, green: 0.27, blue: 0.23)
        case .running: return Color(red: 0.2, green: 0.82, blue: 0.4)
        case .done: return Color(red: 0.25, green: 0.55, blue: 1)
        case .idle: return Color(white: 0.55)
        case nil: return Color(white: 0.35)
        }
    }
}

/// Flush with the top edge and rounded below when it hangs from the notch; a capsule otherwise.
struct NotchShape: Shape {
    var hasNotch: Bool
    var expanded: Bool

    func path(in rect: CGRect) -> Path {
        if !hasNotch && !expanded { return Capsule().path(in: rect) }
        let radius: CGFloat = expanded ? 18 : 10
        if !hasNotch { return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect) }
        return UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous)
            .path(in: rect)
    }
}
