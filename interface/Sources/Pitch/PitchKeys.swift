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
        // The app, and the demo (the app driven by hand), keep every key.
        guard mode == .pitch else { return false }
        // Typing in a field wins over the pitch keys.
        if let responder = NSApp.keyWindow?.firstResponder, responder is NSText || responder is NSTextView { return false }
        if flags.contains(.command) {
            // ⌘R re-reads the deck in pitch mode; every other ⌘ key stays a menu shortcut.
            if mode == .pitch, flags == .command, letter == "r" { pitch.reload(); return true }
            return false
        }
        switch (code, letter) {
        case (PitchKeys.right, _), (PitchKeys.pageDown, _):
            pitchNext()
        case (PitchKeys.left, _), (PitchKeys.pageUp, _):
            pitch.back()
        case (PitchKeys.escape, _):
            pitch.exitToApp()
        case (PitchKeys.space, _):
            pitch.toggleClock()
        case (_, "p"):
            pitch.showPresenter.toggle()
        default:
            return false
        }
        return true
    }
}
