import XCTest
@testable import Provost

/// Compile → hacks → harden → accept → recompile stable → certificate.
final class CompileLoopTests: XCTestCase {
    @MainActor
    private func makeStore() async -> DemoStore {
        let playback = PlaybackSettings(fastForward: true)
        let backend = FixtureBackend(root: FixtureDecoderTests.fixturesRoot, playback: playback, trainingSeconds: 0.05, verifySeconds: 0.05)
        let store = DemoStore(backend: backend, playback: playback)
        await store.loadEnvironments()
        store.select(environment: store.environments.first { $0.id == "mimo-v26-harbor-swe" }!)
        return store
    }

    @MainActor
    private func settle(_ session: RunSession) async throws {
        while session.isBusy || !session.compileFinished { try await Task.sleep(for: .milliseconds(20)) }
    }

    @MainActor
    func testCompileFindsHacksThenHardenAcceptRecompileCertifies() async throws {
        let store = await makeStore()
        let env = store.selectedEnvironment!
        XCTAssertEqual(store.status(for: env), .unassessed)

        // Compile: unstable with hacks.
        let firstStarted = await store.compile()
        let first = try XCTUnwrap(firstStarted)
        try await settle(first)
        XCTAssertFalse(first.isStable)
        XCTAssertEqual(first.hackCount, 4)
        XCTAssertNotNil(first.liftoff)
        XCTAssertEqual(store.status(for: env), .unstable(hacks: 4))

        // Harden one hack: differences attach to the environment.
        let hack = try XCTUnwrap(first.hacks.first { $0.id == "traj-0412-03" })
        await store.harden(hack, in: first)
        let pending = store.pendingChanges(for: env)
        XCTAssertEqual(pending.count, 7)
        XCTAssertEqual(Set(pending.map(\.change.part)), [.observations, .initialState, .evaluation])

        // Accept and reject: the spec changes and the version bumps.
        let before = try XCTUnwrap(store.spec(for: env))
        let add = try XCTUnwrap(pending.first { $0.change.kind == .add })
        let remove = try XCTUnwrap(pending.first { $0.change.kind == .remove })
        store.accept(add, in: env)
        store.accept(remove, in: env)
        store.reject(try XCTUnwrap(pending.first { $0.change.field == "code" }), in: env)
        let after = try XCTUnwrap(store.spec(for: env))
        XCTAssertTrue(after.evaluation.components.contains(add.change.after!))
        XCTAssertFalse(after.observations.visible.contains(remove.change.before!))
        XCTAssertEqual(after.objective, before.objective)
        XCTAssertEqual(store.version(of: env), 3)
        XCTAssertEqual(store.pendingChanges(for: env).count, 4)
        guard case .edited = store.status(for: env) else { return XCTFail("accepting marks the environment edited") }

        // Partial recompile: the hack is closed.
        await first.check(hack)
        XCTAssertEqual(first.checks[hack.id]?.replay?.attackBlocked, true)

        // Full recompile on the hardened environment: stable, no liftoff, certificate.
        store.acceptAll(in: env)
        let secondStarted = await store.compile()
        let second = try XCTUnwrap(secondStarted)
        try await settle(second)
        XCTAssertTrue(second.isStable)
        XCTAssertNil(second.liftoff)
        XCTAssertEqual(second.hackCount, 0)
        XCTAssertEqual(second.version, store.version(of: env))
        XCTAssertTrue(second.findings.count < first.findings.count, "closed findings drop out of the scan")
        // A stable compile signs itself.
        XCTAssertNotNil(second.certificate)
        XCTAssertEqual(second.certificate?.runId, second.id)
        guard case .stable(let signed) = store.status(for: env), signed != nil else { return XCTFail("signed after a stable compile") }
        XCTAssertEqual(store.status(for: env).title, "Stable")
        XCTAssertNil(second.errorMessage)
    }

    /// Tick several hacks, harden them together: every patch attaches, the session opens its report.
    @MainActor
    func testHardenSelectedHacksTogether() async throws {
        let store = await makeStore()
        let env = store.selectedEnvironment!
        let started = await store.compile()
        let session = try XCTUnwrap(started)
        try await settle(session)
        XCTAssertEqual(session.page, .result)
        let two = session.hacks.prefix(2).map(\.id)
        session.selectedHacks = Set(two)
        await store.hardenSelected(in: session)
        XCTAssertEqual(Set(session.patches.keys), Set(two))
        XCTAssertTrue(session.selectedHacks.isEmpty)
        XCTAssertEqual(session.page, .report)
        let changes = store.changes(from: session)
        XCTAssertFalse(changes.isEmpty)
        XCTAssertEqual(Set(changes.flatMap(\.hackIds)).count, 2, "one difference can close two hacks")
        XCTAssertEqual(store.pendingChanges(for: env).count, changes.count)
    }

    /// Every hack carries the step that created it, lit by severity; outputs without steps still split.
    func testTraceStepsAndHackStep() throws {
        let fixtures = FixtureDecoderTests.fixturesRoot.appendingPathComponent("mimo-v26-harbor-swe/trajectories.json")
        let trajectories = try ContractJSON.decoder.decode([Trajectory].self, from: Data(contentsOf: fixtures))
        for hack in trajectories.filter(\.isHack) {
            let index = try XCTUnwrap(hack.hackStepIndex)
            let step = hack.trace[index]
            let needle = try XCTUnwrap(hack.hackExcerpt?.split(separator: "\n").first.map(String.init))
            XCTAssertTrue(step.action.contains(needle) || (step.result?.contains(needle) ?? false), hack.id)
        }
        XCTAssertEqual(trajectories.first { $0.id == "traj-0470-02" }?.hackSeverity, .medium)
        for hack in trajectories.filter(\.isHack) {
            let rows = try XCTUnwrap(hack.comparisons, "every hack explains which requirement it failed")
            XCTAssertTrue(rows.contains(where: \.failed), hack.id)
        }
        XCTAssertEqual(trajectories.first { $0.id == "traj-0412-03" }?.hackSeverity, .high)

        let derived = TraceStep.derive(from: "$ ls /tests\na  b\n$ cat x\nhello\nworld\n$ done")
        XCTAssertEqual(derived.map(\.action), ["ls /tests", "cat x", "done"])
        XCTAssertEqual(derived[1].result, "hello\nworld")
        XCTAssertNil(derived[2].result)
        let message = TraceStep.derive(from: "Just prose, no commands.")
        XCTAssertEqual(message.count, 1)
        XCTAssertEqual(message[0].kind, .message)
    }

    /// The demo path: accept the differences and compile again, with no Recheck in between.
    /// The backend compiles the edited spec, so the recompile is stable; rejecting everything keeps it unstable.
    @MainActor
    func testRecompileReflectsAcceptedDifferencesWithoutRecheck() async throws {
        let store = await makeStore()
        let env = store.selectedEnvironment!
        let firstStarted = await store.compile()
        let first = try XCTUnwrap(firstStarted)
        try await settle(first)
        let hack = try XCTUnwrap(first.hacks.first { $0.id == "traj-0412-03" })
        await store.harden(hack, in: first)

        store.rejectAll(in: env)
        XCTAssertEqual(store.pendingChanges(for: env).count, 0)
        let unchangedStarted = await store.compile()
        let unchanged = try XCTUnwrap(unchangedStarted)
        try await settle(unchanged)
        XCTAssertFalse(unchanged.isStable, "rejecting every difference compiles the original environment")
        XCTAssertEqual(unchanged.hackCount, 4)

        // Hardening the same hack again re-opens the rejected differences.
        await store.harden(hack, in: first)
        XCTAssertEqual(store.pendingChanges(for: env).count, 7)
        store.acceptAll(in: env)
        let editedStarted = await store.compile()
        let edited = try XCTUnwrap(editedStarted)
        try await settle(edited)
        XCTAssertTrue(edited.isStable, "accepted differences are what gets compiled")
        XCTAssertEqual(edited.hackCount, 0)
        XCTAssertNil(edited.liftoff)
    }

    /// Editing the objective by hand is a version bump: the status reads Edited until the next compile.
    @MainActor
    func testEditingObjectiveBumpsVersion() async throws {
        let store = await makeStore()
        let env = store.selectedEnvironment!
        let before = try XCTUnwrap(store.spec(for: env)?.objective)
        store.setObjective(summary: before.summary, constraints: before.constraints, in: env)
        XCTAssertEqual(store.version(of: env), 1, "no change, no bump")
        store.setObjective(summary: "  New objective.  ", constraints: ["Keep tests", "", " No network "], in: env)
        XCTAssertEqual(store.version(of: env), 2)
        XCTAssertEqual(store.spec(for: env)?.objective.summary, "New objective.")
        XCTAssertEqual(store.spec(for: env)?.objective.constraints, ["Keep tests", "No network"])
        let started = await store.compile()
        let session = try XCTUnwrap(started)
        try await settle(session)
        XCTAssertEqual(session.version, 2)
        XCTAssertEqual(session.environment.spec?.objective.summary, "New objective.", "the compile carries the edited spec")
    }

    /// Hardening from the deep dive keeps the rollouts page and lists the differences for that hack.
    @MainActor
    func testHardenFromDeepDiveStaysOnRollouts() async throws {
        let store = await makeStore()
        let env = store.selectedEnvironment!
        let started = await store.compile()
        let session = try XCTUnwrap(started)
        try await settle(session)
        let hack = try XCTUnwrap(session.hacks.first { $0.id == "traj-0412-03" })
        session.selectedHacks = [hack.id]
        await store.hardenSelected(in: session, openReport: false)
        XCTAssertEqual(session.page, .result)
        let changes = store.changes(for: hack, in: env)
        XCTAssertEqual(changes.count, 7)
        store.accept(changes[0], in: env)
        XCTAssertEqual(store.changes(for: hack, in: env).filter { $0.decision == .pending }.count, 6)
        XCTAssertEqual(store.version(of: env), 2)
    }

    /// The fast-forward schedule lands every point inside the budget, in order, with rollouts waiting longer.
    func testLiveScheduleShape() {
        let costly = [50, 120, 300]
        let schedule = FixtureBackend.liveSchedule(count: 400, costly: costly, budget: 4)
        XCTAssertEqual(schedule.count, 400)
        XCTAssertEqual(schedule.last ?? 0, 4, accuracy: 1e-9)
        XCTAssertTrue(zip(schedule, schedule.dropFirst()).allSatisfy { $0 <= $1 })
        let gaps = [0.0] + zip(schedule.dropFirst(), schedule).map { $0 - $1 }
        let costlyGap = costly.map { gaps[$0] }.reduce(0, +) / Double(costly.count)
        let typicalGap = gaps.reduce(0, +) / Double(gaps.count)
        XCTAssertGreaterThan(costlyGap, typicalGap * 3, "a step that sampled a rollout visibly waits for it")
    }

    /// With the app's real replay lengths, a fast-forward compile (scan + training) lands within five seconds.
    func testFastForwardCompileFitsFiveSeconds() async throws {
        let playback = PlaybackSettings(fastForward: true)
        let backend = FixtureBackend(root: FixtureDecoderTests.fixturesRoot, playback: playback)
        let run = try await backend.startAudit(envId: "mimo-v26-harbor-swe", spec: nil)
        let start = ContinuousClock.now
        _ = try await backend.lint(runId: run.id)
        var trajectories = 0
        for try await event in backend.train(runId: run.id) {
            if case .trajectory = event { trajectories += 1 }
        }
        let elapsed = start.duration(to: .now)
        XCTAssertEqual(trajectories, 15)
        XCTAssertLessThan(elapsed, .seconds(5), "fast-forward compile took \(elapsed)")
        XCTAssertGreaterThan(elapsed, .seconds(2.5), "fast-forward should still look like work, took \(elapsed)")
    }

    func testSpecEditorAppliesEachKind() {
        var spec = EnvironmentSpec(
            samples: nil,
            objective: ObjectiveSpec(summary: "s", constraints: ["a", "b"]),
            initialState: InitialStateSpec(summary: "i", items: [KeyValue(key: "Tests", value: "mounted")]),
            observations: ObservationSpec(visible: ["x"], hidden: []),
            actions: [ActionContract(id: "bash", description: "run", arguments: nil)],
            evaluation: EvaluationSpec(summary: "e", components: [], audit: nil),
            episode: EpisodeSpec(termination: "t", maxSteps: 1, reset: "r"),
            provenance: ProvenanceSpec(origin: .synthetic, evidence: [], license: nil))
        SpecEditor.apply(SpecChange(id: "1", part: .objective, kind: .remove, field: "constraints", before: "a", after: nil, rationale: ""), to: &spec)
        SpecEditor.apply(SpecChange(id: "2", part: .objective, kind: .alter, field: "constraints", before: "b", after: "B", rationale: ""), to: &spec)
        SpecEditor.apply(SpecChange(id: "3", part: .initialState, kind: .alter, field: "items", before: "Tests: mounted", after: "Tests: verifier only", rationale: ""), to: &spec)
        SpecEditor.apply(SpecChange(id: "4", part: .actions, kind: .remove, field: "actions", before: "bash: run", after: nil, rationale: ""), to: &spec)
        SpecEditor.apply(SpecChange(id: "5", part: .episode, kind: .alter, field: "max_steps", before: "1", after: "60", rationale: ""), to: &spec)
        XCTAssertEqual(spec.objective.constraints, ["B"])
        XCTAssertEqual(spec.initialState.items.first?.value, "verifier only")
        XCTAssertTrue(spec.actions.isEmpty)
        XCTAssertEqual(spec.episode.maxSteps, 60)
    }
}
