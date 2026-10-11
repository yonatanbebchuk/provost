import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(DemoStore.self) private var store

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            EnvironmentSidebar()
                .frame(minWidth: 230)
                .navigationSplitViewColumnWidth(min: 230, ideal: 250, max: 300)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            VStack(spacing: 0) {
                TopBar()
                Divider()
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Theme.windowBackground)
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear { ProvostApp.applyAppearanceOverride() }
        .task { await store.loadEnvironments() }
        .alert("Something went wrong", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        if let session = store.selectedSession {
            RunView()
                .environment(session)
                .id(session.id)
        } else if let env = store.selectedEnvironment {
            EnvironmentPage(environment: env)
                .id(env.id)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "shield.lefthalf.filled").font(.system(size: 36)).foregroundStyle(.tertiary)
                Text("No environments").font(.title3.weight(.medium))
                Text("File ▸ New Environment… (⌘N) adds one from a folder.").font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Sidebar: environments are projects

struct EnvironmentSidebar: View {
    @Environment(DemoStore.self) private var store
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppConfig.productName).font(.title3.weight(.bold))
                    Text("Environment audit").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { ProvostApp.chooseEnvironmentFolder(store: store) } label: {
                    Image(systemName: "plus").font(.body.weight(.semibold))
                }
                .buttonStyle(.plain)
                .help("New Environment… (⌘N)")
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 14)

            Text("ENVIRONMENTS")
                .font(.caption2.weight(.semibold)).kerning(0.6).foregroundStyle(.secondary)
                .padding(.horizontal, 18)
                .padding(.bottom, 4)

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(store.environments) { env in
                        EnvironmentRow(environment: env)
                        if store.selectedEnvironmentId == env.id {
                            ForEach(store.sessions(for: env)) { session in
                                RunRow(session: session)
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: Binding(get: { store.isFastForward }, set: { store.fastForward = $0 })) {
                    Label("Fast-forward", systemImage: "forward.fill").font(.callout)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                HStack(spacing: 6) {
                    Circle().fill(.secondary).frame(width: 6, height: 6)
                    Text(store.backend.displayName)
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(isDropTargeted ? Color.primary.opacity(0.05) : .clear)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in await store.addEnvironment(at: url) }
            }
            return true
        }
    }
}

private struct EnvironmentRow: View {
    @Environment(DemoStore.self) private var store
    let environment: AuditEnvironment

    private var isSelected: Bool { store.selectedEnvironmentId == environment.id }
    private var isActive: Bool { isSelected && store.selectedRunId == nil }

    var body: some View {
        Button { store.select(environment: environment) } label: {
            HStack(spacing: 10) {
                Image(systemName: "cube")
                    .font(.callout)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(environment.name).font(.body.weight(isSelected ? .semibold : .regular)).lineLimit(1)
                    Text("\(environment.format.displayName) · \(environment.rewardType.displayName)")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                let status = store.status(for: environment)
                Circle().fill(Theme.color(for: status)).frame(width: 7, height: 7)
                    .help(status.title + " · " + status.detail)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isActive ? Color.primary.opacity(0.08) : .clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct RunRow: View {
    @Environment(DemoStore.self) private var store
    let session: RunSession

    private var isActive: Bool { store.selectedRunId == session.id }

    var body: some View {
        Button { store.select(session: session) } label: {
            HStack(spacing: 8) {
                statusDot
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.id).font(.caption.monospaced()).lineLimit(1)
                    Text(session.statusLine).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if session.isBusy { ProgressView().controlSize(.mini) }
            }
            .padding(.leading, 38).padding(.trailing, 10).padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isActive ? Color.primary.opacity(0.08) : .clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var statusDot: some View {
        if session.liftoff != nil && session.certificate == nil {
            Circle().fill(Theme.liftoff).frame(width: 7, height: 7)
        } else if session.certificate != nil {
            Image(systemName: "checkmark.seal.fill").font(.caption2).foregroundStyle(.primary)
        } else {
            Circle().fill(.secondary).frame(width: 7, height: 7)
        }
    }
}

// MARK: - Top bar

struct TopBar: View {
    @Environment(DemoStore.self) private var store

    var body: some View {
        HStack(spacing: 14) {
            if let env = store.selectedEnvironment {
                if store.selectedSession != nil {
                    Button { store.showEnvironmentPage() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left").font(.caption.weight(.bold))
                            Text(env.name).font(.headline)
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(env.name).font(.headline)
                }
                Chip(text: env.format.displayName)
            } else {
                Text("No environment").font(.headline).foregroundStyle(.secondary)
            }
            if let session = store.selectedSession {
                Divider().frame(height: 16)
                Text("\(session.run.config.model) · \(session.run.config.algorithm) · \(session.run.config.steps) steps")
                    .font(.callout.monospaced()).foregroundStyle(.secondary)
                Spacer()
                if let liftoff = session.liftoff {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.right").font(.caption.weight(.bold))
                        Text("Liftoff · step \(liftoff.step)")
                    }
                    .font(.callout.weight(.semibold)).foregroundStyle(Theme.liftoff)
                }
                PhasePill(phase: session.phase, busy: session.isBusy)
                ElapsedLabel(start: session.startedAt, end: session.endedAt)
            } else if let env = store.selectedEnvironment {
                Divider().frame(height: 16)
                Text(env.source).font(.callout.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
            } else {
                Spacer()
            }
            if store.selectedEnvironment != nil {
                OperationsBar()
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 52)
        .background(.bar)
    }
}

/// The processes you can run on an environment. One today; this is where the others go.
struct OperationsBar: View {
    @Environment(DemoStore.self) private var store

    private var isBusy: Bool { store.sessions(for: store.selectedEnvironment!).contains { $0.isBusy } }

    var body: some View {
        Button {
            Task { await store.newRun() }
        } label: {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "play.fill").font(.caption.weight(.bold))
                }
                Text("Run")
            }
            .frame(minWidth: 72)
        }
        .buttonStyle(RoundedProminentButtonStyle())
        .keyboardShortcut("r", modifiers: .command)
        .disabled(isBusy)
        .help("Run the audit on this environment (⌘R)")
    }
}

struct PhasePill: View {
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
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Color.primary.opacity(0.07), in: Capsule())
    }
}

struct ElapsedLabel: View {
    var start: Date?
    var end: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let text: String = {
                guard let start else { return "--:--" }
                return Format.elapsed((end ?? context.date).timeIntervalSince(start))
            }()
            Text(text)
                .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                .frame(minWidth: 48, alignment: .trailing)
        }
    }
}
