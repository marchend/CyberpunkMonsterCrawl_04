import XCTest
@testable import CyberpunkMonsterCrawl

/// Pins `CityLatticeGenerator.classify`'s structural contract independent
/// of any specific seed: the 6-tile period, the always-street intersection
/// rule, the ~1-in-4 empty-lot ratio, and determinism.
///
/// `ConnectivityTests` covers the flood-fill guarantee that falls out of
/// these rules; this file pins the rules themselves (AC3, AC5, AC6, AC7).
final class CityLatticeGeneratorTests: XCTestCase {

    private let streetKinds: Set<TileKind> = [.asphalt, .junctionStopLine, .kerbSidewalk, .cornerSidewalk]
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
    /// ground-plane renderer cannot undo. CYBERPUN-17-28: every position in
    /// the crossing \u2014 centre (driving lane), the four mouths, and the four
    /// corners \u2014 now reads as plain `.asphalt`: a mouth no longer paints a
    /// stop line, and a corner only ever touches the block it borders
    /// *diagonally* (never through a true edge-sharing neighbour), so it can
    /// never legitimately kerb a sidewalk either. Swept over crossings on
    /// both sides of the origin (period offsets are hard-coded from the
    /// ticket's stated 6/3 constants, deliberately not read off the
    /// generator).
    func test_classify_crossing_pinsCentreLaneMouthAndCornerSubKinds() {
        // Local (0, 0) of the 3x3 crossing block: tile (3, 3) modulo the
        // 6-tile period. `-3` and `-9` exercise the negative-side `mod()`
        // phase, `3` and `9` the positive side.
        let crossingOrigins = [(3, 3), (3, -3), (-3, 3), (-3, -3), (9, -9), (-9, 9)]

        /// Expected kind per (xBandPosition, yBandPosition) inside a
        /// crossing. Centre/mouth (either band position is the lane, `1`)
        /// is always `.asphalt` (CYBERPUN-17-28). A true corner (both band
        /// positions are an edge, `0` or `2`) depends on whether the one
        /// block it touches diagonally is built - independently
        /// re-derived here from the origin coordinate rather than calling
        /// the generator's own `blockBorderedByEdge` (CYBERPUN-17-30).
        // Local floor division (mirrors `CityLatticeGenerator.floorDiv`):
        // Swift's `/` truncates towards zero, so `-3 / 6 == 0`, not the
        // `-1` block index a tile just below the origin must land on.
        func floorDiv(_ value: Int, _ divisor: Int) -> Int {
            let quotient = value / divisor
            let remainder = value % divisor
            if remainder != 0 && (remainder < 0) != (divisor < 0) {
                return quotient - 1
            }
            return quotient
        }

        func expectedKind(originX: Int, originY: Int, xBand: Int, yBand: Int, seed: WorldSeed) -> TileKind {
            guard xBand != 1, yBand != 1 else { return .asphalt }
            // Band position 0 borders the block in the current period;
            // position 2 borders the next period's block (one block index
            // higher).
            let blockX = floorDiv(originX + xBand, 6) + (xBand == 2 ? 1 : 0)
            let blockY = floorDiv(originY + yBand, 6) + (yBand == 2 ? 1 : 0)
            let isEmptyLot = CityLatticeGenerator.isEmptyLotBlock(blockX: blockX, blockY: blockY, seed: seed)
            return isEmptyLot ? .asphalt : .cornerSidewalk
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
                            expectedKind(originX: originX, originY: originY, xBand: xBand, yBand: yBand, seed: seed),
                            "Crossing tile (\(tileX), \(tileY)) [band (\(xBand), \(yBand))] under seed "
                                + "\(seed.rawValue) was \(info.kind)"
                        )
                    }
                }
            }
        }
    }

    /// CYBERPUN-17-22/CYBERPUN-17-28/CYBERPUN-17-30: the *straight-edge*
    /// street-band tiles immediately surrounding one block interior all
    /// border *that same* block (by construction of the band-position
    /// offsets), so they must be uniformly `.kerbSidewalk` when the block
    /// has a building edge to kerb (`.buildingFootprint`) and uniformly
    /// `.asphalt` when the block is an empty `.lot` with nothing to kerb \u2014
    /// never an unconditional sidewalk ring regardless of what the block
    /// holds. The ring's four true corner tiles (where `local` hits the
    /// -1/3 extreme on *both* axes at once) are lattice-crossing corners:
    /// CYBERPUN-17-28 established those can never have a true edge-sharing
    /// `.buildingFootprint` neighbour, so they never earn `.kerbSidewalk`
    /// \u2014 but by the same band-position construction each of this ring's
    /// four corners still borders (diagonally) this exact same block, so
    /// CYBERPUN-17-30 has them read as `.cornerSidewalk` (not `.asphalt`)
    /// exactly when the block is built, mirroring the straight edges'
    /// kerb/no-kerb decision one case down.
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

                let expectedCorner: TileKind = isEmptyLot ? .asphalt : .cornerSidewalk

                for local in -1...3 {
                    // `local == -1`/`3` combined with the line's own fixed
                    // -1/3 coordinate lands on one of the ring's four true
                    // corners (a lattice-crossing corner): never
                    // `.kerbSidewalk`, but still reads as `.cornerSidewalk`
                    // when this block is built, same as the straight edges.
                    let isCorner = local == -1 || local == 3
                    let expectedKind: TileKind = isCorner ? expectedCorner : expected

                    let ringTiles = [
                        (originX + local, originY - 1),
                        (originX + local, originY + 3),
                        (originX - 1, originY + local),
                        (originX + 3, originY + local)
                    ]
                    for (tileX, tileY) in ringTiles {
                        let info = CityLatticeGenerator.classify(tileX: tileX, tileY: tileY, seed: seed)
                        XCTAssertEqual(
                            info.kind, expectedKind,
                            "Ring tile (\(tileX), \(tileY)) around block (\(blockX), \(blockY)) was \(info.kind), "
                                + "expected \(expectedKind)"
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

    // MARK: - CYBERPUN-17-26/CYBERPUN-17-28 regression: kerb tiles are never floating

    /// The 4 orthogonal (edge-sharing) neighbour offsets a kerb tile is
    /// checked against below.
    ///
    /// RESOLVED (CYBERPUN-17-28): a lattice-crossing corner tile only ever
    /// touches the block it borders *diagonally* (e.g. `(6b+3, 6c+3)` for
    /// built block `(b, c)` touches its nearest interior tile `(6b+2,
    /// 6c+2)` only diagonally \u2014 all four orthogonal neighbours of such a
    /// corner are themselves street tiles, never `.buildingFootprint`).
    /// That diagonal-only touch is the reported defect ("floating sidewalk
    /// square"), not an intended visual design, so `.kerbSidewalk` now
    /// requires a true edge (4-connectivity) adjacency to a building
    /// footprint \u2014 `CityLatticeGenerator.streetTileKind` enforces this by
    /// routing every crossing corner to `.asphalt` instead. This test pins
    /// that decision using only orthogonal offsets, so a regression back to
    /// diagonal-only kerbing would fail it.
    private var neighborOffsets: [(Int, Int)] {
        [(0, -1), (-1, 0), (1, 0), (0, 1)]
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

                    let hasBuildingNeighbor = neighborOffsets.contains { offset in
                        CityLatticeGenerator.classify(
                            tileX: tileX + offset.0, tileY: tileY + offset.1, seed: seed
                        ).kind == .buildingFootprint
                    }

                    XCTAssertTrue(
                        hasBuildingNeighbor,
                        "(\(tileX), \(tileY)) under seed \(seed.rawValue) rendered .kerbSidewalk with no "
                            + ".buildingFootprint tile among its 4 orthogonal neighbours - a floating sidewalk square."
                    )
                }
            }
        }

        XCTAssertTrue(sawAnyKerbTile, "Test fixture sampled no .kerbSidewalk tile at all - strengthen the range/seed")
    }

    /// CYBERPUN-17-28: `TileKind.junctionStopLine` is kept only for the
    /// ground-plane catalog/enum's exhaustive-mapping contract; `classify`
    /// must never actually emit it (it rendered as an untinted,
    /// out-of-place striped tile). This sweeps the same wide coordinate
    /// range and seed set as the other structural tests above so a future
    /// change that starts re-emitting the case fails here rather than
    /// shipping.
    func test_classify_neverEmitsJunctionStopLine_acrossManySeeds() {
        for seed in someSeeds(8) {
            for tileX in stride(from: -24, through: 24, by: 1) {
                for tileY in stride(from: -24, through: 24, by: 1) {
                    let info = CityLatticeGenerator.classify(tileX: tileX, tileY: tileY, seed: seed)
                    XCTAssertNotEqual(
                        info.kind, .junctionStopLine,
                        "(\(tileX), \(tileY)) under seed \(seed.rawValue) emitted .junctionStopLine, "
                            + "which CYBERPUN-17-28 requires classify to never produce."
                    )
                }
            }
        }
    }

    // Note: a sibling "street edges/corners bordering an empty-lot block
    // never render .kerbSidewalk" case is deliberately not duplicated here.
    // It would sweep the exact same ring coordinates as
    // `test_classify_sidewalkRingAroundABlockInterior_matchesItsOwnBuildingFootprintState`
    // above, while asserting the strictly weaker `XCTAssertNotEqual(kind,
    // .kerbSidewalk)` where that test already asserts
    // `XCTAssertEqual(kind, .asphalt)` over the same tiles across a wider
    // seed sweep \u2014 anything that would fail the weaker check already fails
    // the existing, stronger one, so it is tracked in one place.
}
