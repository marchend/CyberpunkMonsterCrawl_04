import XCTest
@testable import CyberpunkMonsterCrawl

/// Covers AC2\u2013AC4 for `DepthModel`, the painter's-algorithm depth model's
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

    func test_bandFormula_matchesNegatedSumTimesTen() {
        let pairs: [(tileX: Int, tileY: Int)] = [
            (0, 0), (1, 0), (0, 1), (1, 1),
            (5, 3), (-5, 3), (5, -3), (-5, -3),
            (100, 100), (-100, -100), (37, -12)
        ]

        for pair in pairs {
            let tile = TileCoordinate(tileX: pair.tileX, tileY: pair.tileY)
            let expected = -CGFloat(pair.tileX + pair.tileY) * 10
            XCTAssertEqual(
                DepthModel.band(forTile: tile),
                expected,
                accuracy: 1e-9,
                "band(\(pair.tileX), \(pair.tileY)) should equal -(tileX+tileY)*10"
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
        XCTAssertLessThan(DepthModel.buildingContentRange.upperBound, 3)
        XCTAssertTrue(DepthModel.isValidBuildingContentOffset(0))
        XCTAssertTrue(DepthModel.isValidBuildingContentOffset(2.999))
        XCTAssertFalse(DepthModel.isValidBuildingContentOffset(3))
        XCTAssertFalse(DepthModel.isValidBuildingContentOffset(-0.01))
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
        // band as that whole tile \u2014 proving the resolution is rounded, not
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
        // `bandSpacing`), never something in between \u2014 proving the
        // function is a step function of the rounded tile, not a
        // continuous interpolation of the fractional position.
        let justBelowSeam = DepthModel.band(forActorAt: TilePoint(x: 3.49, y: 0))
        let justAboveSeam = DepthModel.band(forActorAt: TilePoint(x: 3.5, y: 0))

        XCTAssertEqual(justBelowSeam - justAboveSeam, DepthModel.bandSpacing, accuracy: 1e-9)
    }

    // MARK: - Cross-reference with the UI layer (documentation constant)

    func test_worldLayerCeilingCrossReference_matchesLayerConstantsWorldMaxZ() {
        XCTAssertEqual(DepthModel.worldLayerCeilingCrossReference, LayerConstants.worldMaxZ)
        XCTAssertLessThan(LayerConstants.worldMaxZ, LayerConstants.uiMinZ)
    }
}
