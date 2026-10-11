import Foundation
import Observation

/// A proposed difference waiting for a decision, attached to an environment.
public struct PendingChange: Identifiable, Hashable, Sendable {
    public enum Decision: Sendable { case pending, accepted, rejected }
    public let id: String
    public let change: SpecChange
    /// The hacks this difference closes. One difference can come out of hardening several hacks.
    public var hackIds: [String]
    public let runId: String
    public var decision: Decision = .pending
    /// The environment version this decision was saved into. Nil while it sits in the change record.
    public var savedIn: Int?

    public var hackId: String? { hackIds.first }
}

/// Single source of truth: environments (the projects), their current editable spec and version,
/// pending differences, compiles, and selection.
@MainActor
@Observable
public final class DemoStore {
    public let backend: any AuditBackend
    public let playback: PlaybackSettings

    public private(set) var environments: [AuditEnvironment] = []
    public private(set) var sessions: [RunSession] = []
    public private(set) var selectedEnvironmentId: String?
    /// Nil shows the environment page; otherwise the compile result.
    public private(set) var selectedRunId: String?
    public var errorMessage: String?
    public var showLog = false
    /// The pitch deck: slide, mode and clocks. The main window and the presenter window read it.
    public let pitch = PitchController()

    /// Current spec per environment, after accepted changes. Absent means unchanged from the fixture.
    private var specs: [String: EnvironmentSpec] = [:]
    private var versions: [String: Int] = [:]
    private var pending: [String: [PendingChange]] = [:]
    /// Policy chosen per environment; absent means the default.
    private var models: [String: String] = [:]
    /// Hand edits (objective) since the last save, per environment.
    private var manualEdits: [String: Int] = [:]
    private var fastForwardMirror = false

    public init(backend: any AuditBackend, playback: PlaybackSettings) {
        self.backend = backend
        self.playback = playback
        self.fastForwardMirror = playback.fastForward
    }

    public var fastForward: Bool {
        get { playback.fastForward }
        set { playback.fastForward = newValue; fastForwardMirror = newValue }
    }
    public var isFastForward: Bool { fastForwardMirror }

    public var selectedEnvironment: AuditEnvironment? { environments.first { $0.id == selectedEnvironmentId } }
    public var selectedSession: RunSession? { sessions.first { $0.id == selectedRunId } }

    public func sessions(for environment: AuditEnvironment) -> [RunSession] {
        sessions.filter { $0.environment.id == environment.id }
    }

    public func version(of environment: AuditEnvironment) -> Int { versions[environment.id] ?? 1 }

    /// The policy the next compile trains against this environment.
    public func policyModel(for environment: AuditEnvironment) -> PolicyModel {
        AppConfig.policyModels.first { $0.id == models[environment.id] } ?? AppConfig.defaultPolicyModel
    }

    public func setPolicyModel(_ model: PolicyModel, for environment: AuditEnvironment) {
        models[environment.id] = model.id
    }
    public func spec(for environment: AuditEnvironment) -> EnvironmentSpec? { specs[environment.id] ?? environment.spec }

    // MARK: Environments

    public func loadEnvironments() async {
        do {
            environments = try await backend.listEnvironments()
            if selectedEnvironmentId == nil {
                let last = UserDefaults.standard.string(forKey: AppConfig.recentEnvironmentKey)
                selectedEnvironmentId = environments.first { $0.id == last }?.id ?? environments.first?.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func select(environment: AuditEnvironment) {
        selectedEnvironmentId = environment.id
        selectedRunId = nil
        UserDefaults.standard.set(environment.id, forKey: AppConfig.recentEnvironmentKey)
    }

    public func showEnvironmentPage() { selectedRunId = nil }

    public func select(session: RunSession) {
        selectedEnvironmentId = session.environment.id
        selectedRunId = session.id
    }

    public func addEnvironment(at url: URL) async {
        do {
            let env = try await backend.loadEnvironment(at: url)
            if !environments.contains(where: { $0.id == env.id }) { environments.insert(env, at: 0) }
            select(environment: env)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Compile

    /// Compile the selected environment at its current version and show the result.
    @discardableResult
    public func compile() async -> RunSession? {
        guard var env = selectedEnvironment else { return nil }
        save(env)
        if let spec = specs[env.id] { env.spec = spec }
        do {
            let run = try await backend.startAudit(envId: env.id, spec: env.spec, model: policyModel(for: env).name)
            let session = RunSession(run: run, environment: env, version: version(of: env), backend: backend)
            sessions.insert(session, at: 0)
            selectedRunId = session.id
            Task { await session.compile() }
            return session
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: Harden

    /// Ask the backend for the differences that close one hack and attach them to the environment.
    public func harden(_ hack: Trajectory, in session: RunSession) async {
        guard let patch = await session.harden(hack) else { return }
        attach(patch, from: hack, in: session)
    }

    /// Harden the ticked hacks together, then show the report (unless the caller shows the
    /// differences itself, as the deep dive does).
    public func hardenSelected(in session: RunSession, openReport: Bool = true) async {
        let hacks = session.hacks.filter { session.selectedHacks.contains($0.id) }
        for hack in hacks {
            guard let patch = await session.harden(hack) else { continue }
            attach(patch, from: hack, in: session)
        }
        session.selectedHacks = []
        if openReport, !pendingChanges(for: session.environment).isEmpty { session.page = .report }
    }

    /// Every difference proposed for one hack, decided or not.
    public func changes(for hack: Trajectory, in environment: AuditEnvironment) -> [PendingChange] {
        (pending[environment.id] ?? []).filter { $0.hackIds.contains(hack.id) }
    }

    private func attach(_ patch: Patch, from hack: Trajectory, in session: RunSession) {
        let envId = session.environment.id
        var list = pending[envId] ?? []
        for change in patch.changes ?? [] {
            let id = "\(patch.id)/\(change.id)"
            if let index = list.firstIndex(where: { $0.id == id }) {
                // The same difference from another hack, or hardening the same hack again: re-open it if
                // it was rejected; accepted ones stay applied.
                if !list[index].hackIds.contains(hack.id) { list[index].hackIds.append(hack.id) }
                if list[index].decision == .rejected { list[index].decision = .pending }
            } else {
                list.append(PendingChange(id: id, change: change, hackIds: [hack.id], runId: session.id))
            }
        }
        pending[envId] = list
    }

    public func pendingChanges(for environment: AuditEnvironment, part: EnvironmentPart? = nil) -> [PendingChange] {
        (pending[environment.id] ?? []).filter { $0.decision == .pending && (part == nil || $0.change.part == part) }
    }

    /// Every difference a session proposed, decided or not, in proposal order.
    public func changes(from session: RunSession) -> [PendingChange] {
        (pending[session.environment.id] ?? []).filter { $0.runId == session.id }
    }

    public func accept(_ change: PendingChange, in environment: AuditEnvironment) {
        decide(change, in: environment, .accepted)
    }

    public func reject(_ change: PendingChange, in environment: AuditEnvironment) {
        decide(change, in: environment, .rejected)
    }

    public func acceptAll(in environment: AuditEnvironment) {
        for change in pendingChanges(for: environment) { accept(change, in: environment) }
    }

    public func rejectAll(in environment: AuditEnvironment) {
        for change in pendingChanges(for: environment) { reject(change, in: environment) }
    }

    private func decide(_ change: PendingChange, in environment: AuditEnvironment, _ decision: PendingChange.Decision) {
        guard var list = pending[environment.id], let index = list.firstIndex(where: { $0.id == change.id }) else { return }
        list[index].decision = decision
        pending[environment.id] = list
        if decision == .accepted, var spec = spec(for: environment) {
            SpecEditor.apply(change.change, to: &spec)
            specs[environment.id] = spec
        }
    }

    /// Direct edit of the objective. Joins the change record; Save makes it a version.
    public func setObjective(summary: String, constraints: [String], in environment: AuditEnvironment) {
        guard var spec = spec(for: environment) else { return }
        let summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let constraints = constraints.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard summary != spec.objective.summary || constraints != spec.objective.constraints else { return }
        spec.objective.summary = summary
        spec.objective.constraints = constraints
        specs[environment.id] = spec
        manualEdits[environment.id, default: 0] += 1
    }

    // MARK: Change record and versions

    /// Decisions not yet saved into a version, accepted and rejected, in decision order.
    public func changeRecord(for environment: AuditEnvironment) -> [PendingChange] {
        (pending[environment.id] ?? []).filter { $0.decision != .pending && $0.savedIn == nil }
    }

    /// Hand edits waiting for a save.
    public func manualEditCount(for environment: AuditEnvironment) -> Int { manualEdits[environment.id] ?? 0 }

    /// What a save would write: accepted differences plus hand edits. Rejections are recorded but
    /// change nothing.
    public func unsavedCount(for environment: AuditEnvironment) -> Int {
        changeRecord(for: environment).filter { $0.decision == .accepted }.count + manualEditCount(for: environment)
    }

    /// Close the circle: the edited environment becomes the next version. Returns the new version,
    /// or nil when there was nothing to save.
    @discardableResult
    public func save(_ environment: AuditEnvironment) -> Int? {
        guard unsavedCount(for: environment) > 0 else { return nil }
        let next = version(of: environment) + 1
        versions[environment.id] = next
        manualEdits[environment.id] = 0
        if var list = pending[environment.id] {
            for i in list.indices where list[i].decision != .pending && list[i].savedIn == nil { list[i].savedIn = next }
            pending[environment.id] = list
        }
        return next
    }

    // MARK: Status

    public func latestCertificate(for environment: AuditEnvironment) -> Certificate? {
        let fromRuns = sessions(for: environment).compactMap(\.certificate)
        return (fromRuns + [environment.lastCertificate].compactMap { $0 }).max { $0.issuedAt < $1.issuedAt }
    }

    public func status(for environment: AuditEnvironment) -> EnvironmentStatus {
        let current = version(of: environment)
        let latest = sessions(for: environment).first
        if let latest, latest.isBusy, !latest.compileFinished { return .compiling }
        let unsaved = unsavedCount(for: environment)
        if unsaved > 0 { return .edited(changes: unsaved) }
        if let latest {
            // Saved into a newer version than the last compile: that version has not been assessed.
            if latest.version < current { return .unassessed }
            if latest.compileFinished {
                if latest.isStable { return .stable(certified: latest.certificate?.issuedAt) }
                return .unstable(hacks: latest.hackCount)
            }
        }
        if let certificate = latestCertificate(for: environment) {
            if let version = certificate.auditorVersion, version != AppConfig.auditorVersion {
                return .stale(certificate.issuedAt, reason: "auditor \(version) → \(AppConfig.auditorVersion)")
            }
            if certificate.auditorVersion == nil { return .stale(certificate.issuedAt, reason: "auditor version unknown") }
            return .stable(certified: certificate.issuedAt)
        }
        return .unassessed
    }
}

// MARK: - Pitch demo

extension DemoStore {
    private var demoSlideIndex: Int { pitch.slides.firstIndex { $0.isDemoHandoff } ?? pitch.index }

    /// `→` on the Demo slide: the app as it stands, for the presenter to drive by hand. Only
    /// Continue pitch (or ⌘⇧P) leads back to the slides.
    public func enterDemo() {
        pitch.beginDemo()
    }

    /// Continue pitch goes on to the next slide; ⌘⇧P returns to the Demo slide.
    public func leaveDemo(toNextSlide: Bool) {
        pitch.endDemo(to: demoSlideIndex + (toNextSlide ? 1 : 0))
    }

    /// The logo and Present: a fresh presentation from slide 1, clocks at zero.
    public func startPresentation() {
        pitch.resetClocks()
        pitch.enterPitch(at: 0)
    }
}

/// Applies a `SpecChange` to an `EnvironmentSpec`. Fields are addressed by name (see `SpecChange`).
public enum SpecEditor {
    public static func apply(_ change: SpecChange, to spec: inout EnvironmentSpec) {
        func edit(_ list: inout [String]) {
            switch change.kind {
            case .add: if let after = change.after, !list.contains(after) { list.append(after) }
            case .remove: list.removeAll { $0 == change.before }
            case .alter:
                if let before = change.before, let after = change.after, let i = list.firstIndex(of: before) { list[i] = after }
                else if let after = change.after { list.append(after) }
            }
        }
        switch (change.part, change.field) {
        case (.objective, "constraints"): edit(&spec.objective.constraints)
        case (.objective, "summary"): if let after = change.after { spec.objective.summary = after }
        case (.observations, "visible"): edit(&spec.observations.visible)
        case (.observations, "hidden"): edit(&spec.observations.hidden)
        case (.evaluation, "components"): edit(&spec.evaluation.components)
        case (.evaluation, "summary"): if let after = change.after { spec.evaluation.summary = after }
        case (.evaluation, "audit"): spec.evaluation.audit = change.after
        case (.initialState, "summary"): if let after = change.after { spec.initialState.summary = after }
        case (.initialState, "items"):
            // "Key: value" strings address items by key.
            func split(_ s: String) -> (String, String) {
                guard let r = s.range(of: ": ") else { return (s, "") }
                return (String(s[..<r.lowerBound]), String(s[r.upperBound...]))
            }
            switch change.kind {
            case .add: if let after = change.after { let (k, v) = split(after); spec.initialState.items.append(KeyValue(key: k, value: v)) }
            case .remove: if let before = change.before { let (k, _) = split(before); spec.initialState.items.removeAll { $0.key == k } }
            case .alter:
                if let after = change.after {
                    let (k, v) = split(after)
                    if let i = spec.initialState.items.firstIndex(where: { $0.key == k }) { spec.initialState.items[i].value = v }
                    else { spec.initialState.items.append(KeyValue(key: k, value: v)) }
                }
            }
        case (.actions, "actions"):
            func split(_ s: String) -> (String, String) {
                guard let r = s.range(of: ": ") else { return (s, "") }
                return (String(s[..<r.lowerBound]), String(s[r.upperBound...]))
            }
            switch change.kind {
            case .add: if let after = change.after { let (k, v) = split(after); spec.actions.append(ActionContract(id: k, description: v, arguments: nil)) }
            case .remove: if let before = change.before { let (k, _) = split(before); spec.actions.removeAll { $0.id == k } }
            case .alter:
                if let after = change.after {
                    let (k, v) = split(after)
                    if let i = spec.actions.firstIndex(where: { $0.id == k }) { spec.actions[i].description = v }
                }
            }
        case (.episode, "termination"): if let after = change.after { spec.episode.termination = after }
        case (.episode, "reset"): if let after = change.after { spec.episode.reset = after }
        case (.episode, "max_steps"): spec.episode.maxSteps = change.after.flatMap(Int.init)
        default:
            // `code` on the reward function and unknown fields have no spec text to rewrite; the
            // decision is recorded and the unified diff documents the change.
            break
        }
    }
}
