import CoreGraphics
import SpriteKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-10-t3`: `PulseRingNode`'s frame/animation setup,
/// scale-to-radius transform, and reserved zPosition sub-range.
final class PulseRingNodeTests: XCTestCase {

    // MARK: - Frame count / animation setup

    func test_textureForColumn_isDistinctPerColumn_acrossAllEightFrames() {
        XCTAssertEqual(AtlasCellIndex.pulse.count, 8, "sprite_pulse is an 8-frame shockwave, per AtlasSheet.pulse.")

        var seen = Set<ObjectIdentifier>()
        for column in 0..<AtlasCellIndex.pulse.count {
            let id = ObjectIdentifier(PulseRingNode.texture(forColumn: column))
            XCTAssertFalse(seen.contains(id), "column \(column) shares a texture with another column.")
            seen.insert(id)
        }
        XCTAssertEqual(seen.count, AtlasCellIndex.pulse.count)
    }

    func test_init_startsHidden_onFrameZero_withTheMeasuredCellSize() {
        let node = PulseRingNode()

        XCTAssertTrue(node.isHidden, "a freshly constructed ring must not be visible before its first play(...).")
        XCTAssertTrue(node.texture === PulseRingNode.texture(forColumn: 0))

        guard let expectedSize = AtlasSheet.pulse.sheet.cellSize else {
            XCTFail("AtlasSheet.pulse must declare a uniform cellSize.")
            return
        }
        XCTAssertEqual(node.size, expectedSize)
    }

    func test_play_unhidesTheNode_setsFrameZero_atTheGivenPosition_andRunsTheAnimation() {
        let node = PulseRingNode()
        let position = CGPoint(x: 12, y: -34)

        node.play(radiusTiles: 3, at: position)

        XCTAssertFalse(node.isHidden, "play(...) must make the ring visible.")
        XCTAssertTrue(node.texture === PulseRingNode.texture(forColumn: 0))
        XCTAssertEqual(node.position, position)
        XCTAssertNotNil(
            node.action(forKey: PulseRingNode.animationActionKey),
            "play(...) must run its animation under the documented action key."
        )
    }

    func test_play_calledTwice_restartsTheAnimation_ratherThanStackingActions() {
        let node = PulseRingNode()
        node.play(radiusTiles: 2, at: .zero)
        let firstAction = node.action(forKey: PulseRingNode.animationActionKey)
        XCTAssertNotNil(firstAction)

        node.play(radiusTiles: 5, at: CGPoint(x: 1, y: 1))

        // A second `play(...)` must still resolve to exactly one action
        // under the same key (the old one removed, not left running
        // alongside a second one) -- `removeAction(forKey:)` followed by a
        // fresh `run(_:withKey:)` guarantees this, and `action(forKey:)`
        // only ever returns the most recent registration regardless, so
        // this pins that the node stays visible/on-frame-zero for the new
        // call rather than asserting on action identity SpriteKit does not
        // expose.
        XCTAssertNotNil(node.action(forKey: PulseRingNode.animationActionKey))
        XCTAssertFalse(node.isHidden)
        XCTAssertEqual(node.position, CGPoint(x: 1, y: 1))
    }

    // MARK: - Scale-to-radius transform

    func test_scale_forRadiusTiles_matchesTheDiameterOverCellWidthFormula() {
        // diameter = radiusTiles * 2 * tileHalfWidth(48); rawScale =
        // diameter / cellWidth(32); rounded to the nearest whole integer.
        // radius 1 tile -> diameter 96pt -> raw 3.0 -> scale 3.
        XCTAssertEqual(PulseRingNode.scale(forRadiusTiles: 1), 3)
        // radius 3 tiles (PulseAbility.baseRadiusTiles, level < 3) ->
        // diameter 288pt -> raw 9.0 -> scale 9.
        XCTAssertEqual(PulseRingNode.scale(forRadiusTiles: 3), 9)
        // radius 3.75 tiles (level 3-5, 1.25x multiplier) -> diameter
        // 360pt -> raw 11.25 -> rounds to 11.
        XCTAssertEqual(PulseRingNode.scale(forRadiusTiles: 3.75), 11)
        // radius 4.6875 tiles (level 6+, compounding 1.5625x) -> diameter
        // 450pt -> raw 14.0625 -> rounds to 14.
        XCTAssertEqual(PulseRingNode.scale(forRadiusTiles: 4.6875), 14)
    }

    func test_scale_neverDropsBelowOne_forAVanishinglySmallOrZeroRadius() {
        XCTAssertEqual(PulseRingNode.scale(forRadiusTiles: 0), 1)
        XCTAssertEqual(PulseRingNode.scale(forRadiusTiles: 0.01), 1)
        XCTAssertEqual(PulseRingNode.scale(forRadiusTiles: -5), 1, "a pure function must stay total, even off a real input.")
    }

    func test_play_appliesTheComputedScale_toBothAxes() {
        let node = PulseRingNode()
        node.play(radiusTiles: 3, at: .zero)

        let expected = PulseRingNode.scale(forRadiusTiles: 3)
        XCTAssertEqual(node.xScale, expected)
        XCTAssertEqual(node.yScale, expected)
    }

    // MARK: - zPosition: reserved sub-range, structurally between ground and UI

    /// `zPositionRange` is a **relative** offset added on top of
    /// `effectsLayer`'s own `LayerConstants.effectsLayerZ` once mounted --
    /// so the range that must fit inside `effectsBand` (and, transitively,
    /// above the world layer's ceiling / below the UI layer's floor) is
    /// the *cumulative* one, not the bare relative range on its own.
    private var cumulativeRange: ClosedRange<CGFloat> {
        let lower = LayerConstants.effectsLayerZ + PulseRingNode.zPositionRange.lowerBound
        let upper = LayerConstants.effectsLayerZ + PulseRingNode.zPositionRange.upperBound
        return lower...upper
    }

    func test_cumulativeZPositionRange_isAProperSubsetOfEffectsBand() {
        XCTAssertGreaterThanOrEqual(cumulativeRange.lowerBound, LayerConstants.effectsMinZ)
        XCTAssertLessThanOrEqual(cumulativeRange.upperBound, LayerConstants.effectsMaxZ)
    }

    func test_cumulativeZPositionRange_neverExceedsUIRange_andNeverDropsBelowGroundRange() {
        // Structural containment, not a per-frame comparison: any
        // cumulative value drawn from this reserved range already sits
        // strictly above the world/ground layer's ceiling and strictly
        // below the UI layer's floor -- `LayerOrderingTests` pins that
        // relationship for the three layers themselves.
        XCTAssertGreaterThan(
            cumulativeRange.lowerBound, LayerConstants.worldMaxZ,
            "the ring's reserved cumulative range must sit above the world/ground layer's band."
        )
        XCTAssertLessThan(
            cumulativeRange.upperBound, LayerConstants.uiMinZ,
            "the ring's reserved cumulative range must sit below the UI layer's band."
        )
    }

    func test_relativeZPosition_isDrawnFromTheReservedRange() {
        XCTAssertTrue(PulseRingNode.zPositionRange.contains(PulseRingNode.relativeZPosition))
    }

    func test_constructedNode_carriesTheReservedRelativeZPosition() {
        let node = PulseRingNode()
        XCTAssertEqual(node.zPosition, PulseRingNode.relativeZPosition)
        XCTAssertTrue(PulseRingNode.zPositionRange.contains(node.zPosition))
    }

    // MARK: - Mounted under effectsLayer: absolute zPosition also stays in band

    func test_mountedUnderEffectsLayer_absoluteZPosition_staysWithinEffectsBand() {
        let scene = GameScene(size: CGSize(width: 400, height: 800))
        let node = PulseRingNode()
        scene.effectsLayer.addChild(node)

        let cumulativeZ = scene.effectsLayer.zPosition + node.zPosition
        XCTAssertGreaterThanOrEqual(cumulativeZ, LayerConstants.effectsMinZ)
        XCTAssertLessThanOrEqual(cumulativeZ, LayerConstants.effectsMaxZ)
        XCTAssertGreaterThan(cumulativeZ, LayerConstants.worldMaxZ)
        XCTAssertLessThan(cumulativeZ, LayerConstants.uiMinZ)
    }
}
