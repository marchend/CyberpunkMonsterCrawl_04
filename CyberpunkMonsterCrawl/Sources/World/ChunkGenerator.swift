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

        return Chunk(origin: chunkCoordinate, tiles: tiles, reservations: reservations)
    }
}
