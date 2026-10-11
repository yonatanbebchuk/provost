import Foundation
import Observation

/// The pitch: which slide, whether the slides or the app are showing, and the two clocks. Owned by
/// `DemoStore`; the main window and the presenter window both read it so they never drift.
@MainActor
@Observable
public final class PitchController {
    public enum Mode: Sendable {
        /// The normal app.
        case app
        /// Slides fill the main pane.
        case pitch
        /// The app, entered from the Demo slide; `→` walks Train → Verify → next slide.
        case demo
    }

    public private(set) var slides: [PitchSlide] = []
    public private(set) var index = 0
    public private(set) var mode: Mode = .app
    public var showPresenter = false
    /// The pitch was left with Exit to app; the top bar offers Resume.
    public private(set) var canResume = false
    public var deckError: String?
    /// Incremented on every slide change so visuals replay from their resting state.
    public private(set) var appearance = 0
    /// How many pieces of a step-revealed visual are showing on the current slide.
    public private(set) var buildIndex = 0

    // Clocks. Elapsed time is derived from a start date, so no timer runs in the store.
    public private(set) var clockRunning = false
    private var slideBase: TimeInterval = 0
    private var totalBase: TimeInterval = 0
    private var startedAt: Date?

    public init() { load() }

    // MARK: Deck

    public func load() {
        guard let url = PitchDeck.locate() else { deckError = "deck.json missing from the bundle"; return }
        do {
            let deck = try PitchDeck.load(from: url)
            guard !deck.slides.isEmpty else { deckError = "deck.json has no slides"; return }
            slides = deck.slides
            index = min(index, slides.count - 1)
            deckError = nil
        } catch {
            deckError = "deck.json: \(error.localizedDescription)"
        }
    }

    /// ⌘R in pitch mode: re-read the deck and replay the current slide.
    public func reload() {
        load()
        appearance += 1
    }

    public var current: PitchSlide? { slides.indices.contains(index) ? slides[index] : nil }
    public var next: PitchSlide? { slides.indices.contains(index + 1) ? slides[index + 1] : nil }
    public var count: Int { slides.count }
    public var totalBudget: Int { slides.reduce(0) { $0 + $1.budgetSeconds } }
    public var isPresenting: Bool { mode == .pitch }
    public var isDemo: Bool { mode == .demo }

    // MARK: Navigation

    public func enterPitch(at newIndex: Int? = nil) {
        if let newIndex { index = max(0, min(slides.count - 1, newIndex)); buildIndex = 0 }
        mode = .pitch
        canResume = false
        appearance += 1
        resetSlideClock()
    }

    /// Exit to app: the normal app, with Resume in the top bar.
    public func exitToApp() {
        mode = .app
        canResume = true
    }

    public func resume() { enterPitch() }

    /// ⌘⇧P: plainly back to the app (⌘⇧P again re-enters at this slide). Esc is the excursion
    /// that leaves Resume in the top bar.
    public func leavePitch() {
        mode = .app
        canResume = false
    }

    /// Advance one slide. Returns false on the last slide and on the demo slide, whose `→` is the
    /// handoff; the caller decides what to do there.
    @discardableResult
    public func advance() -> Bool {
        guard let current else { return false }
        if buildIndex < current.buildCount { buildIndex += 1; return true }
        guard !current.isDemoHandoff, index + 1 < slides.count else { return false }
        go(to: index + 1)
        return true
    }

    /// Back un-reveals the last piece first; from the first piece it goes to the previous slide,
    /// fully built.
    @discardableResult
    public func back() -> Bool {
        if buildIndex > 0 { buildIndex -= 1; return true }
        guard index > 0 else { return false }
        go(to: index - 1)
        buildIndex = current?.buildCount ?? 0
        return true
    }

    public func go(to newIndex: Int) {
        index = max(0, min(slides.count - 1, newIndex))
        appearance += 1
        buildIndex = 0
        resetSlideClock()
    }

    /// The demo: the app shows, the pitch keeps its place on the Demo slide.
    public func beginDemo() {
        mode = .demo
        canResume = false
    }

    /// Back from the demo onto a slide (the Demo slide on Esc, the next one on Continue).
    public func endDemo(to newIndex: Int) {
        mode = .pitch
        index = max(0, min(slides.count - 1, newIndex))
        appearance += 1
        buildIndex = 0
        resetSlideClock()
    }

    // MARK: Clocks

    public func toggleClock() {
        if clockRunning { pause() } else { start() }
    }

    private func start() {
        startedAt = Date()
        clockRunning = true
    }

    private func pause() {
        let delta = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        slideBase += delta
        totalBase += delta
        startedAt = nil
        clockRunning = false
    }

    /// Changing slide resets the slide clock; the total keeps running.
    private func resetSlideClock() {
        if clockRunning, let startedAt {
            totalBase += Date().timeIntervalSince(startedAt)
            self.startedAt = Date()
        }
        slideBase = 0
    }

    public func slideElapsed(at now: Date = Date()) -> TimeInterval {
        slideBase + (clockRunning ? now.timeIntervalSince(startedAt ?? now) : 0)
    }

    public func totalElapsed(at now: Date = Date()) -> TimeInterval {
        totalBase + (clockRunning ? now.timeIntervalSince(startedAt ?? now) : 0)
    }

    public func resetClocks() {
        startedAt = clockRunning ? Date() : nil
        slideBase = 0
        totalBase = 0
    }

    public static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
