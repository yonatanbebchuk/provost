import SwiftUI

/// The environment itself, laid out in its six mandatory parts plus provenance, with its runs below.
struct EnvironmentPage: View {
    @Environment(DemoStore.self) private var store
    let environment: AuditEnvironment

    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let spec = environment.spec {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                        PartCard(part: .objective, patched: patched(.objective)) {
                            Text(spec.objective.summary).font(.callout)
                            if !spec.objective.constraints.isEmpty {
                                bullets(spec.objective.constraints, symbol: "lock")
                            }
                        }
                        PartCard(part: .initialState, patched: patched(.initialState)) {
                            Text(spec.initialState.summary).font(.callout)
                            keyValues(spec.initialState.items)
                        }
                        PartCard(part: .observations, patched: patched(.observations)) {
                            bullets(spec.observations.visible, symbol: "eye")
                            if !spec.observations.hidden.isEmpty {
                                Divider().padding(.vertical, 2)
                                bullets(spec.observations.hidden, symbol: "eye.slash", muted: true)
                            }
                        }
                        PartCard(part: .actions, patched: patched(.actions)) {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(spec.actions) { action in
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text(action.id).font(.callout.monospaced()).frame(width: 90, alignment: .leading)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(action.description).font(.callout)
                                            if let args = action.arguments, !args.isEmpty {
                                                Text(args.map { "\($0)" }.joined(separator: ", "))
                                                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                            }
                            if !environment.sandbox.tools.isEmpty || environment.sandbox.network != "none" {
                                Divider().padding(.vertical, 2)
                                HStack(spacing: 8) {
                                    Text("Sandbox").font(.caption).foregroundStyle(.secondary)
                                    Text("\(environment.sandbox.runtime) · network \(environment.sandbox.network) · \(environment.sandbox.filesystem)")
                                        .font(.caption)
                                }
                            }
                        }
                        PartCard(part: .evaluation, patched: patched(.evaluation)) {
                            HStack(spacing: 8) {
                                Chip(text: environment.rewardType.displayName)
                                Text(spec.evaluation.summary).font(.callout)
                            }
                            if !spec.evaluation.components.isEmpty {
                                HStack(spacing: 6) {
                                    ForEach(spec.evaluation.components, id: \.self) { Chip(text: $0, mono: true) }
                                }
                            }
                            if let audit = spec.evaluation.audit {
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Image(systemName: "checkmark.shield").font(.caption).foregroundStyle(.secondary)
                                    Text(audit).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        PartCard(part: .episode, patched: patched(.episode)) {
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
                        Text("This environment was registered from its packaging only. The six parts of the specification are not available for it yet.")
                            .font(.callout).foregroundStyle(.secondary)
                        keyValues([
                            KeyValue(key: "Runtime", value: environment.sandbox.runtime),
                            KeyValue(key: "Network", value: environment.sandbox.network),
                            KeyValue(key: "Filesystem", value: environment.sandbox.filesystem),
                        ])
                    }
                }
                runs
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func patched(_ part: EnvironmentPart) -> DemoStore.PatchMark? { store.patchMarks(for: environment)[part] }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(environment.name).font(.title.weight(.semibold))
                Chip(text: environment.format.displayName)
                Chip(text: "\(environment.taskCount) tasks")
            }
            Text(environment.id).font(.callout.monospaced()).foregroundStyle(.secondary)
            if let description = environment.description {
                Text(description).font(.callout).foregroundStyle(.secondary).padding(.top, 2)
            }
        }
    }

    /// The last time this environment was signed, and whether that still holds.
    private var certificateCard: some View {
        Card(title: "Last certificate") {
            if let cert = store.latestCertificate(for: environment) {
                let status = store.status(for: environment)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "seal").font(.title3).foregroundStyle(Theme.color(for: status))
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(cert.id).font(.callout.monospaced())
                            StatusBadge(status: status, compact: true)
                        }
                        Text("Signed \(cert.issuedAt.formatted(Format.dateTime)) · auditor \(cert.auditorVersion ?? "unknown") · \(cert.findingsClosed.count) findings closed")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("hack rate \(Format.percent(cert.before.hackRate)) → \(Format.percent(cert.after.hackRate)) · pass rate \(Format.percent(cert.before.passRate)) → \(Format.percent(cert.after.passRate))")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        if case .stale(_, let reason) = status {
                            Text("Stale: \(reason). Run the audit again to re-sign.")
                                .font(.caption.weight(.medium))
                        }
                        Text(Format.shortHash(cert.patchedEnvHash)).font(.caption.monospaced()).foregroundStyle(.tertiary)
                    }
                }
            } else {
                Text("Never signed. A run that closes its findings and verifies the patch issues the first certificate.")
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
                if let license = p.license {
                    Text(license).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var runs: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Runs").font(.title3.weight(.semibold))
                Spacer()
                Button {
                    Task { await store.newRun() }
                } label: {
                    Label("New Run", systemImage: "play.fill")
                }
                .buttonStyle(MonoProminentButtonStyle())
                .keyboardShortcut("r", modifiers: .command)
            }
            let sessions = store.sessions(for: environment)
            if sessions.isEmpty {
                Text("No runs yet. A run scans the environment, trains the adversarial policy against it, and proposes a patch.")
                    .font(.callout).foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                        Button { store.select(session: session) } label: {
                            HStack(spacing: 14) {
                                Text(session.id).font(.callout.monospaced()).frame(width: 220, alignment: .leading)
                                Text(session.run.config.model).font(.callout).foregroundStyle(.secondary).frame(width: 170, alignment: .leading)
                                Text(session.startedAt, format: .dateTime.hour().minute().second()).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                                Spacer()
                                if let liftoff = session.liftoff {
                                    Text("liftoff · \(liftoff.step)").font(.callout.weight(.medium)).foregroundStyle(Theme.liftoff)
                                }
                                if let r = session.verifyResult {
                                    Text("hack \(Format.percent(r.before.hackRate)) → \(Format.percent(r.after.hackRate))")
                                        .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
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
                    Text(item).font(.callout).foregroundStyle(muted ? .secondary : .primary)
                        .fixedSize(horizontal: false, vertical: true)
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

/// One of the six parts. The dot marks a part a proposed patch would change.
private struct PartCard<Content: View>: View {
    let part: EnvironmentPart
    let patched: DemoStore.PatchMark?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: part.systemImage).font(.callout).foregroundStyle(.secondary)
                Text(part.displayName).font(.headline)
                if let patched {
                    let color = patched == .applied ? Theme.statusCertified : Theme.liftoff
                    HStack(spacing: 4) {
                        Circle().fill(color).frame(width: 6, height: 6)
                        Text(patched == .applied ? "patched" : "patch pending").font(.caption.weight(.medium)).foregroundStyle(color)
                    }
                }
                Spacer()
            }
            Text(part.blurb).font(.caption).foregroundStyle(.secondary)
            Divider()
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(.separator))
    }
}
