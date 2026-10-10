import Foundation

/// Single place for product-level constants. Rename the product by editing `productName`.
public enum AppConfig {
    /// Working name of the product. The concept we want judges to remember.
    public static let productName = "Liftoff"
    public static let productTagline = "Independent exploit-and-certify audits for RL training environments"
    public static let buildLabel = "0.1.0 · CamelHack build"

    /// Port the RL team's FastAPI server listens on. One place to change it.
    public static let localBackendPort = 8765
    public static var localBackendURL: URL { URL(string: "http://127.0.0.1:\(localBackendPort)")! }

    /// Wall-clock seconds a full training replay should take at normal speed.
    public static let trainingReplaySeconds: Double = 30
    public static let verifyReplaySeconds: Double = 16

    public static let recentEnvironmentKey = "liftoff.recentEnvironmentPath"
}
