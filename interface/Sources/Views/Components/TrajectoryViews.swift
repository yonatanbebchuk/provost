import SwiftUI

struct LiftoffBanner: View {
    let liftoff: LiftoffEvent

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "arrow.up.right.circle.fill").font(.title3).foregroundStyle(Theme.liftoff)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("Liftoff at step \(liftoff.step)").font(.body.weight(.semibold))
                    Text("·").foregroundStyle(.tertiary)
                    Text("matched").foregroundStyle(.secondary)
                    Text(liftoff.failureMode.rawValue).font(.body.monospaced())
                    Text("·").foregroundStyle(.tertiary)
                    Text("confidence \(Format.score(liftoff.confidence))").foregroundStyle(.secondary)
                }
                Text(liftoff.summary).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(Theme.liftoff.opacity(0.09), in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(Theme.liftoff.opacity(0.5)))
    }
}

/// The hacks a compile found, with Harden and Recheck per row, then the rest of the trajectories.
struct HacksTable: View {
    @Environment(DemoStore.self) private var store
    @Environment(RunSession.self) private var session

    private var rows: [Trajectory] { session.trajectories.reversed().sorted { $0.isHack && !$1.isHack } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(session.hackCount > 0 ? "Hacks" : "Trajectories").font(.headline)
                Text(session.hackCount > 0 ? "\(session.hackCount) of \(session.trajectories.count) trajectories" : "\(session.trajectories.count)")
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Text("Click a row for the full trace").font(.caption).foregroundStyle(.tertiary)
            }
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("Step").frame(width: 44, alignment: .leading)
                    Text("Task").frame(width: 124, alignment: .leading)
                    Text("What it did").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Reward").frame(width: 52, alignment: .trailing)
                    Text("").frame(width: 176)
                }
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.vertical, 6)
                Divider()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, t in
                            HStack(spacing: 12) {
                                Button { session.selectedTrajectory = t } label: {
                                    HStack(spacing: 12) {
                                        Text("\(t.step)").monospacedDigit().frame(width: 44, alignment: .leading)
                                        Text(t.taskId).font(.body.monospaced()).lineLimit(1).truncationMode(.middle).frame(width: 124, alignment: .leading)
                                        HStack(spacing: 6) {
                                            if t.isHack {
                                                Text("HACK").font(.caption2.weight(.bold)).kerning(0.4).fixedSize()
                                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                                    .foregroundStyle(Theme.statusVulnerable)
                                                    .background(Theme.statusVulnerable.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                                            }
                                            Text(t.summary).lineLimit(1)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        Text(Format.score(t.reward.total)).monospacedDigit().frame(width: 52, alignment: .trailing)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                HackActions(hack: t).frame(width: 176, alignment: .trailing)
                            }
                            .font(.callout)
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(index.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.03))
                        }
                    }
                }
                .overlay {
                    if session.trajectories.isEmpty {
                        Text("Rollouts appear here as the compile samples them.").font(.callout).foregroundStyle(.tertiary)
                    }
                }
            }
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(.separator))
        }
    }
}

/// Harden → (differences pending) → Recheck → closed / still rewarded.
struct HackActions: View {
    @Environment(DemoStore.self) private var store
    @Environment(RunSession.self) private var session
    let hack: Trajectory

    var body: some View {
        if hack.isHack {
            HStack(spacing: 8) {
                if let check = session.checks[hack.id] {
                    let closed = check.replay?.attackBlocked ?? (check.after.hackRate == 0)
                    HStack(spacing: 5) {
                        Image(systemName: closed ? "checkmark.circle.fill" : "xmark.circle.fill")
                        Text(closed ? "Closed" : "Still rewarded")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(closed ? Theme.statusCertified : Theme.statusVulnerable)
                } else if session.patches[hack.id] != nil {
                    Text("\(store.pendingChanges(for: session.environment).filter { $0.hackId == hack.id }.count) pending")
                        .font(.caption).foregroundStyle(.secondary)
                    Button(session.checking.contains(hack.id) ? "Checking…" : "Recheck") {
                        Task { await session.check(hack) }
                    }
                    .buttonStyle(MonoSecondaryButtonStyle())
                    .controlSize(.small)
                    .disabled(session.isBusy)
                } else {
                    Button(session.hardening.contains(hack.id) ? "Hardening…" : "Harden") {
                        Task { await store.harden(hack, in: session) }
                    }
                    .buttonStyle(MonoSecondaryButtonStyle())
                    .controlSize(.small)
                    .disabled(session.hardening.contains(hack.id) || !session.compileFinished)
                }
            }
        }
    }
}

struct TrajectoryDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RunSession.self) private var session
    let trajectory: Trajectory

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(trajectory.taskId).font(.title2.weight(.semibold).monospaced())
                Text("step \(trajectory.step)").foregroundStyle(.secondary)
                Text(trajectory.id).font(.callout.monospaced()).foregroundStyle(.tertiary)
                Spacer()
                if trajectory.isHack {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.right").font(.caption.weight(.bold))
                        Text("Reward hack")
                    }
                    .font(.callout.weight(.semibold)).foregroundStyle(Theme.statusVulnerable)
                }
            }
            Text(trajectory.summary).font(.body).foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 16) {
                    section("Prompt") { Text(trajectory.prompt).font(.callout).textSelection(.enabled) }
                    section("Model output") {
                        ScrollView {
                            Text(highlightedOutput).font(.callout.monospaced()).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 240)
                    }
                }
                VStack(alignment: .leading, spacing: 16) {
                    section("Reward breakdown") {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                            ForEach(trajectory.reward.components, id: \.name) { c in
                                GridRow {
                                    Text(c.name).font(.callout.monospaced())
                                    Text(Format.score(c.value)).monospacedDigit().gridColumnAlignment(.trailing)
                                    Text(c.weight.map { "× \(Format.score($0))" } ?? "").font(.caption).foregroundStyle(.tertiary)
                                }
                            }
                            Divider()
                            GridRow {
                                Text("total").font(.callout.weight(.semibold))
                                Text(Format.score(trajectory.reward.total)).monospacedDigit().fontWeight(.semibold)
                                Text("")
                            }
                            if let intended = trajectory.intendedSuccess {
                                GridRow {
                                    Text("intent met").font(.callout)
                                    Text(intended ? "yes" : "no").fontWeight(.semibold)
                                        .foregroundStyle(intended ? Theme.statusCertified : Theme.statusVulnerable)
                                    Text("")
                                }
                            }
                        }
                    }
                    if let judge = trajectory.judgeOutput {
                        section("Judge / verifier output") {
                            ScrollView {
                                Text(judge).font(.callout.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 100)
                        }
                    }
                    section("Grader notes") { Text(trajectory.graderNotes).font(.callout).textSelection(.enabled) }
                }
                .frame(width: 280)
            }

            HStack {
                if let evidence = trajectory.evidence {
                    Label(evidence, systemImage: "doc.badge.ellipsis").font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Spacer()
                HackActions(hack: trajectory)
                Button("Close") { dismiss() }
                    .buttonStyle(MonoProminentButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 860, height: 600)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary).kerning(0.6)
            content()
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.codeBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    private var highlightedOutput: AttributedString {
        var text = AttributedString(trajectory.output)
        guard let excerpt = trajectory.hackExcerpt, let range = text.range(of: excerpt) else { return text }
        text[range].backgroundColor = Theme.statusVulnerable.opacity(0.18)
        text[range].foregroundColor = Theme.statusVulnerable
        text[range].font = .callout.monospaced().weight(.semibold)
        return text
    }
}
