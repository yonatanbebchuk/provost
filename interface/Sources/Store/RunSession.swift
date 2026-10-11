import Foundation
import Observation

/// One line of run output, shown in the run log.
public struct RunLogEntry: Identifiable, Hashable, Sendable {
    public enum Kind: Sendable { case info, phase, finding, liftoff, patch, error }
    public let id: Int
    public let at: Date
    public let kind: Kind
    public let message: String
}

/// One compile of one environment version. Owns what the backend streamed: findings, the adversarial
/// curve, the hacks it found, the hardening patches requested per hack, and partial re-checks.
@MainActor
@Observable
public final class RunSession: Identifiable {
    public let id: String
    public let environment: AuditEnvironment
    /// Environment version this compile ran against.
    public let version: Int
    public private(set) var run: AuditRun

    public private(set) var findings: [LintFinding] = []
    public private(set) var trainingPoints: [TrainingPoint] = []
    public private(set) var trajectories: [Trajectory] = []
    public private(set) var liftoff: LiftoffEvent?
    /// Hardening results, keyed by the hack's trajectory id.
    public private(set) var patches: [String: Patch] = [:]
    /// Partial recompiles: the hack replayed against the hardened environment.
    public private(set) var checks: [String: VerifyResult] = [:]
    public private(set) var checkPoints: [TrainingPoint] = []
    public private(set) var certificate: Certificate?
    public private(set) var log: [RunLogEntry] = []

    public private(set) var isBusy = false
    public private(set) var compileFinished = false
    public private(set) var hardening: Set<String> = []
    public private(set) var checking: Set<String> = []
    public var errorMessage: String?
    public var selectedTrajectory: Trajectory?

    private let backend: any AuditBackend
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var pendingPoints: [TrainingPoint] = []
    @ObservationIgnored private var flushScheduled = false
    @ObservationIgnored private var logCounter = 0
    @ObservationIgnored private var streamingCheck = false

    public init(run: AuditRun, environment: AuditEnvironment, version: Int, backend: any AuditBackend) {
        self.id = run.id
        self.run = run
        self.environment = environment
        self.version = version
        self.backend = backend
    }

    public var phase: AuditPhase { run.phase }
    public var startedAt: Date { run.startedAt }
    public var endedAt: Date? { run.endedAt }
    public var hacks: [Trajectory] { trajectories.filter(\.isHack) }
    public var hackCount: Int { hacks.count }
    /// Stable means the compile finished and found no hack and no liftoff.
    public var isStable: Bool { compileFinished && hacks.isEmpty && liftoff == nil }

    public var resultTitle: String {
        if !compileFinished { return phase == .linting ? "Scanning" : "Compiling" }
        return isStable ? "Stable" : "Unstable"
    }

    public var statusLine: String {
        if isBusy && !compileFinished { return phase == .linting ? "Scanning" : "Compiling" }
        if certificate != nil { return "Stable · certified" }
        if compileFinished { return isStable ? "Stable" : "Unstable · \(hackCount) hack\(hackCount == 1 ? "" : "s")" }
        return phase == .failed ? "Failed" : phase.displayName
    }

    // MARK: Compile

    /// Static scan, then the adversarial run. One compile.
    public func compile() async {
        guard !isBusy, !compileFinished else { return }
        isBusy = true
        note(.info, "Compile \(run.id) · \(environment.name) v\(version) · \(run.config.model) · \(run.config.algorithm) · \(run.config.steps) steps")
        run.phase = .linting
        note(.phase, "Static scan of the environment")
        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                findings = try await backend.lint(runId: run.id).sorted { a, b in
                    a.severity > b.severity || (a.severity == b.severity && a.id < b.id)
                }
                for f in findings { note(.finding, "\(f.id) \(f.severity.displayName.lowercased()) · \(f.failureMode.displayName) · \(f.title)") }
                note(.info, findings.isEmpty ? "No static findings" : "\(findings.count) findings · \(Set(findings.map(\.failureMode)).count) failure modes")
                for try await event in backend.train(runId: run.id) {
                    try Task.checkCancellation()
                    apply(event)
                }
                compileFinished = true
                run.phase = isStable ? .done : .patching
                note(.info, isStable ? "Compile finished · stable · no hacks found in \(trajectories.count) trajectories"
                                     : "Compile finished · unstable · \(hackCount) hack\(hackCount == 1 ? "" : "s") in \(trajectories.count) trajectories")
            } catch is CancellationError {
                note(.error, "Compile cancelled")
            } catch {
                fail(error)
            }
            isBusy = false
        }
        await streamTask?.value
    }

    // MARK: Harden

    /// Ask for the differences that close one hack. The store turns them into pending changes.
    @discardableResult
    public func harden(_ hack: Trajectory) async -> Patch? {
        guard !hardening.contains(hack.id) else { return patches[hack.id] }
        hardening.insert(hack.id)
        defer { hardening.remove(hack.id) }
        note(.phase, "Harden against \(hack.id) · \(hack.taskId)")
        do {
            let patch = try await backend.proposePatch(runId: run.id, trajectoryId: hack.id)
            patches[hack.id] = patch
            let parts = (patch.touches ?? []).map(\.displayName).joined(separator: ", ")
            note(.patch, "\(patch.changes?.count ?? 0) differences proposed for \(hack.id)" + (parts.isEmpty ? "" : " · \(parts)"))
            return patch
        } catch {
            fail(error)
            return nil
        }
    }

    // MARK: Partial recompile

    /// Replay one hack against the hardened environment: is it closed?
    public func check(_ hack: Trajectory) async {
        guard let patch = patches[hack.id], !checking.contains(hack.id), !isBusy else { return }
        checking.insert(hack.id)
        isBusy = true
        streamingCheck = true
        checkPoints = []
        pendingPoints = []
        note(.phase, "Recompile against \(hack.id) with \(patch.id)")
        defer { checking.remove(hack.id); isBusy = false; streamingCheck = false }
        do {
            for try await event in backend.verify(runId: run.id, patchId: patch.id) {
                try Task.checkCancellation()
                if case .verifyResult(let result) = event {
                    checks[hack.id] = result
                    let blocked = result.replay?.attackBlocked ?? (result.after.hackRate == 0)
                    note(blocked ? .info : .error, blocked ? "\(hack.id) is closed · legitimate trajectory still passes"
                                                           : "\(hack.id) still rewarded after hardening")
                } else {
                    apply(event)
                }
            }
            run.phase = .patching
        } catch {
            fail(error)
        }
    }

    public func issueCertificate() async {
        guard !isBusy, isStable, certificate == nil else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            certificate = try await backend.issueCertificate(runId: run.id)
            run.endedAt = Date()
            run.phase = .done
            note(.info, "Certificate \(certificate?.id ?? "") issued")
        } catch {
            fail(error)
        }
    }

    public func cancel() {
        streamTask?.cancel()
        streamTask = nil
    }

    // MARK: Internals

    private func apply(_ event: TrainingEvent) {
        switch event {
        case .phase(let p):
            if !streamingCheck { run.phase = p }
            note(.phase, p.displayName)
        case .point(let point):
            pendingPoints.append(point)
            scheduleFlush()
        case .trajectory(let t):
            flushPoints()
            trajectories.append(t)
            if t.isHack { note(.finding, "step \(t.step) · \(t.taskId) · hack: \(t.summary)") }
        case .liftoff(let event):
            flushPoints()
            liftoff = event
            note(.liftoff, "Liftoff at step \(event.step) · matched \(event.failureMode.rawValue) · confidence \(Format.score(event.confidence))")
        case .verifyResult:
            flushPoints()
        case .completed:
            flushPoints()
        }
    }

    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(33))
            self?.flushPoints()
        }
    }

    private func flushPoints() {
        flushScheduled = false
        guard !pendingPoints.isEmpty else { return }
        if streamingCheck { checkPoints.append(contentsOf: pendingPoints) } else { trainingPoints.append(contentsOf: pendingPoints) }
        pendingPoints.removeAll(keepingCapacity: true)
    }

    private func note(_ kind: RunLogEntry.Kind, _ message: String) {
        logCounter += 1
        log.append(RunLogEntry(id: logCounter, at: Date(), kind: kind, message: message))
    }

    private func fail(_ error: Error) {
        errorMessage = error.localizedDescription
        run.phase = .failed
        note(.error, error.localizedDescription)
    }
}
