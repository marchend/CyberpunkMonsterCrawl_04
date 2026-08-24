import CoreGraphics
import Foundation
import SpriteKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-13-t5`: the real HP-zero -> `.death` trigger. Before this
/// PR, `.death` was reachable in a real build only from the now-deleted
/// DEBUG-only `LaunchGotoState` launch bridge -- once that was removed
/// (`-t3`), nothing but a test's direct `stateMachine.transition(to:
/// .death)` call could reach `.death`, and the whole death/high-scores
/// surface behind it (`DeathScreenNode`, `HighScoreStore`, RUN AGAIN) was
/// dead code on a device. Mirrors `PlayerCombatSceneWiringTests`'s shape:
/// build a real `GameScene` (via the composition root, so the death
/// screen's real `runSummaryProvider`/`highScoreStore` wiring is exercised
/// too, not a bespoke test double -- over a scratch `UserDefaults` suite,
/// never the player's real one; see `scratchSuiteNames`), drive it into
/// `.gameplay`, and assert
/// on the scene's own mounted/transitioned state rather than reconstructing
/// the pipeline by hand.
final class PlayerDeathTriggerTests: XCTestCase {

    /// Scratch `UserDefaults` suites created by `makeGameplayScene()`, torn
    /// down after every test.
    ///
    /// Reaching `.death` for real is the whole subject of this suite, and
    /// `DeathScreenNode.willEnter()` *persists* the run it is handed -- so
    /// against the composition root's default (the real
    /// `HighScoreStore.productionSuiteName` suite) every test here would
    /// append a genuine row to the player's own high-score table, evict
    /// older rows from the bounded top-10, and make any suite asserting on
    /// that table's contents or its empty state order-dependent. That is
    /// exactly the hazard `GameViewController`'s `runSummaryProvider` note
    /// describes, arriving from the other direction. `makeGameScene`'s
    /// `highScoreStore:` parameter (added on PR #55 review) is the seam;
    /// everything this suite actually asserts -- the transition,
    /// `playerCombat` staying mounted, a real non-`nil` `RunSummary` being
    /// recorded -- is unaffected by which suite backs the store.
    private var scratchSuiteNames: [String] = []

    override func tearDown() {
        for suiteName in scratchSuiteNames {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        scratchSuiteNames = []
        super.tearDown()
    }

    /// A per-test-isolated `HighScoreStore` -- the same shape
    /// `HighScoreStoreTests.makeIsolatedDefaults()` /
    /// `ScreensTests.makeIsolatedHighScoreStore()` already establish.
    private func makeIsolatedHighScoreStore() -> HighScoreStore {
        let suiteName = "com.cyberpunkmonstercrawl.tests.playerDeathTrigger.\(UUID().uuidString)"
        scratchSuiteNames.append(suiteName)
        return HighScoreStore(defaults: UserDefaults(suiteName: suiteName)!)
    }

    private func makeGameplayScene() -> GameScene {
        let scene = GameViewController().makeGameScene(
            size: CGSize(width: 400, height: 800),
            highScoreStore: makeIsolatedHighScoreStore()
        )
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))
        return scene
    }

    // MARK: - HP reaching zero transitions to .death

    func test_playerHPReachingZero_duringGameplay_transitionsToDeath() throws {
        let scene = makeGameplayScene()
        let player = try XCTUnwrap(scene.player)

        // Simulate a lethal hit having already been applied this frame
        // (a raccoon bite/rabies tick, in a real run) before the next
        // frame's pipeline runs.
        player.hp = 0

        scene.update(1)

        XCTAssertEqual(
            scene.stateMachine.currentState, .death,
            "the player's HP reaching zero during .gameplay must transition the state machine to "
                + ".death -- otherwise the death screen/high-scores/RUN AGAIN surface stays "
                + "unreachable by a player."
        )
    }

    // MARK: - A healthy player never spuriously transitions

    func test_playerWithPositiveHP_acrossSeveralFrames_staysInGameplay() {
        let scene = makeGameplayScene()

        for frame in 0..<10 {
            scene.update(1 + TimeInterval(frame) / 60)
        }

        XCTAssertEqual(
            scene.player?.hp, PlayerNode.baseMaxHP,
            "precondition: nothing in these frames should have damaged the player."
        )
        XCTAssertEqual(
            scene.stateMachine.currentState, .gameplay,
            "a player with HP remaining must never be spuriously transitioned to .death."
        )
    }

    // MARK: - Reaching .death this way still surfaces a real run summary

    /// The exact regression the old scaffolding note warned about: a
    /// `.death` reached without `playerCombat` staying mounted renders (and
    /// records) an all-zero placeholder summary instead of the run's real
    /// stats. Asserted through the composed `DeathScreenNode`'s own
    /// `lastRecordedRunID` -- non-`nil` only when `willEnter()`'s
    /// `runSummaryProvider()` returned a real (non-`nil`) `RunSummary` and
    /// it was successfully recorded -- rather than re-deriving the summary
    /// by hand, so this pins the same production wiring
    /// `GameViewControllerCompositionTests` already builds against.
    func test_hpZeroDeath_stillMountsPlayerCombat_soTheDeathScreenGetsARealSummary() throws {
        let scene = makeGameplayScene()
        let player = try XCTUnwrap(scene.player)

        XCTAssertNotNil(
            scene.playerCombat,
            "precondition: entering .gameplay must have constructed the player's combat composition."
        )

        player.hp = 0
        scene.update(1)

        XCTAssertEqual(scene.stateMachine.currentState, .death, "precondition: the HP-zero trigger must fire.")
        XCTAssertNotNil(
            scene.playerCombat,
            "playerCombat must stay mounted through the .gameplay -> .death transition, or the death "
                + "screen's runSummaryProvider has nothing real to read."
        )

        let deathScreen = try XCTUnwrap(scene.screens[.death] as? DeathScreenNode)
        XCTAssertNotNil(
            deathScreen.lastRecordedRunID,
            "reaching .death via the HP-zero trigger must still produce a real, recordable "
                + "RunSummary -- a nil here means the death screen fell back to its "
                + "no-run-happened placeholder, silently dropping this run's real stats."
        )
    }
}
