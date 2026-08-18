import CoreGraphics
import SpriteKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-9` PR 2: `BulletPool`'s fixed-capacity acquire/release
/// lifecycle, and `BulletNode`'s tier-indexed texture + shot-vector
/// rotation.
final class BulletPoolTests: XCTestCase {

    // MARK: - Capacity is a hard ceiling

    func test_pool_neverExceedsCapacity_acrossRepeatedAcquireReleaseCycles() {
        let parent = SKNode()
        let pool = BulletPool(capacity: 3, parent: parent)

        let first = pool.acquire(origin: .zero, direction: CGVector(dx: 1, dy: 0), tier: .handgun)
        let second = pool.acquire(origin: .zero, direction: CGVector(dx: 1, dy: 0), tier: .handgun)
        let third = pool.acquire(origin: .zero, direction: CGVector(dx: 1, dy: 0), tier: .handgun)

        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertNotNil(third)
        XCTAssertEqual(pool.activeCount, 3)

        // The pool is exhausted: a fourth acquire must not exceed capacity.
        let fourth = pool.acquire(origin: .zero, direction: CGVector(dx: 1, dy: 0), tier: .handgun)
        XCTAssertNil(fourth, "acquiring beyond capacity must fail rather than grow the pool.")
        XCTAssertEqual(pool.activeCount, 3, "activeCount must never exceed capacity.")

        // Repeated cycles: release-then-acquire must never push activeCount
        // past capacity either.
        for _ in 0..<10 {
            pool.release(first!)
            let reacquired = pool.acquire(origin: .zero, direction: CGVector(dx: 1, dy: 0), tier: .handgun)
            XCTAssertNotNil(reacquired)
            XCTAssertLessThanOrEqual(pool.activeCount, 3)
        }
    }

    // MARK: - Released bullets are reusable

    func test_releasedBullet_isReusable() {
        let parent = SKNode()
        let pool = BulletPool(capacity: 1, parent: parent)

        let bullet = pool.acquire(origin: .zero, direction: CGVector(dx: 1, dy: 0), tier: .handgun)
        XCTAssertNotNil(bullet)
        XCTAssertEqual(pool.activeCount, 1)

        // Capacity 1, already on loan: nothing free to give.
        XCTAssertNil(pool.acquire(origin: .zero, direction: CGVector(dx: 1, dy: 0), tier: .handgun))

        pool.release(bullet!)
        XCTAssertEqual(pool.activeCount, 0)
        XCTAssertTrue(bullet!.isHidden, "a released bullet must be hidden again.")

        let reacquired = pool.acquire(origin: CGPoint(x: 5, y: 5), direction: CGVector(dx: 0, dy: 1), tier: .smg)
        XCTAssertNotNil(reacquired, "a released node must be available for a fresh acquire.")
        XCTAssertEqual(pool.activeCount, 1)
        XCTAssertFalse(reacquired!.isHidden)
    }

    // MARK: - Double-release and foreign-node release are safe no-ops

    func test_doubleRelease_isASafeNoOp() {
        let parent = SKNode()
        let pool = BulletPool(capacity: 2, parent: parent)
        let bullet = pool.acquire(origin: .zero, direction: CGVector(dx: 1, dy: 0), tier: .handgun)!

        pool.release(bullet)
        XCTAssertEqual(pool.activeCount, 0)

        // Releasing again must not go negative or crash.
        pool.release(bullet)
        XCTAssertEqual(pool.activeCount, 0)

        // The freed slot must still be acquirable exactly once (capacity 2,
        // one still free from construction).
        XCTAssertNotNil(pool.acquire(origin: .zero, direction: CGVector(dx: 1, dy: 0), tier: .handgun))
        XCTAssertNotNil(pool.acquire(origin: .zero, direction: CGVector(dx: 1, dy: 0), tier: .handgun))
        XCTAssertEqual(pool.activeCount, 2)
    }

    func test_releasingAForeignNode_isASafeNoOp() {
        let parent = SKNode()
        let pool = BulletPool(capacity: 1, parent: parent)
        let foreignNode = BulletNode(tier: .handgun)

        // Must not crash, must not affect the pool's own bookkeeping.
        pool.release(foreignNode)
        XCTAssertEqual(pool.activeCount, 0)

        XCTAssertNotNil(pool.acquire(origin: .zero, direction: CGVector(dx: 1, dy: 0), tier: .handgun))
        XCTAssertEqual(pool.activeCount, 1)
    }

    // MARK: - Bullet texture index matches tier

    func test_acquiredBullet_texturesMatchTheRequestedTier() {
        let parent = SKNode()
        let pool = BulletPool(capacity: 3, parent: parent)

        for tier in WeaponTier.allCases {
            let bullet = pool.acquire(origin: .zero, direction: CGVector(dx: 1, dy: 0), tier: tier)
            XCTAssertNotNil(bullet)
            XCTAssertTrue(
                bullet!.texture === BulletNode.texture(forTier: tier),
                "\(tier): acquired bullet's texture did not match the tier's bullet variant."
            )
            pool.release(bullet!)
        }
    }

    func test_bulletTexture_isDistinctPerTier() {
        var seen = Set<ObjectIdentifier>()
        for tier in WeaponTier.allCases {
            let id = ObjectIdentifier(BulletNode.texture(forTier: tier))
            XCTAssertFalse(seen.contains(id), "\(tier) shares a texture with another tier.")
            seen.insert(id)
        }
        XCTAssertEqual(seen.count, WeaponTier.allCases.count)
    }

    // MARK: - Rotation: screen-left is 180 degrees from the authored screen-right art

    func test_shotToScreenLeft_rotates180Degrees_fromTheAuthoredScreenRightArt() {
        let parent = SKNode()
        let pool = BulletPool(capacity: 1, parent: parent)

        let rightwardBullet = pool.acquire(origin: .zero, direction: CGVector(dx: 1, dy: 0), tier: .handgun)!
        XCTAssertEqual(rightwardBullet.zRotation, 0, accuracy: 1e-6, "screen-right must match the authored, unrotated pose.")
        pool.release(rightwardBullet)

        // `zRotation` is a `CGFloat` backed by SpriteKit's float32 storage, so
        // `.pi` (a `Double` literal) never reads back bit-identical - it comes
        // back as the nearest float32, `3.1415927410125732`, roughly 8.7e-8
        // away from the `Double` value of `.pi`. That is a representation
        // artifact, not a rotation error, so the accuracy is sized to
        // float32's own precision at this magnitude (~1e-6) rather than 1e-9.
        let leftwardBullet = pool.acquire(origin: .zero, direction: CGVector(dx: -1, dy: 0), tier: .handgun)!
        XCTAssertEqual(
            abs(leftwardBullet.zRotation), .pi, accuracy: 1e-6,
            "a shot to screen-left must be rotated exactly 180 degrees from the authored screen-right art."
        )
    }

    func test_angleForShotVector_matchesSpriteKitsOwnRotationConvention() {
        // SpriteKit: zero at east, counter-clockwise positive, y-up.
        XCTAssertEqual(BulletNode.angle(forShotVector: CGVector(dx: 1, dy: 0)), 0, accuracy: 1e-9)
        XCTAssertEqual(BulletNode.angle(forShotVector: CGVector(dx: 0, dy: 1)), .pi / 2, accuracy: 1e-9)
        XCTAssertEqual(abs(BulletNode.angle(forShotVector: CGVector(dx: -1, dy: 0))), .pi, accuracy: 1e-9)
        XCTAssertEqual(BulletNode.angle(forShotVector: CGVector(dx: 0, dy: -1)), -.pi / 2, accuracy: 1e-9)
        XCTAssertEqual(BulletNode.angle(forShotVector: .zero), 0, accuracy: 1e-9)
    }

    // MARK: - configure never changes the measured 16x16 cell size

    func test_configure_neverChangesTheBulletsMeasuredCellSize() {
        let bullet = BulletNode(tier: .handgun)
        let originalSize = bullet.size

        bullet.configure(tier: .assaultRifle, position: CGPoint(x: 10, y: 10), shotVector: CGVector(dx: 0, dy: 1))

        XCTAssertEqual(bullet.size, originalSize)
    }
}
