import XCTest
@testable import CyberpunkMonsterCrawl

/// Covers this PR's two load-bearing pieces of new engineering:
///
/// - **AC2 (chunk-boundary agreement):** a tile generated as part of a
///   chunk must be identical to the same world tile generated standalone
///   via `CityLatticeGenerator.classify`. Per `CityLatticeGenerator`'s own
///   docs this is true *by construction* (it is a pure function of
///   `(tileX, tileY, seed)` with no neighbour lookups), so this test is
///   deliberately a thin wrapper assertion rather than a search for subtle
///   bugs \u2014 exactly as the ticket's implementation notes describe.
/// - **Lot-reservation no-overlap:** `Chunk.reserve` must refuse a footprint
///   that would overlap an already-reserved one, and must still allow a
///   genuinely disjoint reservation to succeed.
final class ChunkGeneratorTests: XCTestCase {

    // MARK: - AC2: chunk-embedded generation agrees with standalone `classify`

    func test_chunkTiles_matchStandaloneClassify_atChunkEdgesAcrossMultipleChunkPairs() {
        let seeds: [WorldSeed] = [WorldSeed(rawValue: 1), WorldSeed(rawValue: 999_999), WorldSeed(rawValue: 42)]
        let chunkCoordinates = [
            ChunkCoordinate(x: 0, y: 0),
            ChunkCoordinate(x: 1, y: 0),
            ChunkCoordinate(x: 0, y: 1),
            ChunkCoordinate(x: -1, y: 0),
            ChunkCoordinate(x: 0, y: -1),
            ChunkCoordinate(x: -1, y: -1),
            ChunkCoordinate(x: 3, y: -2)
        ]

        for seed in seeds {
            for chunkCoordinate in chunkCoordinates {
                let chunk = ChunkGenerator.generate(chunkCoordinate: chunkCoordinate, seed: seed)
                let origin = chunkCoordinate.worldTileOrigin

                // Every edge/corner local coordinate: (0, 0) is where this
                // chunk sits directly against its lower-index neighbours;
                // (size-1, size-1) is where it sits against its
                // higher-index neighbours. Together with the two mixed
                // corners, this exercises every boundary this chunk shares.
                let edgeLocalCoordinates = [
                    (0, 0), (Chunk.size - 1, Chunk.size - 1),
                    (0, Chunk.size - 1), (Chunk.size - 1, 0),
                    (7, 3), (3, 7)
                ]

                for (localX, localY) in edgeLocalCoordinates {
                    let embedded = chunk.tile(localX: localX, localY: localY)
                    let standalone = CityLatticeGenerator.classify(
                        tileX: origin.tileX + localX,
                        tileY: origin.tileY + localY,
                        seed: seed
                    )
                    XCTAssertEqual(
                        embedded, standalone,
                        "Chunk \(chunkCoordinate) local (\(localX), \(localY)) under seed \(seed.rawValue) "
                            + "disagreed with standalone classify"
                    )
                }
            }
        }
    }

    func test_chunkTiles_matchStandaloneClassify_everyTileInChunk() {
        // A denser sweep than the edges-only test above: every one of the
        // 64 tiles in a handful of chunks, so a bug that only shows up mid-
        // chunk (not just at the boundary) would still be caught.
        let seed = WorldSeed(rawValue: 31_337)
        let chunkCoordinates = [ChunkCoordinate(x: 0, y: 0), ChunkCoordinate(x: -2, y: 5)]

        for chunkCoordinate in chunkCoordinates {
            let chunk = ChunkGenerator.generate(chunkCoordinate: chunkCoordinate, seed: seed)
            let origin = chunkCoordinate.worldTileOrigin

            for localX in 0..<Chunk.size {
                for localY in 0..<Chunk.size {
                    let embedded = chunk.tile(localX: localX, localY: localY)
                    let standalone = CityLatticeGenerator.classify(
                        tileX: origin.tileX + localX,
                        tileY: origin.tileY + localY,
                        seed: seed
                    )
                    XCTAssertEqual(embedded, standalone)
                }
            }
        }
    }

    // MARK: - Lot reservation: no overlap

    /// Finds the first `WorldSeed` (from a fixed candidate list) under
    /// which block `(blockX: 0, blockY: 0)` \u2014 world tiles `(0...2, 0...2)`,
    /// fully inside chunk `(0, 0)` \u2014 is an empty lot, so this test has a
    /// guaranteed 3x3 patch of `.lot` tiles to reserve against rather than
    /// depending on luck with a single hardcoded seed.
    private func seedWithEmptyLotAtOriginBlock() -> WorldSeed {
        for rawSeed in UInt64(0)..<500 {
            let seed = WorldSeed(rawValue: rawSeed)
            if CityLatticeGenerator.isEmptyLotBlock(blockX: 0, blockY: 0, seed: seed) {
                return seed
            }
        }
        XCTFail("Expected at least one seed in 0..<500 to make block (0, 0) an empty lot")
        return WorldSeed(rawValue: 0)
    }

    func test_reserve_twoByTwoFootprint_blocksOverlappingReservations_butAllowsDisjointOnes() {
        let seed = seedWithEmptyLotAtOriginBlock()
        let chunk = ChunkGenerator.generate(chunkCoordinate: ChunkCoordinate(x: 0, y: 0), seed: seed)

        // Sanity: the 3x3 block interior this test relies on is really
        // `.lot` under this seed.
        for tileX in 0..<3 {
            for tileY in 0..<3 {
                XCTAssertEqual(chunk.tile(localX: tileX, localY: tileY).kind, .lot)
            }
        }

        // First reservation: a 2x2 footprint at the block's corner succeeds.
        XCTAssertTrue(chunk.reserve(footprint: .twoByTwo, at: TileCoordinate(tileX: 0, tileY: 0)))

        // Any footprint overlapping the tiles just claimed (0,0)-(1,1) must
        // be refused, whether it's a 1x1 fully inside it or a 2x2 that only
        // partially overlaps it.
        XCTAssertFalse(
            chunk.reserve(footprint: .oneByOne, at: TileCoordinate(tileX: 1, tileY: 1)),
            "A 1x1 footprint inside an already-reserved 2x2 must be refused"
        )
        XCTAssertFalse(
            chunk.reserve(footprint: .twoByTwo, at: TileCoordinate(tileX: 1, tileY: 0)),
            "A 2x2 footprint overlapping an already-reserved 2x2 must be refused"
        )

        // A genuinely disjoint 1x1 footprint elsewhere in the same lot
        // block must still succeed \u2014 refusing overlaps must not turn into
        // refusing everything.
        XCTAssertTrue(
            chunk.reserve(footprint: .oneByOne, at: TileCoordinate(tileX: 2, tileY: 2)),
            "A footprint disjoint from the existing reservation should be allowed"
        )
    }

    func test_reservableFootprints_excludesTilesCoveredByAnExistingReservation() {
        let seed = seedWithEmptyLotAtOriginBlock()
        let chunk = ChunkGenerator.generate(chunkCoordinate: ChunkCoordinate(x: 0, y: 0), seed: seed)

        let beforeReservation = Set(chunk.reservableFootprints(in: .oneByOne))
        XCTAssertTrue(beforeReservation.contains(TileCoordinate(tileX: 1, tileY: 1)))

        XCTAssertTrue(chunk.reserve(footprint: .twoByTwo, at: TileCoordinate(tileX: 0, tileY: 0)))

        let afterReservation = Set(chunk.reservableFootprints(in: .oneByOne))
        XCTAssertFalse(
            afterReservation.contains(TileCoordinate(tileX: 1, tileY: 1)),
            "A tile already claimed by a reservation must not still be offered as reservable"
        )
        XCTAssertTrue(
            afterReservation.contains(TileCoordinate(tileX: 2, tileY: 2)),
            "A tile outside the existing reservation, still .lot, must remain reservable"
        )
    }

    func test_reserve_refusesFootprintOnNonLotTile() {
        // Street tiles are structurally guaranteed at (3...5) mod 6 on
        // either axis regardless of seed, so tile (3, 0) is street under
        // every seed \u2014 no need to search for one.
        let seed = WorldSeed(rawValue: 12_345)
        let chunk = ChunkGenerator.generate(chunkCoordinate: ChunkCoordinate(x: 0, y: 0), seed: seed)

        XCTAssertNotEqual(chunk.tile(localX: 3, localY: 0).kind, .lot)
        XCTAssertFalse(chunk.reserve(footprint: .oneByOne, at: TileCoordinate(tileX: 3, tileY: 0)))
    }
}
