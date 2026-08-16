import XCTest
@testable import CyberpunkMonsterCrawl

/// Covers AC2–AC4 for `DepthModel`, the painter's-algorithm depth model's
/// single source of truth.
final class DepthModelTests: XCTestCase {

    // MARK: - AC2: ground sits 5000 below every band, for a swept range of bands

    func test_groundZPosition_isAlwaysBandMinusFiveThousand() {
        let tileSums = stride(from: -200, through: 200, by: 7)

        for sum in tileSums {
            // Any (tileX, tileY) pair whose sum is `sum` produces the same
            // band, so a single representative pair per sum is sufficient.
            let tile = TileCoordinate(tileX: sum, tileY: 0)
            let band = DepthModel.band(forTile: tile)

            XCTAssertEqual(
                DepthModel.groundZPosition(forBand: band),
                band - 5000,
                accuracy: 1e-9,
                "Ground must sit exactly 5000 below band \(band) (tileX+tileY sum \(sum))."
            )
        }
    }

    func test_groundZPosition_forTile_matchesGroundZPosition_forBand() {
        let tile = TileCoordinate(tileX: 12, tileY: -5)
        let band = DepthModel.band(forTile: tile)

        XCTAssertEqual(
            DepthModel.groundZPosition(forTile: tile),
            DepthModel.groundZPosition(forBand: band),
            accuracy: 1e-9
        )
    }

    // MARK: - AC3: band formula correctness + in-band range constants

    func test_bandOffsetFormula_matchesNegatedSumTimesTen() {
        // `bandOffset` is the brief's raw ordering rule, checked literally
        // against `-(tileX + tileY) * 10`. `band(forTile:)` then anchors it
        // (see the anchoring tests below).
        let pairs: [(tileX: Int, tileY: Int)] = [
            (0, 0), (1, 0), (0, 1), (1, 1),
            (5, 3), (-5, 3), (5, -3), (-5, -3),
            (100, 100), (-100, -100), (37, -12)
        ]

        for pair in pairs {
            let tile = TileCoordinate(tileX: pair.tileX, tileY: pair.tileY)
            let expected = -CGFloat(pair.tileX + pair.tileY) * 10
            XCTAssertEqual(
                DepthModel.bandOffset(forTile: tile),
                expected,
                accuracy: 1e-9,
                "bandOffset(\(pair.tileX), \(pair.tileY)) should equal -(tileX+tileY)*10"
            )
        }
    }

    func test_bandFormula_isTheOffsetFormulaAnchoredAtWorldBaseZ() {
        let pairs: [(tileX: Int, tileY: Int)] = [
            (0, 0), (1, 0), (0, 1), (1, 1),
            (5, 3), (-5, 3), (5, -3), (-5, -3),
            (100, 100), (-100, -100), (37, -12)
        ]

        for pair in pairs {
            let tile = TileCoordinate(tileX: pair.tileX, tileY: pair.tileY)
            let expected = DepthModel.worldBaseZ - CGFloat(pair.tileX + pair.tileY) * 10
            XCTAssertEqual(
                DepthModel.band(forTile: tile),
                expected,
                accuracy: 1e-9,
                "band(\(pair.tileX), \(pair.tileY)) should equal worldBaseZ - (tileX+tileY)*10"
            )
        }
    }

    func test_bandFormula_isMonotonicallyDecreasing_asTileSumIncreases() {
        // Larger tileX+tileY must produce a smaller (more negative) band,
        // per the formula `-(tileX + tileY) * 10`.
        let smallerSum = DepthModel.band(forTile: TileCoordinate(tileX: 1, tileY: 1))
        let largerSum = DepthModel.band(forTile: TileCoordinate(tileX: 2, tileY: 2))

        XCTAssertLessThan(largerSum, smallerSum)
    }

    func test_buildingContentRange_staysStrictlyBelowThree() {
        // `buildingContentRange` is half-open, so its `upperBound` *is* 3 and
        // the meaningful check is that 3 itself is not a legal offset.
        XCTAssertLessThanOrEqual(DepthModel.buildingContentRange.upperBound, 3)
        XCTAssertTrue(DepthModel.isValidBuildingContentOffset(0))
        XCTAssertTrue(DepthModel.isValidBuildingContentOffset(2.999))
        XCTAssertFalse(DepthModel.isValidBuildingContentOffset(3))
        XCTAssertFalse(DepthModel.isValidBuildingContentOffset(-0.01))
    }

    /// CYBERPUN-17-5-t3: `RooftopSignRenderer` sets
    /// `DepthModel.signContentOffset` as its sign node's *child* zPosition,
    /// on top of the building content floor its carrier building already
    /// occupies. That accumulated offset has to stay a legal building-content
    /// offset — this is what makes narrowing `buildingContentRange` fail here
    /// instead of silently drawing signs into a neighbouring content slot.
    func test_signContentOffset_stacksOnTheBuildingContentFloor_andStaysInsideBuildingContentRange() {
        let accumulated = DepthModel.buildingContentRange.lowerBound + DepthModel.signContentOffset

        XCTAssertGreaterThan(
            DepthModel.signContentOffset, 0,
            "A sign must draw in FRONT of the roof it sits on, so its child offset has to be positive."
        )
        XCTAssertTrue(
            DepthModel.isValidBuildingContentOffset(accumulated),
            "A rooftop sign lands at in-band offset \(accumulated), outside "
                + "buildingContentRange (\(DepthModel.buildingContentRange))."
        )
        XCTAssertLessThan(
            accumulated, DepthModel.actorOffsetRange.lowerBound,
            "A rooftop sign must never reach into actorOffsetRange — an actor always draws in front of "
                + "building content in the same band."
        )
    }

    func test_actorOffsetRange_staysWithinSixPointFiveToNinePointNine() {
        XCTAssertEqual(DepthModel.actorOffsetRange.lowerBound, 6.5)
        XCTAssertEqual(DepthModel.actorOffsetRange.upperBound, 9.9)
        XCTAssertTrue(DepthModel.isValidActorOffset(6.5))
        XCTAssertTrue(DepthModel.isValidActorOffset(9.9))
        XCTAssertTrue(DepthModel.isValidActorOffset(8.0))
        XCTAssertFalse(DepthModel.isValidActorOffset(6.4999))
        XCTAssertFalse(DepthModel.isValidActorOffset(9.9001))
    }

    func test_inBandRanges_neverOverlap_andStayInsideBandSpacing() {
        XCTAssertLessThanOrEqual(DepthModel.buildingContentRange.upperBound, DepthModel.actorOffsetRange.lowerBound)
        XCTAssertLessThan(DepthModel.actorOffsetRange.upperBound, DepthModel.bandSpacing)
    }

    // MARK: - AC4: rounded (not continuous) actor band resolution

    func test_actorBand_atExactTileCenter_matchesWholeTileBand() {
        let tile = TileCoordinate(tileX: 4, tileY: 6)
        let expectedBand = DepthModel.band(forTile: tile)

        let actorBand = DepthModel.band(forActorAt: TilePoint(x: 4, y: 6))

        XCTAssertEqual(actorBand, expectedBand, accuracy: 1e-9)
    }

    func test_actorBand_roundsFractionalPositionToNearestIntegerTile() {
        let tile = TileCoordinate(tileX: 4, tileY: 6)
        let expectedBand = DepthModel.band(forTile: tile)

        // A cluster of fractional positions that should all round to the
        // same whole tile (4, 6), and therefore all resolve to the same
        // band as that whole tile — proving the resolution is rounded, not
        // a continuous function of the fractional position.
        let fractionalPositions = [
            TilePoint(x: 4.1, y: 6.1),
            TilePoint(x: 3.6, y: 5.6),
            TilePoint(x: 4.49, y: 6.49),
            TilePoint(x: 3.51, y: 5.51)
        ]

        for position in fractionalPositions {
            XCTAssertEqual(
                DepthModel.band(forActorAt: position),
                expectedBand,
                accuracy: 1e-9,
                "Fractional position \(position) should resolve to whole tile (4, 6)'s band."
            )
        }
    }

    func test_actorBand_roundingBoundary_matchesBuildingBaseTileAlignment() {
        // The rounding boundary is pinned at the same `x.5` seam
        // `IsometricProjection.tile(containing:)` uses (`floor(coordinate +
        // 0.5)`), which is also the rule buildings use to decide their own
        // base tile. A position exactly at the seam belongs to the
        // higher-index tile on both axes.
        let justBelowSeam = DepthModel.band(forActorAt: TilePoint(x: 3.49, y: 3.49))
        let atAndAboveSeam = DepthModel.band(forActorAt: TilePoint(x: 3.5, y: 3.5))

        XCTAssertEqual(justBelowSeam, DepthModel.band(forTile: TileCoordinate(tileX: 3, tileY: 3)), accuracy: 1e-9)
        XCTAssertEqual(atAndAboveSeam, DepthModel.band(forTile: TileCoordinate(tileX: 4, tileY: 4)), accuracy: 1e-9)
        XCTAssertNotEqual(justBelowSeam, atAndAboveSeam)
    }

    func test_actorBand_isDiscontinuous_notInterpolatedBetweenBands() {
        // Two fractional positions on opposite sides of a tile seam must
        // jump by exactly one `bandSpacing` (the band formula is
        // monotonically decreasing as tileX increases, so crossing the seam
        // to the higher tile makes the band *smaller* by exactly
        // `bandSpacing`), never something in between — proving the
        // function is a step function of the rounded tile, not a
        // continuous interpolation of the fractional position.
        let justBelowSeam = DepthModel.band(forActorAt: TilePoint(x: 3.49, y: 0))
        let justAboveSeam = DepthModel.band(forActorAt: TilePoint(x: 3.5, y: 0))

        XCTAssertEqual(justBelowSeam - justAboveSeam, DepthModel.bandSpacing, accuracy: 1e-9)
    }

    // MARK: - AC4 ceiling: DepthModel's own outputs stay inside the world band
    //
    // These sweep `DepthModel`'s *outputs* rather than comparing a constant
    // to itself, and they answer containment through
    // `DepthModel.isWithinWorldBand(_:)`, which delegates to the same
    // inclusive `LayerConstants.worldBand` range
    // `GameScene.nodesEscapingTheirLayerBand()` audits — so this unit test
    // and the runtime audit cannot disagree about where the band ends.

    /// Every tile-sum the model claims to support, checked at both extremes
    /// of what a tile can be handed: its ground plane (the deepest value)
    /// and the top of its actor slot (the highest).
    func test_depthOutputs_stayInsideWorldBand_acrossEverySupportedTileSum() {
        let maxSum = DepthModel.maxSupportedTileSumMagnitude
        XCTAssertGreaterThan(maxSum, 0, "A non-positive bound would make this sweep vacuous.")

        var sums = Array(stride(from: -maxSum, through: maxSum, by: 37))
        // The endpoints and the origin explicitly, since the stride may not
        // land on them — the origin is where the unanchored formula broke.
        sums.append(contentsOf: [-maxSum, -1, 0, 1, maxSum])

        for sum in sums {
            let tile = TileCoordinate(tileX: sum, tileY: 0)
            let band = DepthModel.band(forTile: tile)
            let ground = DepthModel.groundZPosition(forTile: tile)
            let buildingFloor = band + DepthModel.buildingContentRange.lowerBound
            let actorCeiling = band + DepthModel.actorOffsetRange.upperBound

            XCTAssertTrue(
                DepthModel.isWithinSupportedDepthRange(forTile: tile),
                "Tile sum \(sum) is inside maxSupportedTileSumMagnitude (\(maxSum)) by construction."
            )
            XCTAssertTrue(
                DepthModel.isWithinWorldBand(band),
                "band \(band) (tile sum \(sum)) escaped the world band \(LayerConstants.worldBand)."
            )
            XCTAssertTrue(
                DepthModel.isWithinWorldBand(ground),
                "ground \(ground) (tile sum \(sum)) escaped the world band \(LayerConstants.worldBand)."
            )
            XCTAssertTrue(
                DepthModel.isWithinWorldBand(buildingFloor),
                "building floor \(buildingFloor) (tile sum \(sum)) escaped the world band."
            )
            XCTAssertTrue(
                DepthModel.isWithinWorldBand(actorCeiling),
                "actor ceiling \(actorCeiling) (tile sum \(sum)) escaped the world band."
            )
            XCTAssertLessThan(
                actorCeiling,
                LayerConstants.uiMinZ,
                "No world depth may reach the UI layer's floor (tile sum \(sum))."
            )
        }
    }

    /// The origin was the specific case the unanchored formula got wrong:
    /// `bandOffset((0, 0)) == 0`, which is above `worldMaxZ` entirely.
    func test_originTile_landsInsideWorldBand_whereTheRawOffsetWouldNot() {
        let origin = TileCoordinate(tileX: 0, tileY: 0)

        XCTAssertTrue(DepthModel.isWithinWorldBand(DepthModel.band(forTile: origin)))
        XCTAssertTrue(DepthModel.isWithinWorldBand(DepthModel.groundZPosition(forTile: origin)))

        // The hazard the anchor exists to remove: the raw ordering offset at
        // the origin is 0, which is not a legal world zPosition at all.
        XCTAssertEqual(DepthModel.bandOffset(forTile: origin), 0, accuracy: 1e-9)
        XCTAssertFalse(DepthModel.isWithinWorldBand(DepthModel.bandOffset(forTile: origin)))
    }

    /// A player heading north-west drives `tileX + tileY` negative, and the
    /// raw offset climbs: at sum -100 it equals `uiMinZ` exactly, i.e. world
    /// content would out-paint the UI. Anchored, it stays in the world band.
    func test_northWestTiles_stayInsideWorldBand_whereTheRawOffsetWouldReachTheUILayer() {
        let northWest = TileCoordinate(tileX: -60, tileY: -40) // sum -100

        XCTAssertEqual(
            DepthModel.bandOffset(forTile: northWest),
            LayerConstants.uiMinZ,
            accuracy: 1e-9,
            "This is the documented hazard: the raw offset reaches the UI floor at tile sum -100."
        )
        XCTAssertTrue(DepthModel.isWithinWorldBand(DepthModel.band(forTile: northWest)))
        XCTAssertLessThan(
            DepthModel.band(forTile: northWest) + DepthModel.actorOffsetRange.upperBound,
            LayerConstants.uiMinZ
        )
    }

    func test_worldBaseZ_sitsAtTheMidpointOfTheWorldBand() {
        XCTAssertTrue(DepthModel.isWithinWorldBand(DepthModel.worldBaseZ))
        XCTAssertEqual(
            DepthModel.worldBaseZ - LayerConstants.worldMinZ,
            LayerConstants.worldMaxZ - DepthModel.worldBaseZ,
            accuracy: 1e-9,
            "The anchor must leave equal headroom above and below, since tile sums go both ways."
        )
    }

    func test_isWithinWorldBand_isInclusive_matchingTheRuntimeAuditRule() {
        XCTAssertTrue(DepthModel.isWithinWorldBand(LayerConstants.worldMinZ))
        XCTAssertTrue(DepthModel.isWithinWorldBand(LayerConstants.worldMaxZ))
        XCTAssertFalse(DepthModel.isWithinWorldBand(LayerConstants.worldMinZ - 0.01))
        XCTAssertFalse(DepthModel.isWithinWorldBand(LayerConstants.worldMaxZ + 0.01))
        XCTAssertFalse(DepthModel.isWithinWorldBand(LayerConstants.uiMinZ))
    }

    /// The bound has to measure something: one band past it, a real output
    /// (the ground plane) must actually fall out of the band.
    func test_supportedTileSumBound_isTight_notMerelyConservative() {
        let beyond = DepthModel.maxSupportedTileSumMagnitude + 1

        XCTAssertFalse(DepthModel.isWithinSupportedDepthRange(forTile: TileCoordinate(tileX: beyond, tileY: 0)))
        XCTAssertFalse(DepthModel.isWithinSupportedDepthRange(forTile: TileCoordinate(tileX: -beyond, tileY: 0)))
        XCTAssertFalse(
            DepthModel.isWithinWorldBand(DepthModel.groundZPosition(forTile: TileCoordinate(tileX: beyond, tileY: 0))),
            "One band past the bound the ground plane must escape the band, or the bound is not a real limit."
        )
    }

    // MARK: - Container-relative conversion for the first renderer consumer

    func test_worldLayerRelativeZ_accumulatesBackToTheAbsoluteDepth() {
        // SpriteKit accumulates zPosition down the tree, so a node parented
        // directly under `worldLayer` must carry the *relative* value. The
        // sum of the container's own zPosition and that relative value is
        // what the layer-band audit sees.
        for sum in stride(from: -400, through: 400, by: 29) {
            let tile = TileCoordinate(tileX: sum, tileY: 0)
            for absolute in [DepthModel.band(forTile: tile), DepthModel.groundZPosition(forTile: tile)] {
                let relative = DepthModel.worldLayerRelativeZ(forAbsoluteZ: absolute)

                XCTAssertEqual(
                    LayerConstants.worldLayerZ + relative,
                    absolute,
                    accuracy: 1e-9,
                    "Cumulative z under worldLayer must reproduce the absolute depth (tile sum \(sum))."
                )
                XCTAssertGreaterThanOrEqual(
                    relative,
                    0,
                    "A negative relative offset would push the node below worldLayer's own floor."
                )
            }
        }
    }

    // MARK: - Ground clearance vs. the streaming window (derived, not prose)

    /// "Ground draws below band content" is band-relative, so it only holds
    /// while two tiles' sums differ by at most `bandsClearedByGroundOffset`.
    /// Pin that headroom against the resident window's actual size rather
    /// than leaving the derivation in a doc comment.
    func test_groundClearance_exceedsWidestResidentTileSumSpread() {
        let residentWindowSideTiles = (ChunkStreamingManager.residentRadius * 2 + 1) * Chunk.size
        // Both tile axes feed `tileX + tileY`, so the widest spread between
        // two simultaneously-resident tiles is twice the window's side.
        let widestResidentTileSumSpread = 2 * residentWindowSideTiles

        XCTAssertLessThan(
            widestResidentTileSumSpread,
            DepthModel.bandsClearedByGroundOffset,
            "Ground must clear more bands than the resident window can span, or two resident "
                + "tiles' ground and band content could fight for draw order."
        )

        // Concretely, at the widest spread the window allows: the ground of
        // the lowest-sum resident tile still draws below the band content of
        // the highest-sum resident tile.
        let lowestSumTile = TileCoordinate(tileX: 0, tileY: 0)
        let highestSumTile = TileCoordinate(tileX: widestResidentTileSumSpread, tileY: 0)

        XCTAssertLessThan(
            DepthModel.groundZPosition(forTile: lowestSumTile),
            DepthModel.band(forTile: highestSumTile) + DepthModel.buildingContentRange.lowerBound
        )
    }

    func test_supportedTileSumRange_comfortablyCoversAResidentStreamingWindow() {
        let residentWindowSideTiles = (ChunkStreamingManager.residentRadius * 2 + 1) * Chunk.size
        let widestResidentTileSumSpread = 2 * residentWindowSideTiles

        XCTAssertGreaterThan(DepthModel.maxSupportedTileSumMagnitude, widestResidentTileSumSpread)
    }
}
