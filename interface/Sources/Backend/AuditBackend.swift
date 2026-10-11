import Foundation

/// Transport abstraction between the app and the audit pipeline.
///
/// Two implementations: `FixtureBackend` (bundled JSON replayed with realistic timing; what the demo
/// runs on) and `LocalHTTPBackend` (FastAPI server on 127.0.0.1). Swapping is one line in `ProvostApp`.
public protocol AuditBackend: Sendable {
    /// Human-readable name shown in the sidebar footer.
    var displayName: String { get }

    /// Environments the backend already knows about ("recent").
    func listEnvironments() async throws -> [AuditEnvironment]

    /// Register an environment from a folder the user dropped or picked.
    func loadEnvironment(at url: URL) async throws -> AuditEnvironment

    /// Create a compile run for an environment at its current spec. Returns the run in `.queued`.
    /// `spec` is the environment as the user has edited it (accepted differences applied); a backend
    /// compiles that, not the version it first loaded.
    func startAudit(envId: String, spec: EnvironmentSpec?) async throws -> AuditRun

    /// Static lint pass. Resolves when all findings are available.
    func lint(runId: String) async throws -> [LintFinding]

    /// Adversarial training + liftoff detection. Streams points, trajectories, the liftoff event,
    /// phase changes, and finally `.completed`.
    func train(runId: String) -> AsyncThrowingStream<TrainingEvent, Error>

    /// Harden: proposed differences that close one hack (or all findings when `trajectoryId` is nil).
    func proposePatch(runId: String, trajectoryId: String?) async throws -> Patch

    /// Apply the patch and re-run. Streams points, then `.verifyResult`, then `.completed`.
    func verify(runId: String, patchId: String) -> AsyncThrowingStream<TrainingEvent, Error>

    /// Issue the signed certificate for a run whose verification passed.
    func issueCertificate(runId: String) async throws -> Certificate
}

public enum BackendError: LocalizedError, Sendable {
    case notFound(String)
    case decoding(String, underlying: String)
    case transport(String)
    case precondition(String)

    public var errorDescription: String? {
        switch self {
        case .notFound(let what): "Not found: \(what)"
        case .decoding(let what, let underlying): "Could not decode \(what): \(underlying)"
        case .transport(let message): message
        case .precondition(let message): message
        }
    }
}
