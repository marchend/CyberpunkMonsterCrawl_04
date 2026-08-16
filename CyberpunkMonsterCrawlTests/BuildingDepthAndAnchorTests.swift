import CoreGraphics
import SpriteKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// Covers AC4/AC5 of CYBERPUN-17-5-t2: a building sprite anchors
/// bottom-centre at its base tile, and depth-sorts off its footprint's *far*
/// corner (never the base tile), so a building never draws over an actor
/// standing anywhere in front of any part of its footprint.
final class BuildingDepthAndAnchorTests: XCTestCase {

    private func makeRecord(
        lotTile: TileCoordinate,
        footprintTiles: [TileCoordinate],
        farCornerTile: TileCoordinate,
        buildingIndex: Int = 0
    ) -> BuildingPlacementRecord {
        BuildingPlacementRecord(
            lotTile: lotTile,
            building: BuildingCatalog.entry(atIndex: buildingIndex),
            footprintTiles: footprintTiles,
            farCornerTile: farCornerTile
        )
    }

    // MARK: - AC5: anchor point

    func test_makeBuildingNode_anchorsBottomCentre() {
        let tile = TileCoordinate(tileX: 2, tileY: 3)
        let record = makeRecord(lotTile: tile, footprintTiles: [tile], farCornerTile: tile)

        let node = TileFieldRenderer.makeBuildingNode(for: record)

        // Compared component-wise with a tolerance (not `XCTAssertEqual` on
        // the `CGPoint` directly): SpriteKit-backed geometry can round-trip
        // through float32 storage, so an exact equality check on a value
        // that came back out of an `SKSpriteNode` is not reliable even when
        // the value assigned was a simple literal like `(0.5, 0)`.
        XCTAssertEqual(node.anchorPoint.x, 0.5, accuracy: 1e-6)
        XCTAssertEqual(node.anchorPoint.y, 0, accuracy: 1e-6)
    }

    func test_makeBuildingNode_positionsAtLotTilesScreenPoint_roundedToWholeDevicePixels() {
        let lotTile = TileCoordinate(tileX: 5, tileY: 1)
        let record = makeRecord(lotTile: lotTile, footprintTiles: [lotTile], farCornerTile: lotTile)

        let node = TileFieldRenderer.makeBuildingNode(for: record)
        let expectedScreenPoint = IsometricProjection.tileToScreen(
            tileX: Double(lotTile.tileX),
            tileY: Double(lotTile.tileY)
        )

        XCTAssertEqual(node.position.x, expectedScreenPoint.x.rounded(), accuracy: 1e-6)
        XCTAssertEqual(node.position.y, expectedScreenPoint.y.rounded(), accuracy: 1e-6)
        XCTAssertEqual(
            node.position.x, node.position.x.rounded(), accuracy: 1e-6,
            "position.x must land on a whole device pixel"
        )
        XCTAssertEqual(
            node.position.y, node.position.y.rounded(), accuracy: 1e-6,
            "position.y must land on a whole device pixel"
        )
    }

    /// Which tile of a **multi-tile** footprint the sprite anchors to \u2014 the
    /// one thing the two 1x1 cases above structurally cannot see, because for
    /// a 1x1 building the base tile, the merged footprint's centre and the
    /// far corner are all the same tile.
    ///
    /// The convention is the base tile (`record.lotTile`), never the
    /// footprint centre. A 2x2 footprint's merged diamond is centred at
    /// tile-space `(lotX + 0.5, lotY + 0.5)`, which projects exactly
    /// `IsometricProjection.tileHalfHeight` (24px \u2014 half a tile) further up
    /// the screen, so that is the one plausible alternative and the exact
    /// half-tile offset this pins against: without this case a half-tile
    /// slip on `building_08`/`building_09`/`building_11` would ship green.
    ///
    /// Uses `building_08` (a real `.twoByTwo` entry, 144px wide against a
    /// 96px lot) rather than a synthetic record, and asserts both of those
    /// properties before the position, so the case cannot quietly degenerate
    /// into another 1x1 test. Whether the *art* inside that 144px rect is
    /// centred and bottom-aligned is measured separately, from pixel alpha,
    /// by `BuildingSpriteBaseAlignmentTests`.
    func test_makeBuildingNode_twoByTwoFootprint_anchorsAtTheBaseTile_notTheFootprintCentre() {
        let lotTile = TileCoordinate(tileX: 4, tileY: 4)
        let farCornerTile = TileCoordinate(tileX: 5, tileY: 5)
        let footprintTiles = [
            lotTile,
            TileCoordinate(tileX: 5, tileY: 4),
            TileCoordinate(tileX: 4, tileY: 5),
            farCornerTile,
        ]
        let record = makeRecord(
            lotTile: lotTile, footprintTiles: footprintTiles, farCornerTile: farCornerTile, buildingIndex: 8
        )

        XCTAssertEqual(
            record.building.footprintSize, .twoByTwo,
            "This case is only meaningful for a genuinely 2x2 building; building_08 must still be one."
        )

        let node = TileFieldRenderer.makeBuildingNode(for: record)

        let tilePixelWidth = CGFloat(2 * IsometricProjection.tileHalfWidth)
        XCTAssertGreaterThan(
            node.size.width, tilePixelWidth,
            "building_08's art (" + String(describing: node.size.width) + "px) must be wider than one "
                + String(describing: tilePixelWidth) + "px lot, or this case is not exercising a "
                + "wider-than-one-tile building at all."
        )

        let baseTilePoint = IsometricProjection.tileToScreen(
            tileX: Double(lotTile.tileX),
            tileY: Double(lotTile.tileY)
        )
        let footprintCentrePoint = IsometricProjection.tileToScreen(
            tileX: Double(lotTile.tileX) + 0.5,
            tileY: Double(lotTile.tileY) + 0.5
        )

        // Anti-vacuity: the two candidates must actually differ, by exactly
        // half a tile in screen y \\u2014 otherwise the assertions below would
        // pass under either convention.
        XCTAssertEqual(
            footprintCentrePoint.y - baseTilePoint.y,
            CGFloat(IsometricProjection.tileHalfHeight),
            accuracy: 1e-6,
            "A 2x2 footprint's centre must sit exactly half a tile up-screen from its base tile."
        )

        XCTAssertEqual(node.position.x, baseTilePoint.x.rounded(), accuracy: 1e-6)
        XCTAssertEqual(
            node.position.y, baseTilePoint.y.rounded(), accuracy: 1e-6,
            "A 2x2 building anchors at its base tile's screen point."
        )
        XCTAssertNotEqual(
            node.position.y, footprintCentrePoint.y.rounded(), accuracy: 1e-6,
            "A 2x2 building must not be anchored at its merged footprint's centre; that would lift "
                + "building_08/09/11 half a tile up the screen off their own lots."
        )

        // The wider art does not change the anchor itself: still
        // bottom-centre, still on whole device pixels.
        XCTAssertEqual(node.anchorPoint.x, 0.5, accuracy: 1e-6)
        XCTAssertEqual(node.anchorPoint.y, 0, accuracy: 1e-6)
        XCTAssertEqual(node.position.x, node.position.x.rounded(), accuracy: 1e-6)
        XCTAssertEqual(node.position.y, node.position.y.rounded(), accuracy: 1e-6)
    }

    // MARK: - AC4: depth keys off the far corner across the whole footprint, not the base tile

    func test_farCornerTile_amongFootprintTiles_isTheMaxTileSum_notTheBaseTile() {
        let footprintTiles = [
            TileCoordinate(tileX: 4, tileY: 4), // lotTile / base, sum 8
            TileCoordinate(tileX: 5, tileY: 4), // sum 9
            TileCoordinate(tileX: 4, tileY: 5), // sum 9
            TileCoordinate(tileX: 5, tileY: 5), // far corner, sum 10
        ]

        guard let farCorner = IsometricDepthSorting.farCornerTile(amongFootprintTiles: footprintTiles) else {
            XCTFail("Expected a far corner among a non-empty footprint")
            return
        }

        XCTAssertEqual(farCorner, TileCoordinate(tileX: 5, tileY: 5))
    }

    func test_makeBuildingNode_zPosition_usesFarCorner_notTheBaseTile() {
        let lotTile = TileCoordinate(tileX: 4, tileY: 4)
        let farCornerTile = TileCoordinate(tileX: 5, tileY: 5)
        let footprintTiles = [
            lotTile,
            TileCoordinate(tileX: 5, tileY: 4),
            TileCoordinate(tileX: 4, tileY: 5),
            farCornerTile,
        ]
        let record = makeRecord(
            lotTile: lotTile, footprintTiles: footprintTiles, farCornerTile: farCornerTile, buildingIndex: 11
        )

        let node = TileFieldRenderer.makeBuildingNode(for: record)

        let expectedAbsolute = IsometricDepthSorting.zPosition(forBuildingFarCornerTile: farCornerTile)
        let expectedRelative = DepthModel.worldLayerRelativeZ(forAbsoluteZ: expectedAbsolute)
        let wrongAbsoluteUsingBaseTile = IsometricDepthSorting.zPosition(forBuildingFarCornerTile: lotTile)
        let wrongRelativeUsingBaseTile = DepthModel.worldLayerRelativeZ(forAbsoluteZ: wrongAbsoluteUsingBaseTile)

        XCTAssertEqual(node.zPosition, expectedRelative, accuracy: 1e-9)
        XCTAssertNotEqual(node.zPosition, wrongRelativeUsingBaseTile, accuracy: 1e-9)
    }

    func test_zPosition_staysWithinBuildingContentRange_ofItsOwnBand() {
        let farCornerTile = TileCoordinate(tileX: -3, tileY: 8)
        let absoluteZ = IsometricDepthSorting.zPosition(forBuildingFarCornerTile: farCornerTile)
        let band = DepthModel.band(forTile: farCornerTile)

        XCTAssertTrue(DepthModel.isValidBuildingContentOffset(absoluteZ - band))
    }

    /// An actor standing on any tile whose `tileX + tileY` sum is smaller
    /// than the building's far corner's own sum \u2014 i.e. anywhere in front of
    /// (south/east of, per this game's diagonals) the far corner \u2014 must
    /// always resolve a strictly greater zPosition than the building,
    /// regardless of how close or far that tile is. Mirrors the existing
    /// actor-vs-tile z-comparison shape `DepthModelTests` already uses for
    /// non-building content.
    func test_actorInFrontOfFarCorner_alwaysResolvesGreaterZ_thanTheBuilding() {
        let footprintTiles = [
            TileCoordinate(tileX: 5, tileY: 5),
            TileCoordinate(tileX: 6, tileY: 5),
            TileCoordinate(tileX: 5, tileY: 6),
            TileCoordinate(tileX: 6, tileY: 6),
        ]
        guard let farCorner = IsometricDepthSorting.farCornerTile(amongFootprintTiles: footprintTiles) else {
            XCTFail("Expected a far corner among a non-empty footprint")
            return
        }
        XCTAssertEqual(farCorner, TileCoordinate(tileX: 6, tileY: 6))

        let buildingAbsoluteZ = IsometricDepthSorting.zPosition(forBuildingFarCornerTile: farCorner)
        let buildingRelativeZ = DepthModel.worldLayerRelativeZ(forAbsoluteZ: buildingAbsoluteZ)

        let farCornerSum = farCorner.tileX + farCorner.tileY
        for actorSum in [farCornerSum - 1, farCornerSum - 4, 0, -50] {
            let actorAbsoluteZ = DepthModel.band(forActorAt: TilePoint(x: Double(actorSum), y: 0))
                + DepthModel.actorOffsetRange.lowerBound
            let actorRelativeZ = DepthModel.worldLayerRelativeZ(forAbsoluteZ: actorAbsoluteZ)

            XCTAssertGreaterThan(
                actorRelativeZ,
                buildingRelativeZ,
                "Actor tile-sum \(actorSum) (in front of far corner sum \(farCornerSum)) must resolve a greater z."
            )
        }
    }
}
