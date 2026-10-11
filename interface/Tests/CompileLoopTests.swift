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
        guard case .stable(let certified) = store.status(for: env), certified == nil else { return XCTFail("stable before certificate") }
        await second.issueCertificate()
        XCTAssertNotNil(second.certificate)
        guard case .stable(let signed) = store.status(for: env), signed != nil else { return XCTFail("certified after issue") }
        XCTAssertNil(second.errorMessage)
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
