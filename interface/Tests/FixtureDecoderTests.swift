import XCTest
@testable import Liftoff

final class FixtureDecoderTests: XCTestCase {
    /// Resources/fixtures resolved from this source file, so tests don't depend on bundle layout.
    static let fixturesRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/fixtures", isDirectory: true)

    func decode<T: Decodable>(_ type: T.Type, _ env: String, _ file: String) throws -> T {
        let url = Self.fixturesRoot.appendingPathComponent(env).appendingPathComponent(file)
        let data = try Data(contentsOf: url)
        return try ContractJSON.decoder.decode(T.self, from: data)
    }

    func testCodingFixtureDecodesEveryResource() throws {
        let env = "mimo-v26-harbor-swe"
        let environment = try decode(AuditEnvironment.self, env, "environment.json")
        XCTAssertEqual(environment.id, env)
        XCTAssertEqual(environment.format, .harbor)
        XCTAssertEqual(environment.rewardType, .programmatic)
        XCTAssertEqual(environment.taskCount, 48)

        let run = try decode(AuditRun.self, env, "run.json")
        XCTAssertEqual(run.config.model, "Qwen3-1.7B")
        XCTAssertEqual(run.config.algorithm, "GRPO")
        XCTAssertEqual(run.phase, .queued)
        XCTAssertNil(run.endedAt)

        let findings = try decode([LintFinding].self, env, "lint.json")
        XCTAssertEqual(findings.count, 5)
        XCTAssertEqual(findings.first?.failureMode, .answerKeyReachable)
        XCTAssertEqual(findings.filter { $0.severity == .high }.count, 2)

        let points = try decode([TrainingPoint].self, env, "training.json")
        XCTAssertEqual(points.count, 600)
        XCTAssertEqual(points.first?.step, 1)
        XCTAssertEqual(points.last?.step, 600)
        // The story: proxy climbs, true score falls after liftoff.
        XCTAssertGreaterThan(points.last!.proxyReward, 0.85)
        XCTAssertLessThan(points.last!.trueScore, 0.56)
        XCTAssertLessThan(abs(points[300].proxyReward - points[300].trueScore), 0.08)

        let liftoff = try decode(LiftoffEvent.self, env, "liftoff.json")
        XCTAssertEqual(liftoff.step, 412)
        XCTAssertEqual(liftoff.failureMode, .answerKeyReachable)

        let trajectories = try decode([Trajectory].self, env, "trajectories.json")
        XCTAssertFalse(trajectories.isEmpty)
        XCTAssertTrue(trajectories.contains { $0.id == liftoff.trajectoryId })
        let hacks = trajectories.filter(\.isHack)
        XCTAssertFalse(hacks.isEmpty)
        for t in hacks {
            XCTAssertNotNil(t.hackExcerpt)
            XCTAssertTrue(t.output.contains(t.hackExcerpt!), "hack_excerpt must be a substring of output for \(t.id)")
        }

        let patch = try decode(Patch.self, env, "patch.json")
        XCTAssertTrue(patch.diff.contains("--- a/"))
        XCTAssertFalse(patch.learningScope.allow.isEmpty)
        XCTAssertFalse(patch.learningScope.deny.isEmpty)
        for id in patch.findingIds { XCTAssertTrue(findings.contains { $0.id == id }) }

        let verify = try decode(VerifyResult.self, env, "verify.json")
        XCTAssertEqual(verify.verdict, .pass)
        XCTAssertEqual(verify.training?.count, 600)
        XCTAssertEqual(verify.after.hackRate, 0)

        let cert = try decode(Certificate.self, env, "certificate.json")
        XCTAssertEqual(cert.envId, env)
        XCTAssertEqual(cert.findingsClosed.count, patch.findingIds.count)
        XCTAssertTrue(cert.envHash.hasPrefix("sha256:"))
    }

    func testIfevalFixtureDecodesEveryResource() throws {
        let env = "backdoor-ifeval"
        let environment = try decode(AuditEnvironment.self, env, "environment.json")
        XCTAssertEqual(environment.format, .verifiers)
        XCTAssertEqual(environment.rewardType, .hybrid)
        let findings = try decode([LintFinding].self, env, "lint.json")
        XCTAssertEqual(findings.first?.failureMode, .formatExploit)
        XCTAssertTrue(findings.contains { $0.failureMode == .judgeSycophancy })
        let points = try decode([TrainingPoint].self, env, "training.json")
        XCTAssertEqual(points.count, 400)
        _ = try decode(LiftoffEvent.self, env, "liftoff.json")
        _ = try decode([Trajectory].self, env, "trajectories.json")
        _ = try decode(Patch.self, env, "patch.json")
        _ = try decode(VerifyResult.self, env, "verify.json")
        _ = try decode(Certificate.self, env, "certificate.json")
    }

    func testImportedRedTeamFixturesDecode() throws {
        for env in ["agency-bench-clarify", "aidanbench-coherence", "nemotron-structured-outputs"] {
            let environment = try decode(AuditEnvironment.self, env, "environment.json")
            XCTAssertEqual(environment.id, env)
            let findings = try decode([LintFinding].self, env, "lint.json")
            XCTAssertFalse(findings.isEmpty)
            XCTAssertNotNil(findings.first?.snippet, "\(env) findings should carry a source snippet")
            let trajectories = try decode([Trajectory].self, env, "trajectories.json")
            XCTAssertTrue(trajectories.contains(where: \.isHack))
            for t in trajectories {
                XCTAssertNotNil(t.judgeOutput)
                XCTAssertNotNil(t.evidence)
                if let excerpt = t.hackExcerpt { XCTAssertTrue(t.output.contains(excerpt), "\(env) \(t.id)") }
            }
            let liftoff = try decode(LiftoffEvent.self, env, "liftoff.json")
            XCTAssertTrue(trajectories.contains { $0.id == liftoff.trajectoryId && $0.isHack })
            let patch = try decode(Patch.self, env, "patch.json")
            XCTAssertFalse(patch.notes?.isEmpty ?? true)
            XCTAssertTrue(patch.diff.hasPrefix("diff --git"))
            let verify = try decode(VerifyResult.self, env, "verify.json")
            XCTAssertEqual(verify.after.hackRate, 0)
            _ = try decode(Certificate.self, env, "certificate.json")
            _ = try decode(AuditRun.self, env, "run.json")
            XCTAssertEqual(try decode([TrainingPoint].self, env, "training.json").count, 400)
        }
    }

    func testUnknownFailureModeStillDecodes() throws {
        let json = """
        {"id":"X","severity":"warn","failure_mode":"brand_new_mode","title":"t",
         "location":{"file":null,"line":null,"task_id":null},"explanation":"e","suggested_patch":"p"}
        """
        let f = try ContractJSON.decoder.decode(LintFinding.self, from: Data(json.utf8))
        XCTAssertEqual(f.failureMode.rawValue, "brand_new_mode")
        XCTAssertEqual(f.failureMode.displayName, "Brand new mode")
    }

    func testSSEEventDecoding() {
        let point = LocalHTTPBackend.decodeEvent(name: "point", data: #"{"step":3,"proxy_reward":0.2,"true_score":0.2,"kl":0.0,"timestamp":"2026-10-10T19:02:11Z"}"#)
        guard case .point(let p)? = point else { return XCTFail("expected point") }
        XCTAssertEqual(p.step, 3)
        XCTAssertEqual(LocalHTTPBackend.decodeEvent(name: "phase", data: #""training""#), .phase(.training))
        XCTAssertEqual(LocalHTTPBackend.decodeEvent(name: "phase", data: #"{"phase":"detecting"}"#), .phase(.detecting))
        XCTAssertEqual(LocalHTTPBackend.decodeEvent(name: "completed", data: ""), .completed)
        XCTAssertNil(LocalHTTPBackend.decodeEvent(name: "nonsense", data: "{}"))
    }

    func testFixtureBackendEndToEndFast() async throws {
        let playback = PlaybackSettings(fastForward: true)
        let backend = FixtureBackend(root: Self.fixturesRoot, playback: playback, trainingSeconds: 0.1, verifySeconds: 0.1)
        let envs = try await backend.listEnvironments()
        XCTAssertEqual(envs.count, 5)
        let run = try await backend.startAudit(envId: "mimo-v26-harbor-swe")
        let findings = try await backend.lint(runId: run.id)
        XCTAssertEqual(findings.count, 5)
        var points = 0, trajectories = 0, liftoffs = 0, completed = 0
        for try await event in backend.train(runId: run.id) {
            switch event {
            case .point: points += 1
            case .trajectory: trajectories += 1
            case .liftoff: liftoffs += 1
            case .completed: completed += 1
            default: break
            }
        }
        XCTAssertEqual(points, 600)
        XCTAssertEqual(trajectories, 15)
        XCTAssertEqual(liftoffs, 1)
        XCTAssertEqual(completed, 1)
        let patch = try await backend.proposePatch(runId: run.id)
        var result: VerifyResult?
        for try await event in backend.verify(runId: run.id, patchId: patch.id) {
            if case .verifyResult(let r) = event { result = r }
        }
        XCTAssertEqual(result?.verdict, .pass)
        let cert = try await backend.issueCertificate(runId: run.id)
        XCTAssertEqual(cert.runId, run.id)
    }
}
