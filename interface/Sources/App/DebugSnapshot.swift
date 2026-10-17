import AppKit
import SwiftUI

/// Rehearsal aid: launched with `--snapshot-dir <dir>`, the window is sized to 1280 × 800 and the
/// app polls `<dir>/cmd` for one command per line: `snap [label]` writes the key window's content
/// as PNG (no screen-recording permission needed: the view draws itself into a bitmap); `key <name>`
/// sends `right`, `left`, `esc`, `space`, `p`, `f`, `cmd-r` or `cmd-shift-p` through the pitch key
/// handler; `continue` is the Continue pitch button; `dark` / `light` switch appearance; `size W H` resizes the window.
/// The app itself can be driven too: `env <id>` selects an environment, `compile` starts a compile,
/// `tick all|<n>` ticks hacks, `harden` hardens the ticked ones, `open <n>` / `close` show and hide a
/// hack's detail sheet, `recheck [n]` replays a hardened hack, `page result|report|verify|certificate`
/// switches the compile page, `accept-all`, `reject-all` and `save` decide and save differences,
/// `ff on|off` sets fast-forward, and `state` only logs. Every command is echoed to `<dir>/events.log`
/// with the pitch mode, slide, compile page and compile progress after it ran.
@MainActor
enum DebugSnapshot {
    private static var counter = 0
    private static var task: Task<Void, Never>?

    static func installIfRequested(store: DemoStore) {
        let args = CommandLine.arguments
        guard task == nil, let i = args.firstIndex(of: "--snapshot-dir"), i + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        task = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            resize(1280, 800)
            let cmdFile = dir.appendingPathComponent("cmd")
            while !Task.isCancelled {
                if let text = try? String(contentsOf: cmdFile, encoding: .utf8) {
                    try? FileManager.default.removeItem(at: cmdFile)
                    for line in text.split(separator: "\n") {
                        let words = line.split(separator: " ").map(String.init)
                        guard let verb = words.first else { continue }
                        run(verb, words.dropFirst().map { $0 }, dir: dir, store: store)
                        log(dir: dir, "\(line) → \(state(store))")
                    }
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private static func state(_ store: DemoStore) -> String {
        let page = store.selectedSession.map { "\($0.page)" } ?? "-"
        var line = "mode=\(store.pitch.mode) slide=\(store.pitch.index + 1) page=\(page) presenter=\(store.pitch.showPresenter)"
        if let env = store.selectedEnvironment { line += " env=\(env.id) v\(store.version(of: env)) pending=\(store.pendingChanges(for: env).count)" }
        if let s = store.selectedSession {
            line += " busy=\(s.isBusy) finished=\(s.compileFinished) rollouts=\(s.trajectories.count) hacks=\(s.hackCount)"
            line += " ticked=\(s.selectedHacks.count) patches=\(s.patches.count) checks=\(s.checks.count) sheet=\(s.selectedTrajectory != nil)"
        }
        return line
    }

    private static func run(_ verb: String, _ args: [String], dir: URL, store: DemoStore) {
        switch verb {
        case "snap": snapshot(into: dir, label: args.first ?? "")
        case "key":
            let (code, flags, letter): (UInt16, NSEvent.ModifierFlags, String) = switch args.first ?? "" {
            case "right": (124, [], "")
            case "left": (123, [], "")
            case "pagedown": (121, [], "")
            case "pageup": (116, [], "")
            case "esc": (53, [], "\u{1B}")
            case "space": (49, [], " ")
            case "cmd-r": (15, .command, "r")
            case "cmd-shift-p": (35, [.command, .shift], "p")
            case let s: (0, [], s)
            }
            if flags == [.command, .shift], letter == "p" { store.togglePitchMode() }
            else { _ = store.handlePitchKey(code: code, flags: flags, letter: letter) }
        case "continue": store.leaveDemo(toNextSlide: true)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "size": if args.count == 2, let w = Double(args[0]), let h = Double(args[1]) { resize(w, h) }
        case "env":
            if let id = args.first, let env = store.environments.first(where: { $0.id == id || $0.id.hasPrefix(id) }) { store.select(environment: env) }
        case "compile": Task { await store.compile() }
        case "ff": store.fastForward = args.first != "off"
        case "tick":
            guard let session = store.selectedSession else { break }
            if args.first == "all" || args.isEmpty { session.selectedHacks = Set(session.hacks.map(\.id)) }
            else if let n = args.first.flatMap(Int.init), session.hacks.indices.contains(n) { session.selectedHacks.insert(session.hacks[n].id) }
        case "harden":
            guard let session = store.selectedSession else { break }
            if session.selectedHacks.isEmpty { session.selectedHacks = Set(session.hacks.map(\.id)) }
            Task { await store.hardenSelected(in: session) }
        case "open":
            guard let session = store.selectedSession else { break }
            let n = args.first.flatMap(Int.init) ?? 0
            if session.hacks.indices.contains(n) { session.selectedTrajectory = session.hacks[n] }
        case "close": store.selectedSession?.selectedTrajectory = nil
        case "recheck":
            guard let session = store.selectedSession else { break }
            let n = args.first.flatMap(Int.init) ?? 0
            if session.hacks.indices.contains(n) { let hack = session.hacks[n]; Task { await session.check(hack) } }
        case "page":
            guard let session = store.selectedSession else { break }
            switch args.first ?? "" {
            case "result": session.page = .result
            case "report": session.page = .report
            case "verify": session.page = .verify
            case "certificate": session.page = .certificate
            default: break
            }
        case "accept-all": if let env = store.selectedEnvironment { store.acceptAll(in: env) }
        case "reject-all": if let env = store.selectedEnvironment { store.rejectAll(in: env) }
        case "save": if let env = store.selectedEnvironment { store.save(env) }
        case "envpage": store.showEnvironmentPage()
        default: break
        }
    }

    private static func log(dir: URL, _ line: String) {
        let stamp = Date().formatted(.dateTime.hour().minute().second().secondFraction(.fractional(1)))
        let text = "\(stamp) \(line)\n"
        let url = dir.appendingPathComponent("events.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile(); handle.write(Data(text.utf8)); try? handle.close()
        } else {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private static func resize(_ width: Double, _ height: Double) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) }) else { return }
        let size = NSSize(width: width, height: height)
        let origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - size.height)
        window.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private static func snapshot(into dir: URL, label: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) && $0.sheetParent == nil }) else { return }
        counter += 1
        write(window, to: dir, name: String(format: "snap-%03d%@.png", counter, label.isEmpty ? "" : "-" + label))
        if let sheet = window.attachedSheet {
            write(sheet, to: dir, name: String(format: "snap-%03d%@-sheet.png", counter, label.isEmpty ? "" : "-" + label))
        }
    }

    private static func write(_ window: NSWindow, to dir: URL, name: String) {
        // The sidebar's vibrancy layer does not draw into a cached bitmap (nor into a CALayer render),
        // so it comes out blank here; crop it off for stills.
        guard let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: dir.appendingPathComponent(name))
    }
}
