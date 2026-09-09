import CoreGraphics
import SpriteKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-14-t3` (PR 3): the runtime pixel-crispness sweep gate 9
/// calls for -- a pass over **constructed, production-shaped** scene nodes
/// from every sprite consumer in the repo, asserting `PixelCrispness`'s own
/// three invariants (nearest filtering, no mipmaps, whole-integer scale)
/// plus whole-point placement, in one consolidated file a reviewer can read
/// end to end instead of trusting each consumer's own doc comment. This
/// mirrors `AtlasSlicingTests`' role for atlas indices (`CYBERPUN-17-14-t2`):
/// that file is the single place every family's row/column table is
/// exercised at once; this one is the single place every family's *pixel
/// finish* is.
///
/// **What the sweep found (the one real offender).** Every sprite consumer
/// but one already stamped `.nearest`/no-mipmaps directly onto a texture the
/// moment it sliced one out of its sheet (`PlayerNode.texture(row:column:)`,
/// `RaccoonNode.texture(state:row:column:)`, `BulletNode.texture(forTier:)`,
/// `HitEffects.texture(forColumn:)`, `WeaponOverlayRenderer.texture(tier:
/// direction:)`, `PulseRingNode.texture(forColumn:)`) -- because
/// `SpriteSheet.texture(col:row:)`/`texture(forPixelRect:)` crop a *new*
/// `SKTexture` via `SKTexture(rect:in:)`, which does not inherit the parent
/// sheet texture's own filtering/mipmap settings. `PickupNode.texture(
/// forColumn:)` was the one cache-population site that skipped that stamp,
/// relying instead on `PickupNode.init`'s own `PixelCrispness.apply(to:
/// icon)` call to fix the *same* texture object up as a side effect
/// (`SKTexture` is a class, so mutating `node.texture` after assignment
/// mutates the exact instance the cache also holds) -- functionally
/// harmless as long as every consumer keeps calling `apply(to:)`
/// immediately after assigning a fresh texture, but not a guarantee the
/// factory itself provided the way every sibling factory does. Fixed at the
/// cache-population site to match the established pattern (see that file's
/// own comment); this suite is what proves the fix (and would have caught
/// the gap beforehand, since it constructs nodes the same way production
/// does rather than re-deriving the expectation from the code under test).
///
/// `GroundTileRenderer.configure`/`TileFieldRenderer.configure`/
/// `RooftopSignRenderer.makeSignNode` do not cache their sliced textures at
/// all (a fresh crop every call) and instead call `PixelCrispness.apply(to:
/// node)` immediately after assigning it, which is an equally sound pattern
/// -- the sweep below still exercises them directly so a future change
/// cannot silently drop that immediate `apply(to:)` call without a red test.
///
/// **Tolerances, per the project's float32-read-back rule.** Every scale/
/// position value below is read back off a live `SKSpriteNode`, which
/// SpriteKit stores as 32-bit floats internally regardless of the public
/// `CGFloat` type -- so every comparison uses `accuracy:`, sized to the
/// magnitude of the value being compared (a near-1 scale factor gets a tight
/// tolerance; a many-hundred-point world position gets a slightly looser
/// one), never bare `XCTAssertEqual` on a value that came out of a node.
final class PixelCrispnessSweepTests: XCTestCase {

    // MARK: - Shared assertion

    /// Asserts `node` satisfies every `PixelCrispness.apply(to:)` invariant:
    /// `.nearest` filtering + no mipmaps (only if textured -- an untextured
    /// color-fill node, like `PickupNode.pad`, has nothing to check there),
    /// whole-integer `xScale`/`yScale`, and whole-point `position`.
    private func assertPixelCrisp(
        _ node: SKSpriteNode,
        _ label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if let texture = node.texture {
            XCTAssertEqual(
                texture.filteringMode, .nearest,
                "\(label): texture must be nearest-filtered.", file: file, line: line
            )
            XCTAssertFalse(
                texture.usesMipmaps,
                "\(label): texture must not use mipmaps.", file: file, line: line
            )
        }
        XCTAssertTrue(
            PixelCrispness.isIntegerScale(node.xScale),
            "\(label): xScale \(node.xScale) is not a whole integer.", file: file, line: line
        )
        XCTAssertTrue(
            PixelCrispness.isIntegerScale(node.yScale),
            "\(label): yScale \(node.yScale) is not a whole integer.", file: file, line: line
        )
        XCTAssertEqual(
            node.position.x, node.position.x.rounded(), accuracy: 1e-3,
            "\(label): position.x (\(node.position.x)) must land on a whole point.", file: file, line: line
        )
        XCTAssertEqual(
            node.position.y, node.position.y.rounded(), accuracy: 1e-3,
            "\(label): position.y (\(node.position.y)) must land on a whole point.", file: file, line: line
        )
    }

    /// SpriteKit-space (y-up) vectors for every `Direction8` case -- the
    /// same table `PlayerNodeTests`/`RaccoonNodeTests` use, restated here so
    /// this file drives real facing changes without depending on another
    /// test file's private helper.
    private static let spriteKitVectors: [(Direction8, CGVector)] = [
        (.south, CGVector(dx: 0, dy: -1)),
        (.southeast, CGVector(dx: 1, dy: -1)),
        (.east, CGVector(dx: 1, dy: 0)),
        (.northeast, CGVector(dx: 1, dy: 1)),
        (.north, CGVector(dx: 0, dy: 1)),
        (.northwest, CGVector(dx: -1, dy: 1)),
        (.west, CGVector(dx: -1, dy: 0)),
        (.southwest, CGVector(dx: -1, dy: -1)),
    ]

    // MARK: - Actors

    func test_playerNode_body_isPixelCrisp_atConstruction_andForEveryFacing() {
        let fresh = PlayerNode()
        assertPixelCrisp(fresh.body, "PlayerNode.body (fresh)")

        for (direction, vector) in Self.spriteKitVectors {
            let player = PlayerNode()
            player.update(deltaTime: 0, movementVector: vector)
            assertPixelCrisp(player.body, "PlayerNode.body (\(direction))")
        }
    }

    func test_raccoonNode_body_isPixelCrisp_forBothTiers_andEveryFacing_andEveryDeviceScale() {
        for tier in RaccoonTier.allCases {
            for scale: CGFloat in [1, 2, 3] {
                let raccoon = RaccoonNode(tier: tier, deviceScale: scale)
                assertPixelCrisp(raccoon.body, "RaccoonNode.body (\(tier), @\(scale)x, fresh)")

                for (direction, _) in Self.spriteKitVectors {
                    raccoon.setDirection(direction)
                    raccoon.update(deltaTime: 0)
                    assertPixelCrisp(raccoon.body, "RaccoonNode.body (\(tier), @\(scale)x, \(direction))")
                }
            }
        }
    }

    func test_raccoonNode_attackAnimation_stayPixelCrisp() {
        let raccoon = RaccoonNode(tier: .elite)
        raccoon.playAttack()
        raccoon.update(deltaTime: 0)
        assertPixelCrisp(raccoon.body, "RaccoonNode.body (attack, frame 0)")

        raccoon.update(deltaTime: 1.0 / RaccoonAnimationController.attackFramesPerSecond)
        assertPixelCrisp(raccoon.body, "RaccoonNode.body (attack, frame 1)")
    }

    // MARK: - Ground plane

    func test_groundTileRenderer_node_isPixelCrisp_forEveryTileKind() {
        let coordinate = TileCoordinate(tileX: 4, tileY: -3)
        for kind in TileKind.allCases {
            let node = GroundTileRenderer.node(for: kind, at: coordinate)
            assertPixelCrisp(node, "GroundTileRenderer.node(\(kind))")
        }
    }

    // MARK: - Buildings + rooftop signs

    func test_tileFieldRenderer_buildingNode_isPixelCrisp_forEveryCatalogEntry() {
        for index in 0..<12 {
            let tile = TileCoordinate(tileX: 2, tileY: 1)
            let record = BuildingPlacementRecord(
                lotTile: tile,
                building: BuildingCatalog.entry(atIndex: index),
                footprintTiles: [tile],
                farCornerTile: tile
            )
            let node = TileFieldRenderer.makeBuildingNode(for: record)
            assertPixelCrisp(node, "TileFieldRenderer.makeBuildingNode(index \(index))")
        }
    }

    func test_rooftopSignRenderer_signNode_isPixelCrisp_forEveryCell() {
        let tile = TileCoordinate(tileX: 6, tileY: 6)
        let buildingRecord = BuildingPlacementRecord(
            lotTile: tile,
            building: BuildingCatalog.entry(atIndex: 2),
            footprintTiles: [tile],
            farCornerTile: tile
        )
        let buildingNode = TileFieldRenderer.makeBuildingNode(for: buildingRecord)

        for cellIndex in 0..<AtlasCellIndex.signs.count {
            let record = RooftopSignRecord(
                block: BlockCoordinate(x: 0, y: 0), carrierLotTile: tile, signCellIndex: cellIndex
            )
            let signNode = RooftopSignRenderer.makeSignNode(for: record, parent: buildingNode)
            assertPixelCrisp(signNode, "RooftopSignRenderer.makeSignNode(cell \(cellIndex))")
            signNode.removeFromParent()
        }
    }

    // MARK: - Pickups

    func test_pickupNode_icon_isPixelCrisp_forEveryKind() {
        for kind in PickupKind.allCases {
            let node = PickupNode(kind: kind)
            assertPixelCrisp(node.icon, "PickupNode.icon(\(kind))")
            // `pad` is an untextured color fill -- `assertPixelCrisp` skips
            // the (vacuous) filtering checks for it, but scale/position
            // still apply since `PixelCrispness.apply(to:)` is called on it
            // too.
            assertPixelCrisp(node.pad, "PickupNode.pad(\(kind))")
        }
    }

    /// The one real offender this sweep exists to catch (see the type doc
    /// comment): before the fix, `PickupNode.texture(forColumn:)` cached a
    /// texture that had never itself been stamped `.nearest`/no-mipmap --
    /// it only read back correctly because `PickupNode.init` mutated the
    /// very same cached instance as a side effect. This asserts the
    /// *factory* now provides the guarantee directly, independent of any
    /// particular caller's follow-up `apply(to:)` call.
    func test_pickupNode_textureForColumn_isNearestFilteredAndMipmapFree_directlyFromTheFactory() {
        for kind in PickupKind.allCases {
            let texture = PickupNode.texture(forColumn: kind.atlasColumn)
            XCTAssertEqual(texture.filteringMode, .nearest, "\(kind): factory-cached texture must be nearest-filtered.")
            XCTAssertFalse(texture.usesMipmaps, "\(kind): factory-cached texture must not use mipmaps.")
        }
    }

    // MARK: - Combat effects

    func test_bulletNode_isPixelCrisp_forEveryTier_freshAndAfterConfigure() {
        for tier in WeaponTier.allCases {
            let bullet = BulletNode(tier: tier)
            assertPixelCrisp(bullet, "BulletNode(\(tier), fresh)")

            // A whole-integer origin -- the shape every production caller
            // hands `configure(...)`, since a shot always originates from
            // an actor position already resolved through
            // `IsometricProjection`/`PixelCrispness`'s own whole-point
            // contract. `configure` itself does not re-round `position`
            // (that responsibility belongs to the caller, per its own doc
            // comment), so this sweep exercises the caller's contract
            // rather than a guarantee `BulletNode` makes on its own.
            bullet.configure(tier: tier, position: CGPoint(x: 10, y: -20), spriteKitShotVector: CGVector(dx: 1, dy: 0))
            assertPixelCrisp(bullet, "BulletNode(\(tier), configured)")
        }
    }

    func test_hitEffects_muzzleFlashAndHitPuff_arePixelCrisp() {
        let muzzle = HitEffects.spawnMuzzleFlash(at: CGPoint(x: 3, y: -4))
        assertPixelCrisp(muzzle, "HitEffects.spawnMuzzleFlash")

        let puff = HitEffects.spawnHitPuff(at: CGPoint(x: -7, y: 8))
        assertPixelCrisp(puff, "HitEffects.spawnHitPuff")
    }

    func test_pulseRingNode_isPixelCrisp_atConstruction_andAfterPlay() {
        let ring = PulseRingNode()
        assertPixelCrisp(ring, "PulseRingNode(fresh)")

        ring.play(radiusTiles: 3, at: CGPoint(x: 12, y: -6))
        assertPixelCrisp(ring, "PulseRingNode(after play)")
    }

    func test_weaponOverlayRenderer_overlay_isPixelCrisp_forEveryTierAndDirection() {
        let body = SKSpriteNode(texture: nil, color: .clear, size: PlayerSpriteSheet.cellSize)
        body.anchorPoint = PlayerSpriteSheet.anchorPointNormalized

        for tier in WeaponTier.allCases {
            for direction in Direction8.allCases {
                let renderer = WeaponOverlayRenderer(body: body, tier: tier, direction: direction)
                assertPixelCrisp(renderer.overlay, "WeaponOverlayRenderer.overlay(\(tier), \(direction))")
                renderer.overlay.removeFromParent()
            }
        }
    }
}
