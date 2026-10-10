import SwiftUI

/// Numbered source excerpt with the root-cause lines emphasised. Monochrome: the emphasis is a
/// tint plus weight, so the liftoff accent stays reserved.
struct CodeSnippetView: View {
    let snippet: CodeSnippet

    private var lines: [(number: Int, text: String)] {
        snippet.code.split(separator: "\n", omittingEmptySubsequences: false).enumerated().map {
            (snippet.startLine + $0.offset, String($0.element))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text").font(.caption)
                Text(snippet.path).font(.caption.monospaced())
                if let first = snippet.highlights.first {
                    Text("· line \(first)").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            Divider()
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(lines, id: \.number) { line in
                        let hot = snippet.highlights.contains(line.number)
                        HStack(spacing: 0) {
                            Text("\(line.number)")
                                .frame(width: 40, alignment: .trailing)
                                .foregroundStyle(hot ? .primary : .tertiary)
                            Text(hot ? "▸" : " ").frame(width: 14).foregroundStyle(.primary)
                            Text(line.text.isEmpty ? " " : line.text)
                                .fontWeight(hot ? .semibold : .regular)
                        }
                        .font(.system(size: 11.5, design: .monospaced))
                        .padding(.vertical, 1.5)
                        .padding(.trailing, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(hot ? Color.primary.opacity(0.09) : .clear)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.codeBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.separator))
        .textSelection(.enabled)
    }
}
