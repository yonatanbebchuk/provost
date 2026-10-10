import SwiftUI

struct PatchView: View {
    @Environment(DemoStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            if let patch = store.patch {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 16) {
                        header(patch)
                        Card(title: "Rationale") {
                            Text(patch.rationale).font(.callout)
                            if let notes = patch.notes, !notes.isEmpty {
                                Divider().padding(.vertical, 2)
                                VStack(alignment: .leading, spacing: 5) {
                                    ForEach(notes, id: \.self) { note in
                                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                                            Text("•").foregroundStyle(.secondary)
                                            Text(note).fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }
                                .font(.callout)
                            }
                        }
                        LearningScopeView(scope: patch.learningScope)
                        Spacer(minLength: 0)
                    }
                    .frame(width: 400)
                    DiffView(diff: patch.diff)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ProgressView("Proposing patch…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            StageFooter(busyLabel: "Re-verifying…") {
                if let patch = store.patch {
                    Text("Re-runs \(store.run?.config.steps ?? 0) steps on the patched environment, same seed. Closes \(patch.findingIds.count) findings.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func header(_ patch: Patch) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Proposed patch").font(.title2.weight(.semibold))
            HStack(spacing: 6) {
                Text(patch.id).font(.callout.monospaced()).foregroundStyle(.secondary)
                Text("·").foregroundStyle(.tertiary)
                Text("closes").foregroundStyle(.secondary)
                ForEach(patch.findingIds, id: \.self) { id in
                    Chip(text: id, mono: true)
                }
            }
            .font(.callout)
            let modes = Set(store.findings.filter { patch.findingIds.contains($0.id) }.map(\.failureMode))
            if !modes.isEmpty {
                HStack(spacing: 6) {
                    ForEach(modes.sorted { $0.rawValue < $1.rawValue }, id: \.self) { Chip(text: $0.displayName) }
                }
            }
        }
    }
}

/// Allow / deny list for what the policy may learn from. A concept the product owns, so it gets room.
struct LearningScopeView: View {
    let scope: LearningScope

    var body: some View {
        Card(title: "Learning scope") {
            Text("What the policy may and may not learn from on the patched environment.")
                .font(.caption).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(scope.allow, id: \.self) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.primary)
                        Text(item).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(.callout)
            Divider().padding(.vertical, 2)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(scope.deny, id: \.self) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "xmark.circle").foregroundStyle(.secondary)
                        Text(item).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(.callout)
        }
    }
}

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
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Unified diff").font(.headline)
                Spacer()
                let adds = lines.filter { $0.kind == .add }.count
                let removes = lines.filter { $0.kind == .remove }.count
                let files = lines.filter { $0.text.hasPrefix("diff --git") }.count
                Text("\(files) files · +\(adds) −\(removes)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            Divider()
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(lines) { line in
                        Text(line.text.isEmpty ? " " : line.text)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(foreground(line.kind))
                            .fontWeight(line.kind == .fileHeader ? .semibold : .regular)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 1.5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(background(line.kind))
                    }
                }
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(.separator))
    }

    private func foreground(_ kind: Line.Kind) -> Color {
        switch kind {
        case .fileHeader: .primary
        case .hunk, .meta: .secondary
        default: .primary
        }
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
