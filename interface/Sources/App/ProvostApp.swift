import SwiftUI
import AppKit

@main
struct ProvostApp: App {
    @State private var store: DemoStore

    init() {
        // Fast-forward from the start: the demo never has to flip it.
        let playback = PlaybackSettings(fastForward: true)
        // Backend swap: one line. `LocalHTTPBackend()` talks to the FastAPI server on 127.0.0.1:8765.
        let backend: any AuditBackend = FixtureBackend.bundled(playback: playback)
        let store = DemoStore(backend: backend, playback: playback)
        // `make pitch` launches with --pitch: the deck opens on slide 1.
        if CommandLine.arguments.contains("--pitch") { store.pitch.enterPitch(at: 0) }
        _store = State(initialValue: store)
    }

    var body: some Scene {
        WindowGroup(AppConfig.productName) {
            RootView()
                .environment(store)
                .frame(minWidth: 1100, minHeight: 680)
        }
        .defaultSize(width: 1280, height: 800)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Environment…") { ProvostApp.chooseEnvironmentFolder(store: store) }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandMenu("Environment") {
                Button("Compile") { Task { await store.compile() } }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Save Version") { if let env = store.selectedEnvironment { store.save(env) } }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(store.selectedEnvironment.map { store.unsavedCount(for: $0) == 0 } ?? true)
                    .disabled(store.selectedEnvironment == nil)
                Button("Show Environment") { store.showEnvironmentPage() }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(store.selectedEnvironment == nil)
                Divider()
                Toggle("Fast-forward", isOn: Binding(get: { store.isFastForward }, set: { store.fastForward = $0 }))
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                Toggle("Show Run Log", isOn: Binding(get: { store.showLog }, set: { store.showLog = $0 }))
                    .keyboardShortcut("l", modifiers: [.command, .shift])
            }
            CommandGroup(before: .toolbar) {
                Button("Present from Slide 1") { store.pitch.enterPitch(at: 0) }
                    .disabled(store.pitch.mode != .app)
                Toggle("Pitch", isOn: Binding(get: { store.pitch.mode != .app }, set: { _ in store.togglePitchMode() }))
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Toggle("Presenter Panel  (P)", isOn: Binding(get: { store.pitch.showPresenter }, set: { store.pitch.showPresenter = $0 }))
                    .disabled(store.pitch.mode == .app)
                Button("Reload Deck  (⌘R in pitch)") { store.pitch.reload() }
                    .disabled(store.pitch.mode == .app)
                Divider()
            }
        }
    }

    /// File ▸ New Environment…: pick a folder and register it with the backend.
    @MainActor static func chooseEnvironmentFolder(store: DemoStore) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        panel.message = "Choose an environment folder (Harbor, Verifiers, OpenEnv or any folder)."
        if panel.runModal() == .OK, let url = panel.url {
            Task { await store.addEnvironment(at: url) }
        }
    }

    /// Rehearsal aid: `PROVOST_APPEARANCE=dark|light` forces the app's appearance without touching
    /// the system setting. Called once the window exists.
    @MainActor static func applyAppearanceOverride() {
        switch ProcessInfo.processInfo.environment["PROVOST_APPEARANCE"] {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: break
        }
    }
}
