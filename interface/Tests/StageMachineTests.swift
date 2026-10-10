import XCTest
@testable import Liftoff

final class StageMachineTests: XCTestCase {
    func testInitialState() {
        var m = StageMachine()
        XCTAssertEqual(m.selected, .load)
        XCTAssertTrue(m.isUnlocked(.load))
        XCTAssertFalse(m.isUnlocked(.lint))
        XCTAssertFalse(m.advance())
    }

    func testCannotSelectLockedStage() {
        var m = StageMachine()
        XCTAssertFalse(m.select(.train))
        XCTAssertEqual(m.selected, .load)
    }

    func testCompleteUnlocksAndAdvances() {
        var m = StageMachine()
        m.complete(.load)
        XCTAssertTrue(m.isCompleted(.load))
        XCTAssertTrue(m.isUnlocked(.lint))
        XCTAssertEqual(m.selected, .lint)
        XCTAssertFalse(m.isUnlocked(.train))
    }

    func testCompleteWithoutAdvance() {
        var m = StageMachine()
        m.complete(.load, advance: false)
        XCTAssertEqual(m.selected, .load)
        XCTAssertTrue(m.isUnlocked(.lint))
    }

    func testStagesStayRevisitable() {
        var m = StageMachine()
        m.complete(.load); m.complete(.lint); m.complete(.train)
        XCTAssertEqual(m.selected, .patch)
        XCTAssertTrue(m.select(.load))
        XCTAssertEqual(m.selected, .load)
        XCTAssertTrue(m.advance()); XCTAssertEqual(m.selected, .lint)
        XCTAssertTrue(m.advance()); XCTAssertEqual(m.selected, .train)
        XCTAssertTrue(m.advance()); XCTAssertEqual(m.selected, .patch)
        XCTAssertFalse(m.advance(), "verify is still locked")
        XCTAssertTrue(m.retreat()); XCTAssertEqual(m.selected, .train)
    }

    func testUnlockNeverGoesBackwards() {
        var m = StageMachine()
        m.unlock(.verify)
        m.unlock(.lint)
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
    func testStorePrimaryActionFollowsPipeline() async throws {
        let playback = PlaybackSettings(fastForward: true)
        let backend = FixtureBackend(root: FixtureDecoderTests.fixturesRoot, playback: playback, trainingSeconds: 0.05, verifySeconds: 0.05)
        let store = DemoStore(backend: backend, playback: playback)
        await store.loadRecents()
        store.select(environment: store.recentEnvironments.first { $0.id == "mimo-v26-harbor-swe" }!)
        XCTAssertEqual(store.primaryAction, .audit)

        await store.startAudit()
        XCTAssertEqual(store.stage, .lint)
        XCTAssertEqual(store.findings.count, 5)
        XCTAssertEqual(store.primaryAction, .train)

        await store.startTraining()
        XCTAssertEqual(store.stage, .train)
        XCTAssertEqual(store.trainingPoints.count, 600)
        XCTAssertNotNil(store.liftoff)
        XCTAssertNotNil(store.patch)
        XCTAssertEqual(store.primaryAction, .viewPatch)
        store.advance()
        XCTAssertEqual(store.stage, .patch)
        XCTAssertEqual(store.primaryAction, .applyAndVerify)

        await store.applyAndVerify()
        XCTAssertEqual(store.stage, .verify)
        XCTAssertEqual(store.verifyPoints.count, 600)
        XCTAssertEqual(store.verifyResult?.verdict, .pass)
        XCTAssertEqual(store.primaryAction, .issueCertificate)

        await store.issueCertificate()
        XCTAssertEqual(store.stage, .certificate)
        XCTAssertNotNil(store.certificate)
        XCTAssertEqual(store.phase, .done)
        XCTAssertNil(store.primaryAction)
        XCTAssertNil(store.errorMessage)
    }
}
