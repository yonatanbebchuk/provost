import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct LoadView: View {
    @Environment(DemoStore.self) private var store
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 20) {
                recentColumn
                    .frame(width: 340)
                if let env = store.environment {
                    EnvironmentCard(environment: env)
                } else {
                    emptyState
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            StageFooter(busyLabel: "Linting environment…") {
                if store.environment != nil {
                    Text("Static lint runs first, then adversarial training on \(store.environment?.taskCount ?? 0) tasks.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var recentColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent environments").font(.title3.weight(.semibold))
            VStack(spacing: 6) {
                ForEach(store.recentEnvironments) { env in
                    Button { store.select(environment: env) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "folder").foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(env.name).font(.body.weight(.medium))
                                Text("\(env.format.displayName) · \(env.taskCount) tasks · \(env.rewardType.displayName)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if store.environment?.id == env.id {
                                Image(systemName: "checkmark").font(.caption.weight(.bold))
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(store.environment?.id == env.id ? Color.primary.opacity(0.08) : Theme.cardBackground,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.separator))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            dropZone
                .padding(.top, 8)
        }
    }

    private var dropZone: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.down.doc").font(.title2).foregroundStyle(.secondary)
            Text("Drop an environment folder").font(.callout.weight(.medium))
            Text("Harbor, Verifiers, OpenEnv or any folder").font(.caption).foregroundStyle(.secondary)
            Button("Choose Folder…") { chooseFolder() }
                .buttonStyle(MonoSecondaryButtonStyle())
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .foregroundStyle(isDropTargeted ? Color.primary : Color.secondary.opacity(0.6))
        )
        .background(isDropTargeted ? Color.primary.opacity(0.05) : .clear,
                    in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in await store.openEnvironment(at: url) }
            }
            return true
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "shield.lefthalf.filled").font(.system(size: 36)).foregroundStyle(.tertiary)
            Text("Select an environment to audit").font(.title3.weight(.medium))
            Text(AppConfig.productTagline).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Load"
        if panel.runModal() == .OK, let url = panel.url {
            Task { await store.openEnvironment(at: url) }
        }
    }
}

struct EnvironmentCard: View {
    let environment: AuditEnvironment

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Text(environment.name).font(.title.weight(.semibold))
                        Chip(text: environment.format.displayName)
                    }
                    Text(environment.id).font(.callout.monospaced()).foregroundStyle(.secondary)
                    if let description = environment.description {
                        Text(description).font(.body).foregroundStyle(.secondary).padding(.top, 4)
                    }
                }

                HStack(spacing: 12) {
                    StatTile(label: "Format", value: environment.format.displayName)
                    StatTile(label: "Tasks", value: "\(environment.taskCount)")
                    StatTile(label: "Reward", value: environment.rewardType.displayName)
                }

                Card(title: "Sandbox") {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                        row("Runtime", environment.sandbox.runtime)
                        row("Network", environment.sandbox.network)
                        row("Filesystem", environment.sandbox.filesystem)
                        GridRow {
                            Text("Tools").foregroundStyle(.secondary)
                            if environment.sandbox.tools.isEmpty {
                                Text("none").foregroundStyle(.tertiary)
                            } else {
                                HStack(spacing: 6) {
                                    ForEach(environment.sandbox.tools, id: \.self) { Chip(text: $0, mono: true) }
                                }
                            }
                        }
                    }
                    .font(.callout)
                }

                Card(title: "Source") {
                    Text(environment.source).font(.callout.monospaced()).textSelection(.enabled)
                }
            }
            .padding(.trailing, 4)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value)
        }
    }
}
