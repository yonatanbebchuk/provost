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
                ProvostMark.image(height: 30).foregroundStyle(.tertiary).padding(.bottom, 6)
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
                BrandLockup()
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
                Text(environment.name).font(.body.weight(isSelected ? .semibold : .regular)).lineLimit(1)
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
                    Text("Compile v\(session.version)").font(.caption.weight(.medium)).lineLimit(1)
                    Text("\(session.statusLine) · \(session.run.config.model)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
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
        if session.certificate != nil {
            Image(systemName: "checkmark.seal.fill").font(.caption2).foregroundStyle(Theme.statusCertified)
        } else if session.compileFinished {
            Circle().fill(session.isStable ? Theme.statusCertified : Theme.statusVulnerable).frame(width: 7, height: 7)
        } else {
            Circle().fill(.secondary).frame(width: 7, height: 7)
        }
    }
}

// MARK: - Top bar

/// On the environment page: just the operations. On a compile: the way back, the compile, its phase.
struct TopBar: View {
    @Environment(DemoStore.self) private var store
    @State private var showRecord = false

    var body: some View {
        HStack(spacing: 12) {
            if let env = store.selectedEnvironment {
                if let session = store.selectedSession {
                    Button { store.showEnvironmentPage() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left").font(.caption.weight(.bold))
                            Text(env.name).font(.headline)
                        }
                    }
                    .buttonStyle(.plain)
                    Chip(text: "v\(session.version)", mono: true)
                    StatusBadge(status: store.status(for: env))
                    Divider().frame(height: 16)
                    Text("Compile · \(session.run.config.model)").font(.callout).foregroundStyle(.secondary)
                    PhasePill(phase: session.phase, busy: session.isBusy)
                    ElapsedLabel(start: session.startedAt, end: session.endedAt)
                } else {
                    Text(env.name).font(.headline)
                    Chip(text: "v\(store.version(of: env))", mono: true)
                    StatusBadge(status: store.status(for: env))
                }
                Spacer()
                changeRecord(env)
                PolicyModelMenu(environment: env)
                RunMenu()
            } else {
                Text("No environment").font(.headline).foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 52)
        .background(.bar)
    }

    /// The decisions waiting to become a version, and the Save that makes them one.
    @ViewBuilder
    private func changeRecord(_ env: AuditEnvironment) -> some View {
        let unsaved = store.unsavedCount(for: env)
        let record = store.changeRecord(for: env).count + store.manualEditCount(for: env)
        if record > 0 {
            Button {
                showRecord = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.branch").font(.caption)
                    Text("\(record) change\(record == 1 ? "" : "s")")
                }
                .font(.callout.weight(.medium))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Theme.changeAltered.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .help("The change record: what a save writes into the next version")
            .popover(isPresented: $showRecord, arrowEdge: .bottom) { ChangeRecordPopover(environment: env) }
            if unsaved > 0 {
                Button("Save v\(store.version(of: env) + 1)") { store.save(env) }
                    .buttonStyle(RoundedProminentButtonStyle())
                    .keyboardShortcut("s", modifiers: .command)
                    .help("Save the edited environment as the next version (⌘S)")
            }
        }
    }
}

/// The processes you can run on an environment, in one menu. Compile now; Test lights up with Monitor.
struct RunMenu: View {
    @Environment(DemoStore.self) private var store

    private var isBusy: Bool { store.sessions(for: store.selectedEnvironment!).contains { $0.isBusy } }

    var body: some View {
        Menu {
            Button {
                Task { await store.compile() }
            } label: {
                Label("Compile", systemImage: "hammer.fill")
            }
            .disabled(isBusy)
            Button {} label: {
                Label("Test", systemImage: "checkmark.diamond")
            }
            .disabled(true)
        } label: {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "play.fill").font(.caption.weight(.bold))
                }
                Text(isBusy ? "Running" : "Run")
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(.caption2.weight(.bold))
            }
            .frame(minWidth: 108)
        }
        .menuStyle(.button)
        .buttonStyle(RoundedProminentButtonStyle())
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Run a process on this environment. Compile is ⌘R.")
    }
}

/// The change record: every decision since the last save, and the hand edits, with Save.
struct ChangeRecordPopover: View {
    @Environment(DemoStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let environment: AuditEnvironment

    var body: some View {
        let record = store.changeRecord(for: environment)
        let edits = store.manualEditCount(for: environment)
        let unsaved = store.unsavedCount(for: environment)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Change record").font(.headline)
                Text("v\(store.version(of: environment)) → v\(store.version(of: environment) + 1)")
                    .font(.callout.monospaced()).foregroundStyle(.secondary)
                Spacer()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if edits > 0 {
                        HStack(spacing: 8) {
                            Image(systemName: "pencil").font(.caption).foregroundStyle(.secondary)
                            Text("Objective edited by hand\(edits > 1 ? " · \(edits) times" : "")").font(.callout)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    ForEach(record) { change in ChangeRow(change: change, environment: environment, showPart: true) }
                }
            }
            .frame(maxHeight: 420)
            HStack {
                Text(unsaved == 0 ? "Nothing to write: only rejections." : "\(unsaved) change\(unsaved == 1 ? "" : "s") become v\(store.version(of: environment) + 1).")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Save v\(store.version(of: environment) + 1)") { store.save(environment); dismiss() }
                    .buttonStyle(MonoProminentButtonStyle())
                    .disabled(unsaved == 0)
            }
        }
        .padding(18)
        .frame(width: 560)
    }
}

/// Which policy the next compile trains. Open weights and custom tiers, grouped.
struct PolicyModelMenu: View {
    @Environment(DemoStore.self) private var store
    let environment: AuditEnvironment

    var body: some View {
        let current = store.policyModel(for: environment)
        Menu {
            ForEach([PolicyModel.Tier.open, .custom], id: \.self) { tier in
                Section(tier.rawValue) {
                    ForEach(AppConfig.policyModels.filter { $0.tier == tier }) { model in
                        Button {
                            store.setPolicyModel(model, for: environment)
                        } label: {
                            if model.id == current.id {
                                Label(model.name, systemImage: "checkmark")
                            } else {
                                Text(model.name)
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: current.tier == .custom ? "checkmark.shield.fill" : "cpu").font(.caption)
                Text(current.name)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
            .frame(minWidth: 132)
        }
        .menuStyle(.button)
        .buttonStyle(RoundedSecondaryButtonStyle())
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Policy the next compile trains against this environment")
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
