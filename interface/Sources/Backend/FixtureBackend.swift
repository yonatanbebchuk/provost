import Foundation

/// Replays JSON fixtures from `Resources/fixtures/<env-id>/` with realistic timing.
///
/// Layout per environment (see `scripts/make_fixtures.py`):
/// `environment.json`, `run.json`, `lint.json`, `training.json`, `liftoff.json`,
/// `trajectories.json`, `patch.json`, `verify.json`, `certificate.json`.
public final class FixtureBackend: AuditBackend {
    public let displayName = "Fixture replay"

    private let root: URL
    private let playback: PlaybackSettings
    private let trainingSeconds: Double
    private let verifySeconds: Double

    /// Run ids are minted per audit; we remember which env each one belongs to.
    private let runs = Locked<[String: String]>([:])

    /// Fixtures bundled in the app.
    public static func bundled(playback: PlaybackSettings) -> FixtureBackend {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("fixtures", isDirectory: true) else {
            preconditionFailure("Fixtures folder missing from bundle — check project.yml folder reference")
        }
        return FixtureBackend(root: url, playback: playback)
    }

    public init(root: URL, playback: PlaybackSettings = PlaybackSettings(),
                trainingSeconds: Double = AppConfig.trainingReplaySeconds,
                verifySeconds: Double = AppConfig.verifyReplaySeconds) {
        self.root = root
        self.playback = playback
        self.trainingSeconds = trainingSeconds
        self.verifySeconds = verifySeconds
    }

    // MARK: AuditBackend

    public func listEnvironments() async throws -> [AuditEnvironment] {
        let dirs = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try dirs.compactMap { dir in
            let file = dir.appendingPathComponent("environment.json")
            guard FileManager.default.fileExists(atPath: file.path) else { return nil }
            return try load(AuditEnvironment.self, from: file)
        }
    }

    public func loadEnvironment(at url: URL) async throws -> AuditEnvironment {
        // A dropped folder that is itself a fixture set.
        let direct = url.appendingPathComponent("environment.json")
        if FileManager.default.fileExists(atPath: direct.path) {
            return try load(AuditEnvironment.self, from: direct)
        }
        // A dropped folder whose name matches a bundled fixture (e.g. a real env checkout).
        if let match = try await listEnvironments().first(where: { $0.id == url.lastPathComponent || $0.name == url.lastPathComponent }) {
            return match
        }
        // Anything else: describe what we can see so the card still renders honestly.
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        let format: EnvFormat = contents.contains("task.toml") || contents.contains("tasks") ? .harbor
            : contents.contains(where: { $0.hasSuffix(".py") && $0.contains("env") }) ? .verifiers : .custom
        return AuditEnvironment(
            id: url.lastPathComponent, name: url.lastPathComponent, format: format, source: url.path,
            taskCount: contents.filter { !$0.hasPrefix(".") }.count, rewardType: .programmatic,
            sandbox: SandboxSummary(runtime: "unknown", network: "unknown", filesystem: url.path, tools: []),
            description: "Loaded from disk. No fixture data for this environment — audit will not have replay data.")
    }

    public func startAudit(envId: String) async throws -> AuditRun {
        var run = try load(AuditRun.self, from: file("run.json", env: envId))
        run.phase = .queued
        run.startedAt = Date()
        run.endedAt = nil
        runs.withLock { $0[run.id] = envId }
        return run
    }

    public func lint(runId: String) async throws -> [LintFinding] {
        let env = try envId(for: runId)
        try await pause(seconds: 0.9)
        return try load([LintFinding].self, from: file("lint.json", env: env))
    }

    public func train(runId: String) -> AsyncThrowingStream<TrainingEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let env = try envId(for: runId)
                    let points = try load([TrainingPoint].self, from: file("training.json", env: env))
                    let trajectories = try load([Trajectory].self, from: file("trajectories.json", env: env))
                        .sorted { $0.step < $1.step }
                    let liftoff = try load(LiftoffEvent.self, from: file("liftoff.json", env: env))
                    continuation.yield(.phase(.training))
                    try await replay(points, over: trainingSeconds) { point in
                        continuation.yield(.point(point))
                        for t in trajectories where t.step == point.step {
                            continuation.yield(.trajectory(t))
                        }
                        if point.step == liftoff.step {
                            continuation.yield(.liftoff(liftoff))
                            continuation.yield(.phase(.detecting))
                        }
                    }
                    continuation.yield(.phase(.patching))
                    continuation.yield(.completed)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func proposePatch(runId: String) async throws -> Patch {
        let env = try envId(for: runId)
        try await pause(seconds: 0.6)
        return try load(Patch.self, from: file("patch.json", env: env))
    }

    public func verify(runId: String, patchId: String) -> AsyncThrowingStream<TrainingEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let env = try envId(for: runId)
                    var result = try load(VerifyResult.self, from: file("verify.json", env: env))
                    let points = result.training ?? []
                    result.training = nil
                    continuation.yield(.phase(.verifying))
                    try await replay(points, over: verifySeconds) { continuation.yield(.point($0)) }
                    continuation.yield(.verifyResult(result))
                    continuation.yield(.phase(.done))
                    continuation.yield(.completed)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func issueCertificate(runId: String) async throws -> Certificate {
        let env = try envId(for: runId)
        try await pause(seconds: 0.5)
        var cert = try load(Certificate.self, from: file("certificate.json", env: env))
        cert.issuedAt = Date()
        return cert
    }

    // MARK: Helpers

    private func envId(for runId: String) throws -> String {
        guard let env = runs.withLock({ $0[runId] }) else { throw BackendError.notFound("run \(runId)") }
        return env
    }

    private func file(_ name: String, env: String) -> URL {
        root.appendingPathComponent(env, isDirectory: true).appendingPathComponent(name)
    }

    private func load<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        guard let data = FileManager.default.contents(atPath: url.path) else {
            throw BackendError.notFound(url.lastPathComponent)
        }
        do {
            return try ContractJSON.decoder.decode(T.self, from: data)
        } catch {
            throw BackendError.decoding(url.lastPathComponent, underlying: String(describing: error))
        }
    }

    /// Sleep that collapses to ~nothing in fast-forward.
    private func pause(seconds: Double) async throws {
        try await Task.sleep(for: .milliseconds(playback.fastForward ? 30 : Int(seconds * 1000)))
    }

    /// Emit points spread over `seconds` at normal speed; in fast-forward emit in bursts of 8 with a
    /// 1 ms breather so the UI stays responsive.
    private func replay(_ points: [TrainingPoint], over seconds: Double,
                        emit: (TrainingPoint) -> Void) async throws {
        guard !points.isEmpty else { return }
        let perPoint = seconds / Double(points.count)
        var anchor = ContinuousClock.now
        var anchorIndex = 0
        var wasFast = playback.fastForward
        for (i, p) in points.enumerated() {
            try Task.checkCancellation()
            emit(p)
            let fast = playback.fastForward
            if fast != wasFast { anchor = .now; anchorIndex = i; wasFast = fast }
            if fast {
                if i % 16 == 15 { try await Task.sleep(for: .milliseconds(1)) }
            } else {
                // Sleep until this point's deadline so UI render cost doesn't stretch the replay.
                let deadline = anchor + .seconds(perPoint * Double(i - anchorIndex + 1))
                if deadline > .now { try await Task.sleep(until: deadline) }
            }
        }
    }
}

/// Tiny lock wrapper so a `final class` can be `Sendable` without an actor hop.
final class Locked<Value: Sendable>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()
    init(_ value: Value) { self.value = value }
    func withLock<R>(_ body: (inout Value) throws -> R) rethrows -> R {
        lock.lock(); defer { lock.unlock() }
        return try body(&value)
    }
}
