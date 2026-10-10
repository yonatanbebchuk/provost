import SwiftUI

struct RootView: View {
    @Environment(DemoStore.self) private var store

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            StageSidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            VStack(spacing: 0) {
                TopBar()
                Divider()
                stageContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Theme.windowBackground)
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear { LiftoffApp.applyAppearanceOverride() }
        .task { await store.loadRecents() }
        .alert("Something went wrong", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .sheet(item: Binding(get: { store.selectedTrajectory }, set: { store.selectedTrajectory = $0 })) { t in
            TrajectoryDetailSheet(trajectory: t)
        }
    }

    @ViewBuilder
    private var stageContent: some View {
        switch store.stage {
        case .load: LoadView()
        case .lint: LintView()
        case .train: TrainView()
        case .patch: PatchView()
        case .verify: VerifyView()
        case .certificate: CertificateView()
        }
    }
}

// MARK: - Sidebar

struct StageSidebar: View {
    @Environment(DemoStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(AppConfig.productName)
                    .font(.title3.weight(.bold))
                Text("Environment audit")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 18)

            VStack(spacing: 2) {
                ForEach(Stage.allCases) { stage in
                    StageRow(stage: stage)
                }
            }
            .padding(.horizontal, 8)

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: Binding(get: { store.isFastForward }, set: { store.fastForward = $0 })) {
                    Label("Fast-forward", systemImage: "forward.fill")
                        .font(.callout)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                HStack(spacing: 6) {
                    Circle().fill(.secondary).frame(width: 6, height: 6)
                    Text(store.backend.displayName)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct StageRow: View {
    @Environment(DemoStore.self) private var store
    let stage: Stage

    private var isSelected: Bool { store.stage == stage }
    private var isUnlocked: Bool { store.isUnlocked(stage) }
    private var isCompleted: Bool { store.isCompleted(stage) }

    var body: some View {
        Button {
            store.select(stage)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .strokeBorder(isUnlocked ? Color.primary.opacity(0.5) : Color.primary.opacity(0.15), lineWidth: 1)
                        .background(Circle().fill(isCompleted ? Color.primary : .clear))
                        .frame(width: 22, height: 22)
                    if isCompleted {
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.windowBackground)
                    } else {
                        Text("\(stage.rawValue + 1)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(isUnlocked ? .primary : .tertiary)
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(stage.title)
                        .font(.body.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isUnlocked ? .primary : .tertiary)
                    Text(stage.subtitle)
                        .font(.caption)
                        .foregroundStyle(isUnlocked ? .secondary : .quaternary)
                        .lineLimit(1)
                }
                Spacer()
                if stage == .train, store.liftoff != nil {
                    Circle().fill(Theme.liftoff).frame(width: 7, height: 7)
                } else if !isUnlocked {
                    Image(systemName: "lock").font(.caption2).foregroundStyle(.quaternary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.primary.opacity(0.08) : .clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isUnlocked)
    }
}

// MARK: - Top bar

struct TopBar: View {
    @Environment(DemoStore.self) private var store

    var body: some View {
        HStack(spacing: 14) {
            if let env = store.environment {
                Text(env.name).font(.headline)
                Chip(text: env.format.displayName)
            } else {
                Text("No environment").font(.headline).foregroundStyle(.secondary)
            }
            if let run = store.run {
                Divider().frame(height: 16)
                Text("\(run.config.model) · \(run.config.algorithm) · \(run.config.steps) steps")
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let liftoff = store.liftoff {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right").font(.caption.weight(.bold))
                    Text("Liftoff · step \(liftoff.step)")
                }
                .font(.callout.weight(.semibold))
                .foregroundStyle(Theme.liftoff)
            }
            PhasePill(phase: store.phase, busy: store.isBusy)
            ElapsedLabel(start: store.run?.startedAt, end: store.run?.endedAt)
        }
        .padding(.horizontal, 24)
        .frame(height: 48)
        .background(.bar)
    }
}

private struct PhasePill: View {
    var phase: AuditPhase
    var busy: Bool

    var body: some View {
        HStack(spacing: 6) {
            if busy {
                ProgressView().controlSize(.mini)
            } else {
                Circle().fill(phase == .done ? Color.primary : Color.secondary).frame(width: 6, height: 6)
            }
            Text(phase.displayName)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.07), in: Capsule())
    }
}

private struct ElapsedLabel: View {
    var start: Date?
    var end: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let text: String = {
                guard let start else { return "--:--" }
                return Format.elapsed((end ?? context.date).timeIntervalSince(start))
            }()
            Text(text)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 48, alignment: .trailing)
        }
    }
}
