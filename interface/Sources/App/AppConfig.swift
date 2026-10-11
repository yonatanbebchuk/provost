import Foundation

/// Single place for product-level constants. Rename the product by editing `productName`.
public enum AppConfig {
    /// Product name. A provost guides what is learned and certifies it; "liftoff" stays the name of the detection event.
    public static let productName = "Profos"
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

    /// The environment the pitch demo compiles (Resources/fixtures/yelp-sentiment). The other fixtures
    /// stay in the sidebar for Load's "recent" list.
    public static let demoEnvironmentId = "yelp-sentiment"
    /// The demo replays its compile in about this long at normal speed; `F` fast-forwards it.
    public static let demoTrainingReplaySeconds: Double = 14
    public static let demoVerifyReplaySeconds: Double = 5

    /// Policies a compile can train against the environment. The fixture replays the same evidence
    /// whichever one is chosen.
    public static let policyModels: [PolicyModel] = [
        PolicyModel(id: "qwen", name: "Qwen", tier: .open),
        PolicyModel(id: "llama", name: "Llama", tier: .open),
        PolicyModel(id: "profos-secure", name: "\(productName) Secure", tier: .custom),
    ]
    public static var defaultPolicyModel: PolicyModel { policyModels[0] }
}

/// A policy the compile trains against the environment.
public struct PolicyModel: Identifiable, Hashable, Sendable {
    public enum Tier: String, Sendable { case open = "Open", custom = "Custom" }
    public let id: String
    public let name: String
    public let tier: Tier
}
