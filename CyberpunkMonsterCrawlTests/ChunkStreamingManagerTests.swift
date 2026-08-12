import XCTest
@testable import CyberpunkMonsterCrawl

/// Covers AC8: as a camera roams an unbounded world, `ChunkStreamingManager`
/// must keep the resident-chunk count within a fixed window at every step,
/// and a chunk that gets evicted and later revisited must regenerate
/// byte-for-byte identically to the pure `ChunkGenerator`/`CityLatticeGenerator`
/// output \u2014 streaming must never be observable as a change in world content.
final class ChunkStreamingManagerTests: XCTestCase {

    private let seed = WorldSeed(rawValue: 2_024)

    // MARK: - AC8: bounded resident-chunk window

    func test_residentChunkCount_neverExceedsFixedWindow_duringLongStraightSweep() {
        let manager = ChunkStreamingManager(seed: seed)

        for tileX in stride(from: -300, through: 300, by: 5) {
            manager.updateCamera(worldPosition: TilePoint(x: Double(tileX), y: 0))
            XCTAssertLessThanOrEqual(
                manager.residentChunks.count, ChunkStreamingManager.residentWindowSize,
                "Resident chunk count exceeded the fixed window at camera tileX \(tileX)"
            )
        }
    }

    func test_residentChunkCount_neverExceedsFixedWindow_duringDiagonalSweep() {
        let manager = ChunkStreamingManager(seed: seed)

        for step in stride(from: -300, through: 300, by: 5) {
            manager.updateCamera(worldPosition: TilePoint(x: Double(step), y: Double(step)))
            XCTAssertLessThanOrEqual(
                manager.residentChunks.count, ChunkStreamingManager.residentWindowSize,
                "Resident chunk count exceeded the fixed window at diagonal step \(step)"
            )
        }
    }

    func test_residentChunkCount_atRest_equalsTheFullWindowSize() {
        // Far from any world edge (there is none \u2014 the world is
        // unbounded), a single `updateCamera` call should fill the entire
        // window in one shot.
        let manager = ChunkStreamingManager(seed: seed)
        manager.updateCamera(worldPosition: TilePoint(x: 1_000, y: -1_000))
        XCTAssertEqual(manager.residentChunks.count, ChunkStreamingManager.residentWindowSize)
    }

    func test_updateCamera_calledAgainAtTheSamePosition_loadsNothingNew() {
        let manager = ChunkStreamingManager(seed: seed)
        manager.updateCamera(worldPosition: TilePoint(x: 0, y: 0))
        let secondCallNewlyLoaded = manager.updateCamera(worldPosition: TilePoint(x: 0, y: 0))
        XCTAssertTrue(secondCallNewlyLoaded.isEmpty)
        XCTAssertEqual(manager.residentChunks.count, ChunkStreamingManager.residentWindowSize)
    }

    // MARK: - Evicted chunks regenerate identically to pure generation

    func test_evictedChunk_whenRevisited_regeneratesIdenticallyToPureChunkGeneration() {
        let manager = ChunkStreamingManager(seed: seed)
        let originChunkCoordinate = ChunkCoordinate(x: 0, y: 0)

        manager.updateCamera(worldPosition: TilePoint(x: 0, y: 0))
        XCTAssertNotNil(manager.residentChunks[originChunkCoordinate], "Expected the origin chunk to load initially")

        // Move far enough away (well beyond the resident radius, in tiles)
        // that the origin chunk is guaranteed to fall outside the window.
        let farOffset = Double((ChunkStreamingManager.residentRadius + 10) * Chunk.size)
        manager.updateCamera(worldPosition: TilePoint(x: farOffset, y: farOffset))
        XCTAssertNil(
            manager.residentChunks[originChunkCoordinate],
            "Expected the origin chunk to be evicted once the camera moved far away"
        )

        // Move back to the origin chunk.
        manager.updateCamera(worldPosition: TilePoint(x: 0, y: 0))
        guard let revisited = manager.residentChunks[originChunkCoordinate] else {
            XCTFail("Expected the origin chunk to be resident again after returning to it")
            return
        }

        let reference = ChunkGenerator.generate(chunkCoordinate: originChunkCoordinate, seed: seed)
        for localX in 0..<Chunk.size {
            for localY in 0..<Chunk.size {
                XCTAssertEqual(
                    revisited.tile(localX: localX, localY: localY),
                    reference.tile(localX: localX, localY: localY),
                    "Revisited chunk tile (\(localX), \(localY)) disagreed with pure regeneration"
                )
            }
        }
    }

    func test_evictedChunk_whenRevisited_matchesStandaloneClassifyDirectly() {
        // Same guarantee as above, but checked straight against
        // `CityLatticeGenerator.classify` rather than a second
        // `ChunkGenerator.generate` call \u2014 pinning the full chain
        // (streaming -> chunk generation -> pure per-tile classification)
        // end to end.
        let manager = ChunkStreamingManager(seed: seed)
        let farChunkCoordinate = ChunkCoordinate(x: 40, y: -40)
        let farOrigin = farChunkCoordinate.worldTileOrigin

        manager.updateCamera(worldPosition: TilePoint(x: Double(farOrigin.tileX), y: Double(farOrigin.tileY)))
        XCTAssertNotNil(manager.residentChunks[farChunkCoordinate])

        // Evict it by moving back to the world origin.
        manager.updateCamera(worldPosition: TilePoint(x: 0, y: 0))
        XCTAssertNil(manager.residentChunks[farChunkCoordinate])

        // Revisit.
        manager.updateCamera(worldPosition: TilePoint(x: Double(farOrigin.tileX), y: Double(farOrigin.tileY)))
        guard let revisited = manager.residentChunks[farChunkCoordinate] else {
            XCTFail("Expected the far chunk to be resident again after returning to it")
            return
        }

        for localX in 0..<Chunk.size {
            for localY in 0..<Chunk.size {
                let standalone = CityLatticeGenerator.classify(
                    tileX: farOrigin.tileX + localX,
                    tileY: farOrigin.tileY + localY,
                    seed: seed
                )
                XCTAssertEqual(revisited.tile(localX: localX, localY: localY), standalone)
            }
        }
    }

    // MARK: - Chunk coordinate mapping sanity (negative-axis safety)

    func test_chunkCoordinateContaining_isMonotonicAcrossTheOrigin() {
        // Regression guard for the floor-division pitfall
        // `CityLatticeGenerator.floorDiv`'s docs call out: a truncating `/`
        // would put both tile -1 and tile 0 in "chunk 0", colliding two
        // distinct chunks on the negative axis.
        XCTAssertEqual(ChunkCoordinate.containing(tileX: -1, tileY: 0).x, -1)
        XCTAssertEqual(ChunkCoordinate.containing(tileX: -8, tileY: 0).x, -1)
        XCTAssertEqual(ChunkCoordinate.containing(tileX: -9, tileY: 0).x, -2)
        XCTAssertEqual(ChunkCoordinate.containing(tileX: 0, tileY: 0).x, 0)
        XCTAssertEqual(ChunkCoordinate.containing(tileX: 7, tileY: 0).x, 0)
        XCTAssertEqual(ChunkCoordinate.containing(tileX: 8, tileY: 0).x, 1)
    }
}
