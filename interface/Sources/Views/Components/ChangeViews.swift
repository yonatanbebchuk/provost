import SwiftUI

/// One proposed difference: addition in green, removal in red, alteration in yellow. Accept applies it
/// to the environment; a decided row shows its decision and keeps the buttons away.
struct ChangeRow: View {
    @Environment(DemoStore.self) private var store
    let change: PendingChange
    let environment: AuditEnvironment
    var showPart = false

    private var color: Color { Theme.color(for: change.change.kind) }
    private var symbol: String {
        switch change.change.kind {
        case .add: "+"
        case .remove: "−"
        case .alter: "~"
        }
    }
    private var decided: Bool { change.decision != .pending }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(symbol).font(.callout.monospaced().weight(.bold)).foregroundStyle(color).frame(width: 12)
            VStack(alignment: .leading, spacing: 3) {
                if let before = change.change.before, change.change.kind != .add {
                    Text(before).font(.callout)
                        .strikethrough(change.change.kind == .remove, color: color)
                        .foregroundStyle(change.change.kind == .remove ? color : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let after = change.change.after, change.change.kind != .remove {
                    Text(after).font(.callout).fixedSize(horizontal: false, vertical: true)
                }
                Text(change.change.rationale).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    if showPart { Text(change.change.part.displayName).font(.caption).foregroundStyle(.tertiary) }
                    Text(change.change.field).font(.caption.monospaced()).foregroundStyle(.tertiary)
                    if change.hackIds.count == 1 { Text("· \(change.hackIds[0])").font(.caption).foregroundStyle(.tertiary) }
                    else if change.hackIds.count > 1 { Text("· \(change.hackIds.count) hacks").font(.caption).foregroundStyle(.tertiary) }
                }
            }
            Spacer(minLength: 8)
            if decided {
                Text(change.decision == .accepted ? "Accepted" : "Rejected")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(change.decision == .accepted ? Theme.statusCertified : .secondary)
            } else {
                HStack(spacing: 6) {
                    Button { store.reject(change, in: environment) } label: { Image(systemName: "xmark") }
                        .buttonStyle(MonoSecondaryButtonStyle()).help("Reject")
                    Button { store.accept(change, in: environment) } label: { Image(systemName: "checkmark") }
                        .buttonStyle(MonoProminentButtonStyle()).help("Accept")
                }
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(color.opacity(decided ? 0.03 : 0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .leading) { Rectangle().fill(color.opacity(decided ? 0.4 : 1)).frame(width: 3).clipShape(RoundedRectangle(cornerRadius: 2)) }
        .opacity(decided ? 0.7 : 1)
    }
}
