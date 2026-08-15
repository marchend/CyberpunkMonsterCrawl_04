import XCTest
@testable import CyberpunkMonsterCrawl

/// Covers AC8: as a camera roams an unbounded world, `ChunkStreamingManager`
/// must keep the resident-chunk count within a fixed window at every step,
/// and a chunk that gets evicted and later revisited must regenerate
/// byte-for-byte identically to the pure `ChunkGenerator`/`CityLatticeGenerator`
/// output — streaming must never be observable as a change in world content.
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
        // Far from any world edge (there is none — the world is
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

    // MARK: - Worst-case viewport coverage (the claim, not just the bound)

    func test_residentWindow_coversTheReferenceViewport_inBothOrientations() {
        // The suite used to assert only the *upper* bound on residency, so
        // "the player never sees a chunk pop in at the edge" was prose. This
        // checks it, in the worst case (camera on its own chunk's edge) and in
        // both orientations, since bootstrap.md commits to portrait and
        // landscape.
        let viewport = ChunkStreamingManager.referenceViewportPoints

        XCTAssertTrue(
            ChunkStreamingManager.coversViewport(widthPoints: viewport.width, heightPoints: viewport.height),
            "Resident window must cover the reference landscape viewport in the worst case"
        )
        XCTAssertTrue(
            ChunkStreamingManager.coversViewport(widthPoints: viewport.height, heightPoints: viewport.width),
            "Resident window must cover the reference portrait viewport in the worst case"
        )
    }

    func test_guaranteedMargin_countsOnlyTheRingsBeyondTheCamerasOwnChunk() {
        // The margin is radius * chunk size, NOT half the window's width: the
        // camera may sit on the very edge of its own chunk, so that chunk
        // contributes no guaranteed margin.
        XCTAssertEqual(
            ChunkStreamingManager.guaranteedMarginTiles,
            ChunkStreamingManager.residentRadius * Chunk.size
        )

        // Why the radius was raised: the previous radius-2 window guaranteed
        // only 16 tiles, whose projected diamond does not contain the
        // reference viewport (the sum below exceeds 1). Spelled out with
        // literals so this stays a fact about the geometry even if the
        // constant changes again.
        let sixteenTileDiamondHalfWidth = 2.0 * 16.0 * IsometricProjection.tileHalfWidth
        let sixteenTileDiamondHalfHeight = 2.0 * 16.0 * IsometricProjection.tileHalfHeight
        let viewport = ChunkStreamingManager.referenceViewportPoints
        let fitAtSixteenTiles = (viewport.width / 2) / sixteenTileDiamondHalfWidth
            + (viewport.height / 2) / sixteenTileDiamondHalfHeight
        XCTAssertGreaterThan(
            fitAtSixteenTiles, 1,
            "A 16-tile guaranteed margin does not cover the reference viewport; the radius must exceed 2"
        )
        XCTAssertGreaterThanOrEqual(
            ChunkStreamingManager.guaranteedMarginTiles, 24,
            "The guaranteed margin must be large enough for the reference viewport"
        )
    }

    func test_coversViewport_isNotVacuouslyTrue() {
        // Anti-vacuity guard: a coverage predicate that always returns true
        // would make the assertions above meaningless.
        XCTAssertFalse(ChunkStreamingManager.coversViewport(widthPoints: 10_000, heightPoints: 10_000))
    }

    // MARK: - The quickstart ring's coverage claim is checked, not prose (CYBERPUN-17-4-t4)

    func test_quickstartRing_coversAPortraitPhoneViewport() {
        // `GroundPlaneStreamer` mounts only this ring synchronously and defers
        // everything beyond it, so the ring is what may already be on screen.
        // If it did not cover the viewport, the frames the drain takes would
        // show unpainted bands rather than a street. Portrait is the binding
        // case: iso tiles are 2:1, so the vertical axis dominates.
        let phone = ChunkStreamingManager.phoneViewportPoints

        XCTAssertTrue(
            ChunkStreamingManager.coversViewport(
                widthPoints: phone.width,
                heightPoints: phone.height,
                radius: ChunkStreamingManager.quickstartRadius
            ),
            "The quickstart ring must cover a portrait phone viewport in the worst case"
        )
        XCTAssertTrue(
            ChunkStreamingManager.coversViewport(
                widthPoints: phone.height,
                heightPoints: phone.width,
                radius: ChunkStreamingManager.quickstartRadius
            ),
            "The quickstart ring must cover the same phone viewport in landscape too"
        )
    }

    func test_quickstartRadius_isTheSmallestRadiusThatCoversAPortraitPhone() {
        // The other half of the claim on `quickstartRadius`: radius 1 (an
        // 8-tile guaranteed margin) does *not* cover a portrait phone
        // (196.5/768 + 426/384 = 1.37 > 1), which is why the constant is 2 and
        // not 1. Without this, "radius 2 covers" would be satisfiable by any
        // larger radius and the constant would drift upward unchecked.
        let phone = ChunkStreamingManager.phoneViewportPoints

        XCTAssertFalse(
            ChunkStreamingManager.coversViewport(
                widthPoints: phone.width,
                heightPoints: phone.height,
                radius: ChunkStreamingManager.quickstartRadius - 1
            ),
            "A radius one smaller than quickstartRadius should not cover the phone viewport"
        )
        XCTAssertEqual(
            ChunkStreamingManager.quickstartRadius, 2,
            "quickstartRadius is the smallest radius covering phoneViewportPoints"
        )
    }

    func test_quickstartRing_isStrictlySmallerThanTheResidentWindow() {
        // The ring only exists to bound the synchronous mount, so it must stay
        // well inside the resident window; if the two ever coincided, nothing
        // would be deferred and the PLAY-tap stall would be back.
        XCTAssertLessThan(ChunkStreamingManager.quickstartRadius, ChunkStreamingManager.residentRadius)

        let quickstartSide = ChunkStreamingManager.quickstartRadius * 2 + 1
        XCTAssertLessThan(quickstartSide * quickstartSide, ChunkStreamingManager.residentWindowSize)
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
        // `ChunkGenerator.generate` call — pinning the full chain
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

    // MARK: - Camera tile ownership uses the one pinned rounding rule

    func test_updateCamera_usesIsometricProjectionsPinnedOwnershipRule_notFloor() {
        // Tile-space x = 7.6 is owned by tile 8 under the repo's single pinned
        // rule (`IsometricProjection.tile(containing:)`, `floor(coord + 0.5)`),
        // which is chunk 1. A call site rolling its own `rounded(.down)` says
        // tile 7 / chunk 0 and slides the whole resident window one chunk away
        // from the camera. Pinned via chunks that can only be resident for one
        // of the two answers.
        let manager = ChunkStreamingManager(seed: seed)
        manager.updateCamera(worldPosition: TilePoint(x: 7.6, y: 0))

        let radius = ChunkStreamingManager.residentRadius
        XCTAssertNotNil(
            manager.residentChunks[ChunkCoordinate(x: 1 + radius, y: 0)],
            "Camera at tile-space 7.6 owns tile 8 (chunk 1), so the window's far edge is chunk 1 + radius"
        )
        XCTAssertNil(
            manager.residentChunks[ChunkCoordinate(x: -radius, y: 0)],
            "Chunk -radius is only resident if the camera's chunk was computed as 0, i.e. with a floor rule"
        )

        // And the boundary case just below the seam still resolves to chunk 0.
        let below = ChunkStreamingManager(seed: seed)
        below.updateCamera(worldPosition: TilePoint(x: 7.4, y: 0))
        XCTAssertNotNil(below.residentChunks[ChunkCoordinate(x: -radius, y: 0)])
        XCTAssertNil(below.residentChunks[ChunkCoordinate(x: 1 + radius, y: 0)])
    }

    // MARK: - Reservations survive eviction (not just tile content)

    func test_footprintReservation_survivesEvictionAndRevisit() {
        // The gap the tile-identity tests above cannot catch: tile content is
        // reproduced by `classify` on revisit, but a reservation is a
        // decision that cannot be re-derived. When it lived on the `Chunk`
        // instance, eviction destroyed it, so a building placed by
        // `CYBERPUN-17-5` would pop out whenever the camera circled away and
        // back. This asserts survival, not just tile equality.
        let manager = ChunkStreamingManager(seed: seed)

        manager.updateCamera(worldPosition: TilePoint(x: 0, y: 0))

        // `ChunkGenerator.generate` now folds every placed building's
        // footprint into the manager-owned store (`CYBERPUN-17-5-t1`), so the
        // reservations whose survival matters are the placed ones — and a
        // generated chunk no longer leaves a free placement-surface tile to
        // claim by hand, because buildings fill every lot of the blocks it
        // owns. Pick the first resident chunk that actually carries
        // footprints (deterministically, in chunk-coordinate order): the
        // lattice leaves ~1-in-4 blocks empty, so no single chunk is
        // guaranteed to hold buildings under every seed, and this test is
        // about survival rather than about which chunk.
        let residentInCoordinateOrder = manager.residentChunks
            .sorted { ($0.key.x, $0.key.y) < ($1.key.x, $1.key.y) }
        guard let entry = residentInCoordinateOrder.first(where: { !$0.value.reservedTiles.isEmpty }) else {
            XCTFail("Expected at least one resident chunk to carry a placed building footprint")
            return
        }
        let originChunkCoordinate = entry.key
        let chunk = entry.value

        guard let footprintTile = chunk.reservedTiles.sorted(by: {
            ($0.tileX, $0.tileY) < ($1.tileX, $1.tileY)
        }).first else {
            XCTFail("Expected the chosen chunk to place at least one building footprint")
            return
        }
        XCTAssertFalse(
            chunk.reserve(footprint: .oneByOne, at: footprintTile),
            "A tile a placed building stands on must not be reservable by anyone else"
        )

        // Evict it by moving well beyond the resident radius, then come back.
        let farOffset = Double((ChunkStreamingManager.residentRadius + 10) * Chunk.size)
        manager.updateCamera(worldPosition: TilePoint(x: farOffset, y: farOffset))
        XCTAssertNil(manager.residentChunks[originChunkCoordinate], "Expected the origin chunk to be evicted")
        XCTAssertTrue(
            manager.reservations.isReserved(footprintTile),
            "The store outlives the chunk instance — an evicted chunk must not take its reservations with it"
        )

        manager.updateCamera(worldPosition: TilePoint(x: 0, y: 0))
        guard let revisited = manager.residentChunks[originChunkCoordinate] else {
            XCTFail("Expected the origin chunk to be resident again after returning to it")
            return
        }

        XCTAssertTrue(
            revisited.reservedTiles.contains(footprintTile),
            "A footprint reserved before eviction must still be reserved after the chunk is regenerated"
        )
        XCTAssertEqual(
            revisited.reservedTiles,
            chunk.reservedTiles,
            "Regenerating an evicted chunk must re-fold exactly the same footprints, never a different set"
        )
        XCTAssertFalse(
            revisited.reserve(footprint: .oneByOne, at: footprintTile),
            "Re-reserving a surviving reservation must be refused, or two buildings could claim the same tile"
        )
        XCTAssertFalse(
            revisited.reservableFootprints(in: .oneByOne).contains(footprintTile),
            "A surviving reservation must not be offered as reservable again after a revisit"
        )
    }

    func test_reservationsAreOwnedAboveTheChunkCache_soADroppedChunkCannotTakeThemWithIt() {
        // Same contract from the other side: the manager's store, not the
        // chunk instance, is where reservations live.
        let manager = ChunkStreamingManager(seed: seed)
        manager.updateCamera(worldPosition: TilePoint(x: 0, y: 0))

        let residentInCoordinateOrder = manager.residentChunks
            .sorted { ($0.key.x, $0.key.y) < ($1.key.x, $1.key.y) }
        guard
            let entry = residentInCoordinateOrder.first(where: { !$0.value.buildingPlacements.isEmpty }),
            let footprintOrigin = entry.value.buildingPlacements.first?.footprintTiles.first
        else {
            XCTFail("Expected at least one resident chunk to have placed a building")
            return
        }

        XCTAssertFalse(
            manager.reservations.allReservedTiles.isEmpty,
            "Generation folds placed footprints into the manager-owned store, so it cannot be empty "
                + "once a chunk full of buildings is resident"
        )
        XCTAssertTrue(
            manager.reservations.isReserved(footprintOrigin),
            "A footprint placed while generating a chunk must be visible in the manager-owned store"
        )

        let farOffset = Double((ChunkStreamingManager.residentRadius + 10) * Chunk.size)
        manager.updateCamera(worldPosition: TilePoint(x: farOffset, y: farOffset))
        XCTAssertTrue(
            manager.reservations.isReserved(footprintOrigin),
            "Evicting the chunk must not remove its reservations from the store"
        )
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
