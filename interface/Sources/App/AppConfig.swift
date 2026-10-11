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
}
