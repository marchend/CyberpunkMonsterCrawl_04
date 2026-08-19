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

    // MARK: - Render geometry: effects are drawn where the world actually is

    /// The regression guard for the coordinate-space defect PR #44 review
    /// caught: bullets/flashes/puffs are positioned from raw
    /// `IsometricProjection.tileToScreen` points (world space, the space
    /// `CameraController` offsets via `worldLayer`) but are parented under
    /// `effectsLayer`, which nothing ever repositions. Asserting child
    /// counts and `activeCount` cannot see that -- only a *scene-space*
    /// position can, so this test asserts one.
    func test_firedBullet_isDrawnOnTheShooter_inSceneSpace() throws {
        let scene = makeGameplayScene()

        // Drive real frames first so the camera lock has offset `worldLayer`
        // away from the origin. Without that offset both spaces coincide and
        // this test would pass over the broken code too.
        for frame in 0..<3 {
            scene.update(1 + TimeInterval(frame) / 60)
        }

        let combat = try XCTUnwrap(scene.playerCombat)
        let player = try XCTUnwrap(scene.player)
        let origin = try XCTUnwrap(scene.playerWorldPosition)

        XCTAssertNotEqual(
            scene.worldLayer.position, .zero,
            "precondition: the camera lock must have moved worldLayer off the origin."
        )

        let targetTile = TilePoint(x: origin.x + 1, y: origin.y)
        let raccoon = RaccoonNode(tier: .base)
        scene.worldLayer.addChild(raccoon)
        raccoon.position = IsometricProjection.tileToScreen(targetTile)

        // Fires on this frame (the cooldown starts at 0); the tiny delta
        // leaves the bullet still measurably on the muzzle.
        combat.update(
            deltaTime: 1e-6,
            isMoving: true,
            origin: origin,
            direction: .east,
            raccoons: [TargetSelection.Candidate(raccoon: raccoon, position: targetTile)]
        )

        let bullet = try XCTUnwrap(
            scene.effectsLayer.children.compactMap { $0 as? BulletNode }.first { !$0.isHidden },
            "the shot must have unhidden a pooled bullet under effectsLayer."
        )

        let bulletInScene = scene.convert(CGPoint.zero, from: bullet)
        let shooterInScene = scene.convert(CGPoint.zero, from: player)

        XCTAssertEqual(
            bulletInScene.x, shooterInScene.x, accuracy: 1,
            "a just-fired bullet must be drawn on the shooter in SCENE space -- if it is off by "
                + "worldLayer.position, effects are being positioned in a space nothing offsets."
        )
        XCTAssertEqual(
            bulletInScene.y, shooterInScene.y, accuracy: 1,
            "a just-fired bullet must be drawn on the shooter in SCENE space."
        )
    }

    /// The hit puff must land on the target's *current* position (and in
    /// the right space), not where it stood when the shot was fired --
    /// raccoons are re-steered every frame by `RaccoonSpawnDirector`, so a
    /// 0.05-0.5s flight is long enough for the two to diverge visibly.
    func test_hitPuff_landsOnTheTargetsCurrentPosition_notItsFireTimePosition() throws {
        let scene = makeGameplayScene()
        for frame in 0..<3 {
            scene.update(1 + TimeInterval(frame) / 60)
        }

        let combat = try XCTUnwrap(scene.playerCombat)
        let origin = try XCTUnwrap(scene.playerWorldPosition)

        let fireTimeTile = TilePoint(x: origin.x + 1, y: origin.y)
        let raccoon = RaccoonNode(tier: .base)
        scene.worldLayer.addChild(raccoon)
        raccoon.position = IsometricProjection.tileToScreen(fireTimeTile)

        combat.update(
            deltaTime: 1e-6,
            isMoving: true,
            origin: origin,
            direction: .east,
            raccoons: [TargetSelection.Candidate(raccoon: raccoon, position: fireTimeTile)]
        )

        // The swarm re-steers the target mid-flight.
        let arrivalTile = TilePoint(x: origin.x + 2, y: origin.y + 2)
        raccoon.position = IsometricProjection.tileToScreen(arrivalTile)

        // Long enough for the flight timer (~0.06s over one tile) to elapse,
        // with the fire gate closed so no second shot is taken.
        combat.update(deltaTime: 0.5, isMoving: false, origin: origin, direction: .east, raccoons: [])

        XCTAssertEqual(
            raccoon.hp, RaccoonNode.baseMaxHP - WeaponTier.handgun.damage,
            "precondition: the bullet must have arrived and applied its damage."
        )

        // The muzzle flash is an `SKSpriteNode` under the same layer; only
        // the puff runs the hit-puff animation, which is how they are told
        // apart here (actions never advance in a headless scene, so the key
        // is still attached).
        let puff = try XCTUnwrap(
            scene.effectsLayer.children
                .compactMap { $0 as? SKSpriteNode }
                .first { $0.action(forKey: HitEffects.hitPuffAnimationActionKey) != nil },
            "the bullet's arrival must have spawned a hit puff under effectsLayer."
        )

        let puffInScene = scene.convert(CGPoint.zero, from: puff)
        let targetInScene = scene.convert(CGPoint.zero, from: raccoon)

        XCTAssertEqual(
            puffInScene.x, targetInScene.x, accuracy: 1,
            "the hit puff must land on the target's current position, in scene space."
        )
        XCTAssertEqual(
            puffInScene.y, targetInScene.y, accuracy: 1,
            "the hit puff must land on the target's current position, in scene space."
        )
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
