import Foundation

/// The six screens of the demo, in order.
public enum Stage: Int, CaseIterable, Identifiable, Sendable, Comparable {
    case load, lint, train, patch, verify, certificate

    public var id: Int { rawValue }

    public static func < (lhs: Stage, rhs: Stage) -> Bool { lhs.rawValue < rhs.rawValue }

    public var title: String {
        switch self {
        case .load: "Load"
        case .lint: "Lint"
        case .train: "Train"
        case .patch: "Patch"
        case .verify: "Verify"
        case .certificate: "Certificate"
        }
    }

    public var subtitle: String {
        switch self {
        case .load: "Pick an environment"
        case .lint: "Static failure-mode scan"
        case .train: "Adversarial run · liftoff detection"
        case .patch: "Proposed fix · learning scope"
        case .verify: "Re-run on patched env"
        case .certificate: "Signed audit record"
        }
    }

    public var systemImage: String {
        switch self {
        case .load: "folder"
        case .lint: "text.magnifyingglass"
        case .train: "chart.xyaxis.line"
        case .patch: "bandage"
        case .verify: "checkmark.shield"
        case .certificate: "seal"
        }
    }

    public var next: Stage? { Stage(rawValue: rawValue + 1) }
    public var previous: Stage? { Stage(rawValue: rawValue - 1) }
}

/// Pure state machine for stage navigation. Stages unlock in order and stay revisitable.
public struct StageMachine: Equatable, Sendable {
    public private(set) var selected: Stage = .load
    public private(set) var highestUnlocked: Stage = .load
    public private(set) var completed: Set<Stage> = []

    public init() {}

    public func isUnlocked(_ stage: Stage) -> Bool { stage <= highestUnlocked }
    public func isCompleted(_ stage: Stage) -> Bool { completed.contains(stage) }

    /// Select a stage. Returns false (and does nothing) if the stage is still locked.
    @discardableResult
    public mutating func select(_ stage: Stage) -> Bool {
        guard isUnlocked(stage) else { return false }
        selected = stage
        return true
    }

    /// Make `stage` reachable without selecting it.
    public mutating func unlock(_ stage: Stage) {
        if stage > highestUnlocked { highestUnlocked = stage }
    }

    /// Mark `stage` done, unlock the next one and move to it.
    public mutating func complete(_ stage: Stage, advance: Bool = true) {
        completed.insert(stage)
        if let next = stage.next {
            unlock(next)
            if advance { selected = next }
        }
    }

    /// `⌘→`: move to the next stage if it is unlocked.
    @discardableResult
    public mutating func advance() -> Bool {
        guard let next = selected.next, isUnlocked(next) else { return false }
        selected = next
        return true
    }

    /// `⌘←`
    @discardableResult
    public mutating func retreat() -> Bool {
        guard let previous = selected.previous else { return false }
        selected = previous
        return true
    }

    public mutating func reset() { self = StageMachine() }
}
