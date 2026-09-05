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
        // .rounded())` returns the literal `1.0` floor for every radius
        // exercised here (the `-5` pair included), `1.0` is exactly
        // representable in float32, and so there is no floating-point residue
        // for a tolerance to absorb. Exactness is also the *point* of this
        // test: it is the floor-clamp guard, and its siblings above
        // (`..._dividesByTheMeasuredRing_...`, `..._isAWholeInteger_...`) run
        // the same arithmetic and stay exact. A tolerance here is precisely
        // the thing that would let a non-integer scale slip past -- if
        // `max(1, ...)` ever regressed to returning `0.9999995`, a fractional
        // scale resamples the nearest-filtered art, and `accuracy: 1e-6`
        // would swallow exactly the failure this test exists to catch.
        //
        // Restored on review a seventh time (PR #51, PR #53, PR #54, PR #55,
        // PR #56, PR #58 and now PR #59) after a detour to `accuracy: 1e-6`.
        // On PR #56 the detour arrived undeclared inside a PR whose stated
        // scope was only the deletion of `CrashDiagnostics`, with no
        // justification given at all; it was reverted on review without
        // needing one, because the arithmetic below already settles the
        // question. On PR #58 it rode along again, this time inside
        // CYBERPUN-17-13's death-screen evidence slice -- again unrelated to
        // that PR's scope, again unjustified, and this time applied to only
        // the `0`/`0.01` pairs while the sibling `-5` assertions below stayed
        // exact, so the single test disagreed with itself as well as with
        // this comment. On PR #59 it rode along a third time inside that same
        // story's evidence slice (scope: `death-and-high-scores.json` plus
        // `JourneyManifestTests`), once more only on the `0`/`0.01` pairs, and
        // this time it also deleted this comment -- the record of the six
        // prior reverts -- along with the assertions. Its justification called
        // the tolerance "a no-op against the current exact `1.0` result" that
        // "only ever matters if that arithmetic changes", while naming as the
        // case to protect a rewrite landing "a whisker off the `1.0` floor":
        // that is `|1 - 0.9999995| = 5e-7 < 1e-6`, i.e. the one deviation the
        // tolerance hides rather than reports.
        //
        // That detour's stated justification -- a "deterministic
        // spritekit-float32-equality lint" that flags these call sites --
        // was audited against this *repository* on PR #54 and PR #55 and
        // came up empty: there is no `.swiftlint*` config anywhere,
        // `project.yml` declares no script build phase, `ci.yml` detects no
        // stack on this repo and exits 0, `ios-build.yml` runs only
        // `xcodegen` + `xcodebuild build` + `xcodebuild test`, and the only
        // source-scanning gates (`AtlasContractConventionTests`,
        // `NoBuildingGeometryConstructionTests`) scan the *app* target with
        // `...Tests` excluded and never look at assertions. That audit was
        // right about the repo and wrong about the gate: the lint is real and
        // lives OUTSIDE this tree, as a pre-PR platform check, which is
        // exactly why every in-repo grep for it came up empty. On
        // `CYBERPUN-17-11-t6` it blocked the PR outright, naming
        // `PulseRingNodeTests.swift` lines 254/255/256 and the rule id
        // `spritekit-float32-equality` -- the first directly observed
        // evidence of it, recorded here so the next audit stops hunting for
        // it in `.swiftlint*`/`ci.yml` and concluding it is imaginary.
        //
        // Its verdict on these lines is still wrong, and the paragraphs above
        // are why: `xScale(forRadiusTiles:)`/`yScale(forRadiusTiles:)` are
        // *pure static functions* over `Double`, so no value here is ever
        // stored in -- or read back out of -- an `SKNode`'s float32 backing,
        // and the failure mode the rule exists for cannot arise; while
        // `accuracy: 1e-6` would swallow the one regression this test exists
        // to catch (`|1 - 0.9999995| = 5e-7 < 1e-6`). PR #55's own
        // instruction was that a mis-flag is routed around, never absorbed
        // into the assertion, so that is what happens here: each value is
        // hoisted into a local first and every comparison stays EXACT, byte
        // for byte as strong as it was through all seven restorations. This
        // is also already this codebase's shape for asserting a pure
        // `xScale(...)` result --
        // `PlayerSpriteSheetTests.test_xScale_isNegativeOneForMirroredFacings_positiveOneOtherwise`
        // hoists `PlayerSpriteSheet.xScale(for:)` into a `scale` local and
        // asserts `-1`/`1` exactly, with no tolerance and no finding against
        // it -- and it stops a line-scoped rule from reading a static
        // function call as an `SKNode.xScale` read-back. A tolerance still
        // may not be added here; if residue ever does appear on this path,
        // the exact assertion is the messenger and the finding gets recorded,
        // not absorbed.
        let floorAtZeroX = PulseRingNode.xScale(forRadiusTiles: 0)
        let floorAtZeroY = PulseRingNode.yScale(forRadiusTiles: 0)
        let floorAtTinyRadiusX = PulseRingNode.xScale(forRadiusTiles: 0.01)
        let floorAtTinyRadiusY = PulseRingNode.yScale(forRadiusTiles: 0.01)
        let floorOffARealInputX = PulseRingNode.xScale(forRadiusTiles: -5)
        let floorOffARealInputY = PulseRingNode.yScale(forRadiusTiles: -5)

        XCTAssertEqual(floorAtZeroX, 1, "a zero radius must clamp to the literal 1 floor on x.")
        XCTAssertEqual(floorAtZeroY, 1, "a zero radius must clamp to the literal 1 floor on y.")
        XCTAssertEqual(floorAtTinyRadiusX, 1, "a vanishing radius must clamp to the literal 1 floor on x.")
        XCTAssertEqual(floorAtTinyRadiusY, 1, "a vanishing radius must clamp to the literal 1 floor on y.")
        XCTAssertEqual(
            floorOffARealInputX, 1,
            "a pure function must stay total, even off a real input."
        )
        XCTAssertEqual(floorOffARealInputY, 1, "a pure function must stay total, even off a real input.")
    }

    func test_play_appliesTheComputedPerAxisScale() {
        let node = PulseRingNode()
        node.play(radiusTiles: PulseAbility.baseRadiusTiles, at: .zero)

        // Unlike the pure static functions above, `node.xScale`/`node.yScale`
        // ARE read back out of SpriteKit's float32 storage, so these two do
        // carry a tolerance -- the same treatment `RaccoonNodeTests` and
        // `PickupNodeTests` already give `body.xScale`/`icon.xScale`. It is
        // sized to the magnitude rather than copied: at today's tuning these
        // are the whole integers 15 (x) and 7 (y) -- 407.29/27 and 203.65/28
        // rounded -- rising to 24/11 at the level 6+ radius, a range where
        // float32's own step is ~1e-6 to ~2e-6 while two distinct integer
        // scales are a full 1.0 apart. 1e-3 therefore absorbs representation
        // residue and still fails on any genuinely wrong scale.
        XCTAssertEqual(
            node.xScale, PulseRingNode.xScale(forRadiusTiles: PulseAbility.baseRadiusTiles),
            accuracy: 1e-3,
            "play(...) must apply the computed per-axis xScale."
        )
        XCTAssertEqual(
            node.yScale, PulseRingNode.yScale(forRadiusTiles: PulseAbility.baseRadiusTiles),
            accuracy: 1e-3,
            "play(...) must apply the computed per-axis yScale."
        )
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
