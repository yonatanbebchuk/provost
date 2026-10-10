import Foundation
import Observation

/// Single source of truth for the app. Owns the stage machine, the current run and everything the
/// backend has streamed so far. All mutation happens on the main actor.
@MainActor
@Observable
public final class DemoStore {
    public let backend: any AuditBackend
    public let playback: PlaybackSettings

    // Navigation
    public private(set) var machine = StageMachine()
    public var stage: Stage { machine.selected }

    // Data
    public private(set) var recentEnvironments: [AuditEnvironment] = []
    public private(set) var environment: AuditEnvironment?
    public private(set) var run: AuditRun?
    public private(set) var findings: [LintFinding] = []
    public private(set) var trainingPoints: [TrainingPoint] = []
    public private(set) var trajectories: [Trajectory] = []
    public private(set) var liftoff: LiftoffEvent?
    public private(set) var patch: Patch?
    public private(set) var verifyPoints: [TrainingPoint] = []
    public private(set) var verifyResult: VerifyResult?
    public private(set) var certificate: Certificate?

    // Activity
    public private(set) var isBusy = false
    public private(set) var trainingFinished = false
    public private(set) var verifyFinished = false
    public var errorMessage: String?
    public var selectedTrajectory: Trajectory?
    public var fastForward: Bool {
        get { playback.fastForward }
        set { playback.fastForward = newValue; fastForwardMirror = newValue }
    }
    /// Observable mirror of the lock-protected flag, so views update on toggle.
    private var fastForwardMirror = false

    @ObservationIgnored private var streamTask: Task<Void, Never>?
    /// Points arrive faster than the chart can redraw in fast-forward; buffer and flush ~30 Hz.
    @ObservationIgnored private var pendingPoints: [TrainingPoint] = []
    @ObservationIgnored private var flushScheduled = false

    public init(backend: any AuditBackend, playback: PlaybackSettings) {
        self.backend = backend
        self.playback = playback
        self.fastForwardMirror = playback.fastForward
    }

    public var phase: AuditPhase { run?.phase ?? .queued }
    public var isFastForward: Bool { fastForwardMirror }

    // MARK: Stage actions

    /// What the primary button on the current stage does, if anything is ready.
    public enum PrimaryAction: Equatable {
        case audit, train, viewPatch, applyAndVerify, issueCertificate

        public var title: String {
            switch self {
            case .audit: "Audit"
            case .train: "Run adversarial training"
            case .viewPatch: "View proposed patch"
            case .applyAndVerify: "Apply & re-verify"
            case .issueCertificate: "Issue certificate"
            }
        }
    }

    public var primaryAction: PrimaryAction? {
        guard !isBusy else { return nil }
        switch stage {
        case .load: return environment != nil ? .audit : nil
        case .lint: return findings.isEmpty ? nil : .train
        case .train: return trainingFinished && patch != nil ? .viewPatch : nil
        case .patch: return patch != nil && !verifyFinished ? .applyAndVerify : nil
        case .verify: return verifyFinished && certificate == nil ? .issueCertificate : nil
        case .certificate: return nil
        }
    }

    public func performPrimaryAction() {
        guard let action = primaryAction else { return }
        switch action {
        case .audit: Task { await startAudit() }
        case .train: Task { await startTraining() }
        case .viewPatch: machine.select(.patch)
        case .applyAndVerify: Task { await applyAndVerify() }
        case .issueCertificate: Task { await issueCertificate() }
        }
    }

    // MARK: Navigation

    public func select(_ stage: Stage) { machine.select(stage) }

    /// `⌘→`: go to the next stage if unlocked, otherwise fire the current stage's primary action.
    public func advance() {
        if machine.advance() { return }
        performPrimaryAction()
    }

    public func retreat() { machine.retreat() }

    public func isUnlocked(_ stage: Stage) -> Bool { machine.isUnlocked(stage) }
    public func isCompleted(_ stage: Stage) -> Bool { machine.isCompleted(stage) }

    // MARK: Load

    public func loadRecents() async {
        do {
            recentEnvironments = try await backend.listEnvironments()
            if environment == nil,
               let last = UserDefaults.standard.string(forKey: AppConfig.recentEnvironmentKey),
               let match = recentEnvironments.first(where: { $0.id == last }) {
                environment = match
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func select(environment env: AuditEnvironment) {
        if env.id != environment?.id { resetRun() }
        environment = env
        UserDefaults.standard.set(env.id, forKey: AppConfig.recentEnvironmentKey)
    }

    public func openEnvironment(at url: URL) async {
        do {
            let env = try await backend.loadEnvironment(at: url)
            select(environment: env)
            if !recentEnvironments.contains(where: { $0.id == env.id }) {
                recentEnvironments.insert(env, at: 0)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Pipeline

    public func startAudit() async {
        guard let env = environment, !isBusy else { return }
        resetRun()
        isBusy = true
        defer { isBusy = false }
        do {
            var newRun = try await backend.startAudit(envId: env.id)
            newRun.phase = .linting
            run = newRun
            findings = try await backend.lint(runId: newRun.id).sorted { a, b in
                a.severity > b.severity || (a.severity == b.severity && a.id < b.id)
            }
            machine.complete(.load)
        } catch {
            fail(error)
        }
    }

    public func startTraining() async {
        guard let runId = run?.id, !isBusy, !trainingFinished else { return }
        isBusy = true
        trainingPoints = []
        pendingPoints = []
        trajectories = []
        liftoff = nil
        machine.complete(.lint)
        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await event in backend.train(runId: runId) {
                    try Task.checkCancellation()
                    apply(event)
                }
                trainingFinished = true
                patch = try await backend.proposePatch(runId: runId)
                machine.unlock(.patch)
            } catch is CancellationError {
            } catch {
                fail(error)
            }
            isBusy = false
        }
        await streamTask?.value
    }

    public func applyAndVerify() async {
        guard let runId = run?.id, let patch, !isBusy, !verifyFinished else { return }
        isBusy = true
        verifyPoints = []
        pendingPoints = []
        verifyResult = nil
        machine.complete(.train, advance: false)
        machine.complete(.patch)
        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await event in backend.verify(runId: runId, patchId: patch.id) {
                    try Task.checkCancellation()
                    apply(event)
                }
                verifyFinished = true
            } catch is CancellationError {
            } catch {
                fail(error)
            }
            isBusy = false
        }
        await streamTask?.value
    }

    public func issueCertificate() async {
        guard let runId = run?.id, !isBusy, verifyResult != nil else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            certificate = try await backend.issueCertificate(runId: runId)
            run?.endedAt = Date()
            machine.complete(.verify)
            machine.complete(.certificate, advance: false)
        } catch {
            fail(error)
        }
    }

    /// Back to Load with the same environment selected.
    public func resetRun() {
        streamTask?.cancel()
        streamTask = nil
        run = nil
        findings = []
        trainingPoints = []
        trajectories = []
        liftoff = nil
        patch = nil
        verifyPoints = []
        pendingPoints = []
        flushScheduled = false
        verifyResult = nil
        certificate = nil
        trainingFinished = false
        verifyFinished = false
        isBusy = false
        errorMessage = nil
        selectedTrajectory = nil
        machine.reset()
    }

    // MARK: Internals

    private func apply(_ event: TrainingEvent) {
        switch event {
        case .phase(let p):
            run?.phase = p
        case .point(let point):
            pendingPoints.append(point)
            scheduleFlush()
        case .trajectory(let t):
            flushPoints()
            trajectories.append(t)
        case .liftoff(let event):
            flushPoints()
            liftoff = event
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

    private func fail(_ error: Error) {
        errorMessage = error.localizedDescription
        run?.phase = .failed
    }
}
