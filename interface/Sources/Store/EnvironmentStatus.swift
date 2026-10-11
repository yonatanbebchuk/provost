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
        case .stable: "Stable"
        case .stale: "Stale"
        }
    }

    public var detail: String {
        switch self {
        case .unassessed: "Not compiled"
        case .compiling: "Compiling"
        case .unstable(let hacks): "\(hacks) hack\(hacks == 1 ? "" : "s")"
        case .edited(let changes): "\(changes) change\(changes == 1 ? "" : "s") · compile again"
        case .stable(let certified): certified.map { $0.formatted(Format.date) } ?? "Unsigned"
        case .stale(let date, let reason): "\(date.formatted(Format.date)) · \(reason)"
        }
    }
}
