import CoreGraphics
import SpriteKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-9` PR 3: `Player`'s end-to-end composition of
/// targeting/firing/bullets/effects/progression -- AC1 (the full gated
/// auto-fire loop, bullets never leak), AC7 (XP/level curve; overlay row
/// swap in the same frame as the level-up) and AC8 (cumulative damage
/// dealt and kill count) all proven through the same live `Player`
/// instance `GameScene.startPlayer(at:)` mounts and
/// `advanceMovementAndCamera(currentTime:)` drives -- this same PR, per
/// `Player`'s own "Production mount" doc section. (An earlier revision of
/// this header cited a later integration task `CYBERPUN-17-16`; no such
/// ticket has been filed, and this codebase does not reference invented
/// ticket IDs -- `BulletPool` and `WeaponFiringController` state the same
/// rule.) `PlayerCombatSceneWiringTests` covers the scene-side wiring and
/// the render-space geometry; this file drives the composition directly.
final class WeaponFiringControllerIntegrationTests: XCTestCase {

    private func makeBody() -> SKSpriteNode {
        let body = SKSpriteNode(texture: nil, color: .clear, size: PlayerSpriteSheet.cellSize)
        body.anchorPoint = PlayerSpriteSheet.anchorPointNormalized
        return body
    }

    // MARK: - AC1 gate: no fire at all while standing still

    func test_stationaryPlayer_neverFires_evenWithATargetInRange() {
        let world = SKNode()
        let player = Player(body: makeBody(), effectsParent: SKNode())
        let raccoon = RaccoonNode(tier: .base)
        world.addChild(raccoon)

        for _ in 0..<120 {
            player.update(
                deltaTime: 1.0 / 60.0,
                isMoving: false,
                origin: TilePoint(x: 0, y: 0),
                direction: .east,
                raccoons: [TargetSelection.Candidate(raccoon: raccoon, position: TilePoint(x: 1, y: 0))]
            )
        }

        XCTAssertEqual(player.bulletPool.activeCount, 0, "a stationary player must never fire a bullet.")
        XCTAssertEqual(raccoon.hp, RaccoonNode.baseMaxHP, "no damage without ever firing.")
    }

    // MARK: - AC1/AC8: moving player fires, bullet travels, hit applies damage,
    // kill awards XP and increments both counters

    func test_movingPlayer_withARaccoonInRange_firesTravelsHitsKillsAndAwardsXP() {
        let world = SKNode()
        let effects = SKNode()
        let player = Player(body: makeBody(), effectsParent: effects)

        let raccoon = RaccoonNode(tier: .base)
        world.addChild(raccoon)
        let origin = TilePoint(x: 0, y: 0)
        let targetPosition = TilePoint(x: 1, y: 0)

        func tick(_ count: Int) {
            for _ in 0..<count {
                player.update(
                    deltaTime: 1.0 / 60.0,
                    isMoving: true,
                    origin: origin,
                    direction: .east,
                    raccoons: raccoon.isDead ? [] : [TargetSelection.Candidate(raccoon: raccoon, position: targetPosition)]
                )
            }
        }

        // Fires on the very first qualifying frame (cooldown starts at 0).
        tick(1)
        XCTAssertEqual(player.bulletPool.activeCount, 1, "the shot must have claimed a bullet from the pool.")
        XCTAssertEqual(raccoon.hp, RaccoonNode.baseMaxHP, "damage must not apply before the bullet has travelled.")

        // Advance past the bullet's flight time, well short of the next
        // cooldown (handgun: 0.6s) so exactly one hit has landed.
        tick(30) // 0.5s
        XCTAssertEqual(
            raccoon.hp, RaccoonNode.baseMaxHP - WeaponTier.handgun.damage,
            "the bullet's arrival must apply exactly the handgun's damage."
        )
        XCTAssertEqual(player.runStats.damageDealt, WeaponTier.handgun.damage)
        XCTAssertEqual(player.runStats.killCount, 0)
        XCTAssertEqual(player.bulletPool.activeCount, 0, "the bullet must be released back to the pool on arrival.")

        // Let two more shots land -- 20 HP at 8 damage/shot dies on the
        // third hit. Comfortably enough simulated time for two more
        // cooldown + travel cycles.
        tick(200) // ~3.3s more

        XCTAssertTrue(raccoon.isDead, "three handgun hits (24 damage total) must have killed a 20 HP raccoon.")
        XCTAssertEqual(
            player.runStats.damageDealt, WeaponTier.handgun.damage * 3,
            "cumulative damage dealt must reflect all three hits, including the overkill on the last one."
        )
        XCTAssertEqual(player.runStats.killCount, 1, "the kill must be recorded exactly once.")
        XCTAssertEqual(
            player.xpLevelSystem.xp, Player.xpPerKill,
            "the kill must award exactly one kill's worth of XP."
        )
        XCTAssertEqual(player.bulletPool.activeCount, 0, "no bullet may be left on loan once the target is dead.")
    }

    // MARK: - AC1 visual: the fired bullet actually crosses the gap

    /// PR #44 review caught that the pooled node was configured once at the
    /// muzzle and never moved again -- on screen a bullet popped into
    /// existence, sat still for its whole `travelDuration`, then vanished.
    /// This pins the position moving toward the target on every frame of
    /// the flight, which no counter-based assertion can see.
    func test_firedBullet_movesFromTheMuzzleTowardsItsTarget_everyFrameOfItsFlight() throws {
        let world = SKNode()
        let effects = SKNode()
        let player = Player(body: makeBody(), effectsParent: effects)

        let raccoon = RaccoonNode(tier: .base)
        world.addChild(raccoon)

        let origin = TilePoint(x: 0, y: 0)
        // ~215pt away, i.e. ~0.24s of flight at 900pt/s, so every frame
        // measured below lands mid-flight.
        let targetPosition = TilePoint(x: 4, y: 0)
        let originScreen = IsometricProjection.tileToScreen(origin)
        let targetScreen = IsometricProjection.tileToScreen(targetPosition)
        let candidate = TargetSelection.Candidate(raccoon: raccoon, position: targetPosition)

        func distanceToTarget(from point: CGPoint) -> CGFloat {
            hypot(targetScreen.x - point.x, targetScreen.y - point.y)
        }

        // Fires on the first qualifying frame (cooldown starts at 0); the
        // tiny delta leaves it measurably still on the muzzle.
        player.update(deltaTime: 1e-6, isMoving: true, origin: origin, direction: .east, raccoons: [candidate])

        let bullet = try XCTUnwrap(
            effects.children.compactMap { $0 as? BulletNode }.first { !$0.isHidden },
            "the shot must have unhidden a pooled bullet."
        )
        XCTAssertEqual(
            hypot(bullet.position.x - originScreen.x, bullet.position.y - originScreen.y), 0, accuracy: 1,
            "a just-fired bullet starts on the muzzle."
        )

        var previousDistance = distanceToTarget(from: bullet.position)
        for frame in 0..<5 {
            // Fire gate closed so no second shot can claim another bullet.
            player.update(deltaTime: 1.0 / 60.0, isMoving: false, origin: origin, direction: .east, raccoons: [candidate])

            let distance = distanceToTarget(from: bullet.position)
            XCTAssertLessThan(
                distance, previousDistance,
                "frame \(frame): the bullet must have moved closer to its target, not sat at the muzzle."
            )
            previousDistance = distance
        }

        XCTAssertEqual(
            player.bulletPool.activeCount, 1,
            "the bullet must still be in flight -- otherwise the frames above measured an arrival, not travel."
        )
        XCTAssertEqual(raccoon.hp, RaccoonNode.baseMaxHP, "no damage may apply before the flight timer elapses.")
    }

    // MARK: - AC7: reaching level 3 / level 6 swaps both the decision layer's
    // tier and the overlay's drawn row in the same frame as the level-up

    func test_reachingLevel3And6_swapsWeaponTierAndOverlayRow_inTheSameFrameAsTheLevelUpKill() {
        let world = SKNode()
        let player = Player(body: makeBody(), effectsParent: SKNode())

        let origin = TilePoint(x: 0, y: 0)
        let targetPosition = TilePoint(x: 1, y: 0)

        // hp: 1 so every handgun hit is a one-shot kill -- this test only
        // cares about how many *kills* it takes to cross the level-3/6 XP
        // thresholds (10 and 25 respectively at 20 XP/kill), not about
        // multi-hit raccoon HP, which the previous test already covers.
        var currentRaccoon = RaccoonNode(tier: .base, hp: 1)
        world.addChild(currentRaccoon)

        var sawLevel3TierSwap = false
        var sawLevel6TierSwap = false

        // Comfortably more simulated time than 25 one-shot kills need at
        // the handgun's 0.6s cooldown plus a short travel time each.
        for _ in 0..<4000 {
            if currentRaccoon.isDead {
                let fresh = RaccoonNode(tier: .base, hp: 1)
                world.addChild(fresh)
                currentRaccoon = fresh
            }

            let levelBefore = player.xpLevelSystem.level

            player.update(
                deltaTime: 0.05,
                isMoving: true,
                origin: origin,
                direction: .east,
                raccoons: [TargetSelection.Candidate(raccoon: currentRaccoon, position: targetPosition)]
            )

            if player.xpLevelSystem.level != levelBefore {
                let expectedTier = XPLevelSystem.tier(forLevel: player.xpLevelSystem.level)
                XCTAssertEqual(
                    player.weaponFiringController.tier, expectedTier,
                    "WeaponFiringController.setTier must run on the exact frame the level-up happened."
                )
                XCTAssertEqual(
                    player.weaponOverlayRenderer.tier, expectedTier,
                    "WeaponOverlayRenderer.update must run on the exact frame the level-up happened."
                )
                if player.xpLevelSystem.level == 3 { sawLevel3TierSwap = true }
                if player.xpLevelSystem.level == 6 { sawLevel6TierSwap = true }
            }

            if sawLevel6TierSwap { break }
        }

        XCTAssertTrue(sawLevel3TierSwap, "the run never reached level 3 within the simulated time budget.")
        XCTAssertTrue(sawLevel6TierSwap, "the run never reached level 6 within the simulated time budget.")
        XCTAssertEqual(player.weaponFiringController.tier, .assaultRifle)
        XCTAssertEqual(player.weaponOverlayRenderer.tier, .assaultRifle)
    }

    // MARK: - Bullet-leak regression: a target that despawns mid-flight

    func test_targetDespawningMidFlight_releasesTheBulletWithoutApplyingDamage_noLeak() {
        let world = SKNode()
        let player = Player(body: makeBody(), effectsParent: SKNode())

        let raccoon = RaccoonNode(tier: .base)
        world.addChild(raccoon)
        let origin = TilePoint(x: 0, y: 0)
        let targetPosition = TilePoint(x: 1, y: 0)

        player.update(
            deltaTime: 1.0 / 60.0,
            isMoving: true,
            origin: origin,
            direction: .east,
            raccoons: [TargetSelection.Candidate(raccoon: raccoon, position: targetPosition)]
        )
        XCTAssertEqual(player.bulletPool.activeCount, 1, "the shot must have claimed a bullet.")

        // Simulate the target despawning mid-flight -- a raccoon removed by
        // some other system (killed elsewhere, or its chunk streamed out)
        // before this bullet's flight timer has elapsed.
        raccoon.removeFromParent()

        // Advance well past the bullet's flight time.
        for _ in 0..<30 {
            player.update(
                deltaTime: 1.0 / 60.0,
                isMoving: true,
                origin: origin,
                direction: .east,
                raccoons: [] // the despawned target is no longer a valid candidate
            )
        }

        XCTAssertEqual(
            player.bulletPool.activeCount, 0,
            "a bullet whose target despawned mid-flight must be released back to the pool, not leaked."
        )
        XCTAssertEqual(
            raccoon.hp, RaccoonNode.baseMaxHP,
            "a despawned target must take no damage from its own in-flight bullet."
        )
        XCTAssertEqual(player.runStats.damageDealt, 0)
        XCTAssertEqual(player.runStats.killCount, 0)
    }

    // MARK: - Repeated fire/despawn cycles never exceed the pool's capacity

    func test_repeatedFireAndDespawnCycles_neverLeaveMoreBulletsOnLoanThanFired() {
        let world = SKNode()
        let player = Player(body: makeBody(), effectsParent: SKNode(), bulletPoolCapacity: 4)
        let origin = TilePoint(x: 0, y: 0)
        let targetPosition = TilePoint(x: 1, y: 0)

        for _ in 0..<4 {
            let raccoon = RaccoonNode(tier: .base)
            world.addChild(raccoon)

            // Fire with a short deltaTime so the bullet is still in flight
            // (rather than resolving within this same tick), then despawn
            // before it arrives, then advance well past its flight time --
            // exercising the leak-safety path repeatedly against a small,
            // easily-exhausted pool.
            player.update(
                deltaTime: 1.0 / 60.0,
                isMoving: true,
                origin: origin,
                direction: .east,
                raccoons: [TargetSelection.Candidate(raccoon: raccoon, position: targetPosition)]
            )
            raccoon.removeFromParent()
            for _ in 0..<10 {
                player.update(deltaTime: 1.0, isMoving: false, origin: origin, direction: .east, raccoons: [])
            }
        }

        XCTAssertEqual(
            player.bulletPool.activeCount, 0,
            "every fired bullet must have been released once its (despawned) target was discovered gone."
        )
    }
}
