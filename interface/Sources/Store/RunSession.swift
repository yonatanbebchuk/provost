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

/// One audit run of one environment. Owns everything the backend streams for it and the stage
/// machine that gates Train → Patch → Verify → Certificate.
@MainActor
@Observable
public final class RunSession: Identifiable {
    public let id: String
    public let environment: AuditEnvironment
    public private(set) var run: AuditRun
    public private(set) var machine = StageMachine()
    public var stage: Stage { machine.selected }

    public private(set) var findings: [LintFinding] = []
    public private(set) var trainingPoints: [TrainingPoint] = []
    public private(set) var trajectories: [Trajectory] = []
    public private(set) var liftoff: LiftoffEvent?
    public private(set) var patch: Patch?
    public private(set) var verifyPoints: [TrainingPoint] = []
    public private(set) var verifyResult: VerifyResult?
    public private(set) var certificate: Certificate?
    public private(set) var log: [RunLogEntry] = []

    public private(set) var isBusy = false
    public private(set) var trainingFinished = false
    public private(set) var verifyFinished = false
    public var errorMessage: String?
    public var selectedTrajectory: Trajectory?

    private let backend: any AuditBackend
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var pendingPoints: [TrainingPoint] = []
    @ObservationIgnored private var flushScheduled = false
    @ObservationIgnored private var logCounter = 0

    public init(run: AuditRun, environment: AuditEnvironment, backend: any AuditBackend) {
        self.id = run.id
        self.run = run
        self.environment = environment
        self.backend = backend
    }

    public var phase: AuditPhase { run.phase }
    public var startedAt: Date { run.startedAt }
    public var endedAt: Date? { run.endedAt }
    public var hackCount: Int { trajectories.filter(\.isHack).count }

    /// Short status line for lists.
    public var statusLine: String {
        switch phase {
        case .done: certificate != nil ? "Certified" : "Verified"
        case .failed: "Failed"
        case .detecting: liftoff.map { "Liftoff · step \($0.step)" } ?? "Detecting"
        default: phase.displayName
        }
    }

    // MARK: Stage actions

    public enum PrimaryAction: Equatable {
        case viewPatch, applyAndVerify, issueCertificate

        public var title: String {
            switch self {
            case .viewPatch: "View proposed patch"
            case .applyAndVerify: "Apply & re-verify"
            case .issueCertificate: "Issue certificate"
            }
        }
    }

    public var primaryAction: PrimaryAction? {
        guard !isBusy else { return nil }
        switch stage {
        case .train: return trainingFinished && patch != nil ? .viewPatch : nil
        case .patch: return patch != nil && !verifyFinished ? .applyAndVerify : nil
        case .verify: return verifyFinished && certificate == nil ? .issueCertificate : nil
        case .certificate: return nil
        }
    }

    public func performPrimaryAction() {
        guard let action = primaryAction else { return }
        switch action {
        case .viewPatch: machine.select(.patch)
        case .applyAndVerify: Task { await applyAndVerify() }
        case .issueCertificate: Task { await issueCertificate() }
        }
    }

    public func select(_ stage: Stage) { machine.select(stage) }
    public func advance() { if !machine.advance() { performPrimaryAction() } }
    public func retreat() { machine.retreat() }
    public func isUnlocked(_ stage: Stage) -> Bool { machine.isUnlocked(stage) }
    public func isCompleted(_ stage: Stage) -> Bool { machine.isCompleted(stage) }

    // MARK: Pipeline

    /// Static findings, then adversarial training, then the proposed patch. One "run".
    public func start() async {
        guard !isBusy, !trainingFinished else { return }
        isBusy = true
        note(.info, "Run \(run.id) started on \(environment.name) · \(run.config.model) · \(run.config.algorithm) · \(run.config.steps) steps")
        run.phase = .linting
        note(.phase, "Static scan of the environment")
        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                findings = try await backend.lint(runId: run.id).sorted { a, b in
                    a.severity > b.severity || (a.severity == b.severity && a.id < b.id)
                }
                for f in findings { note(.finding, "\(f.id) \(f.severity.displayName.lowercased()) · \(f.failureMode.displayName) · \(f.title)") }
                note(.info, "\(findings.count) findings · \(Set(findings.map(\.failureMode)).count) failure modes")
                for try await event in backend.train(runId: run.id) {
                    try Task.checkCancellation()
                    apply(event)
                }
                trainingFinished = true
                note(.info, "Training finished · \(trajectories.count) trajectories · \(hackCount) hacks")
                patch = try await backend.proposePatch(runId: run.id)
                if let patch {
                    let parts = (patch.touches ?? []).map(\.displayName).joined(separator: ", ")
                    note(.patch, "Patch \(patch.id) proposed · closes \(patch.findingIds.joined(separator: ", "))" + (parts.isEmpty ? "" : " · changes \(parts)"))
                }
                machine.complete(.train, advance: false)
            } catch is CancellationError {
                note(.error, "Run cancelled")
            } catch {
                fail(error)
            }
            isBusy = false
        }
        await streamTask?.value
    }

    public func applyAndVerify() async {
        guard let patch, !isBusy, !verifyFinished else { return }
        isBusy = true
        verifyPoints = []
        pendingPoints = []
        verifyResult = nil
        machine.complete(.patch)
        note(.phase, "Applying \(patch.id) and re-running \(run.config.steps) steps")
        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await event in backend.verify(runId: run.id, patchId: patch.id) {
                    try Task.checkCancellation()
                    apply(event)
                }
                verifyFinished = true
                if let r = verifyResult {
                    note(.info, "Verdict: \(r.verdict.displayName) · hack rate \(Format.percent(r.before.hackRate)) → \(Format.percent(r.after.hackRate))")
                }
            } catch is CancellationError {
                note(.error, "Verification cancelled")
            } catch {
                fail(error)
            }
            isBusy = false
        }
        await streamTask?.value
    }

    public func issueCertificate() async {
        guard !isBusy, verifyResult != nil else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            certificate = try await backend.issueCertificate(runId: run.id)
            run.endedAt = Date()
            machine.complete(.verify)
            machine.complete(.certificate, advance: false)
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
            run.phase = p
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
        case .verifyResult(let result):
            flushPoints()
            verifyResult = result
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
        if phase == .verifying || phase == .done { verifyPoints.append(contentsOf: pendingPoints) } else { trainingPoints.append(contentsOf: pendingPoints) }
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
