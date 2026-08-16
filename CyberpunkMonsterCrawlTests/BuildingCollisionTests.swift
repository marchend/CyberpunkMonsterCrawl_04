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
    ///
    /// **What a fixture-based walkability assertion can and cannot prove.**
    /// This fixture derives each tile's `kind` from `record.footprintTiles`
    /// itself, so an `isWalkable` assertion against it is a read-back of
    /// what this test just wrote: it would stay green even if
    /// `ChunkGenerator`/`CityLatticeGenerator` stopped classifying reserved
    /// footprints as `.buildingFootprint`, or if
    /// `TileKind.buildingFootprint.isWalkable` flipped to `true`. What it
    /// does prove is the *parity* half - that two records differing only in
    /// which sprite was chosen produce identical obstruction - which is what
    /// AC6 forbids diverging.
    ///
    /// The generation half ("a placed building's footprint is solid because
    /// generation made it solid, whatever sprite landed there") is a property
    /// of `ChunkGenerator`, not of any fixture, so it is asserted against
    /// real generated chunks below:
    /// `test_generatedChunk_tallAndShortPlacements_bothObstructTheirWholeFootprint`
    /// and `test_everyGeneratedPlacement_hasAWhollySolidFootprint`.
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

    // MARK: - AC6 from real generated chunks, not from a hand-built fixture

    /// Seed swept by the generation-derived cases. Generation is a pure
    /// function of `(coordinate, seed)`, so these cases are deterministic:
    /// they cannot pass on one run and fail on the next.
    private static let generatedSeed = WorldSeed(rawValue: 90_210)

    /// Chunk coordinates swept, on each axis. Wide enough that the
    /// tall/short pairing below is found many times over (a chunk owns 1-4
    /// blocks, each non-empty block interior places up to 9 buildings drawn
    /// from all 12 catalog entries), and small enough to stay a fast unit
    /// test.
    private static let sweptChunkAxis = -5...5

    private struct GeneratedTallShortPair {
        let chunk: Chunk
        let tall: BuildingPlacementRecord
        let short: BuildingPlacementRecord
    }

    /// The first generated chunk that placed **both** a `.tall`
    /// (`building_05`, ~4 storey) and a `.lowest` (`building_10`, ~1 storey)
    /// building - the tall/short pair AC6 is about, taken from
    /// `ChunkGenerator.generate` rather than hand-assembled, so nothing about
    /// the tiles or the records is chosen by this test.
    private func firstGeneratedChunkPairingTallAndShortBuildings() -> GeneratedTallShortPair? {
        for chunkX in Self.sweptChunkAxis {
            for chunkY in Self.sweptChunkAxis {
                let chunk = ChunkGenerator.generate(
                    chunkCoordinate: ChunkCoordinate(x: chunkX, y: chunkY),
                    seed: Self.generatedSeed
                )
                guard
                    let tall = chunk.buildingPlacements.first(where: { $0.building.heightClass == .tall }),
                    let short = chunk.buildingPlacements.first(where: { $0.building.heightClass == .lowest })
                else { continue }
                return GeneratedTallShortPair(chunk: chunk, tall: tall, short: short)
            }
        }
        return nil
    }

    /// This chunk's own `TileInfo` for a world tile, or `nil` when the tile
    /// falls outside it. A chunk legitimately owns placements whose footprint
    /// spills across a chunk seam (`Chunk.buildingPlacements`' doc comment),
    /// so a footprint tile is not guaranteed to be in the owning chunk's own
    /// 8x8 grid - `classify` is the check that covers every tile either way.
    private func chunkTileInfo(_ tile: TileCoordinate, in chunk: Chunk) -> TileInfo? {
        let worldOrigin = chunk.origin.worldTileOrigin
        let localX = tile.tileX - worldOrigin.tileX
        let localY = tile.tileY - worldOrigin.tileY
        guard (0..<Chunk.size).contains(localX), (0..<Chunk.size).contains(localY) else { return nil }
        return chunk.tile(localX: localX, localY: localY)
    }

    /// Asserts `record`'s footprint is solid **in generation**: for every
    /// footprint tile, `CityLatticeGenerator.classify` - a pure function of
    /// `(tileX, tileY, seed)` that has no idea which building was later
    /// chosen for that tile, and that this test does not feed the record into
    /// - reports `Chunk.placementSurface` and a non-walkable tile. That is
    /// the AC6 claim ("visual height must never affect collision") stated
    /// about the generator instead of about a fixture: nothing here can be
    /// satisfied by a tile kind this test wrote itself.
    private func assertFootprintIsSolidInGeneration(
        _ record: BuildingPlacementRecord,
        in chunk: Chunk,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(
            record.footprintTiles.isEmpty,
            "A placed building must cover at least one tile.",
            file: file, line: line
        )

        for tile in record.footprintTiles {
            let generated = CityLatticeGenerator.classify(
                tileX: tile.tileX,
                tileY: tile.tileY,
                seed: Self.generatedSeed
            )

            XCTAssertEqual(
                generated.kind, Chunk.placementSurface,
                record.building.assetName + " was placed on " + String(describing: tile)
                    + ", which classify reports as " + String(describing: generated.kind)
                    + " rather than " + String(describing: Chunk.placementSurface) + ".",
                file: file, line: line
            )
            XCTAssertFalse(
                generated.isWalkable,
                record.building.assetName + " (" + String(describing: record.building.heightClass)
                    + ") covers " + String(describing: tile) + ", which generation left walkable - a placed "
                    + "building's footprint must be solid regardless of which sprite landed on it.",
                file: file, line: line
            )
            XCTAssertTrue(
                chunk.reservations.isReserved(tile),
                String(describing: tile) + " is covered by a generated placement but not reserved in the "
                    + "world store.",
                file: file, line: line
            )
            XCTAssertTrue(
                BuildingObstruction.isObstructed(tile, by: record),
                "BuildingObstruction must agree with the footprint the generator recorded for "
                    + String(describing: tile) + ".",
                file: file, line: line
            )

            if let info = chunkTileInfo(tile, in: chunk) {
                XCTAssertFalse(
                    info.isWalkable,
                    "The owning chunk's stored grid disagrees with classify about "
                        + String(describing: tile) + ".",
                    file: file, line: line
                )
            }
        }
    }

    /// AC6 taken from generation: a real generated chunk that placed both a
    /// 4-storey `building_05` and a 1-storey `building_10` has *both*
    /// footprints solid across every tile, even though the two sprites'
    /// rendered heights differ by more than 2x.
    func test_generatedChunk_tallAndShortPlacements_bothObstructTheirWholeFootprint() {
        guard let pair = firstGeneratedChunkPairingTallAndShortBuildings() else {
            XCTFail(
                "No chunk in the swept range placed both a tall (building_05) and a lowest (building_10) "
                    + "building under this seed, so this case would prove nothing - widen the sweep or "
                    + "change the seed rather than deleting the assertions."
            )
            return
        }

        XCTAssertEqual(pair.tall.building.heightClass, .tall)
        XCTAssertEqual(pair.short.building.heightClass, .lowest)

        assertFootprintIsSolidInGeneration(pair.tall, in: pair.chunk)
        assertFootprintIsSolidInGeneration(pair.short, in: pair.chunk)

        // The visual half of AC6: the two really are a tall/short pair, so
        // the identical solidity above cannot be an artifact of the two
        // buildings looking alike.
        let tallNode = TileFieldRenderer.makeBuildingNode(for: pair.tall)
        let shortNode = TileFieldRenderer.makeBuildingNode(for: pair.short)
        XCTAssertGreaterThan(
            tallNode.size.height, shortNode.size.height * 2,
            "building_05 should render more than twice as tall as building_10."
        )

        // ... and neither sprite's height reaches the collision answer: the
        // tall building blocks exactly its own footprint tiles, no more.
        for tile in pair.short.footprintTiles where !pair.tall.footprintTiles.contains(tile) {
            XCTAssertFalse(
                BuildingObstruction.isObstructed(tile, by: pair.tall),
                "The tall building must not obstruct " + String(describing: tile)
                    + " - that tile belongs to another footprint."
            )
        }
    }

    /// The same property, swept: **every** placement of every generated chunk
    /// in the swept range has a wholly solid footprint, across every height
    /// class the catalog can produce. Counts what it checked and which height
    /// classes it saw, so the sweep cannot pass vacuously if generation ever
    /// stops placing buildings.
    func test_everyGeneratedPlacement_hasAWhollySolidFootprint() {
        var checkedRecords = 0
        var heightClassesSeen: [BuildingCatalog.HeightClass] = []

        for chunkX in Self.sweptChunkAxis {
            for chunkY in Self.sweptChunkAxis {
                let chunk = ChunkGenerator.generate(
                    chunkCoordinate: ChunkCoordinate(x: chunkX, y: chunkY),
                    seed: Self.generatedSeed
                )
                for record in chunk.buildingPlacements {
                    assertFootprintIsSolidInGeneration(record, in: chunk)
                    checkedRecords += 1
                    if !heightClassesSeen.contains(record.building.heightClass) {
                        heightClassesSeen.append(record.building.heightClass)
                    }
                }
            }
        }

        XCTAssertGreaterThan(
            checkedRecords, 200,
            "The swept range should generate hundreds of placements; " + String(checkedRecords)
                + " means generation placed almost nothing and the assertions above ran vacuously."
        )
        XCTAssertGreaterThanOrEqual(
            heightClassesSeen.count, 4,
            "The sweep should cover nearly every height class, so solidity is not being proven only for "
                + "one building; saw " + String(heightClassesSeen.count) + "."
        )
    }
}
