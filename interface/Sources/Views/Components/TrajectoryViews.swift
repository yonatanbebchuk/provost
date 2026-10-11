import SwiftUI

/// The rollouts of one compile as a growing list. Each row is one trajectory; press the row to drop
/// its trace down, press the name to open the deep dive. Hack steps are painted red, a softer red for
/// medium severity.
struct RolloutList: View {
    @Environment(DemoStore.self) private var store
    @Environment(RunSession.self) private var session
    @State private var expanded: Set<String> = []

    private var rows: [Trajectory] { session.trajectories }
    private var sampling: Bool { session.isBusy && !session.compileFinished }
    /// Hacks that can still be ticked: not hardened yet.
    private var selectable: [String] { session.hacks.filter { session.patches[$0.id] == nil }.map(\.id) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    header
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, t in
                        RolloutRow(trajectory: t, zebra: !index.isMultiple(of: 2), isExpanded: expanded.contains(t.id)) {
                            if expanded.contains(t.id) { expanded.remove(t.id) } else { expanded.insert(t.id) }
                        }
                        .id(t.id)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    if sampling {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("Rolling out · training step \(session.trainingPoints.last?.step ?? 0) / \(session.run.config.steps)")
                                .font(.callout).foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 14).frame(height: 34)
                        .id("rolling")
                    }
                }
                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(.separator))
                .padding(.horizontal, 24).padding(.vertical, 4)
            }
            .onChange(of: session.trajectories.count) { _, _ in
                guard sampling else { return }
                withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo("rolling", anchor: .bottom) }
            }
            .overlay {
                if rows.isEmpty && !sampling {
                    Text("No rollouts.").font(.callout).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            // Ticks every hack that can be hardened, or clears the selection.
            if session.compileFinished && !selectable.isEmpty {
                let all = Set(selectable)
                let selected = session.selectedHacks.intersection(all)
                Toggle("", isOn: Binding(
                    get: { !selected.isEmpty && selected == all },
                    set: { on in session.selectedHacks = on ? all : [] }
                ))
                .toggleStyle(.checkbox).labelsHidden().frame(width: 14)
                .help(selected == all ? "Deselect all hacks" : "Select all hacks")
            } else {
                Text("").frame(width: 14)
            }
            Text("Rollout").frame(width: 190, alignment: .leading)
            Text("What it did").frame(maxWidth: .infinity, alignment: .leading)
            Text("Reward").frame(width: 56, alignment: .trailing)
            Text("Intent").frame(width: 56, alignment: .trailing)
            Text("").frame(width: 190)
        }
        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        .padding(.horizontal, 14).frame(height: 30)
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// One rollout: a row that drops its trace down when pressed. The name opens the deep dive.
struct RolloutRow: View {
    @Environment(DemoStore.self) private var store
    @Environment(RunSession.self) private var session
    let trajectory: Trajectory
    var zebra: Bool
    var isExpanded: Bool
    var toggle: () -> Void

    private var tint: Color? { trajectory.isHack ? Theme.color(for: trajectory.hackSeverity) : nil }
    private var isSelected: Bool { session.selectedHacks.contains(trajectory.id) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if trajectory.isHack && session.compileFinished {
                    Toggle("", isOn: Binding(
                        get: { isSelected },
                        set: { on in if on { session.selectedHacks.insert(trajectory.id) } else { session.selectedHacks.remove(trajectory.id) } }
                    ))
                    .toggleStyle(.checkbox).labelsHidden().frame(width: 14)
                } else {
                    Circle().fill(tint ?? .clear).frame(width: 7, height: 7).frame(width: 14)
                }
                // The row is a tap target, not a button, so the name inside stays its own button.
                HStack(spacing: 12) {
                    Group {
                        Button { session.selectedTrajectory = trajectory } label: {
                            HStack(spacing: 6) {
                                Text(trajectory.taskId).font(.callout.weight(.semibold).monospaced()).lineLimit(1).truncationMode(.middle)
                                Image(systemName: "arrow.up.forward.square").font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Open the deep dive · sampled at training step \(trajectory.step)")
                        .frame(width: 190, alignment: .leading)
                        HStack(spacing: 6) {
                            if trajectory.isHack {
                                Text("HACK").font(.caption2.weight(.bold)).kerning(0.4).fixedSize()
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .foregroundStyle(tint!)
                                    .background(tint!.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                            }
                            Text(trajectory.summary).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(Format.score(trajectory.reward.total)).monospacedDigit().fontWeight(trajectory.isHack ? .semibold : .regular)
                            .foregroundStyle(tint ?? .primary).frame(width: 56, alignment: .trailing)
                        intent.frame(width: 56, alignment: .trailing)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: toggle)
                HStack(spacing: 8) {
                    if trajectory.isHack && session.compileFinished { HackActions(hack: trajectory, compact: true) }
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .frame(width: 190, alignment: .trailing)
            }
            .font(.callout)
            .padding(.horizontal, 14).frame(height: 34)
            .background(isExpanded ? Color.primary.opacity(0.05) : (zebra ? Color.primary.opacity(0.025) : .clear))
            if isExpanded {
                TraceTimeline(trajectory: trajectory)
                    .padding(.leading, 14 + 14 + 12).padding(.trailing, 24).padding(.vertical, 10)
                    .background(Color.primary.opacity(0.025))
                    .overlay(alignment: .top) { Divider() }
            }
        }
        .overlay(alignment: .leading) {
            if let tint { Rectangle().fill(tint).frame(width: 3) }
        }
    }

    @ViewBuilder
    private var intent: some View {
        if let met = trajectory.intendedSuccess {
            Text(met ? "met" : "failed").font(.caption.weight(.semibold))
                .foregroundStyle(met ? Theme.statusCertified : (tint ?? Theme.statusVulnerable))
        } else {
            Text("—").foregroundStyle(.tertiary)
        }
    }
}

/// The steps of a rollout as a timeline: dot and line down the left, the step that created a hack in
/// red. `full` shows whole results; otherwise they are clipped to a few lines.
struct TraceTimeline: View {
    let trajectory: Trajectory
    var full = false

    private var tint: Color { Theme.color(for: trajectory.hackSeverity) }

    var body: some View {
        let steps = trajectory.trace
        VStack(alignment: .leading, spacing: 0) {
            ForEach(steps) { step in
                let lit = step.index == trajectory.hackStepIndex
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 0) {
                        Circle().fill(lit ? tint : Color.secondary.opacity(0.5)).frame(width: lit ? 9 : 7, height: lit ? 9 : 7).padding(.top, 6)
                        if step.index < steps.count - 1 {
                            Rectangle().fill(.separator).frame(width: 1).frame(maxHeight: .infinity)
                        }
                    }
                    .frame(width: 10)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(step.index + 1)").font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(lit ? tint : .secondary)
                            Text((step.kind == .command ? "$ " : "") + step.action).font(.callout.monospaced())
                                .foregroundStyle(lit ? tint : .primary).lineLimit(full ? nil : 3).textSelection(.enabled)
                            if lit {
                                Text("hack · \(trajectory.hackSeverity.displayName.lowercased())").font(.caption.weight(.semibold)).foregroundStyle(tint).fixedSize()
                            }
                        }
                        if let result = step.result {
                            Text(result).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(full ? nil : 3).textSelection(.enabled)
                        }
                    }
                    .padding(.vertical, 6).padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(lit ? tint.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .padding(.bottom, 4)
                }
            }
        }
    }
}

/// Harden → (differences pending) → Recheck → closed / still rewarded.
struct HackActions: View {
    @Environment(DemoStore.self) private var store
    @Environment(RunSession.self) private var session
    let hack: Trajectory
    /// Row-height buttons for the list.
    var compact = false
    /// Where hardening leads: the report page, or nowhere because the caller shows the differences.
    var opensReport = true

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
                    Button(session.checking.contains(hack.id) ? "Checking…" : "Recheck") {
                        Task { await session.check(hack) }
                    }
                    .modifier(HackButton(compact: compact))
                    .disabled(session.isBusy)
                } else {
                    Button(session.hardening.contains(hack.id) ? "Hardening…" : "Harden") {
                        Task {
                            session.selectedHacks = [hack.id]
                            await store.hardenSelected(in: session, openReport: opensReport)
                        }
                    }
                    .modifier(HackButton(compact: compact))
                    .disabled(session.hardening.contains(hack.id) || !session.compileFinished)
                }
            }
        }
    }
}

/// Compact in a list row, regular elsewhere.
private struct HackButton: ViewModifier {
    var compact: Bool
    func body(content: Content) -> some View {
        if compact {
            content.buttonStyle(MonoCompactButtonStyle())
        } else {
            content.buttonStyle(MonoSecondaryButtonStyle()).controlSize(.small)
        }
    }
}

/// The deep dive on one rollout: reward earned against human intent, requirement by requirement,
/// the full trace, the reward's own checks, the judge, and the hardening actions.
struct TrajectoryDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RunSession.self) private var session
    let trajectory: Trajectory

    @Environment(DemoStore.self) private var store
    private var tint: Color { trajectory.isHack ? Theme.color(for: trajectory.hackSeverity) : .primary }
    private var intentMet: Bool? { trajectory.intendedSuccess }
    private var changes: [PendingChange] { store.changes(for: trajectory, in: session.environment) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    verdict
                    if let rows = trajectory.comparisons, !rows.isEmpty { comparisons(rows) }
                    if trajectory.isHack { differences }
                    section("Trace · \(trajectory.trace.count) steps") { TraceTimeline(trajectory: trajectory, full: true) }
                    HStack(alignment: .top, spacing: 20) {
                        section("Reward checks") { rewardChecks }.frame(maxWidth: .infinity)
                        VStack(alignment: .leading, spacing: 16) {
                            section("Grader") { Text(trajectory.graderNotes).font(.callout).textSelection(.enabled) }
                            if let judge = trajectory.judgeOutput {
                                section("Judge") { Text(judge).font(.callout.monospaced()).textSelection(.enabled) }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    section("Prompt") { Text(trajectory.prompt).font(.callout).textSelection(.enabled) }
                    if let evidence = trajectory.evidence {
                        Label(evidence, systemImage: "doc.badge.ellipsis").font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            Divider()
            HStack {
                Spacer()
                HackActions(hack: trajectory, opensReport: false)
                Button("Close") { dismiss() }
                    .buttonStyle(MonoProminentButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 24).padding(.vertical, 12)
            .background(.bar)
        }
        .frame(width: 980, height: 720)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(trajectory.taskId).font(.title.weight(.semibold).monospaced())
            Text("sampled at training step \(trajectory.step)").font(.callout).foregroundStyle(.secondary)
            Text(trajectory.id).font(.callout.monospaced()).foregroundStyle(.tertiary)
            Spacer()
            if trajectory.isHack {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill").font(.caption.weight(.bold))
                    Text("Reward hack · \(trajectory.hackSeverity.displayName)")
                }
                .font(.callout.weight(.semibold)).foregroundStyle(tint)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(tint.opacity(0.12), in: Capsule())
            }
        }
    }

    /// Reward earned against human intent, side by side: the whole story in two numbers.
    private var verdict: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("REWARD EARNED").font(.caption.weight(.semibold)).foregroundStyle(.secondary).kerning(0.6)
                Text(Format.score(trajectory.reward.total))
                    .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(trajectory.isHack ? tint : .primary)
                Text("what the environment paid").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(.separator))

            VStack(alignment: .leading, spacing: 4) {
                Text("HUMAN INTENT").font(.caption.weight(.semibold)).foregroundStyle(.secondary).kerning(0.6)
                Text(intentMet.map { $0 ? "Met" : "Failed" } ?? "Unknown")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(intentMet.map { $0 ? Theme.statusCertified : Theme.statusVulnerable } ?? .secondary)
                Text("what the task actually asked for").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(.separator))

            VStack(alignment: .leading, spacing: 6) {
                Text("WHAT IT DID").font(.caption.weight(.semibold)).foregroundStyle(.secondary).kerning(0.6)
                Text(trajectory.summary).font(.body).fixedSize(horizontal: false, vertical: true)
                if trajectory.isHack, let i = trajectory.hackStepIndex {
                    Text("Created at step \(i + 1) of \(trajectory.trace.count).").font(.caption).foregroundStyle(tint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(.separator))
        }
    }

    /// What hardening proposes for this hack, accept or reject in place. Before hardening, the invitation.
    @ViewBuilder
    private var differences: some View {
        let pending = changes.filter { $0.decision == .pending }.count
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(changes.isEmpty ? "DIFFERENCES" : "DIFFERENCES · \(pending) OF \(changes.count) UNDECIDED")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary).kerning(0.6)
                Spacer()
                if pending > 0 {
                    Button("Reject all") { for c in changes where c.decision == .pending { store.reject(c, in: session.environment) } }
                        .buttonStyle(MonoCompactButtonStyle())
                    Button("Accept all") { for c in changes where c.decision == .pending { store.accept(c, in: session.environment) } }
                        .buttonStyle(MonoCompactButtonStyle())
                }
            }
            if changes.isEmpty {
                HStack(spacing: 12) {
                    Text(session.hardening.contains(trajectory.id) ? "Hardening…" : "Harden this hack to see what would close it.")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    if !session.hardening.contains(trajectory.id) {
                        Button("Harden") {
                            Task {
                                session.selectedHacks = [trajectory.id]
                                await store.hardenSelected(in: session, openReport: false)
                            }
                        }
                        .buttonStyle(MonoProminentButtonStyle()).controlSize(.small)
                        .disabled(!session.compileFinished)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.codeBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(changes) { change in ChangeRow(change: change, environment: session.environment, showPart: true) }
                }
            }
        }
    }

    /// Requirement by requirement: what the task asked, what happened, what it cost.
    private func comparisons(_ rows: [OutcomeComparison]) -> some View {
        section("Requirements · \(rows.filter(\.failed).count) of \(rows.count) failed") {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("Requirement").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Expected").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Observed").frame(maxWidth: .infinity, alignment: .leading)
                    Text("").frame(width: 60)
                }
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.bottom, 6)
                ForEach(rows) { row in
                    Divider()
                    HStack(alignment: .top, spacing: 12) {
                        Text(row.label).font(.callout.weight(.medium)).frame(maxWidth: .infinity, alignment: .leading)
                        Text(row.expected).font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.observed).font(.callout).foregroundStyle(row.failed ? tint : .primary)
                            if let consequence = row.consequence {
                                Text(consequence).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(row.failed ? "failed" : "met").font(.caption.weight(.semibold))
                            .foregroundStyle(row.failed ? tint : Theme.statusCertified).frame(width: 60, alignment: .trailing)
                    }
                    .padding(.vertical, 7)
                }
            }
        }
    }

    private var rewardChecks: some View {
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
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary).kerning(0.6)
            content()
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.codeBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }
}
