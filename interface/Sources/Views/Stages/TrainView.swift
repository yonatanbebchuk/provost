import SwiftUI

struct TrainView: View {
    @Environment(RunSession.self) private var session

    private var totalSteps: Int { session.run.config.steps }
    private var currentStep: Int { session.trainingPoints.last?.step ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                header
                TrainingChart(points: session.trainingPoints, totalSteps: totalSteps, liftoff: session.liftoff)
                    .frame(minHeight: 150, idealHeight: 260, maxHeight: 280)
                    .padding(.top, 6)
                HStack {
                    ChartLegend(showLiftoff: session.liftoff != nil)
                    Spacer()
                    if let last = session.trainingPoints.last {
                        HStack(spacing: 14) {
                            metric("proxy", last.proxyReward)
                            metric("true", last.trueScore)
                            metric("gap", last.gap, emphasize: session.liftoff != nil)
                            metric("kl", last.kl, digits: 3)
                        }
                    }
                }
                if let liftoff = session.liftoff {
                    LiftoffBanner(liftoff: liftoff)
                }
                HStack(alignment: .top, spacing: 16) {
                    TrajectoryTable(trajectories: session.trajectories)
                    FindingsPanel(findings: session.findings)
                        .frame(width: 420)
                }
                .frame(minHeight: 110, maxHeight: .infinity)
                .layoutPriority(1)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            StageFooter(busyLabel: session.phase == .linting ? "Scanning environment…" : "Training · step \(currentStep) / \(totalSteps)") {
                if session.trainingFinished {
                    Text("\(session.trajectories.count) trajectories sampled · \(session.hackCount) flagged as hacks")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Adversarial run").font(.title2.weight(.semibold))
                let run = session.run
                Text("\(run.config.model) · \(run.config.algorithm) · seed \(run.config.seed)" + (run.config.rolloutsPerStep.map { " · \($0) rollouts/step" } ?? ""))
                    .font(.callout.monospaced()).foregroundStyle(.secondary)
            }
            Spacer()
            Text("step \(currentStep) / \(totalSteps)")
                .font(.title3.monospacedDigit().weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private func metric(_ label: String, _ value: Double, digits: Int = 2, emphasize: Bool = false) -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(.secondary)
            Text(String(format: "%+.\(digits)f", value).replacingOccurrences(of: "+", with: label == "gap" ? "+" : ""))
                .foregroundStyle(emphasize ? Theme.liftoff : .primary)
                .fontWeight(emphasize ? .semibold : .regular)
        }
        .font(.callout.monospacedDigit())
    }
}

struct LiftoffBanner: View {
    let liftoff: LiftoffEvent

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "arrow.up.right.circle.fill")
                .font(.title3)
                .foregroundStyle(Theme.liftoff)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("Liftoff at step \(liftoff.step)").font(.body.weight(.semibold))
                    Text("·").foregroundStyle(.tertiary)
                    Text("matched").foregroundStyle(.secondary)
                    Text(liftoff.failureMode.rawValue).font(.body.monospaced())
                    Text("·").foregroundStyle(.tertiary)
                    Text("confidence \(Format.score(liftoff.confidence))").foregroundStyle(.secondary)
                }
                Text(liftoff.summary).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(Theme.liftoff.opacity(0.09), in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(Theme.liftoff.opacity(0.5)))
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

struct TrajectoryTable: View {
    @Environment(RunSession.self) private var session
    var trajectories: [Trajectory]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Trajectories").font(.headline)
                Text("\(trajectories.count)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Text("Click a row for the full rollout").font(.caption).foregroundStyle(.tertiary)
            }
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("Step").frame(width: 44, alignment: .leading)
                    Text("Task").frame(width: 150, alignment: .leading)
                    Text("What it did").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Reward").frame(width: 56, alignment: .trailing)
                    Text("Flag").frame(width: 56, alignment: .leading)
                }
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.vertical, 6)
                Divider()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(trajectories.reversed().enumerated()), id: \.element.id) { index, t in
                            Button { session.selectedTrajectory = t } label: {
                                HStack(spacing: 12) {
                                    Text("\(t.step)").monospacedDigit().frame(width: 44, alignment: .leading)
                                    Text(t.taskId).font(.body.monospaced()).lineLimit(1).frame(width: 150, alignment: .leading)
                                    Text(t.summary).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                    Text(Format.score(t.reward.total)).monospacedDigit().frame(width: 56, alignment: .trailing)
                                    Group {
                                        if t.isHack {
                                            Text("HACK")
                                                .font(.caption2.weight(.bold)).kerning(0.4)
                                                .padding(.horizontal, 6).padding(.vertical, 2)
                                                .foregroundStyle(Theme.liftoff)
                                                .background(Theme.liftoff.opacity(0.14), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                                        } else if t.hackExcerpt != nil {
                                            Text("tell").font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(width: 56, alignment: .leading)
                                }
                                .font(.callout)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(index.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.03))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .overlay {
                    if trajectories.isEmpty {
                        Text("Rollouts appear here as training samples them.")
                            .font(.callout).foregroundStyle(.tertiary)
                    }
                }
            }
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(.separator))
        }
    }
}

struct TrajectoryDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
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
                    .font(.callout.weight(.semibold)).foregroundStyle(Theme.liftoff)
                }
            }
            Text(trajectory.summary).font(.body).foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 16) {
                    section("Prompt") {
                        Text(trajectory.prompt).font(.callout).textSelection(.enabled)
                    }
                    section("Model output") {
                        ScrollView {
                            Text(highlightedOutput)
                                .font(.callout.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 260)
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
                        }
                    }
                    if let judge = trajectory.judgeOutput {
                        section("Judge / verifier output") {
                            ScrollView {
                                Text(judge).font(.callout.monospaced()).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 110)
                        }
                    }
                    section("Grader notes") {
                        Text(trajectory.graderNotes).font(.callout).textSelection(.enabled)
                    }
                }
                .frame(width: 280)
            }

            HStack {
                if let evidence = trajectory.evidence {
                    Label(evidence, systemImage: "doc.badge.ellipsis")
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
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
        text[range].backgroundColor = Theme.liftoff.opacity(0.22)
        text[range].foregroundColor = Theme.liftoff
        text[range].font = .callout.monospaced().weight(.semibold)
        return text
    }
}
