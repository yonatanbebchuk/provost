import SwiftUI

/// The result of one compile: Stable or Unstable, the hacks with their traces, the static findings,
/// and the run log. Harden and Recheck act per hack; the certificate is issued from a stable compile.
struct RunView: View {
    @Environment(DemoStore.self) private var store
    @Environment(RunSession.self) private var session
    @State private var showCertificate = false

    private var totalSteps: Int { session.run.config.steps }
    private var currentStep: Int { session.trainingPoints.last?.step ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            if showCertificate, session.certificate != nil {
                CertificateView()
            } else {
                result
            }
            if store.showLog {
                Divider()
                RunLogView().frame(height: 120)
            }
        }
        .sheet(item: Binding(get: { session.selectedTrajectory }, set: { session.selectedTrajectory = $0 })) { t in
            TrajectoryDetailSheet(trajectory: t)
        }
    }

    private var result: some View {
        VStack(spacing: 0) {
            ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                TrainingChart(points: session.trainingPoints, totalSteps: totalSteps, liftoff: session.liftoff)
                    .frame(height: 230)
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
                if let liftoff = session.liftoff { LiftoffBanner(liftoff: liftoff) }
                if let check = session.checks.values.first, let replay = check.replay, session.checks.count == 1 {
                    ReplayChecks(replay: replay)
                }
                HStack(alignment: .top, spacing: 16) {
                    HacksTable()
                    FindingsPanel(findings: session.findings).frame(width: 360)
                }
                .frame(height: 360)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            footer
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text(session.resultTitle).font(.title2.weight(.semibold))
                        .foregroundStyle(session.compileFinished ? (session.isStable ? Theme.statusCertified : Theme.statusVulnerable) : .primary)
                    if session.compileFinished {
                        Text(session.isStable ? "No hack found in \(session.trajectories.count) trajectories · \(session.findings.count) static findings"
                                              : "\(session.hackCount) hack\(session.hackCount == 1 ? "" : "s") in \(session.trajectories.count) trajectories · \(session.findings.count) static findings")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                let run = session.run
                Text("v\(session.version) · \(run.config.model) · \(run.config.algorithm) · seed \(run.config.seed)" + (run.config.rolloutsPerStep.map { " · \($0) rollouts/step" } ?? ""))
                    .font(.callout.monospaced()).foregroundStyle(.secondary)
            }
            Spacer()
            if session.certificate != nil {
                Picker("", selection: $showCertificate) {
                    Text("Result").tag(false)
                    Text("Certificate").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 200)
            }
            Text("step \(currentStep) / \(totalSteps)").font(.title3.monospacedDigit().weight(.medium)).foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if session.compileFinished {
                let pending = store.pendingChanges(for: session.environment).count
                if pending > 0 {
                    Button("\(pending) difference\(pending == 1 ? "" : "s") pending on the environment") { store.showEnvironmentPage() }
                        .buttonStyle(MonoSecondaryButtonStyle())
                }
            }
            Spacer()
            if session.isBusy {
                ProgressView().controlSize(.small)
                Text(session.compileFinished ? "Rechecking…" : (session.phase == .linting ? "Scanning environment…" : "Compiling · step \(currentStep) / \(totalSteps)"))
                    .foregroundStyle(.secondary)
            } else if session.isStable && session.certificate == nil {
                Button("Issue certificate") { Task { await session.issueCertificate(); showCertificate = true } }
                    .buttonStyle(MonoProminentButtonStyle())
                    .keyboardShortcut(.defaultAction)
            } else if session.compileFinished && !session.isStable {
                Text(session.patches.isEmpty ? "Harden a hack to get differences." : "Accept differences on the environment page, then compile again.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func metric(_ label: String, _ value: Double, digits: Int = 2, emphasize: Bool = false) -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(.secondary)
            Text(String(format: "%+.\(digits)f", value).replacingOccurrences(of: "+", with: label == "gap" ? "+" : ""))
                .foregroundStyle(emphasize ? Theme.liftoff : .primary).fontWeight(emphasize ? .semibold : .regular)
        }
        .font(.callout.monospacedDigit())
    }
}

/// Run output. Reads like a build log: phases, findings, liftoff, patch, errors.
struct RunLogView: View {
    @Environment(RunSession.self) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Compile log").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text("\(session.log.count)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.horizontal, 24).padding(.vertical, 6)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(session.log) { entry in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(entry.at, format: .dateTime.hour().minute().second()).foregroundStyle(.tertiary)
                                Text(prefix(entry.kind)).foregroundStyle(color(entry.kind)).frame(width: 52, alignment: .leading)
                                Text(entry.message).foregroundStyle(entry.kind == .liftoff ? Theme.liftoff : .primary)
                                    .fontWeight(entry.kind == .liftoff ? .semibold : .regular).textSelection(.enabled)
                            }
                            .font(.system(size: 11.5, design: .monospaced))
                            .id(entry.id)
                        }
                    }
                    .padding(.horizontal, 24).padding(.bottom, 8)
                }
                .onChange(of: session.log.count) { _, _ in
                    if let last = session.log.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
        .background(Theme.codeBackground)
    }

    private func prefix(_ kind: RunLogEntry.Kind) -> String {
        switch kind {
        case .info: "info"
        case .phase: "phase"
        case .finding: "find"
        case .liftoff: "LIFTOFF"
        case .patch: "harden"
        case .error: "error"
        }
    }

    private func color(_ kind: RunLogEntry.Kind) -> Color {
        switch kind {
        case .liftoff: Theme.liftoff
        case .error: Theme.statusVulnerable
        default: .secondary
        }
    }
}
