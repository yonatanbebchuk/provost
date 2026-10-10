import SwiftUI
import AppKit

@main
struct LiftoffApp: App {
    @State private var store: DemoStore

    init() {
        let playback = PlaybackSettings()
        // Backend swap: one line. `LocalHTTPBackend()` talks to the FastAPI server on 127.0.0.1:8765.
        let backend: any AuditBackend = FixtureBackend.bundled(playback: playback)
        _store = State(initialValue: DemoStore(backend: backend, playback: playback))
    }

    /// Rehearsal aid: `LIFTOFF_APPEARANCE=dark|light` forces the app's appearance without touching
    /// the system setting. Called once the window exists.
    @MainActor static func applyAppearanceOverride() {
        switch ProcessInfo.processInfo.environment["LIFTOFF_APPEARANCE"] {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: break
        }
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
            CommandMenu("Demo") {
                Button("Next stage") { store.advance() }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                Button("Previous stage") { store.retreat() }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                Divider()
                Toggle("Fast-forward", isOn: Binding(get: { store.isFastForward }, set: { store.fastForward = $0 }))
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                Divider()
                Button("Reset run") { store.resetRun() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}
