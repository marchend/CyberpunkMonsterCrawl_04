import Foundation

/// Wraps `CityLatticeGenerator.classify` into 8x8 `Chunk`s.
///
/// The whole point of this type is that it adds *nothing* beyond
/// packaging: `generate` iterates exactly the chunk's own 8x8 world-tile
/// footprint and calls `classify` once per tile, with no neighbour lookups
/// and no chunk-local state feeding back into the classification. Because
/// `classify` is a pure function of `(tileX, tileY, seed)` alone
/// (`CityLatticeGenerator`'s own contract), a tile generated here is
/// byte-for-byte identical to the same tile generated standalone \u2014 that
/// equivalence is what `ChunkGeneratorTests`'s boundary-agreement test
/// pins (AC2), and it is true by construction rather than by careful
/// bookkeeping.
enum ChunkGenerator {
    /// Generates the chunk at `chunkCoordinate` under `seed`: every tile in
    /// its 8x8 world-tile footprint, classified independently.
    ///
    /// `reservations` is the building-footprint reservation store the new
    /// chunk reads and writes through. It defaults to a fresh private store
    /// (so a standalone call still yields a self-contained chunk), but
    /// `ChunkStreamingManager` passes its own world-lifetime store, which is
    /// what makes a reservation survive eviction and regeneration — tile
    /// content is reproduced by `classify`, reservations cannot be.
    static func generate(
        chunkCoordinate: ChunkCoordinate,
        seed: WorldSeed,
        reservations: LotReservationStore = LotReservationStore()
    ) -> Chunk {
        let worldOrigin = chunkCoordinate.worldTileOrigin

        let tiles: [[TileInfo]] = (0..<Chunk.size).map { localX in
            (0..<Chunk.size).map { localY in
                CityLatticeGenerator.classify(
                    tileX: worldOrigin.tileX + localX,
                    tileY: worldOrigin.tileY + localY,
                    seed: seed
                )
            }
        }

        // Building/rooftop-sign placement (`CYBERPUN-17-5-t1`) is decided
        // per *block*, not per chunk, and is a pure function of
        // `(blockCoordinate, seed)` — so this is not "generation" the way
        // `tiles` above is; it's aggregation of an already-pure decision
        // onto the chunk that happens to fully contain it.
        // `BuildingPlacement.blockCoordinates(fullyContainedInChunk:)`
        // deliberately only offers blocks whose entire 3x3 interior sits
        // inside this chunk (the same no-cross-chunk-lookup discipline
        // `Chunk.reservableFootprints(in:)` already applies), so a block
        // straddling the boundary is resolved by neither neighbour here —
        // an accepted limitation, same as reservable footprints.
        var buildingPlacements: [BuildingPlacementRecord] = []
        var roofSigns: [RooftopSignRecord] = []
        for block in BuildingPlacement.blockCoordinates(fullyContainedInChunk: chunkCoordinate) {
            let placements = BuildingPlacement.generate(forBlock: block, seed: seed)
            buildingPlacements.append(contentsOf: placements)
            if let sign = RooftopSignPlacement.generate(forBlock: block, placements: placements, seed: seed) {
                roofSigns.append(sign)
            }
        }

        return Chunk(
            origin: chunkCoordinate,
            tiles: tiles,
            reservations: reservations,
            buildingPlacements: buildingPlacements,
            roofSigns: roofSigns
        )
    }
}
