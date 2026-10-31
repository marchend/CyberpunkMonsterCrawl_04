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

    // MARK: - Intersection sub-classification

    /// The sub-kind inside a 3x3 crossing is a data-model decision the
    /// ground-plane renderer cannot undo, so it is pinned here by name:
    /// centre = driving lane, the four mouths = painted stop line, the four
    /// corners = the sidewalk band continuing through the junction. Swept
    /// over crossings on both sides of the origin (period offsets are
    /// hard-coded from the ticket's stated 6/3 constants, deliberately not
    /// read off the generator).
    func test_classify_crossing_pinsCentreLaneMouthAndCornerSubKinds() {
        // Local (0, 0) of the 3x3 crossing block: tile (3, 3) modulo the
        // 6-tile period. `-3` and `-9` exercise the negative-side `mod()`
        // phase, `3` and `9` the positive side.
        let crossingOrigins = [(3, 3), (3, -3), (-3, 3), (-3, -3), (9, -9), (-9, 9)]

        /// Local, source-independent floor division \u2014 mirrors
        /// `CityLatticeGenerator`'s private `floorDiv`, needed here to
        /// derive which block a crossing corner borders (see
        /// `expectedKind`'s corner case) without reaching into the
        /// generator's internals.
        func localFloorDiv(_ value: Int, _ divisor: Int) -> Int {
            let quotient = value / divisor
            let remainder = value % divisor
            if remainder != 0 && (remainder < 0) != (divisor < 0) {
                return quotient - 1
            }
            return quotient
        }

        /// Expected kind per (xBandPosition, yBandPosition) inside a
        /// crossing. A corner's kind now depends on whether the one block
        /// interior it borders has a building edge to kerb
        /// (`CityLatticeGenerator.isEmptyLotBlock`) \u2014 this is the
        /// CYBERPUN-17-22 fix: an empty-lot-bordering corner reads as
        /// `.asphalt`, not an unconditional `.kerbSidewalk`.
        func expectedKind(tileX: Int, tileY: Int, xBand: Int, yBand: Int, seed: WorldSeed) -> TileKind {
            let xIsLane = (xBand == 1)
            let yIsLane = (yBand == 1)
            if xIsLane && yIsLane { return .asphalt }
            if xIsLane || yIsLane { return .junctionStopLine }
            let blockX = localFloorDiv(tileX, 6) + (xBand == 2 ? 1 : 0)
            let blockY = localFloorDiv(tileY, 6) + (yBand == 2 ? 1 : 0)
            let isEmpty = CityLatticeGenerator.isEmptyLotBlock(blockX: blockX, blockY: blockY, seed: seed)
            return isEmpty ? .asphalt : .kerbSidewalk
        }

        for seed in someSeeds(5) {
            for (originX, originY) in crossingOrigins {
                for xBand in 0..<3 {
                    for yBand in 0..<3 {
                        let tileX = originX + xBand
                        let tileY = originY + yBand
                        let info = CityLatticeGenerator.classify(tileX: tileX, tileY: tileY, seed: seed)

                        XCTAssertTrue(
                            isStreetBand(tileX) && isStreetBand(tileY),
                            "(\(tileX), \(tileY)) was expected to be a crossing tile - check the test's offsets"
                        )
                        XCTAssertEqual(
                            info.kind,
                            expectedKind(tileX: tileX, tileY: tileY, xBand: xBand, yBand: yBand, seed: seed),
                            "Crossing tile (\(tileX), \(tileY)) [band (\(xBand), \(yBand))] under seed "
                                + "\(seed.rawValue) was \(info.kind)"
                        )
                    }
                }
            }
        }
    }

    /// CYBERPUN-17-22: the ring of street-band edge/corner tiles
    /// immediately surrounding one block interior all border *that same*
    /// block (by construction of the band-position offsets), so the ring
    /// must be uniformly `.kerbSidewalk` when the block has a building
    /// edge to kerb (`.buildingFootprint`) and uniformly `.asphalt` when
    /// the block is an empty `.lot` with nothing to kerb \u2014 never an
    /// unconditional sidewalk ring regardless of what the block holds.
    func test_classify_sidewalkRingAroundABlockInterior_matchesItsOwnBuildingFootprintState() {
        let seed = WorldSeed(rawValue: 31_337)
        var sawLotRing = false
        var sawBuildingRing = false

        for blockX in -2..<2 {
            for blockY in -2..<2 {
                // Block interior spans local 0...2; the ring is local -1
                // and 3 on each axis (6-tile period, 3-tile block).
                let originX = blockX * 6
                let originY = blockY * 6
                let isEmptyLot = CityLatticeGenerator.isEmptyLotBlock(blockX: blockX, blockY: blockY, seed: seed)
                let expected: TileKind = isEmptyLot ? .asphalt : .kerbSidewalk
                if isEmptyLot {
                    sawLotRing = true
                } else {
                    sawBuildingRing = true
                }

                for local in -1...3 {
                    let ringTiles = [
                        (originX + local, originY - 1),
                        (originX + local, originY + 3),
                        (originX - 1, originY + local),
                        (originX + 3, originY + local)
                    ]
                    for (tileX, tileY) in ringTiles {
                        let info = CityLatticeGenerator.classify(tileX: tileX, tileY: tileY, seed: seed)
                        XCTAssertEqual(
                            info.kind, expected,
                            "Ring tile (\(tileX), \(tileY)) around block (\(blockX), \(blockY)) was \(info.kind), "
                                + "expected \(expected) to match the block's own building-footprint state"
                        )
                    }
                }
            }
        }

        XCTAssertTrue(sawLotRing, "Test fixture sampled no empty-lot block - strengthen the seed/range")
        XCTAssertTrue(
            sawBuildingRing,
            "Test fixture sampled no building-footprint block - strengthen the seed/range"
        )
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

    // MARK: - CYBERPUN-17-26 regression: kerb tiles are never floating

    /// The 8 neighbour offsets (orthogonal + diagonal) a kerb tile is
    /// checked against below \u2014 a lattice-crossing corner tile only ever
    /// touches the block it kerbs *diagonally*, never orthogonally (it sits
    /// one tile off on both axes from the block's own corner tile), so
    /// 4-connectivity alone would under-report and fail every legitimate
    /// corner.
    private var neighborOffsets: [(Int, Int)] {
        [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)]
    }

    /// Black-box regression for CYBERPUN-17-26 (\"building sidewalks not
    /// rendered correctly\" \u2014 stray `.kerbSidewalk` squares reported with no
    /// building actually next to them). Independently proves the ticket's
    /// literal acceptance criterion by calling `classify` on a tile's
    /// *actual* neighbouring coordinates, rather than re-deriving
    /// `blockBorderedByEdge`'s internal block-index arithmetic the way
    /// `test_classify_crossing_pinsCentreLaneMouthAndCornerSubKinds` and
    /// `test_classify_sidewalkRingAroundABlockInterior_matchesItsOwnBuildingFootprintState`
    /// do above. A regression that broke the adjacency guarantee while still
    /// agreeing with itself on those two self-referential tests would still
    /// be caught here, because this test never consults the generator's
    /// internal formula \u2014 only its public output at real neighbour tiles.
    func test_everyKerbSidewalkTile_hasAnActualBuildingFootprintNeighbor_acrossManySeeds() {
        var sawAnyKerbTile = false

        for seed in someSeeds(8) {
            for tileX in stride(from: -24, through: 24, by: 1) {
                for tileY in stride(from: -24, through: 24, by: 1) {
                    let info = CityLatticeGenerator.classify(tileX: tileX, tileY: tileY, seed: seed)
                    guard info.kind == .kerbSidewalk else { continue }
                    sawAnyKerbTile = true

                    let hasBuildingNeighbor = neighborOffsets.contains { dx, dy in
                        CityLatticeGenerator.classify(
                            tileX: tileX + dx, tileY: tileY + dy, seed: seed
                        ).kind == .buildingFootprint
                    }

                    XCTAssertTrue(
                        hasBuildingNeighbor,
                        "(\(tileX), \(tileY)) under seed \(seed.rawValue) rendered .kerbSidewalk with no "
                            + ".buildingFootprint tile among its 8 neighbours - a floating sidewalk square."
                    )
                }
            }
        }

        XCTAssertTrue(sawAnyKerbTile, "Test fixture sampled no .kerbSidewalk tile at all - strengthen the range/seed")
    }

    /// The sibling half of the same acceptance criterion: a street edge or
    /// lattice-crossing corner bordering a block the seed chose to leave as
    /// an empty `.lot` must never read as `.kerbSidewalk`, independent of
    /// which specific edge/corner position it is. Picks fixture coordinates
    /// via `isEmptyLotBlock` but never uses it to compute the *expected*
    /// kind \u2014 the expectation checked here is simply \"never kerb\", not a
    /// restatement of the generator's own formula.
    func test_streetEdgesAndCornersBorderingAnEmptyLotBlock_neverRenderAsKerbSidewalk() {
        let seed = WorldSeed(rawValue: 2024)
        var sawEmptyLotBlock = false

        for blockX in -6..<6 {
            for blockY in -6..<6 {
                guard CityLatticeGenerator.isEmptyLotBlock(blockX: blockX, blockY: blockY, seed: seed) else {
                    continue
                }
                sawEmptyLotBlock = true

                let originX = blockX * CityLatticeGenerator.period
                let originY = blockY * CityLatticeGenerator.period

                for local in -1...3 {
                    let ringTiles = [
                        (originX + local, originY - 1),
                        (originX + local, originY + 3),
                        (originX - 1, originY + local),
                        (originX + 3, originY + local)
                    ]
                    for (tileX, tileY) in ringTiles {
                        let info = CityLatticeGenerator.classify(tileX: tileX, tileY: tileY, seed: seed)
                        XCTAssertNotEqual(
                            info.kind, .kerbSidewalk,
                            "(\(tileX), \(tileY)) borders empty-lot block (\(blockX), \(blockY)) but rendered "
                                + ".kerbSidewalk - an empty lot has nothing to kerb."
                        )
                    }
                }
            }
        }

        XCTAssertTrue(sawEmptyLotBlock, "Test fixture sampled no empty-lot block - strengthen the seed/range")
    }
}
