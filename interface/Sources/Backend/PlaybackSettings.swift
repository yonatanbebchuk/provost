import Foundation
import Synchronization

/// Shared, thread-safe knob the UI toggles and the fixture backend reads between ticks.
public final class PlaybackSettings: Sendable {
    private let state = Mutex<Bool>(false)

    public init(fastForward: Bool = false) {
        state.withLock { $0 = fastForward }
    }

    public var fastForward: Bool {
        get { state.withLock { $0 } }
        set { state.withLock { $0 = newValue } }
    }
}
