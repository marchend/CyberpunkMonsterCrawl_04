import CoreGraphics
import SpriteKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// CYBERPUN-17-8-t1: `RaccoonNode` composes the atlas-sliced body sprite,
/// `RaccoonAnimationController`, `RaccoonTier`'s elite scale and the shared
/// `ActorShadowNode` into a live SpriteKit node graph.
final class RaccoonNodeTests: XCTestCase {

    // MARK: - Base tier: unscaled, exactly the measured cell size

    func test_baseTier_bodySize_equalsTheMeasuredCellSize() {
        let raccoon = RaccoonNode(tier: .base)
        XCTAssertEqual(raccoon.body.size, RaccoonAnimationController.cellSize)
    }

    // MARK: - Elite tier: 1.6x the base cell size

    func test_eliteTier_bodySize_is1_6xTheBaseCellSize_atWholePointScale() {
        // At deviceScale 1 (the headless-scene fallback) a whole point and a
        // whole device pixel coincide, so this is the clearest statement of
        // "1.6x the base cell size" on its own, before the pixel-snap
        // tolerance the multi-scale test below introduces.
        let raccoon = RaccoonNode(tier: .elite, deviceScale: 1)
        let baseCellSize = RaccoonAnimationController.cellSize

        XCTAssertEqual(raccoon.body.size.width, baseCellSize.width * 1.6, accuracy: 1)
        XCTAssertEqual(raccoon.body.size.height, baseCellSize.height * 1.6, accuracy: 1)
    }

    func test_eliteTier_scaleFactor_is1_6() {
        XCTAssertEqual(RaccoonTier.elite.scale, 1.6, accuracy: 1e-9)
        XCTAssertEqual(RaccoonTier.base.scale, 1.0, accuracy: 1e-9)
    }

    /// AC4: "elites render at 1.6x the base cell size and their nodes still
    /// land on whole device pixels" -- swept across the device scales this
    /// game actually ships at (`@1x`/`@2x`/`@3x`), the same simulated-scale
    /// treatment `PixelCrispnessTests` gives `snappedPosition(for:scale:)`
    /// itself, since `RaccoonNode.scaledSize(forTier:deviceScale:)` is built
    /// directly on top of it.
    func test_eliteTier_bodySize_landsOnWholeDevicePixels_acrossASpreadOfScaleFactors() {
        let baseCellSize = RaccoonAnimationController.cellSize

        for scale: CGFloat in [1, 2, 3] {
            let raccoon = RaccoonNode(tier: .elite, deviceScale: scale)

            assertIsWholeDevicePixel(raccoon.body.size, scale: scale)

            // Still recognizably "1.6x the base cell size" and not some
            // other scale entirely -- within one whole device pixel's worth
            // of the un-snapped 1.6x value, at every simulated scale.
            let tolerance = 1.0 / scale + 1e-6
            XCTAssertEqual(
                raccoon.body.size.width,
                baseCellSize.width * RaccoonTier.elite.scale,
                accuracy: tolerance,
                "scale \(scale): elite body width drifted too far from 1.6x the base cell width."
            )
            XCTAssertEqual(
                raccoon.body.size.height,
                baseCellSize.height * RaccoonTier.elite.scale,
                accuracy: tolerance,
                "scale \(scale): elite body height drifted too far from 1.6x the base cell height."
            )
        }
    }

    func test_baseTier_bodySize_landsOnWholeDevicePixels_acrossASpreadOfScaleFactors() {
        // The base tier's cell size (48x28) is already a whole number, so
        // this must hold trivially at every scale -- pinned directly rather
        // than assumed, so a future change to the base scale factor (away
        // from an exact `1.0`) cannot silently break this invariant.
        for scale: CGFloat in [1, 2, 3] {
            let raccoon = RaccoonNode(tier: .base, deviceScale: scale)
            assertIsWholeDevicePixel(raccoon.body.size, scale: scale)
        }
    }

    // MARK: - isWounded: true iff hp < maxHP

    func test_isWounded_isFalse_whenSpawnedAtFullHP() {
        let raccoon = RaccoonNode(tier: .base)
        XCTAssertEqual(raccoon.hp, raccoon.maxHP)
        XCTAssertFalse(raccoon.isWounded)
    }

    func test_isWounded_isTrue_whenHpIsBelowMaxHP() {
        let raccoon = RaccoonNode(tier: .base, hp: 1)
        XCTAssertTrue(raccoon.isWounded)
    }

    func test_isWounded_isFalse_atExactlyMaxHP_andTrueOneBelowIt() {
        let raccoon = RaccoonNode(tier: .elite)
        XCTAssertFalse(raccoon.isWounded, "At full HP the raccoon must not report wounded.")

        raccoon.hp -= 1
        XCTAssertTrue(raccoon.isWounded, "One HP below max must report wounded.")

        raccoon.hp = raccoon.maxHP
        XCTAssertFalse(raccoon.isWounded, "Restoring to exactly maxHP must clear wounded.")
    }

    func test_isWounded_tracksHp_acrossASpreadOfValues() {
        let raccoon = RaccoonNode(tier: .base)
        for hp in stride(from: raccoon.maxHP, through: 0, by: -1) {
            raccoon.hp = hp
            XCTAssertEqual(raccoon.isWounded, hp < raccoon.maxHP, "hp \(hp) of maxHP \(raccoon.maxHP)")
        }
    }

    // MARK: - maxHP: base * tier's HP multiplier

    func test_maxHP_isBaseMaxHP_scaledByTheTiersMultiplier() {
        let base = RaccoonNode(tier: .base)
        let elite = RaccoonNode(tier: .elite)

        XCTAssertEqual(base.maxHP, Int((CGFloat(RaccoonNode.baseMaxHP) * RaccoonTier.base.maxHPMultiplier).rounded()))
        XCTAssertEqual(elite.maxHP, Int((CGFloat(RaccoonNode.baseMaxHP) * RaccoonTier.elite.maxHPMultiplier).rounded()))
        XCTAssertGreaterThan(elite.maxHP, base.maxHP, "The elite tier must be tougher, per the story.")
    }

    func test_defaultHp_spawnsAtFullMaxHp() {
        let raccoon = RaccoonNode(tier: .elite)
        XCTAssertEqual(raccoon.hp, raccoon.maxHP)
    }

    // MARK: - Node assembly: body + shadow, anchor, pixel crispness

    func test_body_anchorPoint_matchesRaccoonAnimationController() {
        let raccoon = RaccoonNode(tier: .base)
        // `raccoon.body.anchorPoint` round-trips through a live `SKSpriteNode`,
        // which (unlike the pure-Swift `RaccoonAnimationController` constant)
        // SpriteKit is free to store internally at `Float` (32-bit) precision
        // -- so the value read back is not bit-identical to the `Double`
        // literal it was set from. `1e-6` is far larger than that float32
        // truncation at this 0...1 magnitude, yet far smaller than a real
        // anchor mismatch.
        XCTAssertEqual(
            raccoon.body.anchorPoint.x, RaccoonAnimationController.anchorPointNormalized.x, accuracy: 1e-6
        )
        XCTAssertEqual(
            raccoon.body.anchorPoint.y, RaccoonAnimationController.anchorPointNormalized.y, accuracy: 1e-6
        )
    }

    func test_shadow_isADistinctChildNode_zOrderedBeneathTheBody() {
        let raccoon = RaccoonNode(tier: .base)

        XCTAssertTrue(raccoon.children.contains { $0 === raccoon.shadow })
        XCTAssertTrue(raccoon.children.contains { $0 === raccoon.body })
        XCTAssertNotEqual(ObjectIdentifier(raccoon.shadow), ObjectIdentifier(raccoon.body))
        XCTAssertLessThan(raccoon.shadow.zPosition, raccoon.body.zPosition)
    }

    func test_eliteShadow_isWiderThanBaseShadow() {
        let base = RaccoonNode(tier: .base)
        let elite = RaccoonNode(tier: .elite)
        XCTAssertGreaterThan(elite.shadow.width, base.shadow.width)
    }

    func test_body_isPixelCrisp() {
        let raccoon = RaccoonNode(tier: .base)

        XCTAssertEqual(raccoon.body.texture?.filteringMode, .nearest)
        XCTAssertEqual(raccoon.body.texture?.usesMipmaps, false)
        XCTAssertTrue(PixelCrispness.isIntegerScale(raccoon.body.xScale))
        XCTAssertTrue(PixelCrispness.isIntegerScale(raccoon.body.yScale))
    }

    // MARK: - Facing / texture wiring at construction

    func test_init_withNonDefaultFacing_setsBodyTextureAndMirroring() {
        let raccoon = RaccoonNode(tier: .base, facing: .west)
        let mapping = RaccoonAnimationController.rowMapping(for: .west)

        XCTAssertEqual(raccoon.facing, .west)
        XCTAssertTrue(raccoon.body.texture === RaccoonNode.texture(state: .walk, row: mapping.row, column: 0))
        XCTAssertEqual(raccoon.body.xScale, mapping.mirrored ? -1 : 1, accuracy: 1e-9)
    }

    // MARK: - update(deltaTime:) advances the animation and refreshes the body

    func test_update_advancesWalkFrames_atTenFps() {
        let raccoon = RaccoonNode(tier: .base, facing: .east)
        let row = RaccoonAnimationController.rowMapping(for: .east).row

        XCTAssertTrue(raccoon.body.texture === RaccoonNode.texture(state: .walk, row: row, column: 0))

        raccoon.update(deltaTime: 1.0 / RaccoonAnimationController.walkFramesPerSecond)
        XCTAssertTrue(raccoon.body.texture === RaccoonNode.texture(state: .walk, row: row, column: 1))
    }

    func test_playAttack_switchesTheBodyToTheAttackSheet() {
        let raccoon = RaccoonNode(tier: .base, facing: .south)
        let row = RaccoonAnimationController.rowMapping(for: .south).row

        raccoon.playAttack()
        raccoon.update(deltaTime: 0)

        XCTAssertTrue(raccoon.body.texture === RaccoonNode.texture(state: .attack, row: row, column: 0))
    }

    func test_setDirection_thenUpdate_retexturesTheBodyForTheNewFacing() {
        let raccoon = RaccoonNode(tier: .base, facing: .south)

        raccoon.setDirection(.north)
        raccoon.update(deltaTime: 0)

        let mapping = RaccoonAnimationController.rowMapping(for: .north)
        XCTAssertTrue(raccoon.body.texture === RaccoonNode.texture(state: .walk, row: mapping.row, column: 0))
        XCTAssertEqual(raccoon.body.xScale, mapping.mirrored ? -1 : 1, accuracy: 1e-9)
    }

    // MARK: - Depth: DepthBanding's non-player actor offset, rounded tile sampling

    func test_updateDepth_usesDepthBandingsNonPlayerActorOffsetRange() {
        XCTAssertTrue(DepthBanding.nonPlayerActorOffsetRange.contains(RaccoonNode.depthOffset))
        XCTAssertFalse(
            RaccoonNode.depthOffset == DepthBanding.playerActorOffset,
            "A raccoon must never be able to tie with the player's own offset."
        )
    }

    func test_updateDepth_setsZPosition_toDepthBandingsWorldLayerRelativeValue() {
        let raccoon = RaccoonNode(tier: .base)
        let position = TilePoint(x: 5, y: -2)

        raccoon.updateDepth(atTilePosition: position)

        let expectedAbsolute = DepthBanding.actorZPosition(forActorAt: position, offset: RaccoonNode.depthOffset)
        let expectedRelative = DepthModel.worldLayerRelativeZ(forAbsoluteZ: expectedAbsolute)

        // `raccoon.zPosition` round-trips through a live SKNode (Float32
        // storage internally), so this uses the same generous tolerance
        // `PlayerDepthTests.test_playerNode_updateDepth_...` documents for
        // exactly the same reason -- far larger than Float's own truncation
        // at this magnitude, far smaller than a real band/offset mismatch.
        XCTAssertEqual(raccoon.zPosition, expectedRelative, accuracy: 0.01)
    }

    func test_updateDepth_neverReachesThePlayersZPosition_inTheSameBand() {
        let raccoon = RaccoonNode(tier: .base)
        let position = TilePoint(x: 5, y: -2)

        raccoon.updateDepth(atTilePosition: position)

        // `raccoon.zPosition` is `updateDepth`'s *world-layer-relative* value
        // (see `test_updateDepth_setsZPosition_toDepthBandingsWorldLayerRelativeValue`
        // just above), so the player's own absolute zPosition has to be
        // converted through the same `worldLayerRelativeZ` step before the
        // two are comparable -- comparing a relative value against an
        // absolute one is an apples-to-oranges bug, not a real depth-banding
        // violation.
        let playerZAbsolute = DepthBanding.playerZPosition(at: position)
        let playerZRelative = DepthModel.worldLayerRelativeZ(forAbsoluteZ: playerZAbsolute)

        XCTAssertLessThan(raccoon.zPosition, playerZRelative)
    }

    // MARK: - Helpers

    /// Asserts `size`, multiplied by `scale`, lands on a whole number in
    /// both axes -- the same "whole device pixel" check
    /// `PixelCrispnessTests` uses for `snappedPosition(for:scale:)` itself,
    /// restated for a `CGSize`.
    private func assertIsWholeDevicePixel(_ size: CGSize, scale: CGFloat, file: StaticString = #filePath, line: UInt = #line) {
        let scaledWidth = size.width * scale
        let scaledHeight = size.height * scale
        // `size` round-trips through a live `SKSpriteNode`'s Float (32-bit)
        // storage, so a scaled value that is mathematically a whole number
        // (e.g. 230) can read back as 229.99999237060547 -- a float32
        // representation artifact, not a real pixel-alignment bug. At this
        // point-value magnitude (tens to hundreds) float32's own step is
        // already on the order of 1e-5; `1e-3` is comfortably larger than
        // that truncation yet far smaller than any real misalignment.
        XCTAssertEqual(
            scaledWidth, scaledWidth.rounded(), accuracy: 1e-3,
            "width (\(size.width)) is not pixel-aligned at scale \(scale).", file: file, line: line
        )
        XCTAssertEqual(
            scaledHeight, scaledHeight.rounded(), accuracy: 1e-3,
            "height (\(size.height)) is not pixel-aligned at scale \(scale).", file: file, line: line
        )
    }
}
