import SwiftUI

/// One compile. Rollouts as a growing list, each dropping down into its trace, hacks painted red; tick hacks and harden them
/// together; the differences in one report; the certificate when the compile is stable.
struct RunView: View {
    @Environment(DemoStore.self) private var store
    @Environment(RunSession.self) private var session
    @State private var showFindings = false

    private var totalSteps: Int { session.run.config.steps }
    private var currentStep: Int { session.trainingPoints.last?.step ?? 0 }
    private var differenceCount: Int { store.changes(from: session).count }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            switch session.page {
            case .result: result
            case .report: HardenReportView()
            case .certificate: CertificateView()
            }
            if store.showLog {
                Divider()
                RunLogView().frame(height: 120)
            }
        }
        .sheet(item: Binding(get: { session.selectedTrajectory }, set: { session.selectedTrajectory = $0 })) { t in
            TrajectoryDetailSheet(trajectory: t)
        }
        .onChange(of: session.certificate) { _, cert in
            if cert != nil { session.page = .certificate }
        }
    }

    // MARK: Header: result, page tabs, actions

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Text(session.resultTitle).font(.title2.weight(.semibold))
                .foregroundStyle(session.compileFinished ? (session.isStable ? Theme.statusCertified : Theme.statusVulnerable) : .primary)
            if session.compileFinished {
                Text(session.isStable ? "\(session.trajectories.count) rollouts, no hack"
                                      : "\(session.hackCount) hack\(session.hackCount == 1 ? "" : "s") in \(session.trajectories.count) rollouts")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text("step \(currentStep) / \(totalSteps)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer()
            tabs
            if session.page == .result && session.compileFinished { actions }
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
    }

    @ViewBuilder
    private var tabs: some View {
        let hasReport = differenceCount > 0
        let hasCertificate = session.certificate != nil
        if hasReport || hasCertificate {
            MonoSegment(selection: Binding(get: { session.page }, set: { session.page = $0 }), options: pageOptions)
        }
    }

    private var pageOptions: [(String, RunSession.Page)] {
        var options: [(String, RunSession.Page)] = [("Rollouts", .result)]
        if differenceCount > 0 { options.append(("Differences · \(differenceCount)", .report)) }
        if session.certificate != nil { options.append(("Certificate", .certificate)) }
        return options
    }

    @ViewBuilder
    private var actions: some View {
        if session.hackCount > 0 {
            let n = session.selectedHacks.count
            Button(session.hardening.isEmpty ? (n == 0 ? "Harden" : "Harden \(n)") : "Hardening…") {
                Task { await store.hardenSelected(in: session) }
            }
            .buttonStyle(MonoProminentButtonStyle())
            .disabled(n == 0 || !session.hardening.isEmpty || session.isBusy)
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: Rollouts

    private var result: some View {
        VStack(spacing: 0) {
            RolloutList()
                .frame(maxHeight: .infinity)
                .padding(.vertical, 8)
            Divider()
            findings
            if session.isStable && session.certificate == nil {
                Divider()
                HStack {
                    Text("No hack found. Sign this version.").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button(session.isBusy ? "Issuing…" : "Issue certificate") { Task { await session.issueCertificate() } }
                        .buttonStyle(MonoProminentButtonStyle())
                        .disabled(session.isBusy)
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 24).padding(.vertical, 12)
                .background(.bar)
            }
        }
    }

    private var findings: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { showFindings.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .rotationEffect(.degrees(showFindings ? 90 : 0))
                    Text("Static findings").font(.callout.weight(.medium))
                    Text("\(session.findings.count)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    if let worst = session.findings.first, !showFindings {
                        Text("·").foregroundStyle(.tertiary)
                        Text(worst.title).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                }
                .padding(.horizontal, 24).padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showFindings {
                FindingsList(findings: session.findings).frame(height: 220).padding(.horizontal, 24).padding(.bottom, 12)
            }
        }
    }
}

/// Findings without their own header; the parent provides the row above.
private struct FindingsList: View {
    let findings: [LintFinding]
    @State private var expanded: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(findings) { finding in
                    FindingRow(finding: finding, isExpanded: expanded.contains(finding.id)) {
                        if expanded.contains(finding.id) { expanded.remove(finding.id) } else { expanded.insert(finding.id) }
                    }
                }
            }
        }
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
