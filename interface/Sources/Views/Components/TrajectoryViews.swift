import SwiftUI

/// The rollouts of one compile, side by side. Each card is one trajectory: its steps in order, the
/// step that created a hack lit in red or yellow by severity. Cards appear as the compile samples them.
struct TrajectoryBoard: View {
    @Environment(DemoStore.self) private var store
    @Environment(RunSession.self) private var session
    var hacksOnly: Bool

    private var rows: [Trajectory] {
        hacksOnly ? session.hacks : session.trajectories
    }

    @State private var position = ScrollPosition(edge: .leading)

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(rows) { t in
                    TrajectoryCard(trajectory: t, animate: session.isBusy && !session.compileFinished)
                        .id(t.id)
                }
                if session.isBusy && !session.compileFinished {
                    RollingCard().id("rolling")
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 4)
        }
        .scrollPosition($position)
        // A finished compile gets a fresh scroll view, so it opens on the first card.
        .id(session.compileFinished)
        .onChange(of: session.trajectories.count) { _, _ in
            // Follow the newest rollout while the compile is sampling.
            withAnimation(.easeOut(duration: 0.35)) { position.scrollTo(edge: .trailing) }
        }
        .onChange(of: session.compileFinished) { _, finished in
            // The fresh scroll view binds to this position, so it must point at the start again.
            if finished { position = ScrollPosition(edge: .leading) }
        }
        .overlay {
            if rows.isEmpty && !(session.isBusy && !session.compileFinished) {
                Text(hacksOnly ? "No hacks." : "No rollouts.").font(.callout).foregroundStyle(.tertiary)
            }
        }
    }
}

/// One rollout. Header: task, step, reward, and the hack tick-box. Body: the steps.
struct TrajectoryCard: View {
    @Environment(DemoStore.self) private var store
    @Environment(RunSession.self) private var session
    let trajectory: Trajectory
    var animate: Bool
    @State private var revealed = 0

    private var steps: [TraceStep] { trajectory.trace }
    private var hackIndex: Int? { trajectory.hackStepIndex }
    private var tint: Color { Theme.color(for: trajectory.hackSeverity) }
    private var isSelected: Bool { session.selectedHacks.contains(trajectory.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if trajectory.isHack, let hackIndex {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill").font(.caption2.weight(.bold))
                    Text("Hack at step \(hackIndex + 1)").font(.caption.weight(.semibold))
                    Text("·").foregroundStyle(.secondary)
                    Text(trajectory.hackSeverity.displayName).font(.caption.weight(.medium))
                    Spacer()
                }
                .foregroundStyle(tint)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(tint.opacity(0.12))
            }
            Divider()
            Button { session.selectedTrajectory = trajectory } label: {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(steps.prefix(revealed)) { step in
                            StepRow(step: step, lit: step.index == hackIndex ? tint : nil)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        if revealed < steps.count {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.mini)
                                Text("step \(revealed + 1)").font(.caption).foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Divider()
            footer
        }
        .frame(width: 320)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
            .strokeBorder(trajectory.isHack ? tint.opacity(isSelected ? 0.9 : 0.5) : Color(nsColor: .separatorColor), lineWidth: isSelected ? 2 : 1))
        .task(id: trajectory.id) {
            guard animate else { revealed = steps.count; return }
            revealed = 0
            let pause = store.isFastForward ? 45 : 180
            for i in 1...max(steps.count, 1) {
                try? await Task.sleep(for: .milliseconds(pause))
                withAnimation(.easeOut(duration: 0.2)) { revealed = i }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if trajectory.isHack && session.compileFinished {
                Toggle("", isOn: Binding(
                    get: { isSelected },
                    set: { on in if on { session.selectedHacks.insert(trajectory.id) } else { session.selectedHacks.remove(trajectory.id) } }
                ))
                .toggleStyle(.checkbox).labelsHidden()
            }
            Text(trajectory.taskId).font(.callout.weight(.semibold).monospaced()).lineLimit(1).truncationMode(.middle)
            Spacer()
            Text("step \(trajectory.step)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Text(Format.score(trajectory.reward.total)).font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(trajectory.isHack ? tint : .primary)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(trajectory.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            if trajectory.isHack && session.compileFinished {
                HackActions(hack: trajectory)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
    }
}

/// One step of a rollout: number, what the policy did, what came back.
struct StepRow: View {
    let step: TraceStep
    var lit: Color?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(step.index + 1)").font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(lit ?? .secondary).frame(width: 16, alignment: .trailing).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.action).font(.callout.monospaced()).foregroundStyle(lit ?? .primary)
                    .lineLimit(step.kind == .message ? 8 : 3).fixedSize(horizontal: false, vertical: true)
                if let result = step.result {
                    Text(result).font(.caption.monospaced()).foregroundStyle(.tertiary).lineLimit(3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(lit.map { $0.opacity(0.14) } ?? .clear)
        .overlay(alignment: .leading) {
            if let lit { Rectangle().fill(lit).frame(width: 3) }
        }
    }
}

/// Placeholder at the end of the board while the compile is still sampling.
struct RollingCard: View {
    @Environment(RunSession.self) private var session

    var body: some View {
        VStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Rolling out").font(.callout.weight(.medium))
            Text("training step \(session.trainingPoints.last?.step ?? 0) / \(session.run.config.steps)")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .frame(width: 200)
        .frame(maxHeight: .infinity)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4])).foregroundStyle(.separator))
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
                    let pending = store.pendingChanges(for: session.environment).filter { $0.hackIds.contains(hack.id) }.count
                    Button(pending > 0 ? "\(pending) pending" : "Differences") { session.page = .report }
                        .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(session.checking.contains(hack.id) ? "Checking…" : "Recheck") {
                        Task { await session.check(hack) }
                    }
                    .buttonStyle(MonoSecondaryButtonStyle())
                    .controlSize(.small)
                    .disabled(session.isBusy)
                } else {
                    Spacer()
                    Button(session.hardening.contains(hack.id) ? "Hardening…" : "Harden") {
                        Task {
                            session.selectedHacks = [hack.id]
                            await store.hardenSelected(in: session)
                        }
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

    private var tint: Color { Theme.color(for: trajectory.hackSeverity) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(trajectory.taskId).font(.title2.weight(.semibold).monospaced())
                Text("step \(trajectory.step)").foregroundStyle(.secondary)
                Spacer()
                if trajectory.isHack, let i = trajectory.hackStepIndex {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill").font(.caption.weight(.bold))
                        Text("Hack at step \(i + 1) · \(trajectory.hackSeverity.displayName)")
                    }
                    .font(.callout.weight(.semibold)).foregroundStyle(tint)
                }
            }
            Text(trajectory.summary).font(.body).foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 16) {
                    section("Prompt") { Text(trajectory.prompt).font(.callout).textSelection(.enabled) }
                    section("Steps") {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(trajectory.trace) { step in
                                    FullStepRow(step: step, lit: step.index == trajectory.hackStepIndex ? tint : nil)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 300)
                    }
                }
                VStack(alignment: .leading, spacing: 16) {
                    section("Reward") {
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
                        section("Judge") {
                            ScrollView {
                                Text(judge).font(.callout.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 100)
                        }
                    }
                    section("Grader") { Text(trajectory.graderNotes).font(.callout).textSelection(.enabled) }
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
        .frame(width: 880, height: 640)
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
}

/// A step with its full action and result, for the detail sheet.
private struct FullStepRow: View {
    let step: TraceStep
    var lit: Color?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(step.index + 1)").font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(lit ?? .secondary).frame(width: 18, alignment: .trailing)
            VStack(alignment: .leading, spacing: 3) {
                Text((step.kind == .command ? "$ " : "") + step.action).font(.callout.monospaced())
                    .foregroundStyle(lit ?? .primary).textSelection(.enabled)
                if let result = step.result {
                    Text(result).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6).padding(.horizontal, 6)
        .background(lit.map { $0.opacity(0.14) } ?? .clear, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}
