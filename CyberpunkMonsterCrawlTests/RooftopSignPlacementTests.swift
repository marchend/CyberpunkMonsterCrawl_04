import XCTest
@testable import CyberpunkMonsterCrawl

/// Covers this PR's rooftop-sign half of `CYBERPUN-17-5-t1` (AC7's
/// sign-placement slice):
///
/// - The observed signed-block ratio, sampled over a large region, is close
///   to 1-in-3 *among building blocks* (an empty block is never eligible at
///   all — `RooftopSignPlacement.generate`'s `placements.isEmpty` guard —
///   so the ratio is only meaningful measured against blocks that actually
///   have a building to carry a sign).
/// - No block ever carries more than one sign.
/// - Determinism: same seed + same block (+ its placements) yields the same
///   signed decision, carrier lot and sign cell.
final class RooftopSignPlacementTests: XCTestCase {

    // MARK: - ~1-in-3 signed-block ratio

    func test_signedBlockRatio_isCloseToOneInThree_amongBuildingBlocks() {
        // 10 seeds x a 40x40 block region each \u2014 the same "many seeds, wide
        // sample" shape `CityLatticeGeneratorTests`'s own ~1-in-4 ratio test
        // uses, so this ratio claim rests on a comparably large sample
        // (~12,000 building blocks after the lattice's own ~1-in-4 empty
        // blocks are excluded) rather than being tight on a small one.
        let seeds: [WorldSeed] = (0..<10).map { WorldSeed(rawValue: UInt64($0) &* 104_729 &+ 17) }
        var buildingBlockCount = 0
        var signedCount = 0

        for seed in seeds {
            for blockX in -20..<20 {
                for blockY in -20..<20 {
                    let block = BlockCoordinate(x: blockX, y: blockY)
                    let placements = BuildingPlacement.generate(forBlock: block, seed: seed)
                    guard !placements.isEmpty else { continue }
                    buildingBlockCount += 1
                    if RooftopSignPlacement.generate(forBlock: block, placements: placements, seed: seed) != nil {
                        signedCount += 1
                    }
                }
            }
        }

        XCTAssertGreaterThan(buildingBlockCount, 5_000, "Sample too small to make a reliable ratio claim")
        let ratio = Double(signedCount) / Double(buildingBlockCount)
        XCTAssertEqual(
            ratio, 1.0 / 3.0, accuracy: 0.03,
            "Expected ~1-in-3 building blocks to carry a rooftop sign, got \(ratio) "
                + "(\(signedCount)/\(buildingBlockCount))"
        )
    }

    func test_emptyLotBlock_isNeverSigned_regardlessOfTheDecisionRoll() {
        let seed = WorldSeed(rawValue: 1)

        for blockX in -50...50 {
            for blockY in -50...50 {
                guard CityLatticeGenerator.isEmptyLotBlock(blockX: blockX, blockY: blockY, seed: seed) else {
                    continue
                }
                let block = BlockCoordinate(x: blockX, y: blockY)
                let placements = BuildingPlacement.generate(forBlock: block, seed: seed)
                XCTAssertTrue(placements.isEmpty)
                XCTAssertNil(RooftopSignPlacement.generate(forBlock: block, placements: placements, seed: seed))
            }
        }
    }

    // MARK: - At most one sign per block

    func test_whenSigned_theRecordNamesALotThatActuallyHoldsABuilding_andAValidSignCell() {
        let seed = WorldSeed(rawValue: 55)

        for blockX in -20...20 {
            for blockY in -20...20 {
                let block = BlockCoordinate(x: blockX, y: blockY)
                let placements = BuildingPlacement.generate(forBlock: block, seed: seed)
                guard
                    let sign = RooftopSignPlacement.generate(forBlock: block, placements: placements, seed: seed)
                else {
                    continue
                }

                XCTAssertEqual(sign.block, block)
                XCTAssertTrue(
                    placements.contains { $0.lotTile == sign.carrierLotTile },
                    "Rooftop sign for block \(block) names a lot no placed building occupies"
                )
                XCTAssertTrue(
                    (0..<RooftopSignPlacement.signCellCount).contains(sign.signCellIndex),
                    "Sign cell index \(sign.signCellIndex) out of the sprite_signs atlas's 12-cell range"
                )
            }
        }
    }

    // MARK: - Determinism

    func test_generate_sameSeedSameBlock_yieldsTheSameSignedDecisionCarrierAndCell() {
        let seed = WorldSeed(rawValue: 77)
        let block = BlockCoordinate(x: 4, y: -3)
        let placements = BuildingPlacement.generate(forBlock: block, seed: seed)

        let first = RooftopSignPlacement.generate(forBlock: block, placements: placements, seed: seed)
        let second = RooftopSignPlacement.generate(forBlock: block, placements: placements, seed: seed)
        let third = RooftopSignPlacement.generate(forBlock: block, placements: placements, seed: seed)

        XCTAssertEqual(first, second)
        XCTAssertEqual(second, third)
    }

    func test_determinism_holdsAcrossManySeedsAndBlocks() {
        let seeds: [WorldSeed] = [
            WorldSeed(rawValue: 1), WorldSeed(rawValue: 42), WorldSeed(rawValue: 999), WorldSeed(rawValue: 31_337)
        ]
        let blocks = [
            BlockCoordinate(x: 0, y: 0),
            BlockCoordinate(x: 5, y: -3),
            BlockCoordinate(x: -7, y: 12),
            BlockCoordinate(x: 100, y: 100)
        ]

        for seed in seeds {
            for block in blocks {
                let placements = BuildingPlacement.generate(forBlock: block, seed: seed)
                let first = RooftopSignPlacement.generate(forBlock: block, placements: placements, seed: seed)
                let second = RooftopSignPlacement.generate(forBlock: block, placements: placements, seed: seed)
                XCTAssertEqual(
                    first, second,
                    "Block \(block) under seed \(seed.rawValue) disagreed with itself across repeated calls"
                )
            }
        }
    }
}
