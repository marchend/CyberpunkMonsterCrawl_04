import CoreGraphics
import SpriteKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-9` PR 2: `WeaponOverlayRenderer` -- the weapon overlay
/// composited on the same 36x40 cell and anchor as the player's body
/// sprite, indexed `weapon[tier][dir]`.
final class WeaponOverlayRendererTests: XCTestCase {

    /// A stand-in body sprite carrying the exact size/anchor the real
    /// `PlayerNode.body` uses, so this file never re-derives (or
    /// hand-picks) the cell geometry the overlay is supposed to match.
    private func makeBody(xScale: CGFloat = 1) -> SKSpriteNode {
        let body = SKSpriteNode(texture: nil, color: .clear, size: PlayerSpriteSheet.cellSize)
        body.anchorPoint = PlayerSpriteSheet.anchorPointNormalized
        body.xScale = xScale
        return body
    }

    // MARK: - Same cell rect/anchor as the body, for every direction and tier

    func test_overlaySizeAndAnchor_matchTheBody_forEveryDirection_andEveryTier() {
        for tier in WeaponTier.allCases {
            for direction in Direction8.allCases {
                let body = makeBody()
                let renderer = WeaponOverlayRenderer(body: body, tier: tier, direction: direction)

                XCTAssertEqual(
                    renderer.overlay.size, body.size,
                    "\(tier)/\(direction): overlay size must equal the body's cell size."
                )
                XCTAssertEqual(
                    renderer.overlay.anchorPoint, body.anchorPoint,
                    "\(tier)/\(direction): overlay anchor must equal the body's anchor."
                )
                XCTAssertTrue(
                    renderer.overlay.parent === body,
                    "\(tier)/\(direction): overlay must be parented directly under the body node."
                )
            }
        }
    }

    // MARK: - Texture indexes [tier][direction] correctly

    func test_initialTexture_isTheTierAndDirectionsCell() {
        for tier in WeaponTier.allCases {
            for direction in Direction8.allCases {
                let body = makeBody()
                let renderer = WeaponOverlayRenderer(body: body, tier: tier, direction: direction)
                let expected = WeaponOverlayRenderer.texture(tier: tier, direction: direction)

                XCTAssertTrue(
                    renderer.overlay.texture === expected,
                    "\(tier)/\(direction): overlay texture did not match the expected [tier][dir] cell."
                )
            }
        }
    }

    func test_update_swapsTextureToTheNewTiersRow_sameDirection() {
        let body = makeBody()
        let renderer = WeaponOverlayRenderer(body: body, tier: .handgun, direction: .east)

        renderer.update(tier: .assaultRifle, direction: .east)

        let expected = WeaponOverlayRenderer.texture(tier: .assaultRifle, direction: .east)
        XCTAssertTrue(renderer.overlay.texture === expected)
        XCTAssertEqual(renderer.tier, .assaultRifle)
        XCTAssertEqual(renderer.direction, .east)
    }

    func test_update_swapsTextureToTheNewDirectionsColumn_sameTier() {
        let body = makeBody()
        let renderer = WeaponOverlayRenderer(body: body, tier: .smg, direction: .south)

        renderer.update(tier: .smg, direction: .northwest)

        let expected = WeaponOverlayRenderer.texture(tier: .smg, direction: .northwest)
        XCTAssertTrue(renderer.overlay.texture === expected)
    }

    /// Distinct tiers/directions must never collide on the same cached
    /// texture -- otherwise two genuinely different cells would render
    /// identically.
    func test_everyTierDirectionPair_resolvesADistinctTexture() {
        var seen: [ObjectIdentifier: (WeaponTier, Direction8)] = [:]
        for tier in WeaponTier.allCases {
            for direction in Direction8.allCases {
                let texture = WeaponOverlayRenderer.texture(tier: tier, direction: direction)
                let id = ObjectIdentifier(texture)
                if let existing = seen[id] {
                    XCTFail("\(tier)/\(direction) shares a texture with \(existing.0)/\(existing.1).")
                }
                seen[id] = (tier, direction)
            }
        }
        XCTAssertEqual(seen.count, WeaponTier.allCases.count * Direction8.allCases.count)
    }

    // MARK: - Column ordering is a bijection over Direction8.allCases

    func test_column_isABijection_overAllEightDirections() {
        let columns = Direction8.allCases.map { WeaponOverlayRenderer.column(for: $0) }
        XCTAssertEqual(Set(columns).count, 8, "every direction must map to a distinct column 0..<8")
        XCTAssertEqual(Set(columns), Set(0..<8))
    }

    // MARK: - Mirrored body facings never leave the overlay art backwards

    func test_construction_withAMirroredBody_cancelsTheInheritedFlip() {
        let mirroredBody = makeBody(xScale: -1)
        let renderer = WeaponOverlayRenderer(body: mirroredBody, tier: .handgun, direction: .west)

        XCTAssertEqual(
            renderer.overlay.xScale, -1,
            "overlay xScale must cancel the parent's -1 flip so the unmirrored weapon art renders true."
        )
    }

    func test_update_reReadsTheBodysCurrentMirrorState() {
        let body = makeBody(xScale: 1)
        let renderer = WeaponOverlayRenderer(body: body, tier: .handgun, direction: .east)
        XCTAssertEqual(renderer.overlay.xScale, 1)

        body.xScale = -1
        renderer.update(tier: .handgun, direction: .west)

        XCTAssertEqual(renderer.overlay.xScale, -1)
    }
}
