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
    /// Environments whose patch has been applied (a verify ran). Their next compile replays the clean
    /// curve from verify.json with the closed findings removed: the hardened environment compiles stable.
    private let hardened = Locked<Set<String>>([])

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

    public func startAudit(envId: String, spec: EnvironmentSpec?) async throws -> AuditRun {
        // The fixture has one hardened outcome. Compiling a spec that differs from the one shipped with the
        // environment (accepted differences applied) replays it; compiling the original replays the hacks.
        if let spec, let original = try? load(AuditEnvironment.self, from: file("environment.json", env: envId)).spec {
            hardened.withLock { if spec != original { $0.insert(envId) } else { $0.remove(envId) } }
        }
        var run = try load(AuditRun.self, from: file("run.json", env: envId))
        // Every compile is its own run, even when it replays the same fixture.
        let serial = runs.withLock { $0.count + 1 }
        run.id = "\(run.id)-\(serial)"
        run.phase = .queued
        run.startedAt = Date()
        run.endedAt = nil
        runs.withLock { $0[run.id] = envId }
        return run
    }

    public func lint(runId: String) async throws -> [LintFinding] {
        let env = try envId(for: runId)
        try await pause(seconds: 0.9)
        let findings = try load([LintFinding].self, from: file("lint.json", env: env))
        guard hardened.withLock({ $0.contains(env) }) else { return findings }
        let closed = Set((try? load(Patch.self, from: file("patch.json", env: env)))?.findingIds ?? [])
        return findings.filter { !closed.contains($0.id) }
    }

    public func train(runId: String) -> AsyncThrowingStream<TrainingEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let env = try envId(for: runId)
                    let isHardened = hardened.withLock { $0.contains(env) }
                    let points: [TrainingPoint]
                    let trajectories: [Trajectory]
                    let liftoff: LiftoffEvent?
                    if isHardened {
                        points = try load(VerifyResult.self, from: file("verify.json", env: env)).training ?? []
                        trajectories = try load([Trajectory].self, from: file("trajectories.json", env: env))
                            .filter { !$0.isHack }.sorted { $0.step < $1.step }
                        liftoff = nil
                    } else {
                        points = try load([TrainingPoint].self, from: file("training.json", env: env))
                        trajectories = try load([Trajectory].self, from: file("trajectories.json", env: env))
                            .sorted { $0.step < $1.step }
                        liftoff = try load(LiftoffEvent.self, from: file("liftoff.json", env: env))
                    }
                    continuation.yield(.phase(.training))
                    let rolloutSteps = Set(trajectories.map(\.step))
                    try await replay(points, over: trainingSeconds, costly: rolloutSteps) { point in
                        continuation.yield(.point(point))
                        for t in trajectories where t.step == point.step {
                            continuation.yield(.trajectory(t))
                        }
                        if let liftoff, point.step == liftoff.step {
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

    public func proposePatch(runId: String, trajectoryId: String?) async throws -> Patch {
        let env = try envId(for: runId)
        try await pause(seconds: 0.6)
        var patch = try load(Patch.self, from: file("patch.json", env: env))
        patch.trajectoryId = trajectoryId
        return patch
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
                    hardened.withLock { _ = $0.insert(env) }
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
        cert.runId = runId
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

    /// Fast-forward keeps the shape of a real run but fits it in a few seconds: a normal-speed replay
    /// of `seconds` becomes this long. Tests pass tiny `seconds`, so they stay instant.
    private func fastBudget(for seconds: Double) -> Double { min(4.0, seconds * 0.13) }

    /// A short, uneven wait. Fast-forward keeps up to half a second of it so a phase still reads as work.
    private func pause(seconds: Double) async throws {
        let ms = playback.fastForward ? Int(Double.random(in: 0.3...0.7) * min(seconds, 0.8) * 1000)
                                      : Int(seconds * 1000)
        try await Task.sleep(for: .milliseconds(ms))
    }

    /// Emit points spread over `seconds` at normal speed. In fast-forward the same points land inside
    /// `fastBudget` with the irregular rhythm of a live run: bursts, hiccups, and a visible pause before
    /// each step that produced a rollout (`costly`).
    private func replay(_ points: [TrainingPoint], over seconds: Double, costly: Set<Int> = [],
                        emit: (TrainingPoint) -> Void) async throws {
        guard !points.isEmpty else { return }
        let perPoint = seconds / Double(points.count)
        let schedule = Self.liveSchedule(count: points.count, costly: points.indices.filter { costly.contains(points[$0].step) },
                                         budget: fastBudget(for: seconds))
        var anchor = ContinuousClock.now
        var anchorIndex = 0
        var wasFast = playback.fastForward
        for (i, p) in points.enumerated() {
            try Task.checkCancellation()
            let fast = playback.fastForward
            if fast != wasFast { anchor = .now; anchorIndex = i; wasFast = fast }
            // Sleep until this point's deadline so UI render cost doesn't stretch the replay.
            let deadline = fast
                ? anchor + .seconds(schedule[i] - (anchorIndex > 0 ? schedule[anchorIndex - 1] : 0))
                : anchor + .seconds(perPoint * Double(i - anchorIndex + 1))
            if deadline > .now { try await Task.sleep(until: deadline) }
            emit(p)
        }
    }

    /// Cumulative seconds at which each point lands, summing to `budget`. Gaps are log-normal, so
    /// most are quick and a few drag; runs of points arrive almost together; about one in twenty-five
    /// hiccups; and a step that sampled a rollout waits for it.
    static func liveSchedule(count: Int, costly: [Int], budget: Double) -> [Double] {
        var rng = SystemRandomNumberGenerator()
        func gauss() -> Double {
            let u = max(Double.random(in: 0..<1, using: &rng), 1e-9), v = Double.random(in: 0..<1, using: &rng)
            return (-2 * log(u)).squareRoot() * cos(2 * .pi * v)
        }
        let costlySet = Set(costly)
        var weights: [Double] = []
        var burstLeft = 0
        for i in 0..<count {
            var w = exp(gauss() * 0.9)
            if burstLeft > 0 { w *= 0.08; burstLeft -= 1 }
            else if Double.random(in: 0..<1, using: &rng) < 0.06 { burstLeft = Int.random(in: 5...14, using: &rng) }
            if Double.random(in: 0..<1, using: &rng) < 0.04 { w *= 10 }
            if costlySet.contains(i) { w *= 30 }
            weights.append(w)
        }
        let total = weights.reduce(0, +)
        var acc = 0.0
        return weights.map { acc += $0; return budget * acc / total }
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
