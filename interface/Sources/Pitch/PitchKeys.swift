import AppKit
import SwiftUI

/// Window-level keys for the pitch and the demo. A local event monitor sees every key before any
/// view does, so the arrows work with nothing focused. Installed once from `RootView`.
@MainActor
enum PitchKeys {
    private static var monitor: Any?

    static func install(store: DemoStore) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // NSEvent is not Sendable: pull the three values out before hopping to the main actor.
            let code = event.keyCode
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let letter = event.charactersIgnoringModifiers?.lowercased() ?? ""
            let consumed = MainActor.assumeIsolated { store.handlePitchKey(code: code, flags: flags, letter: letter) }
            return consumed ? nil : event
        }
    }

    // Key codes (US layout independent).
    static let left: UInt16 = 123, right: UInt16 = 124, pageUp: UInt16 = 116, pageDown: UInt16 = 121
    static let escape: UInt16 = 53, space: UInt16 = 49
}

extension DemoStore {
    /// Returns true when the key was consumed.
    func handlePitchKey(code: UInt16, flags: NSEvent.ModifierFlags, letter: String) -> Bool {
        let mode = pitch.mode
        guard mode != .app else { return false }
        // Typing in a field wins over the pitch keys.
        if let responder = NSApp.keyWindow?.firstResponder, responder is NSText || responder is NSTextView { return false }
        if flags.contains(.command) {
            // ⌘R re-reads the deck in pitch mode; every other ⌘ key stays a menu shortcut.
            if mode == .pitch, flags == .command, letter == "r" { pitch.reload(); return true }
            return false
        }
        switch (mode, code, letter) {
        case (.pitch, PitchKeys.right, _), (.pitch, PitchKeys.pageDown, _):
            if pitch.current?.isDemoHandoff == true { Task { await enterDemo() } } else { pitch.advance() }
        case (.pitch, PitchKeys.left, _), (.pitch, PitchKeys.pageUp, _):
            pitch.back()
        case (.pitch, PitchKeys.escape, _):
            pitch.exitToApp()
        case (.demo, PitchKeys.right, _), (.demo, PitchKeys.pageDown, _):
            demoAdvance()
        case (.demo, PitchKeys.left, _), (.demo, PitchKeys.pageUp, _):
            demoBack()
        case (.demo, PitchKeys.escape, _):
            leaveDemo(toNextSlide: false)
        case (.demo, _, "f"):
            fastForward.toggle()
        case (_, PitchKeys.space, _):
            pitch.toggleClock()
        case (_, _, "p"):
            pitch.showPresenter.toggle()
        default:
            return false
        }
        return true
    }
}
