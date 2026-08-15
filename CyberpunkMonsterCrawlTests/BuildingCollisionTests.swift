import XCTest
@testable import CyberpunkMonsterCrawl

/// AC6 of CYBERPUN-17-5-t2: collision is derived solely from a building's
/// reserved footprint, never from its rendered sprite's bounding box \u2014
/// `docs/bootstrap.md` \u00a71: "collision is a tile query, not `SKPhysicsBody`
/// ... Visual height must never affect collision."
///
/// A tall (4-storey, `building_05`) and a short (1-storey, `building_10`)
/// building sharing an *identical* footprint must obstruct identically: the
/// same blocked tiles, and the same walkable boundary immediately outside
/// the footprint \u2014 even though their rendered sprites differ enormously in
/// height (`BuildingSprite.building05.declaredPixelSize` is 96x240 vs
/// `.building10`'s 96x80).
final class BuildingCollisionTests: XCTestCase {

    private let footprintOrigin = TileCoordinate(tileX: 10, tileY: 10)

    private var footprintTiles: [TileCoordinate] {
        [
            footprintOrigin,
            TileCoordinate(tileX: footprintOrigin.tileX + 1, tileY: footprintOrigin.tileY),
            TileCoordinate(tileX: footprintOrigin.tileX, tileY: footprintOrigin.tileY + 1),
            TileCoordinate(tileX: footprintOrigin.tileX + 1, tileY: footprintOrigin.tileY + 1),
        ]
    }

    private func makeRecord(buildingIndex: Int) -> BuildingPlacementRecord {
        BuildingPlacementRecord(
            lotTile: footprintOrigin,
            building: BuildingCatalog.entry(atIndex: buildingIndex),
            footprintTiles: footprintTiles,
            farCornerTile: TileCoordinate(tileX: footprintOrigin.tileX + 1, tileY: footprintOrigin.tileY + 1)
        )
    }

    /// Mounts `record` into a hand-built chunk fixture (rather than a
    /// lattice-generated one), so the footprint's exact tile pattern \u2014 and
    /// the boundary immediately around it \u2014 is fully known. Follows the
    /// same "hand-assembled `Chunk` fixture" pattern
    /// `ChunkGeneratorTests.unplacedChunk` already uses for the reservation-
    /// API tests, streaming the synthetic building into a known chunk/tile
    /// exactly as a real `ChunkGenerator.generate` chunk would carry it.
    private func mountedChunk(for record: BuildingPlacementRecord) -> Chunk {
        let origin = ChunkCoordinate(x: 1, y: 1) // world tiles 8...15 on each axis; covers footprintOrigin (10, 10).
        let worldOrigin = origin.worldTileOrigin
        let footprintSet = Set(record.footprintTiles)

        let tiles: [[TileInfo]] = (0..<Chunk.size).map { localX in
            (0..<Chunk.size).map { localY -> TileInfo in
                let worldTileX = worldOrigin.tileX + localX
                let worldTileY = worldOrigin.tileY + localY
                let kind: TileKind = footprintSet.contains(TileCoordinate(tileX: worldTileX, tileY: worldTileY))
                    ? .buildingFootprint
                    : .lot
                return TileInfo(tileX: worldTileX, tileY: worldTileY, kind: kind)
            }
        }

        let reservations = LotReservationStore()
        reservations.reserve(record.footprintTiles)
        return Chunk(origin: origin, tiles: tiles, reservations: reservations, buildingPlacements: [record])
    }

    private func isWalkable(_ tile: TileCoordinate, in chunk: Chunk) -> Bool {
        let worldOrigin = chunk.origin.worldTileOrigin
        let localX = tile.tileX - worldOrigin.tileX
        let localY = tile.tileY - worldOrigin.tileY
        return chunk.tile(localX: localX, localY: localY).isWalkable
    }

    // MARK: - Tall vs. short: identical collision

    func test_tallAndShortBuilding_sharingTheSameFootprint_obstructIdenticalTiles() {
        let tallRecord = makeRecord(buildingIndex: 5) // building_05, ~4 storey ("tall")
        let shortRecord = makeRecord(buildingIndex: 10) // building_10, ~1 storey ("lowest")

        XCTAssertEqual(BuildingSprite(rawValue: tallRecord.building.index)?.heightClass, .tall)
        XCTAssertEqual(BuildingSprite(rawValue: shortRecord.building.index)?.heightClass, .lowest)

        let tallChunk = mountedChunk(for: tallRecord)
        let shortChunk = mountedChunk(for: shortRecord)

        // Every footprint tile is solid in both, regardless of the chosen
        // building's height.
        for tile in footprintTiles {
            XCTAssertFalse(isWalkable(tile, in: tallChunk), "\(tile) should be blocked by the tall building")
            XCTAssertFalse(isWalkable(tile, in: shortChunk), "\(tile) should be blocked by the short building")
        }

        // The approach boundary immediately outside the shared footprint \u2014
        // one tile beyond each edge \u2014 is walkable in both, identically.
        let boundaryTiles = [
            TileCoordinate(tileX: footprintOrigin.tileX - 1, tileY: footprintOrigin.tileY),
            TileCoordinate(tileX: footprintOrigin.tileX - 1, tileY: footprintOrigin.tileY + 1),
            TileCoordinate(tileX: footprintOrigin.tileX + 2, tileY: footprintOrigin.tileY),
            TileCoordinate(tileX: footprintOrigin.tileX + 2, tileY: footprintOrigin.tileY + 1),
            TileCoordinate(tileX: footprintOrigin.tileX, tileY: footprintOrigin.tileY - 1),
            TileCoordinate(tileX: footprintOrigin.tileX + 1, tileY: footprintOrigin.tileY - 1),
            TileCoordinate(tileX: footprintOrigin.tileX, tileY: footprintOrigin.tileY + 2),
            TileCoordinate(tileX: footprintOrigin.tileX + 1, tileY: footprintOrigin.tileY + 2),
        ]
        for tile in boundaryTiles {
            XCTAssertTrue(isWalkable(tile, in: tallChunk), "\(tile) should approach the tall building freely")
            XCTAssertTrue(isWalkable(tile, in: shortChunk), "\(tile) should approach the short building freely")
        }

        // The `BuildingObstruction` entry point \u2014 the one a movement
        // resolver would call \u2014 agrees, tile-for-tile, between the two.
        for tile in footprintTiles + boundaryTiles {
            XCTAssertEqual(
                BuildingObstruction.isObstructed(tile, by: tallRecord),
                BuildingObstruction.isObstructed(tile, by: shortRecord),
                "\(tile) must obstruct identically for a tall and a short building sharing the same footprint."
            )
        }
    }

    /// Proves the two fixtures above are a genuine tall/short pair (not two
    /// names for the same height) while the collision behaviour just proven
    /// to match stays identical \u2014 the whole point of AC6: visual height
    /// must never leak into collision.
    func test_tallAndShortBuildingSprites_haveVeryDifferentRenderedHeights() {
        let tallNode = TileFieldRenderer.makeBuildingNode(for: makeRecord(buildingIndex: 5))
        let shortNode = TileFieldRenderer.makeBuildingNode(for: makeRecord(buildingIndex: 10))

        XCTAssertGreaterThan(tallNode.size.height, shortNode.size.height * 2)
    }

    // MARK: - BuildingObstruction: footprint-only, independent of any chunk

    func test_buildingObstruction_isObstructed_isPurelyFootprintMembership() {
        let record = makeRecord(buildingIndex: 8) // building_08, mid height class

        for tile in footprintTiles {
            XCTAssertTrue(BuildingObstruction.isObstructed(tile, by: record))
        }
        XCTAssertFalse(
            BuildingObstruction.isObstructed(
                TileCoordinate(tileX: footprintOrigin.tileX - 1, tileY: footprintOrigin.tileY),
                by: record
            )
        )
    }
}
