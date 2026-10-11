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

    /// Create an audit run for an environment. Returns the run in `.queued`.
    func startAudit(envId: String) async throws -> AuditRun

    /// Static lint pass. Resolves when all findings are available.
    func lint(runId: String) async throws -> [LintFinding]

    /// Adversarial training + liftoff detection. Streams points, trajectories, the liftoff event,
    /// phase changes, and finally `.completed`.
    func train(runId: String) -> AsyncThrowingStream<TrainingEvent, Error>

    /// Proposed patch for the findings confirmed by training.
    func proposePatch(runId: String) async throws -> Patch

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
