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

/// Fixed-height bar at the bottom of a stage holding the stage's one primary action.
struct StageFooter<Leading: View>: View {
    @Environment(RunSession.self) private var session
    var busyLabel: String? = nil
    @ViewBuilder var leading: Leading

    var body: some View {
        HStack(spacing: 12) {
            leading
            Spacer()
            if session.isBusy, let busyLabel {
                ProgressView().controlSize(.small)
                Text(busyLabel).foregroundStyle(.secondary)
            }
            if let action = session.primaryAction {
                Button(action.title) { session.performPrimaryAction() }
                    .buttonStyle(MonoProminentButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

extension StageFooter where Leading == EmptyView {
    init(busyLabel: String? = nil) {
        self.init(busyLabel: busyLabel) { EmptyView() }
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
    static func shortHash(_ h: String) -> String {
        guard let colon = h.firstIndex(of: ":") else { return String(h.prefix(16)) }
        let digest = h[h.index(after: colon)...]
        return "\(h[..<colon]):\(digest.prefix(12))…\(digest.suffix(6))"
    }
}
