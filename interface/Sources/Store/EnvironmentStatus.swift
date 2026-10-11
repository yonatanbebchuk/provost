import Foundation

/// Where an environment stands in the compile → harden → recompile loop.
public enum EnvironmentStatus: Equatable, Sendable {
    /// Never compiled.
    case unassessed
    /// A compile is in progress on the current version.
    case compiling
    /// The latest compile found hacks and nothing was accepted since.
    case unstable(hacks: Int)
    /// Changes were accepted since the last compile; compile again.
    case edited(changes: Int)
    /// The latest compile on the current version found nothing. `certified` when signed.
    case stable(certified: Date?)
    /// Signed by an older auditor. Compile again to re-sign.
    case stale(Date, reason: String)

    public var title: String {
        switch self {
        case .unassessed: "Unassessed"
        case .compiling: "Compiling"
        case .unstable: "Unstable"
        case .edited: "Edited"
        case .stable(let certified): certified == nil ? "Stable" : "Stable · certified"
        case .stale: "Stale"
        }
    }

    public var detail: String {
        switch self {
        case .unassessed: "No compile on record"
        case .compiling: "Adversarial compile running"
        case .unstable(let hacks): "\(hacks) hack\(hacks == 1 ? "" : "s") found · harden and recompile"
        case .edited(let changes): "\(changes) change\(changes == 1 ? "" : "s") accepted · compile again"
        case .stable(let certified):
            certified.map { "Signed \($0.formatted(.dateTime.month(.abbreviated).day().hour().minute()))" } ?? "No hacks found · issue a certificate"
        case .stale(let date, let reason): "Signed \(date.formatted(.dateTime.month(.abbreviated).day())) · \(reason)"
        }
    }
}
