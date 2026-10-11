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

    public enum PatchMark: Equatable { case pending, applied }

    /// Parts of the environment a patch touches: `.applied` once a run verified it, else `.pending`.
    public func patchMarks(for environment: AuditEnvironment) -> [EnvironmentPart: PatchMark] {
        var marks: [EnvironmentPart: PatchMark] = [:]
        for session in sessions(for: environment).reversed() {
            for part in session.patch?.touches ?? [] {
                let mark: PatchMark = session.verifyFinished ? .applied : .pending
                if marks[part] != .applied { marks[part] = mark }
            }
        }
        return marks
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
