import SwiftUI

/// Unified diff with line-level colouring. Pure string parsing, no dependencies.
struct DiffView: View {
    let diff: String

    private struct Line: Identifiable {
        enum Kind { case fileHeader, hunk, add, remove, context, meta }
        let id: Int
        let kind: Kind
        let text: String
    }

    private var lines: [Line] {
        diff.split(separator: "\n", omittingEmptySubsequences: false).enumerated().map { i, raw in
            let s = String(raw)
            let kind: Line.Kind
            if s.hasPrefix("diff --git") || s.hasPrefix("--- ") || s.hasPrefix("+++ ") { kind = .fileHeader }
            else if s.hasPrefix("@@") { kind = .hunk }
            else if s.hasPrefix("+") { kind = .add }
            else if s.hasPrefix("-") { kind = .remove }
            else if s.hasPrefix("index ") { kind = .meta }
            else { kind = .context }
            return Line(id: i, kind: kind, text: s)
        }
    }

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(lines) { line in
                    Text(line.text.isEmpty ? " " : line.text)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(line.kind == .hunk || line.kind == .meta ? Color.secondary : Color.primary)
                        .fontWeight(line.kind == .fileHeader ? .semibold : .regular)
                        .padding(.horizontal, 12).padding(.vertical, 1.5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(background(line.kind))
                }
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .textSelection(.enabled)
        }
        .background(Theme.codeBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func background(_ kind: Line.Kind) -> Color {
        switch kind {
        case .add: Theme.diffAdd
        case .remove: Theme.diffRemove
        case .fileHeader: Color.primary.opacity(0.05)
        default: .clear
        }
    }
}
