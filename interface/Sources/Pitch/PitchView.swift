import SwiftUI

/// Pitch mode: the top bar, one slide full-bleed at 16:10, and the presenter panel on `P`.
struct PitchView: View {
    @Environment(DemoStore.self) private var store
    private var pitch: PitchController { store.pitch }

    var body: some View {
        VStack(spacing: 0) {
            PitchTopBar()
            Divider()
            stage
            if pitch.showPresenter {
                Divider()
                PresenterPanel()
            }
        }
        .background(Theme.windowBackground)
    }

    private var stage: some View {
        GeometryReader { geo in
            let inset: CGFloat = 32
            let width = max(200, min(geo.size.width - 2 * inset, (geo.size.height - 2 * inset) * 1.6))
            let height = width / 1.6
            ZStack {
                if let error = pitch.deckError {
                    VStack(spacing: 8) {
                        Text("The deck did not load").font(.title3.weight(.medium))
                        Text(error).font(.callout).foregroundStyle(.secondary)
                    }
                } else if let slide = pitch.current {
                    PitchSlideView(slide: slide, build: pitch.buildIndex)
                        .id("\(slide.id)-\(pitch.appearance)")
                }
            }
            .frame(width: width, height: height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { location in
                if location.x >= geo.size.width / 2 { store.pitchNext() } else { pitch.back() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Product name · Pitch · slide counter · Exit to app.
struct PitchTopBar: View {
    @Environment(DemoStore.self) private var store
    private var pitch: PitchController { store.pitch }

    var body: some View {
        HStack(spacing: 12) {
            Button { store.startPresentation() } label: { BrandLockup() }
                .buttonStyle(.plain)
                .help("Start the presentation over from slide 1")
            Text("·").foregroundStyle(.tertiary)
            Text("Pitch").font(.headline)
            Spacer()
            Chip(text: "\(pitch.index + 1) / \(pitch.count)", mono: true)
            Button("Exit to app") { pitch.exitToApp() }
                .buttonStyle(RoundedSecondaryButtonStyle())
                .help("Back to the app (Esc). Resume from the top bar.")
        }
        .padding(.horizontal, 24)
        .frame(height: 52)
        .background(.bar)
    }
}

extension DemoStore {
    /// `→`: the next slide, or the demo from the Demo slide.
    func pitchNext() {
        if pitch.current?.isDemoHandoff == true { enterDemo() } else { pitch.advance() }
    }

    /// ⌘⇧P: pitch mode on or off. From the demo it returns to the Demo slide.
    func togglePitchMode() {
        switch pitch.mode {
        case .app: pitch.enterPitch()
        case .pitch: pitch.leavePitch()
        case .demo: leaveDemo(toNextSlide: false)
        }
    }
}

/// The script and the clocks, below the slide. Shown during the demo too, so the words stay in view.
struct PresenterPanel: View {
    @Environment(DemoStore.self) private var store
    private var pitch: PitchController { store.pitch }

    var body: some View {
        let slide = pitch.current
        HStack(alignment: .top, spacing: 22) {
            ScrollView {
                Text(slide?.script ?? "")
                    .font(.system(size: 15))
                    .lineSpacing(15 * 0.5)
                    .frame(maxWidth: 78 * 8, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 150)
            PresenterClock()
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
        .background(Theme.cardBackground)
    }
}

/// `m:ss / m:ss` for the slide, a bar that turns accent over budget, the pitch total underneath.
struct PresenterClock: View {
    @Environment(DemoStore.self) private var store
    private var pitch: PitchController { store.pitch }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let budget = TimeInterval(pitch.current?.budgetSeconds ?? 0)
            let elapsed = pitch.slideElapsed(at: context.date)
            let total = pitch.totalElapsed(at: context.date)
            let over = budget > 0 && elapsed > budget
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(PitchController.clock(elapsed))
                        .font(.system(size: 30, weight: .semibold).monospacedDigit())
                        .foregroundStyle(over ? Theme.liftoff : .primary)
                    Text("/ \(PitchController.clock(budget))")
                        .font(.system(size: 14).monospacedDigit()).foregroundStyle(.secondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.1))
                        Capsule().fill(over ? Theme.liftoff : Color.primary)
                            .frame(width: budget > 0 ? geo.size.width * min(1, elapsed / budget) : 0)
                    }
                }
                .frame(height: 6)
                Text("\(PitchController.clock(total)) / \(PitchController.clock(TimeInterval(pitch.totalBudget))) total")
                    .font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary)
                Text(pitch.clockRunning ? "space pauses" : "space starts · resets on slide change")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            .frame(width: 200)
        }
    }
}
