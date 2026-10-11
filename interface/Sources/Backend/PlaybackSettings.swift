import Foundation
import Synchronization

/// Shared, thread-safe knobs the UI sets and the fixture backend reads between ticks: fast-forward,
/// and optional replay lengths (the demo replays its compile in ~14 s instead of the default).
public final class PlaybackSettings: Sendable {
    private struct State {
        var fastForward: Bool
        var trainingSeconds: Double?
        var verifySeconds: Double?
    }
    private let state: Mutex<State>

    public init(fastForward: Bool = false) {
        state = Mutex(State(fastForward: fastForward, trainingSeconds: nil, verifySeconds: nil))
    }

    public var fastForward: Bool {
        get { state.withLock { $0.fastForward } }
        set { state.withLock { $0.fastForward = newValue } }
    }

    /// Normal-speed length of the training replay, when overridden. Nil keeps the backend default.
    public var trainingSeconds: Double? {
        get { state.withLock { $0.trainingSeconds } }
        set { state.withLock { $0.trainingSeconds = newValue } }
    }

    public var verifySeconds: Double? {
        get { state.withLock { $0.verifySeconds } }
        set { state.withLock { $0.verifySeconds = newValue } }
    }
}
