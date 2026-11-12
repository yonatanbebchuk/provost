import SwiftUI

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
