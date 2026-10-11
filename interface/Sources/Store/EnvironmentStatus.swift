import Foundation

/// Where an environment stands in the audit loop. Derived from its last certificate and its runs.
public enum EnvironmentStatus: Equatable, Sendable {
    /// Never run, or run without a finding and without a certificate.
    case unassessed
    /// The latest run found liftoff and no certificate has been issued since.
    case vulnerable(step: Int)
    /// Signed by the current auditor and nothing has changed since.
    case certified(Date)
    /// Signed once, but the auditor moved on or the environment changed. Re-run.
    case stale(Date, reason: String)

    public var title: String {
        switch self {
        case .unassessed: "Unassessed"
        case .vulnerable: "Unstable"
        case .certified: "Stable"
        case .stale: "Stale"
        }
    }

    public var detail: String {
        switch self {
        case .unassessed: "No audit on record"
        case .vulnerable(let step): "Liftoff at step \(step) · not yet patched"
        case .certified(let date): "Signed \(date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))"
        case .stale(let date, let reason): "Signed \(date.formatted(.dateTime.month(.abbreviated).day())) · \(reason)"
        }
    }
}

extension DemoStore {
    /// Most recent certificate for an environment: from its runs or shipped with it.
    public func latestCertificate(for environment: AuditEnvironment) -> Certificate? {
        let fromRuns = sessions(for: environment).compactMap(\.certificate)
        return (fromRuns + [environment.lastCertificate].compactMap { $0 }).max { $0.issuedAt < $1.issuedAt }
    }

    public func status(for environment: AuditEnvironment) -> EnvironmentStatus {
        let runs = sessions(for: environment)
        let certificate = latestCertificate(for: environment)
        // A finding newer than the last certificate wins.
        if let latest = runs.first, let liftoff = latest.liftoff, latest.certificate == nil {
            if certificate == nil || latest.startedAt > certificate!.issuedAt {
                return .vulnerable(step: liftoff.step)
            }
        }
        guard let certificate else { return .unassessed }
        if let version = certificate.auditorVersion, version != AppConfig.auditorVersion {
            return .stale(certificate.issuedAt, reason: "auditor \(version) → \(AppConfig.auditorVersion)")
        }
        if certificate.auditorVersion == nil {
            return .stale(certificate.issuedAt, reason: "auditor version unknown")
        }
        return .certified(certificate.issuedAt)
    }
}
