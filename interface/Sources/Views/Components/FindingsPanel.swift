import SwiftUI

/// Static findings from the environment scan, grouped by severity, expandable in place.
struct FindingsPanel: View {
    let findings: [LintFinding]
    @State private var expanded: Set<String> = []

    private var grouped: [(Severity, [LintFinding])] {
        Severity.allCases.reversed().compactMap { sev in
            let items = findings.filter { $0.severity == sev }
            return items.isEmpty ? nil : (sev, items)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Static findings").font(.headline)
                Text("\(findings.count)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                if !findings.isEmpty {
                    Text("\(Set(findings.map(\.failureMode)).count) failure modes").font(.caption).foregroundStyle(.tertiary)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(grouped, id: \.0) { severity, items in
                        ForEach(items) { finding in
                            FindingRow(finding: finding, isExpanded: expanded.contains(finding.id)) {
                                if expanded.contains(finding.id) { expanded.remove(finding.id) } else { expanded.insert(finding.id) }
                            }
                        }
                    }
                }
            }
            .overlay {
                if findings.isEmpty {
                    Text("Scanning the environment…").font(.callout).foregroundStyle(.tertiary)
                }
            }
        }
    }
}

struct FindingRow: View {
    let finding: LintFinding
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0)).frame(width: 12)
                    SeverityBadge(severity: finding.severity)
                    Text(finding.title).font(.callout.weight(.medium)).lineLimit(isExpanded ? nil : 1)
                    Spacer()
                    Chip(text: finding.failureMode.rawValue, mono: true)
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().padding(.horizontal, 12)
                VStack(alignment: .leading, spacing: 12) {
                    Text(finding.explanation).font(.callout).fixedSize(horizontal: false, vertical: true)
                    if let snippet = finding.snippet {
                        CodeSnippetView(snippet: snippet)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Proposed fix").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(finding.suggestedPatch).font(.callout.monospaced())
                            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.codeBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    HStack(spacing: 14) {
                        Label(finding.id, systemImage: "number")
                        Label(finding.location.displayString, systemImage: "location")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                .padding(12)
            }
        }
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(.separator))
    }
}
