import SwiftUI

/// Every difference the hardening of this compile proposed, in one place, grouped by the part of the
/// environment it touches. Accept or reject here; whatever is left undecided stays on the environment
/// page as a diff.
struct HardenReportView: View {
    @Environment(DemoStore.self) private var store
    @Environment(RunSession.self) private var session

    private var changes: [PendingChange] { store.changes(from: session) }
    private var pending: [PendingChange] { changes.filter { $0.decision == .pending } }
    private var hacks: [Trajectory] {
        let ids = Set(changes.flatMap(\.hackIds))
        return session.hacks.filter { ids.contains($0.id) }
    }
    private var parts: [EnvironmentPart] {
        var seen: [EnvironmentPart] = []
        for c in changes where !seen.contains(c.change.part) { seen.append(c.change.part) }
        return seen
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Differences").font(.title2.weight(.semibold))
                    Text("\(pending.count) of \(changes.count) undecided · \(hacks.count) hack\(hacks.count == 1 ? "" : "s")")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    if !pending.isEmpty {
                        Button("Reject all") { store.rejectAll(in: session.environment) }.buttonStyle(MonoSecondaryButtonStyle())
                        Button("Accept all") { store.acceptAll(in: session.environment) }.buttonStyle(MonoProminentButtonStyle())
                    }
                }

                if !hacks.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(hacks.enumerated()), id: \.element.id) { index, hack in
                            HStack(spacing: 12) {
                                Circle().fill(Theme.color(for: hack.hackSeverity)).frame(width: 7, height: 7)
                                Text(hack.taskId).font(.callout.monospaced()).frame(width: 200, alignment: .leading)
                                Text("step \(hack.step)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
                                Text(hack.summary).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                                Spacer()
                                HackActions(hack: hack).fixedSize()
                            }
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(index.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.03))
                        }
                    }
                    .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(.separator))
                }

                ForEach(parts, id: \.self) { part in
                    let rows = changes.filter { $0.change.part == part }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: part.systemImage).font(.callout).foregroundStyle(.secondary)
                            Text(part.displayName).font(.headline)
                            Text("\(rows.count)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        ForEach(rows) { change in ChangeRow(change: change, environment: session.environment) }
                    }
                }

                if changes.isEmpty {
                    Text("No differences yet. Tick hacks on the rollouts page and harden them.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    Text("Undecided differences stay on the environment page. Accepted ones are applied; compile again to confirm.")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}
