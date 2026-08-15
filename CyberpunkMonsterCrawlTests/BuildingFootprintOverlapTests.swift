import XCTest
@testable import CyberpunkMonsterCrawl

/// Covers this PR's no-overlap / containment half of `CYBERPUN-17-5-t1`:
///
/// - Across many seeds and a large sampled region of blocks, no two
///   `BuildingPlacementRecord`s ever claim the same world tile (within a
///   block, and across adjacent blocks).
/// - Every 2x2 building's footprint tiles lie entirely within the one block
///   interior it was placed in — a 2x2 building can never straddle two
///   blocks' interiors (which, since blocks are separated by a 3-tile
///   street band, would also mean straddling a street).
final class BuildingFootprintOverlapTests: XCTestCase {

    func test_acrossManySeedsAndBlocks_footprintsNeverOverlapWithinABlock_and2x2FootprintsStayInsideOneBlockInterior() {
        let seeds: [WorldSeed] = [
            WorldSeed(rawValue: 0), WorldSeed(rawValue: 1), WorldSeed(rawValue: 7), WorldSeed(rawValue: 42),
            WorldSeed(rawValue: 999), WorldSeed(rawValue: 123_456), WorldSeed(rawValue: 31_337),
            WorldSeed(rawValue: 2_024)
        ]
        let blockRange = -6...6

        for seed in seeds {
            for blockX in blockRange {
                for blockY in blockRange {
                    let block = BlockCoordinate(x: blockX, y: blockY)
                    let placements = BuildingPlacement.generate(forBlock: block, seed: seed)
                    let interiorOrigin = block.interiorOrigin
                    let interiorSize = CityLatticeGenerator.blockSize

                    var seenTiles: Set<TileCoordinate> = []
                    for record in placements {
                        for tile in record.footprintTiles {
                            XCTAssertTrue(
                                seenTiles.insert(tile).inserted,
                                "Tile \(tile) claimed by more than one building in block \(block) "
                                    + "under seed \(seed.rawValue)"
                            )
                        }

                        for tile in record.footprintTiles {
                            XCTAssertTrue(
                                tile.tileX >= interiorOrigin.tileX
                                    && tile.tileX < interiorOrigin.tileX + interiorSize
                                    && tile.tileY >= interiorOrigin.tileY
                                    && tile.tileY < interiorOrigin.tileY + interiorSize,
                                "Building at \(record.lotTile) (footprint \(record.footprintTiles)) in "
                                    + "block \(block) escaped its own block interior"
                            )
                        }
                    }
                }
            }
        }
    }

    func test_acrossAdjacentBlocks_footprintsNeverOverlapGlobally() {
        // Redundant with the per-block containment check above in theory
        // (disjoint block interiors can never share a tile by construction
        // of the lattice), but checked directly here rather than only
        // inferred, so a future change to `interiorOrigin`'s arithmetic
        // that broke that assumption would be caught.
        let seeds: [WorldSeed] = [WorldSeed(rawValue: 2_024), WorldSeed(rawValue: 31_337)]

        for seed in seeds {
            var allTiles: Set<TileCoordinate> = []
            for blockX in -10...10 {
                for blockY in -10...10 {
                    let block = BlockCoordinate(x: blockX, y: blockY)
                    let placements = BuildingPlacement.generate(forBlock: block, seed: seed)
                    for record in placements {
                        for tile in record.footprintTiles {
                            XCTAssertTrue(
                                allTiles.insert(tile).inserted,
                                "Tile \(tile) claimed by more than one block under seed \(seed.rawValue)"
                            )
                        }
                    }
                }
            }
        }
    }
}
