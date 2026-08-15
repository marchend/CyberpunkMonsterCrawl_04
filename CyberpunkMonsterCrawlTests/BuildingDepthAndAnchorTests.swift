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
