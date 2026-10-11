import SwiftUI

/// The environment, read like a README: what it is for, what the policy sees, then Reward, Action
/// space and Observation space side by side. Proposed differences sit in the part they change.
struct EnvironmentPage: View {
    @Environment(DemoStore.self) private var store
    let environment: AuditEnvironment
    @State private var showReward = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let spec = store.spec(for: environment) {
                    HStack(alignment: .top, spacing: 16) {
                        ObjectiveBlock(environment: environment, objective: spec.objective)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        certificateCard.frame(width: 236)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    if !store.pendingChanges(for: environment).isEmpty { pendingBanner }
                    if let samples = spec.samples, !samples.isEmpty {
                        TrainingDataStrip(samples: samples, taskCount: environment.taskCount)
                    }
                    HStack(alignment: .top, spacing: 16) {
                        PartCard(part: .evaluation, environment: environment, action: { showReward = true }) {
                            rewardSummary(spec)
                        }
                        PartCard(part: .actions, environment: environment) { actionSpace(spec) }
                        PartCard(part: .observations, environment: environment, alsoParts: [.initialState]) { observationSpace(spec) }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    Card(title: "Specification") {
                        Text("Registered from its packaging only. Its parts are not available yet.")
                            .font(.callout).foregroundStyle(.secondary)
                        keyValues([
                            KeyValue(key: "Runtime", value: environment.sandbox.runtime),
                            KeyValue(key: "Network", value: environment.sandbox.network),
                            KeyValue(key: "Filesystem", value: environment.sandbox.filesystem),
                        ])
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .sheet(isPresented: $showReward) {
            if let spec = store.spec(for: environment) {
                RewardSheet(environment: environment, evaluation: spec.evaluation, diff: codeDiff)
            }
        }
    }

    /// The unified diff behind an accepted or pending `code` change on the reward function.
    private var codeDiff: String? {
        for session in store.sessions(for: environment) {
            if let patch = session.patches.values.first(where: { $0.changes?.contains { $0.field == "code" } == true }) {
                return patch.diff
            }
        }
        return nil
    }

    // MARK: Header and objective

    private var pendingBanner: some View {
        let changes = store.pendingChanges(for: environment)
        let hacks = Set(changes.flatMap(\.hackIds))
        let session = store.sessions(for: environment).first { s in changes.contains { $0.runId == s.id } }
        return HStack(spacing: 12) {
            Circle().fill(Theme.changeAltered).frame(width: 8, height: 8)
            Text("\(changes.count) proposed difference\(changes.count == 1 ? "" : "s") from \(hacks.count) hack\(hacks.count == 1 ? "" : "s")")
                .font(.callout.weight(.medium))
            Spacer()
            if let session {
                Button("Review") { store.select(session: session); session.page = .report }.buttonStyle(MonoSecondaryButtonStyle())
            }
            Button("Reject all") { store.rejectAll(in: environment) }.buttonStyle(MonoSecondaryButtonStyle())
            Button("Accept all") { store.acceptAll(in: environment) }.buttonStyle(MonoProminentButtonStyle())
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Theme.changeAltered.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(Theme.changeAltered.opacity(0.5)))
    }

    // MARK: Parts

    @ViewBuilder
    private func rewardSummary(_ spec: EnvironmentSpec) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(spec.evaluation.summary).font(.body).fixedSize(horizontal: false, vertical: true)
            ForEach(spec.evaluation.components, id: \.self) { component in
                let parts = component.components(separatedBy: " · ")
                Tile(title: parts.first ?? component, detail: parts.dropFirst().joined(separator: " · "), mono: true)
            }
            HStack(spacing: 4) {
                Image(systemName: "curlybraces").font(.caption)
                Text(spec.evaluation.codePath ?? "Reward function")
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
            }
            .font(.callout.weight(.medium)).foregroundStyle(.secondary)
            .padding(.top, 2)
        }
    }

    private func actionSpace(_ spec: EnvironmentSpec) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(spec.actions) { action in
                Tile(title: action.id, detail: action.description, mono: true)
            }
        }
    }

    /// What the policy sees. The header's eye says it; the rows just name things.
    private func observationSpace(_ spec: EnvironmentSpec) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(spec.observations.visible, id: \.self) { item in
                Tile(title: item, detail: "", mono: false)
            }
        }
    }

    /// The latest certificate, beside the objective. Pressing it opens the compile that issued it.
    @ViewBuilder
    private var certificateCard: some View {
        let status = store.status(for: environment)
        let cert = store.latestCertificate(for: environment)
        let issuer = cert.flatMap { c in store.sessions(for: environment).first { $0.certificate?.id == c.id } }
        let body = VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: cert == nil ? "seal" : "checkmark.seal.fill").font(.body)
                    .foregroundStyle(cert == nil ? Color.secondary : Theme.color(for: status))
                Text("Certificate").font(.headline)
                Spacer()
                if issuer != nil { Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary) }
            }
            if let cert {
                Text(cert.issuedAt.formatted(Format.date)).font(.callout.weight(.medium))
                Text("hacks \(Format.percent(cert.before.hackRate)) → \(Format.percent(cert.after.hackRate))")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                if case .stale(_, let reason) = status {
                    Text("Stale · \(reason)").font(.caption.weight(.medium))
                }
                if let issuer { Text("Compile v\(issuer.version)").font(.caption).foregroundStyle(.tertiary) }
            } else {
                Text("Not signed").font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(.separator))
        if let issuer {
            Button {
                store.select(session: issuer)
                issuer.page = .certificate
            } label: { body.contentShape(Rectangle()) }
            .buttonStyle(.plain)
            .help("Open the compile that issued this certificate")
        } else {
            body
        }
    }

    private func bullets(_ items: [String], symbol: String, muted: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: symbol).font(.caption).foregroundStyle(muted ? .tertiary : .secondary).frame(width: 14)
                    Text(item).font(.callout).foregroundStyle(muted ? .secondary : .primary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func keyValues(_ items: [KeyValue]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
            ForEach(items, id: \.key) { item in
                GridRow {
                    Text(item.key).font(.caption).foregroundStyle(.secondary).gridColumnAlignment(.leading)
                    Text(item.value).font(.callout).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Icon and text on one centre line, the icon a touch smaller.
private struct ConstraintLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 5) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}

/// One item of a part: a name and, under it, what it means. Fills the card's width.
private struct Tile: View {
    let title: String
    let detail: String
    var mono: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(mono ? .body.weight(.semibold).monospaced() : .body.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            if !detail.isEmpty {
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// One part of the environment, with its proposed differences underneath, each accept-or-reject.
/// With an `action`, the content is pressable and the header shows a chevron.
private struct PartCard<Content: View>: View {
    @Environment(DemoStore.self) private var store
    let part: EnvironmentPart
    let environment: AuditEnvironment
    var action: (() -> Void)? = nil
    /// Other parts folded into this card; their differences show here too.
    var alsoParts: [EnvironmentPart] = []
    @ViewBuilder var content: Content
    @State private var hovering = false

    private var changes: [PendingChange] {
        ([part] + alsoParts).flatMap { store.pendingChanges(for: environment, part: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: part.systemImage).font(.body).foregroundStyle(.secondary)
                Text(part.displayName).font(.title3.weight(.semibold))
                if !changes.isEmpty {
                    HStack(spacing: 4) {
                        Circle().fill(Theme.changeAltered).frame(width: 6, height: 6)
                        Text("\(changes.count)").font(.caption.weight(.semibold)).foregroundStyle(Theme.changeAltered)
                    }
                }
                Spacer()
                if action != nil {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            Divider()
            if let action {
                Button(action: action) {
                    VStack(alignment: .leading, spacing: 10) { content }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering = $0 }
            } else {
                content
            }
            if !changes.isEmpty {
                Divider().padding(.top, 4)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(changes) { change in ChangeRow(change: change, environment: environment) }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(hovering ? Color.primary.opacity(0.03) : Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
            .strokeBorder(changes.isEmpty ? Color(nsColor: .separatorColor) : Theme.changeAltered.opacity(0.6)))
    }
}

/// What the policy is trained on: a few of the task inputs, each opening in full.
private struct TrainingDataStrip: View {
    let samples: [SampleInput]
    let taskCount: Int
    @State private var open: SampleInput?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "tray.full").font(.body).foregroundStyle(.secondary)
                Text("Training data").font(.title3.weight(.semibold))
                Spacer()
            }
            // The strip keeps going: the samples repeat, so it scrolls as far as anyone drags it.
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(0..<(samples.count * 200), id: \.self) { i in
                        let sample = samples[i % samples.count]
                        Button { open = sample } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(sample.id).font(.caption.weight(.semibold).monospaced()).foregroundStyle(.secondary)
                                    Spacer()
                                    Image(systemName: "arrow.up.left.and.arrow.down.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                                }
                                Text(sample.prompt).font(.callout).lineLimit(5).fixedSize(horizontal: false, vertical: true)
                                    .multilineTextAlignment(.leading)
                            }
                            .padding(14)
                            .frame(width: 300, alignment: .topLeading)
                            .frame(maxHeight: .infinity, alignment: .topLeading)
                            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(.separator))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .sheet(item: $open) { sample in TrainingInputSheet(sample: sample) }
    }
}

/// One training input in full.
private struct TrainingInputSheet: View {
    @Environment(\.dismiss) private var dismiss
    let sample: SampleInput

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(sample.id).font(.title2.weight(.semibold).monospaced())
                if let source = sample.source {
                    Text(source).font(.callout.monospaced()).foregroundStyle(.tertiary).textSelection(.enabled)
                }
                Spacer()
            }
            ScrollView {
                Text(sample.prompt).font(.body).textSelection(.enabled)
                    .padding(14).frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(Theme.codeBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            HStack {
                Spacer()
                Button("Close") { dismiss() }.buttonStyle(MonoProminentButtonStyle()).keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 720, height: 520)
    }
}

/// The objective, read like a README lead. Press the pencil to edit the text and the constraints;
/// saving bumps the environment version, so the status reads Edited until the next compile.
private struct ObjectiveBlock: View {
    @Environment(DemoStore.self) private var store
    let environment: AuditEnvironment
    let objective: ObjectiveSpec
    @State private var editing = false
    @State private var summary = ""
    @State private var constraints = ""
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if editing {
                TextEditor(text: $summary)
                    .font(.title3).scrollContentBackground(.hidden)
                    .frame(minHeight: 60, maxHeight: 120)
                    .padding(8)
                    .background(Theme.codeBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Constraints, one per line").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $constraints)
                        .font(.callout).scrollContentBackground(.hidden)
                        .frame(minHeight: 50, maxHeight: 110)
                        .padding(8)
                        .background(Theme.codeBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                HStack {
                    Spacer()
                    Button("Cancel") { editing = false }.buttonStyle(MonoSecondaryButtonStyle()).keyboardShortcut(.cancelAction)
                    Button("Save") {
                        store.setObjective(summary: summary, constraints: constraints.split(separator: "\n").map(String.init), in: environment)
                        editing = false
                    }
                    .buttonStyle(MonoProminentButtonStyle())
                    .keyboardShortcut(.defaultAction)
                }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    Text(objective.summary).font(.title3).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button { begin() } label: {
                        Image(systemName: "pencil").font(.callout.weight(.medium)).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain).help("Edit the objective")
                    .opacity(hovering ? 1 : 0.35)
                }
                if !objective.constraints.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(objective.constraints, id: \.self) { c in
                            Label(c, systemImage: "lock").font(.caption)
                                .labelStyle(ConstraintLabelStyle())
                                .padding(.horizontal, 9).padding(.vertical, 4)
                                .background(Color.primary.opacity(0.06), in: Capsule())
                        }
                    }
                }
            }
            let changes = store.pendingChanges(for: environment, part: .objective)
            if !changes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(changes) { change in ChangeRow(change: change, environment: environment) }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(.separator))
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { if !editing { begin() } }
    }

    private func begin() {
        summary = objective.summary
        constraints = objective.constraints.joined(separator: "\n")
        editing = true
    }
}

/// The reward function in depth: its source, its components, the audit check, and the diff when a
/// hardening touched it.
private struct RewardSheet: View {
    @Environment(\.dismiss) private var dismiss
    let environment: AuditEnvironment
    let evaluation: EvaluationSpec
    let diff: String?
    @State private var showDiff = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Reward").font(.title2.weight(.semibold))
                Chip(text: environment.rewardType.displayName)
                Spacer()
                if diff != nil {
                    MonoSegment(selection: $showDiff, options: [("Source", false), ("Diff", true)])
                }
            }
            Text(evaluation.summary).font(.body).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text((showDiff ? "Diff" : (evaluation.codePath ?? "Source")).uppercased())
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary).kerning(0.6)
                    if showDiff, let diff {
                        DiffView(diff: diff)
                    } else if let code = evaluation.code {
                        ScrollView([.vertical, .horizontal]) {
                            Text(code).font(.callout.monospaced()).textSelection(.enabled)
                                .padding(12).fixedSize()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(Theme.codeBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    } else {
                        Text("The backend did not send the reward function source.")
                            .font(.callout).foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Theme.codeBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("COMPONENTS").font(.caption.weight(.semibold)).foregroundStyle(.secondary).kerning(0.6)
                        ForEach(evaluation.components, id: \.self) { Text($0).font(.callout.monospaced()) }
                    }
                    if let audit = evaluation.audit {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("AUDIT CHECK").font(.caption.weight(.semibold)).foregroundStyle(.secondary).kerning(0.6)
                            Text(audit).font(.callout)
                        }
                    }
                    Spacer()
                }
                .frame(width: 260)
            }
            HStack {
                Spacer()
                Button("Close") { dismiss() }.buttonStyle(MonoProminentButtonStyle()).keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 940, height: 640)
    }
}
