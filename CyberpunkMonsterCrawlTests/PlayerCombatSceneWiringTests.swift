import CoreGraphics
import SpriteKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-9` PR 3: `Player`'s *scene* wiring -- proving the
/// auto-fire/progression composition is reachable from
/// `GameScene`'s real production pipeline, not just from
/// `WeaponFiringControllerIntegrationTests`'s standalone `Player`
/// construction. Mirrors the shape `PlayerMountTests` and
/// `RaccoonSwarmSceneWiringTests` already established for `PlayerNode` and
/// `RaccoonSpawnDirector`: assert on the scene's own mounted state rather
/// than reconstructing a `Player` by hand.
final class PlayerCombatSceneWiringTests: XCTestCase {

    private func makeGameplayScene() -> GameScene {
        let scene = GameScene(size: CGSize(width: 400, height: 800))
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))
        return scene
    }

    // MARK: - The composition exists on a real device build

    func test_enteringGameplay_constructsPlayerCombat() {
        let scene = makeGameplayScene()
        XCTAssertNotNil(
            scene.playerCombat,
            "Entering .gameplay must construct the player's combat/progression composition -- "
                + "otherwise the auto-fire loop is dead code on a real device build."
        )
    }

    func test_playerCombat_sharesTheMountedPlayersBodyForItsOverlay() throws {
        let scene = makeGameplayScene()
        let player = try XCTUnwrap(scene.player)
        let combat = try XCTUnwrap(scene.playerCombat)

        XCTAssertTrue(
            combat.weaponOverlayRenderer.overlay.parent === player.body,
            "the weapon overlay must be composited onto the mounted player's own body sprite."
        )
    }

    func test_playerCombatsBulletPool_isMountedUnderEffectsLayer() throws {
        let scene = makeGameplayScene()
        let combat = try XCTUnwrap(scene.playerCombat)

        XCTAssertGreaterThan(
            scene.effectsLayer.children.count, 0,
            "the bullet pool's pre-mounted (hidden) bullet nodes must live under effectsLayer."
        )
        XCTAssertEqual(combat.bulletPool.activeCount, 0, "no bullet is in flight before any frame has run.")
    }

    // MARK: - Restarting a run reuses (and resets) the same composition

    func test_restartingARun_reusesTheSamePlayerCombat_ratherThanRebuildingIt() throws {
        let scene = makeGameplayScene()
        let first = try XCTUnwrap(scene.playerCombat)

        // Simulate some progression before the run ends.
        first.xpLevelSystem.awardXP(50)
        first.runStats.recordDamage(8)
        first.runStats.recordKill()

        XCTAssertTrue(scene.stateMachine.transition(to: .death))
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))

        XCTAssertTrue(
            scene.playerCombat === first,
            "RUN AGAIN must reuse the same Player composition, not build a second one."
        )
        XCTAssertEqual(first.xpLevelSystem.xp, 0, "RUN AGAIN must not inherit the previous run's XP.")
        XCTAssertEqual(first.runStats.damageDealt, 0, "RUN AGAIN must not inherit the previous run's damage dealt.")
        XCTAssertEqual(first.runStats.killCount, 0, "RUN AGAIN must not inherit the previous run's kill count.")
    }

    // MARK: - Structural invariants still hold with the composition mounted

    func test_playerCombat_keepsTheScenesLayerAndDispatchInvariantsIntact() {
        let scene = makeGameplayScene()

        XCTAssertTrue(
            scene.nodesEscapingTheirLayerBand().isEmpty,
            "The player's bullet pool / weapon overlay escaped their layer band: "
                + "\(scene.layerBandViolationReport())"
        )
        XCTAssertTrue(
            scene.nodesBypassingSceneTouchDispatch().isEmpty,
            "A bullet or overlay node opted into UIKit touch delivery and would bypass the scene's dispatch."
        )
    }

    // MARK: - No raccoon in range -> the loop stays quiet (no crash, no bullet)

    func test_earlyGameplayFrames_withNoRaccoonYetInRange_fireNothing() {
        // Raccoons spawn far off-screen and only after
        // `RaccoonSpawnDirector.initialSpawnInterval` (3s) at the earliest,
        // so a handful of early frames must drive the whole pipeline
        // (including `playerCombat`) without crashing and without ever
        // claiming a bullet.
        let scene = makeGameplayScene()

        for frame in 0..<10 {
            scene.update(1 + TimeInterval(frame) / 60)
        }

        XCTAssertEqual(
            scene.playerCombat?.bulletPool.activeCount, 0,
            "with no raccoon in range yet, the auto-fire loop must not claim a bullet."
        )
    }
}
