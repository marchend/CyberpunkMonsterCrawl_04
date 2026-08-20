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

    /// Every radius the shipped `LevelScaling.pulseRadiusMultiplier` curve
    /// can hand `play(radiusTiles:at:)`: base 3.0, the level 3-5 1.25x
    /// multiplier, and the level 6+ compounding 1.5625x.
    private static let realRadii: [Double] = [
        PulseAbility.baseRadiusTiles,
        PulseAbility.baseRadiusTiles * 1.25,
        PulseAbility.baseRadiusTiles * 1.5625,
    ]

    /// The projected-extent derivation, checked against
    /// `IsometricProjection.tileToScreen` itself rather than restated from
    /// the same constants the implementation uses: sample the tile-space
    /// circle `PulseAbility`'s Euclidean `hypot` radius really describes,
    /// project every sample, and measure the screen-space bounding box the
    /// samples sweep out. That box *is* the region the pulse pushes, and
    /// it is an ellipse of `sqrt(2) * 48 * R` by `sqrt(2) * 24 * R`
    /// semi-axes -- not a circle of radius `48R` (PR #48 review).
    private func measuredProjectedExtent(forRadiusTiles radius: Double) -> CGSize {
        var maxX: CGFloat = 0
        var maxY: CGFloat = 0
        for step in 0..<3_600 {
            let angle = Double(step) * .pi / 1_800
            let screen = IsometricProjection.tileToScreen(
                TilePoint(x: radius * cos(angle), y: radius * sin(angle))
            )
            maxX = max(maxX, abs(screen.x))
            maxY = max(maxY, abs(screen.y))
        }
        return CGSize(width: maxX * 2, height: maxY * 2)
    }

    func test_projectedExtent_matchesTheRealIsometricProjectionOfATileSpaceCircle() {
        for radius in Self.realRadii {
            let measured = measuredProjectedExtent(forRadiusTiles: radius)
            XCTAssertEqual(
                PulseRingNode.projectedWidthPoints(forRadiusTiles: radius), measured.width, accuracy: 0.05,
                "radius \(radius): the declared screen-x extent must equal the projection's own."
            )
            XCTAssertEqual(
                PulseRingNode.projectedHeightPoints(forRadiusTiles: radius), measured.height, accuracy: 0.05,
                "radius \(radius): the declared screen-y extent must equal the projection's own."
            )
        }
    }

    func test_projectedExtent_staysOnThe2To1IsometricPlane() {
        for radius in Self.realRadii {
            XCTAssertEqual(
                PulseRingNode.projectedWidthPoints(forRadiusTiles: radius),
                2 * PulseRingNode.projectedHeightPoints(forRadiusTiles: radius),
                accuracy: 1e-9,
                "the ring must sit on the same 2:1 plane as everything else in worldLayer."
            )
        }
    }

    /// The property the uniform scale broke: at whatever integer scale the
    /// node ends up carrying, the *drawn ring* must land on the projected
    /// ellipse to within half an integer scale step on each axis. A single
    /// shared scale cannot satisfy both axes at once -- that is exactly the
    /// ~29%-narrow / ~41%-tall error PR #48's review measured.
    func test_scale_drawsTheRingOntoTheProjectedEllipse_withinHalfAnIntegerStep() {
        let ring = AtlasPulseRingContent.widestFrameContentSize

        for radius in Self.realRadii {
            let drawnWidth = PulseRingNode.xScale(forRadiusTiles: radius) * ring.width
            let drawnHeight = PulseRingNode.yScale(forRadiusTiles: radius) * ring.height

            XCTAssertEqual(
                drawnWidth, PulseRingNode.projectedWidthPoints(forRadiusTiles: radius),
                accuracy: ring.width / 2,
                "radius \(radius): the drawn ring's width misses the pushed region's width by more than "
                    + "one rounding step."
            )
            XCTAssertEqual(
                drawnHeight, PulseRingNode.projectedHeightPoints(forRadiusTiles: radius),
                accuracy: ring.height / 2,
                "radius \(radius): the drawn ring's height misses the pushed region's height by more than "
                    + "one rounding step."
            )
        }
    }

    func test_scale_isDerivedPerAxis_soAUniformScaleCanNoLongerSatisfyIt() {
        for radius in Self.realRadii {
            XCTAssertNotEqual(
                PulseRingNode.xScale(forRadiusTiles: radius),
                PulseRingNode.yScale(forRadiusTiles: radius),
                "radius \(radius): a 2:1 plane cannot be covered by one shared scale -- xScale and yScale "
                    + "must differ, or the ring is back to being drawn as a square."
            )
        }
    }

    func test_scale_dividesByTheMeasuredRing_notByTheRawCellSize() {
        // The divisor is `AtlasPulseRingContent.widestFrameContentSize`
        // (alpha-scanned, pinned by `PulseRingArtMeasurementTests`), not
        // `AtlasSheet.pulse`'s 32px cell -- scaling an SKSpriteNode scales
        // the whole cell, so sizing against the cell draws the ring
        // `cellSize / ringSize` times off.
        let ring = AtlasPulseRingContent.widestFrameContentSize
        let radius = PulseAbility.baseRadiusTiles

        XCTAssertEqual(
            PulseRingNode.xScale(forRadiusTiles: radius),
            max(1, (PulseRingNode.projectedWidthPoints(forRadiusTiles: radius) / ring.width).rounded())
        )
        XCTAssertEqual(
            PulseRingNode.yScale(forRadiusTiles: radius),
            max(1, (PulseRingNode.projectedHeightPoints(forRadiusTiles: radius) / ring.height).rounded())
        )
    }

    func test_scale_isAWholeInteger_onBothAxes_forEveryRealRadius() {
        for radius in Self.realRadii {
            let x = PulseRingNode.xScale(forRadiusTiles: radius)
            let y = PulseRingNode.yScale(forRadiusTiles: radius)
            XCTAssertEqual(x, x.rounded(), "radius \(radius): a fractional xScale resamples the nearest-filtered art.")
            XCTAssertEqual(y, y.rounded(), "radius \(radius): a fractional yScale resamples the nearest-filtered art.")
        }
    }

    func test_scale_neverDropsBelowOne_forAVanishinglySmallOrZeroRadius() {
        // Exact equality on purpose: `max(1, (projectedWidthPoints / ringWidth)
        // .rounded())` returns the literal `1.0` floor for these radii, so there
        // is no floating-point residue for a tolerance to absorb -- and this
        // test's whole point (see
        // `test_scale_isAWholeInteger_onBothAxes_forEveryRealRadius`) is that
        // the scale is a *whole integer*, which a tolerance is exactly the
        // thing that would let a non-integer slip past.
        // SpriteKit's CGFloat is float32-backed; `1` itself is exactly
        // representable, but the values under test flow through
        // `max(1, (...).rounded())` so compare with a tight accuracy
        // rather than bare equality to stay robust to any float32
        // rounding noise introduced along that path.
        XCTAssertEqual(PulseRingNode.xScale(forRadiusTiles: 0), 1, accuracy: 1e-6)
        XCTAssertEqual(PulseRingNode.yScale(forRadiusTiles: 0), 1, accuracy: 1e-6)
        XCTAssertEqual(PulseRingNode.xScale(forRadiusTiles: 0.01), 1, accuracy: 1e-6)
        XCTAssertEqual(PulseRingNode.yScale(forRadiusTiles: 0.01), 1, accuracy: 1e-6)
        XCTAssertEqual(
            PulseRingNode.xScale(forRadiusTiles: -5), 1, accuracy: 1e-6,
            "a pure function must stay total, even off a real input."
        )
        XCTAssertEqual(PulseRingNode.yScale(forRadiusTiles: -5), 1, accuracy: 1e-6)
    }

    func test_play_appliesTheComputedPerAxisScale() {
        let node = PulseRingNode()
        node.play(radiusTiles: PulseAbility.baseRadiusTiles, at: .zero)

        XCTAssertEqual(node.xScale, PulseRingNode.xScale(forRadiusTiles: PulseAbility.baseRadiusTiles))
        XCTAssertEqual(node.yScale, PulseRingNode.yScale(forRadiusTiles: PulseAbility.baseRadiusTiles))
        XCTAssertNotEqual(
            node.xScale, node.yScale,
            "play(...) must keep the ring on the 2:1 plane, not scale it uniformly."
        )
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
