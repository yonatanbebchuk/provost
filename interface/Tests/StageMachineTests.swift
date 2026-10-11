import XCTest
@testable import Provost

final class StageMachineTests: XCTestCase {
    func testInitialState() {
        var m = StageMachine()
        XCTAssertEqual(m.selected, .train)
        XCTAssertTrue(m.isUnlocked(.train))
        XCTAssertFalse(m.isUnlocked(.patch))
        XCTAssertFalse(m.advance())
    }

    func testCannotSelectLockedStage() {
        var m = StageMachine()
        XCTAssertFalse(m.select(.verify))
        XCTAssertEqual(m.selected, .train)
    }

    func testCompleteUnlocksAndAdvances() {
        var m = StageMachine()
        m.complete(.train)
        XCTAssertTrue(m.isCompleted(.train))
        XCTAssertTrue(m.isUnlocked(.patch))
        XCTAssertEqual(m.selected, .patch)
        XCTAssertFalse(m.isUnlocked(.verify))
    }

    func testCompleteWithoutAdvance() {
        var m = StageMachine()
        m.complete(.train, advance: false)
        XCTAssertEqual(m.selected, .train)
        XCTAssertTrue(m.isUnlocked(.patch))
    }

    func testStagesStayRevisitable() {
        var m = StageMachine()
        m.complete(.train); m.complete(.patch)
        XCTAssertEqual(m.selected, .verify)
        XCTAssertTrue(m.select(.train))
        XCTAssertTrue(m.advance()); XCTAssertEqual(m.selected, .patch)
        XCTAssertTrue(m.advance()); XCTAssertEqual(m.selected, .verify)
        XCTAssertFalse(m.advance(), "certificate is still locked")
        XCTAssertTrue(m.retreat()); XCTAssertEqual(m.selected, .patch)
    }

    func testUnlockNeverGoesBackwards() {
        var m = StageMachine()
        m.unlock(.verify)
        m.unlock(.patch)
        XCTAssertEqual(m.highestUnlocked, .verify)
    }

    func testFullWalkthroughEndsOnCertificate() {
        var m = StageMachine()
        for stage in Stage.allCases { m.complete(stage) }
        XCTAssertEqual(m.selected, .certificate)
        XCTAssertEqual(m.completed.count, Stage.allCases.count)
        m.reset()
        XCTAssertEqual(m, StageMachine())
    }

    @MainActor
    func testRunSessionWalksThePipeline() async throws {
        let playback = PlaybackSettings(fastForward: true)
        let backend = FixtureBackend(root: FixtureDecoderTests.fixturesRoot, playback: playback, trainingSeconds: 0.05, verifySeconds: 0.05)
        let store = DemoStore(backend: backend, playback: playback)
        await store.loadEnvironments()
        XCTAssertEqual(store.environments.count, 5)
        store.select(environment: store.environments.first { $0.id == "mimo-v26-harbor-swe" }!)
        XCTAssertNil(store.selectedSession)
        XCTAssertNotNil(store.selectedEnvironment?.spec)

        // newRun starts the session in a detached task; drive it directly here for determinism.
        let run = try await backend.startAudit(envId: "mimo-v26-harbor-swe")
        let session = RunSession(run: run, environment: store.selectedEnvironment!, backend: backend)
        XCTAssertNil(session.primaryAction)
        await session.start()
        XCTAssertEqual(session.findings.count, 5)
        XCTAssertEqual(session.trainingPoints.count, 600)
        XCTAssertNotNil(session.liftoff)
        XCTAssertNotNil(session.patch)
        XCTAssertEqual(session.patch?.touches, [.initialState, .observations, .evaluation])
        XCTAssertTrue(session.log.contains { $0.kind == .liftoff })
        XCTAssertEqual(session.stage, .train)
        XCTAssertEqual(session.primaryAction, .viewPatch)
        session.advance()
        XCTAssertEqual(session.stage, .patch)
        XCTAssertEqual(session.primaryAction, .applyAndVerify)

        await session.applyAndVerify()
        XCTAssertEqual(session.stage, .verify)
        XCTAssertEqual(session.verifyPoints.count, 600)
        XCTAssertEqual(session.verifyResult?.verdict, .pass)
        XCTAssertEqual(session.primaryAction, .issueCertificate)

        await session.issueCertificate()
        XCTAssertEqual(session.stage, .certificate)
        XCTAssertNotNil(session.certificate)
        XCTAssertEqual(session.phase, .done)
        XCTAssertNil(session.primaryAction)
        XCTAssertNil(session.errorMessage)
    }
}
