import SwiftUI

/// One run: a stepper across its stages, the stage content, and the run log.
struct RunView: View {
    @Environment(DemoStore.self) private var store
    @Environment(RunSession.self) private var session

    var body: some View {
        VStack(spacing: 0) {
            RunStepper()
            Divider()
            stageContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if store.showLog {
                Divider()
                RunLogView()
                    .frame(height: 120)
            }
        }
        .sheet(item: Binding(get: { session.selectedTrajectory }, set: { session.selectedTrajectory = $0 })) { t in
            TrajectoryDetailSheet(trajectory: t)
        }
    }

    @ViewBuilder
    private var stageContent: some View {
        switch session.stage {
        case .train: TrainView()
        case .patch: PatchView()
        case .verify: VerifyView()
        case .certificate: CertificateView()
        }
    }
}

struct RunStepper: View {
    @Environment(RunSession.self) private var session

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Stage.allCases) { stage in
                let unlocked = session.isUnlocked(stage)
                let completed = session.isCompleted(stage)
                let selected = session.stage == stage
                Button { session.select(stage) } label: {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .strokeBorder(unlocked ? Color.primary.opacity(0.5) : Color.primary.opacity(0.15), lineWidth: 1)
                                .background(Circle().fill(completed ? Color.primary : .clear))
                                .frame(width: 20, height: 20)
                            if completed {
                                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.windowBackground)
                            } else {
                                Text("\(stage.rawValue + 1)").font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .foregroundStyle(unlocked ? .primary : .tertiary)
                            }
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            Text(stage.title).font(.callout.weight(selected ? .semibold : .regular))
                                .foregroundStyle(unlocked ? .primary : .tertiary)
                            Text(stage.subtitle).font(.caption2).foregroundStyle(unlocked ? .secondary : .quaternary).lineLimit(1)
                        }
                        if stage == .train, session.liftoff != nil {
                            Circle().fill(Theme.liftoff).frame(width: 6, height: 6)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(selected ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!unlocked)
                if stage != Stage.allCases.last {
                    Rectangle().fill(Color.primary.opacity(0.15)).frame(width: 28, height: 1).padding(.horizontal, 4)
                }
            }
            Spacer()
            Text(session.id).font(.caption.monospaced()).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background(Theme.windowBackground)
    }
}

/// Run output. Reads like a build log: phases, findings, liftoff, patch, errors.
struct RunLogView: View {
    @Environment(RunSession.self) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Run log").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text("\(session.log.count)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.horizontal, 24).padding(.vertical, 6)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(session.log) { entry in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(entry.at, format: .dateTime.hour().minute().second())
                                    .foregroundStyle(.tertiary)
                                Text(prefix(entry.kind)).foregroundStyle(color(entry.kind)).frame(width: 52, alignment: .leading)
                                Text(entry.message).foregroundStyle(entry.kind == .liftoff ? Theme.liftoff : .primary)
                                    .fontWeight(entry.kind == .liftoff ? .semibold : .regular)
                                    .textSelection(.enabled)
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
        case .patch: "patch"
        case .error: "error"
        }
    }

    private func color(_ kind: RunLogEntry.Kind) -> Color {
        switch kind {
        case .liftoff: Theme.liftoff
        case .error: .red
        default: .secondary
        }
    }
}
