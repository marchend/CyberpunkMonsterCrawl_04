import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-9` PR 1: `WeaponFiringController`'s decision layer \u2014
/// movement-gated auto-fire, the fire-rate cooldown, and `setTier(_:)`'s
/// in-place tier swap.
final class WeaponFiringControllerTests: XCTestCase {

    private func candidate(atTileX tileX: Double, tileY: Double = 0) -> TargetSelection.Candidate {
        TargetSelection.Candidate(raccoon: RaccoonNode(tier: .base), position: TilePoint(x: tileX, y: tileY))
    }

    // MARK: - Firing only while moving, with a target in range

    func test_firesOnlyWhileMoving_withATargetInRange() {
        let controller = WeaponFiringController(tier: .handgun)
        var fireCount = 0
        controller.onFire = { _, _, _ in fireCount += 1 }
        let origin = TilePoint(x: 0, y: 0)
        let raccoons = [candidate(atTileX: 1)]

        // Ready immediately (cooldown starts at 0): moving, with a target
        // in range, must fire on the very first qualifying frame.
        controller.update(deltaTime: 1.0 / 60.0, isMoving: true, origin: origin, raccoons: raccoons)

        XCTAssertEqual(fireCount, 1)
    }

    func test_standingStill_suppressesFire_evenWithATargetInRange_howeverLongTheCooldownHasHadToElapse() {
        let controller = WeaponFiringController(tier: .handgun)
        var fireCount = 0
        controller.onFire = { _, _, _ in fireCount += 1 }
        let origin = TilePoint(x: 0, y: 0)
        let raccoons = [candidate(atTileX: 1)]

        // 10 seconds at 60fps -- far past the handgun's own cooldown
        // (0.6s), but never moving.
        for _ in 0..<600 {
            controller.update(deltaTime: 1.0 / 60.0, isMoving: false, origin: origin, raccoons: raccoons)
        }

        XCTAssertEqual(fireCount, 0, "a stationary controller must never fire")
    }

    func test_movingWithNoTargetInRange_doesNotFire() {
        let controller = WeaponFiringController(tier: .handgun)
        var fireCount = 0
        controller.onFire = { _, _, _ in fireCount += 1 }

        controller.update(deltaTime: 1.0, isMoving: true, origin: TilePoint(x: 0, y: 0), raccoons: [])

        XCTAssertEqual(fireCount, 0)
    }

    // MARK: - Fires exactly on cooldown expiry, then withholds until it elapses again

    func test_fires_onlyAtOrAfterCooldownExpiry_thenWithholdsUntilItElapsesAgain() {
        let controller = WeaponFiringController(tier: .handgun)
        var fireEvents: [(target: RaccoonNode, targetPosition: TilePoint, origin: TilePoint, tier: WeaponTier)] = []
        controller.onFire = { target, origin, tier in
            fireEvents.append((target.raccoon, target.position, origin, tier))
        }
        let origin = TilePoint(x: 0, y: 0)
        let raccoon = RaccoonNode(tier: .base)
        let raccoons = [TargetSelection.Candidate(raccoon: raccoon, position: TilePoint(x: 2, y: 0))]

        // Ready immediately: fires on the very first qualifying frame.
        controller.update(deltaTime: 1.0 / 60.0, isMoving: true, origin: origin, raccoons: raccoons)
        XCTAssertEqual(fireEvents.count, 1)
        XCTAssertTrue(fireEvents[0].target === raccoon)
        XCTAssertEqual(fireEvents[0].tier, .handgun)

        // Both ends of the shot must reach the consumer: a bullet/muzzle
        // spawn needs the target's tile position, not just its identity.
        XCTAssertEqual(fireEvents[0].targetPosition.x, 2)
        XCTAssertEqual(fireEvents[0].targetPosition.y, 0)
        XCTAssertEqual(fireEvents[0].origin.x, origin.x)
        XCTAssertEqual(fireEvents[0].origin.y, origin.y)

        // Well inside the newly-armed cooldown (0.6s): no second shot.
        controller.update(
            deltaTime: WeaponTier.handgun.fireIntervalSeconds - 0.05,
            isMoving: true,
            origin: origin,
            raccoons: raccoons
        )
        XCTAssertEqual(fireEvents.count, 1, "must not fire again before the cooldown elapses")

        // The remaining sliver of the cooldown now elapses: fires again.
        controller.update(deltaTime: 0.06, isMoving: true, origin: origin, raccoons: raccoons)
        XCTAssertEqual(fireEvents.count, 2, "must fire exactly once the cooldown has fully elapsed")
    }

    // MARK: - setTier mid-cooldown preserves the remaining cooldown time

    func test_setTier_midCooldown_preservesTheRemainingCooldownTime_ratherThanResettingToTheNewTiersInterval() {
        let controller = WeaponFiringController(tier: .handgun)
        var fireCount = 0
        controller.onFire = { _, _, _ in fireCount += 1 }
        let origin = TilePoint(x: 0, y: 0)
        let raccoons = [candidate(atTileX: 1)]

        // Fires immediately (cooldown starts at 0) and arms the cooldown
        // at .handgun's own interval, 0.6s.
        controller.update(deltaTime: 0.0001, isMoving: true, origin: origin, raccoons: raccoons)
        XCTAssertEqual(fireCount, 1)

        // Burn most of the handgun cooldown, leaving ~0.2s remaining.
        controller.update(deltaTime: 0.3999, isMoving: true, origin: origin, raccoons: raccoons)
        XCTAssertEqual(fireCount, 1)

        // Swap to a much faster tier (0.15s interval) mid-cooldown.
        controller.setTier(.assaultRifle)
        XCTAssertEqual(controller.tier, .assaultRifle)

        // 0.16s is *more* than the new tier's own 0.15s interval but
        // *less* than the ~0.2s actually remaining on the in-flight
        // cooldown. If `setTier` had reset the cooldown to the new
        // tier's interval, this tick would already fire; it must not.
        controller.update(deltaTime: 0.16, isMoving: true, origin: origin, raccoons: raccoons)
        XCTAssertEqual(
            fireCount, 1,
            "setTier must not reset the in-flight cooldown to the new tier's shorter interval"
        )

        // The preserved remainder of the *original* cooldown now elapses.
        controller.update(deltaTime: 0.05, isMoving: true, origin: origin, raccoons: raccoons)
        XCTAssertEqual(fireCount, 2, "the preserved cooldown must still expire and permit the next shot")
    }

    func test_setTier_changesTheTierUsedByTheNextShot() {
        let controller = WeaponFiringController(tier: .handgun)
        var lastTier: WeaponTier?
        controller.onFire = { _, _, tier in lastTier = tier }
        let origin = TilePoint(x: 0, y: 0)
        let raccoons = [candidate(atTileX: 1)]

        controller.setTier(.smg)
        controller.update(deltaTime: 1.0 / 60.0, isMoving: true, origin: origin, raccoons: raccoons)

        XCTAssertEqual(lastTier, .smg)
    }

    // MARK: - deltaTime <= 0 is a no-op

    func test_zeroOrNegativeDeltaTime_isANoOp() {
        let controller = WeaponFiringController(tier: .handgun)
        var fireCount = 0
        controller.onFire = { _, _, _ in fireCount += 1 }
        let origin = TilePoint(x: 0, y: 0)
        let raccoons = [candidate(atTileX: 1)]

        controller.update(deltaTime: 0, isMoving: true, origin: origin, raccoons: raccoons)
        controller.update(deltaTime: -1, isMoving: true, origin: origin, raccoons: raccoons)

        XCTAssertEqual(fireCount, 0)
    }
}
