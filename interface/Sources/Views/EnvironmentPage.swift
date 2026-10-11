import SwiftUI

/// The environment itself, laid out in its parts, with proposed differences shown in place, its last
/// certificate, and its compiles.
struct EnvironmentPage: View {
    @Environment(DemoStore.self) private var store
    let environment: AuditEnvironment

    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if !store.pendingChanges(for: environment).isEmpty { pendingBanner }
                if let spec = store.spec(for: environment) {
                    if let samples = spec.samples, !samples.isEmpty {
                        SampleInputsStrip(samples: samples, taskCount: environment.taskCount)
                    }
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                        PartCard(part: .evaluation, environment: environment) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Chip(text: environment.rewardType.displayName)
                                Text(spec.evaluation.summary).font(.callout).fixedSize(horizontal: false, vertical: true)
                            }
                            if !spec.evaluation.components.isEmpty {
                                FlowChips(items: spec.evaluation.components)
                            }
                            if let audit = spec.evaluation.audit {
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Image(systemName: "checkmark.shield").font(.caption).foregroundStyle(.secondary)
                                    Text(audit).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            if let diff = codeDiff {
                                DisclosureGroup("Reward function diff") {
                                    DiffView(diff: diff).frame(height: 260).padding(.top, 6)
                                }
                                .font(.callout)
                            }
                        }
                        PartCard(part: .actions, environment: environment) {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(spec.actions) { action in
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text(action.id).font(.callout.monospaced()).frame(width: 90, alignment: .leading)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(action.description).font(.callout)
                                            if let args = action.arguments, !args.isEmpty {
                                                Text(args.joined(separator: ", ")).font(.caption.monospaced()).foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                            }
                            if !environment.sandbox.tools.isEmpty || environment.sandbox.network != "none" {
                                Divider().padding(.vertical, 2)
                                HStack(spacing: 8) {
                                    Text("Sandbox").font(.caption).foregroundStyle(.secondary)
                                    Text("\(environment.sandbox.runtime) · network \(environment.sandbox.network) · \(environment.sandbox.filesystem)").font(.caption)
                                }
                            }
                        }
                        PartCard(part: .observations, environment: environment) {
                            bullets(spec.observations.visible, symbol: "eye")
                            if !spec.observations.hidden.isEmpty {
                                Divider().padding(.vertical, 2)
                                bullets(spec.observations.hidden, symbol: "eye.slash", muted: true)
                            }
                        }
                        PartCard(part: .objective, environment: environment) {
                            Text(spec.objective.summary).font(.callout).fixedSize(horizontal: false, vertical: true)
                            if !spec.objective.constraints.isEmpty { bullets(spec.objective.constraints, symbol: "lock") }
                        }
                        PartCard(part: .initialState, environment: environment) {
                            Text(spec.initialState.summary).font(.callout).fixedSize(horizontal: false, vertical: true)
                            keyValues(spec.initialState.items)
                        }
                        PartCard(part: .episode, environment: environment) {
                            keyValues([
                                KeyValue(key: "Ends when", value: spec.episode.termination),
                                KeyValue(key: "Step budget", value: spec.episode.maxSteps.map(String.init) ?? "unbounded"),
                                KeyValue(key: "Reset", value: spec.episode.reset),
                            ])
                        }
                    }
                    HStack(alignment: .top, spacing: 16) {
                        provenance(spec.provenance)
                        certificateCard
                    }
                } else {
                    Card(title: "Specification") {
                        Text("This environment was registered from its packaging only. Its parts are not available yet.")
                            .font(.callout).foregroundStyle(.secondary)
                        keyValues([
                            KeyValue(key: "Runtime", value: environment.sandbox.runtime),
                            KeyValue(key: "Network", value: environment.sandbox.network),
                            KeyValue(key: "Filesystem", value: environment.sandbox.filesystem),
                        ])
                    }
                }
                compiles
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    /// The unified diff behind an accepted or pending `code` change on the reward function.
    private var codeDiff: String? {
        for session in store.sessions(for: environment) {
            if let patch = session.patches.values.first, patch.changes?.contains(where: { $0.field == "code" }) == true {
                return patch.diff
            }
        }
        return nil
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(environment.name).font(.title.weight(.semibold))
                Chip(text: environment.format.displayName)
                Chip(text: "\(environment.taskCount) tasks")
                Chip(text: "v\(store.version(of: environment))", mono: true)
                Spacer()
                StatusBadge(status: store.status(for: environment))
            }
            Text(environment.id).font(.callout.monospaced()).foregroundStyle(.secondary)
            if let description = environment.description {
                Text(description).font(.callout).foregroundStyle(.secondary).padding(.top, 2)
            }
        }
    }

    private var pendingBanner: some View {
        let changes = store.pendingChanges(for: environment)
        let hacks = Set(changes.compactMap(\.hackId))
        return HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.branch").foregroundStyle(Theme.changeAltered)
            Text("\(changes.count) proposed difference\(changes.count == 1 ? "" : "s") from hardening \(hacks.count) hack\(hacks.count == 1 ? "" : "s"). Accept or reject each one below, then compile again.")
                .font(.callout)
            Spacer()
            Button("Reject all") { store.rejectAll(in: environment) }.buttonStyle(MonoSecondaryButtonStyle())
            Button("Accept all") { store.acceptAll(in: environment) }.buttonStyle(MonoProminentButtonStyle())
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Theme.changeAltered.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(Theme.changeAltered.opacity(0.5)))
    }

    private var certificateCard: some View {
        Card(title: "Last certificate") {
            if let cert = store.latestCertificate(for: environment) {
                let status = store.status(for: environment)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "seal").font(.title3).foregroundStyle(Theme.color(for: status))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(cert.id).font(.callout.monospaced())
                        Text("Signed \(cert.issuedAt.formatted(Format.dateTime)) · auditor \(cert.auditorVersion ?? "unknown") · \(cert.findingsClosed.count) findings closed")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("hack rate \(Format.percent(cert.before.hackRate)) → \(Format.percent(cert.after.hackRate)) · pass rate \(Format.percent(cert.before.passRate)) → \(Format.percent(cert.after.passRate))")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        if case .stale(_, let reason) = status {
                            Text("Stale: \(reason). Compile again to re-sign.").font(.caption.weight(.medium))
                        }
                        Text(Format.shortHash(cert.patchedEnvHash)).font(.caption.monospaced()).foregroundStyle(.tertiary)
                    }
                }
            } else {
                Text("Never signed. A compile that comes back stable can issue the first certificate.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(width: 420)
    }

    private func provenance(_ p: ProvenanceSpec) -> some View {
        Card(title: "Provenance") {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Chip(text: p.origin.displayName)
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(p.evidence, id: \.self) { Text($0).font(.caption.monospaced()).textSelection(.enabled) }
                }
                Spacer()
                if let license = p.license { Text(license).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }

    private var compiles: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Compiles").font(.title3.weight(.semibold))
            let sessions = store.sessions(for: environment)
            if sessions.isEmpty {
                Text("Not compiled yet. Compile (⌘R) scans the environment and trains a policy against it to find what it can exploit.")
                    .font(.callout).foregroundStyle(.secondary).padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                        Button { store.select(session: session) } label: {
                            HStack(spacing: 14) {
                                Text("v\(session.version)").font(.callout.monospaced()).frame(width: 40, alignment: .leading)
                                Text(session.id).font(.callout.monospaced()).foregroundStyle(.secondary).frame(width: 220, alignment: .leading)
                                Text(session.startedAt, format: .dateTime.hour().minute().second()).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                                Spacer()
                                if session.compileFinished {
                                    Text(session.isStable ? "Stable" : "Unstable · \(session.hackCount) hack\(session.hackCount == 1 ? "" : "s")")
                                        .font(.callout.weight(.medium))
                                        .foregroundStyle(session.isStable ? Theme.statusCertified : Theme.statusVulnerable)
                                }
                                if !session.checks.isEmpty {
                                    let closed = session.checks.values.filter { $0.replay?.attackBlocked ?? ($0.after.hackRate == 0) }.count
                                    Text("\(closed)/\(session.checks.count) rechecked closed").font(.caption).foregroundStyle(.secondary)
                                }
                                PhasePill(phase: session.phase, busy: session.isBusy)
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(index.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.03))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(.separator))
            }
        }
        .padding(.top, 6)
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

/// Wrapping row of mono chips.
private struct FlowChips: View {
    let items: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { Chip(text: $0, mono: true) }
        }
    }
}

/// One part of the environment, with its proposed differences underneath, each accept-or-reject.
private struct PartCard<Content: View>: View {
    @Environment(DemoStore.self) private var store
    let part: EnvironmentPart
    let environment: AuditEnvironment
    @ViewBuilder var content: Content

    private var changes: [PendingChange] { store.pendingChanges(for: environment, part: part) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: part.systemImage).font(.callout).foregroundStyle(.secondary)
                Text(part.displayName).font(.headline)
                if !changes.isEmpty {
                    HStack(spacing: 4) {
                        Circle().fill(Theme.changeAltered).frame(width: 6, height: 6)
                        Text("\(changes.count) proposed").font(.caption.weight(.medium)).foregroundStyle(Theme.changeAltered)
                    }
                }
                Spacer()
            }
            Text(part.blurb).font(.caption).foregroundStyle(.secondary)
            Divider()
            content
            if !changes.isEmpty {
                Divider().padding(.top, 4)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(changes) { change in ChangeRow(change: change, environment: environment) }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
            .strokeBorder(changes.isEmpty ? Color(nsColor: .separatorColor) : Theme.changeAltered.opacity(0.6)))
    }
}

/// Addition in green, removal in red, alteration in yellow. Accept applies it to the environment.
private struct ChangeRow: View {
    @Environment(DemoStore.self) private var store
    let change: PendingChange
    let environment: AuditEnvironment

    private var color: Color { Theme.color(for: change.change.kind) }
    private var symbol: String {
        switch change.change.kind {
        case .add: "+"
        case .remove: "−"
        case .alter: "~"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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
                    HStack(spacing: 6) {
                        Text(change.change.field).font(.caption.monospaced()).foregroundStyle(.tertiary)
                        if let hack = change.hackId { Text("· from \(hack)").font(.caption).foregroundStyle(.tertiary) }
                    }
                    Text(change.change.rationale).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
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
        .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 3).clipShape(RoundedRectangle(cornerRadius: 2)) }
    }
}

/// What the policy is trained on: a few task inputs, scrollable sideways.
private struct SampleInputsStrip: View {
    let samples: [SampleInput]
    let taskCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "tray.full").font(.callout).foregroundStyle(.secondary)
                Text("Sample inputs").font(.headline)
                Text("\(samples.count) of \(taskCount) tasks · what the policy is trained on").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(samples) { sample in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(sample.id).font(.caption.monospaced()).foregroundStyle(.secondary)
                                Spacer()
                                if let source = sample.source {
                                    Text(source).font(.caption2.monospaced()).foregroundStyle(.tertiary).lineLimit(1)
                                }
                            }
                            Text(sample.prompt).font(.callout).lineLimit(7).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        }
                        .padding(14)
                        .frame(width: 360, alignment: .topLeading)
                        .frame(maxHeight: .infinity, alignment: .topLeading)
                        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(.separator))
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }
}
