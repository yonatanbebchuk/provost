import Foundation

/// Single place for product-level constants. Rename the product by editing `productName`.
public enum AppConfig {
    /// Product name. A provost guides what is learned and certifies it; "liftoff" stays the name of the detection event.
    public static let productName = "Provost"
    public static let productTagline = "Guides what a policy learns from an environment, and certifies it"
    public static let buildLabel = "0.1.0 · CamelHack build"
    /// Version of the auditor (detector + review process). A certificate issued by an older
    /// auditor is stale: the environment should be re-run.
    public static let auditorVersion = "0.1.0"

    /// Port the RL team's FastAPI server listens on. One place to change it.
    public static let localBackendPort = 8765
    public static var localBackendURL: URL { URL(string: "http://127.0.0.1:\(localBackendPort)")! }

    /// Wall-clock seconds a full training replay should take at normal speed.
    public static let trainingReplaySeconds: Double = 30
    public static let verifyReplaySeconds: Double = 16

    public static let recentEnvironmentKey = "liftoff.recentEnvironmentPath"

    /// Policies a compile can train against the environment. Open weights run locally; the custom
    /// tier is a hosted checkpoint behind an API. The fixture replays the same evidence either way.
    public static let policyModels: [PolicyModel] = [
        PolicyModel(id: "qwen3-1.7b", name: "Qwen3-1.7B", provider: "open weights · local vLLM", tier: .open),
        PolicyModel(id: "qwen3-8b", name: "Qwen3-8B", provider: "open weights · local vLLM", tier: .open),
        PolicyModel(id: "llama-3.1-8b", name: "Llama-3.1-8B", provider: "open weights · local vLLM", tier: .open),
        PolicyModel(id: "policy-ckpt-2026-10", name: "policy-ckpt-2026-10", provider: "custom checkpoint · hosted API", tier: .custom),
        PolicyModel(id: "frontier-rl-preview", name: "frontier-rl-preview", provider: "custom · partner endpoint", tier: .custom),
    ]
    public static var defaultPolicyModel: PolicyModel { policyModels[0] }
}

/// A policy the compile trains against the environment.
public struct PolicyModel: Identifiable, Hashable, Sendable {
    public enum Tier: String, Sendable { case open = "Open", custom = "Custom" }
    public let id: String
    public let name: String
    public let provider: String
    public let tier: Tier
}
