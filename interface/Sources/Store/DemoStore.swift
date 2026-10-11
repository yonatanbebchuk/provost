import Foundation
import Observation

/// Single source of truth for the app: the environments (projects), their runs, and what is selected.
@MainActor
@Observable
public final class DemoStore {
    public let backend: any AuditBackend
    public let playback: PlaybackSettings

    public private(set) var environments: [AuditEnvironment] = []
    public private(set) var sessions: [RunSession] = []
    public private(set) var selectedEnvironmentId: String?
    /// Nil shows the environment page; otherwise the run view.
    public private(set) var selectedRunId: String?
    public var errorMessage: String?
    public var showLog = true

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

    public var selectedEnvironment: AuditEnvironment? {
        environments.first { $0.id == selectedEnvironmentId }
    }

    public var selectedSession: RunSession? {
        sessions.first { $0.id == selectedRunId }
    }

    public func sessions(for environment: AuditEnvironment) -> [RunSession] {
        sessions.filter { $0.environment.id == environment.id }
    }

    /// Parts of the environment that a proposed patch in any of its runs would change.
    public func patchedParts(for environment: AuditEnvironment) -> Set<EnvironmentPart> {
        Set(sessions(for: environment).compactMap { $0.patch?.touches }.joined())
    }

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
            if !environments.contains(where: { $0.id == env.id }) {
                environments.insert(env, at: 0)
            }
            select(environment: env)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Runs

    /// Create a run for the selected environment and start it (static scan + adversarial training).
    @discardableResult
    public func newRun() async -> RunSession? {
        guard let env = selectedEnvironment else { return nil }
        do {
            let run = try await backend.startAudit(envId: env.id)
            let session = RunSession(run: run, environment: env, backend: backend)
            sessions.insert(session, at: 0)
            selectedRunId = session.id
            Task { await session.start() }
            return session
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    public func advance() { selectedSession?.advance() }
    public func retreat() { selectedSession?.retreat() }
}
