import XCTest
@testable import CyberpunkMonsterCrawl

/// Pins `CityLatticeGenerator.classify`'s structural contract independent
/// of any specific seed: the 6-tile period, the always-street intersection
/// rule, the ~1-in-4 empty-lot ratio, and determinism.
///
/// `ConnectivityTests` covers the flood-fill guarantee that falls out of
/// these rules; this file pins the rules themselves (AC3, AC5, AC6, AC7).
final class CityLatticeGeneratorTests: XCTestCase {

    private let streetKinds: Set<TileKind> = [.asphalt, .junctionStopLine, .kerbSidewalk]
    private let blockInteriorKinds: Set<TileKind> = [.lot, .buildingFootprint]

    /// Local, source-independent re-derivation of "is this coordinate in
    /// the street band" from the ticket's stated constants (6-tile period,
    /// 3-tile block, 3-tile corridor) \u2014 deliberately not calling into any
    /// generator internals, so this pins the *contract* rather than
    /// mirroring the implementation.
    private func isStreetBand(_ coordinate: Int) -> Bool {
        let remainder = ((coordinate % 6) + 6) % 6
        return remainder >= 3
    }

    private func someSeeds(_ count: Int) -> [WorldSeed] {
        (0..<count).map { WorldSeed(rawValue: UInt64($0) &* 0x9E3779B9 &+ 1) }
    }

    // MARK: - AC3: 6-tile period

    func test_classify_streetPositions_areAlwaysStreetKinds_acrossManySeeds() {
        for seed in someSeeds(10) {
            for tileX in stride(from: -18, through: 18, by: 1) {
                for tileY in stride(from: -18, through: 18, by: 1) {
                    guard isStreetBand(tileX) || isStreetBand(tileY) else { continue }
                    let info = CityLatticeGenerator.classify(tileX: tileX, tileY: tileY, seed: seed)
                    XCTAssertTrue(
                        streetKinds.contains(info.kind),
                        "(\(tileX), \(tileY)) under seed \(seed.rawValue) should be a street kind, got \(info.kind)"
                    )
                }
            }
        }
    }

    func test_classify_blockInteriorPositions_areAlwaysBlockInteriorKinds_acrossManySeeds() {
        for seed in someSeeds(10) {
            for tileX in stride(from: -18, through: 18, by: 1) {
                for tileY in stride(from: -18, through: 18, by: 1) {
                    guard !isStreetBand(tileX) && !isStreetBand(tileY) else { continue }
                    let info = CityLatticeGenerator.classify(tileX: tileX, tileY: tileY, seed: seed)
                    XCTAssertTrue(
                        blockInteriorKinds.contains(info.kind),
                        "(\(tileX), \(tileY)) under seed \(seed.rawValue) should be a block-interior kind, got \(info.kind)"
                    )
                }
            }
        }
    }

    // MARK: - AC5: intersection tiles are structurally always street

    func test_classify_intersectionTiles_areAlwaysStreetAndWalkable_regardlessOfSeed() {
        for seed in someSeeds(25) {
            for tileX in stride(from: -18, through: 18, by: 1) {
                for tileY in stride(from: -18, through: 18, by: 1) {
                    guard isStreetBand(tileX) && isStreetBand(tileY) else { continue }
                    let info = CityLatticeGenerator.classify(tileX: tileX, tileY: tileY, seed: seed)
                    XCTAssertTrue(
                        streetKinds.contains(info.kind),
                        "Intersection tile (\(tileX), \(tileY)) under seed \(seed.rawValue) was \(info.kind), not a street kind"
                    )
                    XCTAssertTrue(info.isWalkable)
                }
            }
        }
    }

    // MARK: - AC6: ~1-in-4 blocks are empty lots

    func test_classify_emptyLotBlockRatio_isApproximatelyOneInFour_acrossManySeeds() {
        let seeds: [WorldSeed] = (0..<30).map { WorldSeed(rawValue: UInt64($0) &* 104_729 &+ 17) }
        var totalBlocks = 0
        var emptyLotBlocks = 0

        for seed in seeds {
            for blockX in -20..<20 {
                for blockY in -20..<20 {
                    // Sample the block's local (0, 0) corner tile \u2014 every
                    // interior tile of a block shares the same decision,
                    // which the consistency test below pins directly.
                    let tileX = blockX * CityLatticeGenerator.period
                    let tileY = blockY * CityLatticeGenerator.period
                    let info = CityLatticeGenerator.classify(tileX: tileX, tileY: tileY, seed: seed)
                    totalBlocks += 1
                    if info.kind == .lot {
                        emptyLotBlocks += 1
                    }
                }
            }
        }

        let ratio = Double(emptyLotBlocks) / Double(totalBlocks)
        XCTAssertEqual(
            ratio, 0.25, accuracy: 0.03,
            "Empty-lot ratio drifted from ~1-in-4: \(ratio) over \(totalBlocks) blocks"
        )
    }

    /// The seed decides per *block*, not per tile \u2014 every interior tile of
    /// one block must agree.
    func test_classify_allInteriorTilesOfABlock_shareTheSameDecision() {
        let seed = WorldSeed(rawValue: 424_242)

        for blockX in -5..<5 {
            for blockY in -5..<5 {
                var kinds: Set<TileKind> = []
                for localX in 0..<CityLatticeGenerator.blockSize {
                    for localY in 0..<CityLatticeGenerator.blockSize {
                        let tileX = blockX * CityLatticeGenerator.period + localX
                        let tileY = blockY * CityLatticeGenerator.period + localY
                        let info = CityLatticeGenerator.classify(tileX: tileX, tileY: tileY, seed: seed)
                        kinds.insert(info.kind)
                    }
                }
                XCTAssertEqual(kinds.count, 1, "Block (\(blockX), \(blockY)) has mixed interior kinds: \(kinds)")
            }
        }
    }

    // MARK: - AC7: deterministic, side-effect free

    func test_classify_calledTwiceForSameInput_returnsIdenticalOutput() {
        let seed = WorldSeed(rawValue: 987_654_321)

        for tileX in stride(from: -10, through: 10, by: 1) {
            for tileY in stride(from: -10, through: 10, by: 1) {
                let first = CityLatticeGenerator.classify(tileX: tileX, tileY: tileY, seed: seed)
                let second = CityLatticeGenerator.classify(tileX: tileX, tileY: tileY, seed: seed)
                XCTAssertEqual(first, second, "classify was not deterministic at (\(tileX), \(tileY))")
            }
        }
    }

    func test_classify_differentSeeds_canProduceDifferentBlockDecisions() {
        // Not a hard guarantee for any single block, but across many
        // blocks and two different seeds, at least one decision must
        // differ \u2014 otherwise the seed isn't actually driving anything.
        let seedA = WorldSeed(rawValue: 1)
        let seedB = WorldSeed(rawValue: 2)
        var anyDifference = false

        outer: for blockX in 0..<20 {
            for blockY in 0..<20 {
                let tileX = blockX * CityLatticeGenerator.period
                let tileY = blockY * CityLatticeGenerator.period
                let a = CityLatticeGenerator.classify(tileX: tileX, tileY: tileY, seed: seedA)
                let b = CityLatticeGenerator.classify(tileX: tileX, tileY: tileY, seed: seedB)
                if a.kind != b.kind {
                    anyDifference = true
                    break outer
                }
            }
        }

        XCTAssertTrue(anyDifference, "Two different seeds produced identical block decisions everywhere sampled")
    }
}
