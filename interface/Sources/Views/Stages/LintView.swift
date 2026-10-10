import SwiftUI

struct LintView: View {
    @Environment(DemoStore.self) private var store
    @State private var expanded: Set<String> = []

    private var grouped: [(Severity, [LintFinding])] {
        Severity.allCases.reversed().compactMap { sev in
            let items = store.findings.filter { $0.severity == sev }
            return items.isEmpty ? nil : (sev, items)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    ForEach(grouped, id: \.0) { severity, items in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                SeverityBadge(severity: severity)
                                Text("\(items.count) \(items.count == 1 ? "finding" : "findings")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            ForEach(items) { finding in
                                FindingRow(finding: finding, isExpanded: expanded.contains(finding.id)) {
                                    if expanded.contains(finding.id) { expanded.remove(finding.id) } else { expanded.insert(finding.id) }
                                }
                            }
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            StageFooter(busyLabel: "Starting GRPO run…") {
                Text("Adversarial training checks whether a small policy actually finds these.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .onAppear {
            if expanded.isEmpty, let first = store.findings.first { expanded = [first.id] }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Static lint").font(.title2.weight(.semibold))
            HStack(spacing: 6) {
                Text("\(store.findings.count) findings")
                ForEach(grouped, id: \.0) { sev, items in
                    Text("·").foregroundStyle(.tertiary)
                    Text("\(items.count) \(sev.displayName.lowercased())")
                }
                Text("·").foregroundStyle(.tertiary)
                Text("\(Set(store.findings.map(\.failureMode)).count) failure modes")
            }
            .font(.callout).foregroundStyle(.secondary)
        }
    }
}

private struct FindingRow: View {
    let finding: LintFinding
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 12)
                    Text(finding.id).font(.callout.monospaced()).foregroundStyle(.secondary).frame(width: 56, alignment: .leading)
                    Text(finding.title).font(.body.weight(.medium))
                    Spacer()
                    Chip(text: finding.failureMode.rawValue, mono: true)
                    Text(finding.location.displayString)
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                        .lineLimit(1).frame(maxWidth: 260, alignment: .trailing)
                }
                .padding(.horizontal, 14).padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().padding(.horizontal, 14)
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Why it matters").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(finding.explanation).font(.callout)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Proposed fix").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(finding.suggestedPatch)
                            .font(.callout.monospaced())
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.codeBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    HStack(spacing: 14) {
                        Label(finding.failureMode.displayName, systemImage: "tag")
                        Label(finding.location.displayString, systemImage: "location")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14).padding(.leading, 24).padding(.vertical, 14)
            }
        }
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(.separator))
    }
}
