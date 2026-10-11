import SwiftUI
import AppKit

/// Monochrome everywhere, one accent reserved for the liftoff / finding state.
enum Theme {
    /// The only chromatic colour in the app. Appears the first time liftoff is detected.
    static let liftoff = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 1.00, green: 0.58, blue: 0.32, alpha: 1)
            : NSColor(srgbRed: 0.83, green: 0.36, blue: 0.11, alpha: 1)
    })

    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    static let windowBackground = Color(nsColor: .windowBackgroundColor)
    static let inset = Color(nsColor: .textBackgroundColor)
    static let codeBackground = Color.primary.opacity(0.045)

    /// Environment status. The only other chromatic colours besides the liftoff accent.
    static let statusVulnerable = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 1.00, green: 0.45, blue: 0.45, alpha: 1)
            : NSColor(srgbRed: 0.80, green: 0.18, blue: 0.18, alpha: 1)
    })
    static let statusCertified = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.40, green: 0.85, blue: 0.55, alpha: 1)
            : NSColor(srgbRed: 0.12, green: 0.55, blue: 0.30, alpha: 1)
    })

    /// Alterations in proposed differences. Additions use `statusCertified`, removals `statusVulnerable`.
    static let changeAltered = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.95, green: 0.78, blue: 0.30, alpha: 1)
            : NSColor(srgbRed: 0.72, green: 0.52, blue: 0.05, alpha: 1)
    })

    static func color(for kind: ChangeKind) -> Color {
        switch kind {
        case .add: statusCertified
        case .remove: statusVulnerable
        case .alter: changeAltered
        }
    }

    /// Hack severity: two shades of red. High is the status red; medium is a softer one.
    static let hackMedium = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.95, green: 0.60, blue: 0.50, alpha: 1)
            : NSColor(srgbRed: 0.85, green: 0.42, blue: 0.32, alpha: 1)
    })

    static func color(for severity: HackSeverity) -> Color {
        severity == .high ? statusVulnerable : hackMedium
    }

    static func color(for status: EnvironmentStatus) -> Color {
        switch status {
        case .unassessed, .compiling: .secondary
        case .unstable: statusVulnerable
        case .edited: changeAltered
        case .stable: statusCertified
        case .stale: .secondary
        }
    }

    /// Diff tints: deliberately muted so they read as structure, not alarm.
    static let diffAdd = Color.green.opacity(0.13)
    static let diffRemove = Color.red.opacity(0.13)

    static let cornerRadius: CGFloat = 10
}

// MARK: - Reusable pieces

struct Card<Content: View>: View {
    var title: String?
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .kerning(0.6)
            }
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(.separator))
    }
}

struct Chip: View {
    var text: String
    var mono = false
    var tint: Color? = nil

    var body: some View {
        Text(text)
            .font(mono ? .caption.monospaced() : .caption.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(tint ?? .primary)
            .background((tint ?? Color.primary).opacity(0.09), in: Capsule())
    }
}

/// Unassessed / Vulnerable / Certified / Stale.
struct StatusBadge: View {
    var status: EnvironmentStatus
    var compact = false

    /// Only the states with a count worth reading carry a detail; Stable is one word.
    private var showsDetail: Bool {
        switch status {
        case .unstable, .edited: true
        default: false
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Theme.color(for: status)).frame(width: 7, height: 7)
            Text(status.title.uppercased())
                .font(.caption2.weight(.bold)).kerning(0.5)
                .foregroundStyle(Theme.color(for: status))
            if !compact, showsDetail {
                Text(status.detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, compact ? 7 : 9).padding(.vertical, compact ? 3 : 5)
        .background(Theme.color(for: status).opacity(0.10), in: Capsule())
    }
}

struct SeverityBadge: View {
    var severity: Severity

    var body: some View {
        Text(severity.displayName.uppercased())
            .font(.caption2.weight(.bold))
            .kerning(0.4)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(severity == .high ? Color(nsColor: .windowBackgroundColor) : .primary)
            .background(
                severity == .high ? Color.primary : Color.primary.opacity(severity == .warn ? 0.14 : 0.07),
                in: RoundedRectangle(cornerRadius: 4, style: .continuous)
            )
    }
}

struct StatTile: View {
    var label: String
    var value: String
    var caption: String? = nil
    var emphasized = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary).kerning(0.6)
            Text(value)
                .font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(emphasized ? Theme.liftoff : .primary)
            if let caption {
                Text(caption).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(.separator))
    }
}

/// Segmented choice without the system accent: the chosen segment sits on the card colour.
struct MonoSegment<T: Hashable>: View {
    @Binding var selection: T
    let options: [(String, T)]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.1) { title, value in
                Button(title) { selection = value }
                    .buttonStyle(.plain)
                    .font(.callout.weight(selection == value ? .semibold : .regular))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(selection == value ? Theme.cardBackground : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Black-on-white / white-on-black primary button; the system accent never shows.
struct MonoProminentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .foregroundStyle(Theme.windowBackground)
            .background(Color.primary.opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.35),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Pill-shaped version of the prominent button, for the operations bar.
struct RoundedProminentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .foregroundStyle(Theme.windowBackground)
            .background(Color.primary.opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.35), in: Capsule())
    }
}

/// Pill-shaped secondary button, the quiet partner of `RoundedProminentButtonStyle`.
struct RoundedSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color.primary.opacity(configuration.isPressed ? 0.14 : 0.07), in: Capsule())
    }
}

/// Row-height secondary button: fits a 34-point list row.
struct MonoCompactButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(configuration.isPressed ? 0.14 : 0.07),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct MonoSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(configuration.isPressed ? 0.14 : 0.07),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Formatting helpers

enum Format {
    static func percent(_ v: Double) -> String { String(format: "%.0f%%", v * 100) }
    static func score(_ v: Double) -> String { String(format: "%.2f", v) }
    static func elapsed(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.down))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
                         : String(format: "%02d:%02d", s / 60, s % 60)
    }
    static let dateTime: Date.FormatStyle = .dateTime.year().month(.abbreviated).day().hour().minute().timeZone()
    static let date: Date.FormatStyle = .dateTime.day().month(.abbreviated).year()
    static func shortHash(_ h: String) -> String {
        guard let colon = h.firstIndex(of: ":") else { return String(h.prefix(16)) }
        let digest = h[h.index(after: colon)...]
        return "\(h[..<colon]):\(digest.prefix(12))…\(digest.suffix(6))"
    }
}
