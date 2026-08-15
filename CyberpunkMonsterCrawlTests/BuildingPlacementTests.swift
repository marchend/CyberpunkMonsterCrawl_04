import XCTest
@testable import CyberpunkMonsterCrawl

/// Covers this PR's building-selection half of `CYBERPUN-17-5-t1`:
///
/// - **Determinism:** same seed + same lot must yield the same sprite,
///   across repeated calls (the plan's required
///   `BuildingPlacementTests.swift` coverage).
/// - **Lattice agreement:** an empty-lot block (`CityLatticeGenerator
///   .isEmptyLotBlock`) must never get a building; a building block must
///   have every one of its 9 lots covered by some building's footprint.
/// - **Footprint bookkeeping:** `farCornerTile`/`footprintTiles` must agree
///   with the chosen building's declared footprint span.
final class BuildingPlacementTests: XCTestCase {

    // MARK: - Determinism

    func test_generate_sameSeedSameBlock_yieldsIdenticalResult_acrossRepeatedCalls() {
        let seed = seedWithBuildingBlock(x: 0, y: 0)
        let block = BlockCoordinate(x: 0, y: 0)

        let first = BuildingPlacement.generate(forBlock: block, seed: seed)
        let second = BuildingPlacement.generate(forBlock: block, seed: seed)
        let third = BuildingPlacement.generate(forBlock: block, seed: seed)

        XCTAssertFalse(first.isEmpty, "Expected the chosen seed to make block (0, 0) a building block")
        XCTAssertEqual(first, second)
        XCTAssertEqual(second, third)
    }

    func test_generate_sameSeedSameLot_alwaysPicksTheSameSprite_acrossManyBlocksAndSeeds() {
        // A denser sweep than the single-block test above: every lot in a
        // handful of (seed, block) combinations must resolve to the same
        // `BuildingCatalog.Entry` no matter how many times it's asked.
        let seeds: [WorldSeed] = [
            WorldSeed(rawValue: 1), WorldSeed(rawValue: 42), WorldSeed(rawValue: 999), WorldSeed(rawValue: 31_337)
        ]
        let blocks = [
            BlockCoordinate(x: 0, y: 0),
            BlockCoordinate(x: 5, y: -3),
            BlockCoordinate(x: -7, y: 12)
        ]

        for seed in seeds {
            for block in blocks {
                let first = BuildingPlacement.generate(forBlock: block, seed: seed)
                let second = BuildingPlacement.generate(forBlock: block, seed: seed)
                XCTAssertEqual(
                    first, second,
                    "Block \(block) under seed \(seed.rawValue) produced different results on repeated calls"
                )

                // Same lot, looked up by tile, must agree between the two
                // independently-generated arrays.
                let firstByLot = Dictionary(uniqueKeysWithValues: first.map { ($0.lotTile, $0.building.index) })
                let secondByLot = Dictionary(uniqueKeysWithValues: second.map { ($0.lotTile, $0.building.index) })
                XCTAssertEqual(firstByLot, secondByLot)
            }
        }
    }

    // MARK: - Lattice agreement

    func test_generate_isEmpty_forAnEmptyLotBlock() {
        let seed = seedWithEmptyLotBlock(x: 0, y: 0)
        let placements = BuildingPlacement.generate(forBlock: BlockCoordinate(x: 0, y: 0), seed: seed)
        XCTAssertTrue(placements.isEmpty, "An empty-lot block must never receive a building")
    }

    func test_generate_buildingBlock_fillsEveryLotOfTheInterior() {
        let seed = seedWithBuildingBlock(x: 0, y: 0)
        let placements = BuildingPlacement.generate(forBlock: BlockCoordinate(x: 0, y: 0), seed: seed)

        let coveredTiles = Set(placements.flatMap(\.footprintTiles))
        XCTAssertEqual(
            coveredTiles.count,
            CityLatticeGenerator.blockSize * CityLatticeGenerator.blockSize,
            "A building block's whole 3x3 interior must be covered by some building's footprint"
        )
    }

    /// The test above proves full 3x3 coverage for exactly one
    /// `(seed, block)` pair, and the invariant it checks is held up entirely
    /// by the 2x2-doesn't-fit fallback — the path most likely to leave a lot
    /// uncovered, and the one a single sample is least likely to exercise.
    /// So sweep it across the same seed/block matrix
    /// `BuildingFootprintOverlapTests` already uses.
    func test_generate_everyBuildingBlock_fillsAllNineLots_acrossTheSameSeedAndBlockMatrixAsTheOverlapSweep() {
        let seeds: [WorldSeed] = [
            WorldSeed(rawValue: 0), WorldSeed(rawValue: 1), WorldSeed(rawValue: 7), WorldSeed(rawValue: 42),
            WorldSeed(rawValue: 999), WorldSeed(rawValue: 123_456), WorldSeed(rawValue: 31_337),
            WorldSeed(rawValue: 2_024)
        ]
        let blockRange = -6...6
        let interiorSize = CityLatticeGenerator.blockSize

        var buildingBlockCount = 0
        var observedFootprintSizes: Set<BuildingFootprintSize> = []

        for seed in seeds {
            for blockX in blockRange {
                for blockY in blockRange {
                    let block = BlockCoordinate(x: blockX, y: blockY)
                    let placements = BuildingPlacement.generate(forBlock: block, seed: seed)

                    guard !placements.isEmpty else {
                        XCTAssertTrue(
                            CityLatticeGenerator.isEmptyLotBlock(blockX: blockX, blockY: blockY, seed: seed),
                            "Block \(block) under seed \(seed.rawValue) got no buildings but is not an empty-lot "
                                + "block — a building block with no buildings is a hole in the city."
                        )
                        continue
                    }
                    buildingBlockCount += 1
                    observedFootprintSizes.formUnion(placements.map(\.building.footprintSize))

                    let interiorOrigin = block.interiorOrigin
                    var expectedTiles: Set<TileCoordinate> = []
                    for localX in 0..<interiorSize {
                        for localY in 0..<interiorSize {
                            expectedTiles.insert(
                                TileCoordinate(
                                    tileX: interiorOrigin.tileX + localX,
                                    tileY: interiorOrigin.tileY + localY
                                )
                            )
                        }
                    }

                    XCTAssertEqual(
                        Set(placements.flatMap(\.footprintTiles)),
                        expectedTiles,
                        "Block \(block) under seed \(seed.rawValue) does not have its 3x3 interior covered "
                            + "exactly — the 2x2 fallback left a lot empty or a footprint escaped the interior."
                    )
                }
            }
        }

        XCTAssertGreaterThan(buildingBlockCount, 500, "Sample too small to claim the invariant sweeps.")
        XCTAssertEqual(
            observedFootprintSizes,
            Set(BuildingFootprintSize.allCases),
            "The sweep never placed one of the two footprint sizes, so it did not exercise both paths."
        )
    }

    // MARK: - Footprint bookkeeping

    func test_generate_farCornerAndFootprintTiles_agreeWithTheChosenBuildingsSpan() {
        let seed = seedWithBuildingBlock(x: 0, y: 0)
        let placements = BuildingPlacement.generate(forBlock: BlockCoordinate(x: 0, y: 0), seed: seed)
        XCTAssertFalse(placements.isEmpty)

        for record in placements {
            let span = record.building.footprintSize.tileSpan
            XCTAssertEqual(record.footprintTiles.count, span * span)
            XCTAssertEqual(record.farCornerTile.tileX, record.lotTile.tileX + span - 1)
            XCTAssertEqual(record.farCornerTile.tileY, record.lotTile.tileY + span - 1)
            XCTAssertTrue(record.footprintTiles.contains(record.lotTile))
            XCTAssertTrue(record.footprintTiles.contains(record.farCornerTile))
        }
    }

    // MARK: - Helpers

    private func seedWithEmptyLotBlock(x: Int, y: Int) -> WorldSeed {
        for rawSeed in UInt64(0)..<500 {
            let seed = WorldSeed(rawValue: rawSeed)
            if CityLatticeGenerator.isEmptyLotBlock(blockX: x, blockY: y, seed: seed) {
                return seed
            }
        }
        XCTFail("Expected at least one seed in 0..<500 to make block (\(x), \(y)) an empty lot")
        return WorldSeed(rawValue: 0)
    }

    private func seedWithBuildingBlock(x: Int, y: Int) -> WorldSeed {
        for rawSeed in UInt64(0)..<500 {
            let seed = WorldSeed(rawValue: rawSeed)
            if !CityLatticeGenerator.isEmptyLotBlock(blockX: x, blockY: y, seed: seed) {
                return seed
            }
        }
        XCTFail("Expected at least one seed in 0..<500 to make block (\(x), \(y)) a building block")
        return WorldSeed(rawValue: 0)
    }
}
