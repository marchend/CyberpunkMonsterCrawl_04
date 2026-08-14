import Foundation

/// A block-space coordinate: one unit here is one 3x3 building-block
/// interior (`CityLatticeGenerator.blockSize`) — the same block
/// `CityLatticeGenerator.isEmptyLotBlock(blockX:blockY:seed:)` already
/// decides "empty or building" for. Kept distinct from a bare `(Int, Int)`
/// for the same reason `ChunkCoordinate` and `TileCoordinate` are kept
/// distinct from each other elsewhere in `World`: chunk space, block space
/// and tile space are three different "two ints" that must never be
/// silently interchangeable.
struct BlockCoordinate: Hashable {
    let x: Int
    let y: Int

    /// This block's own interior lower-corner tile, in world-tile space:
    /// `CityLatticeGenerator.blockInteriorTileKind`'s `floorDiv(tileX,
    /// period)` derivation, run the other way (block -> tile). The block
    /// interior occupies exactly `CityLatticeGenerator.blockSize` tiles from
    /// here on each axis — the remaining `period - blockSize` tiles of the
    /// period are always street.
    var interiorOrigin: TileCoordinate {
        TileCoordinate(tileX: x * CityLatticeGenerator.period, tileY: y * CityLatticeGenerator.period)
    }
}

/// One building placed by `BuildingPlacement.generate`: which lot it
/// occupies, which of the 12 `BuildingCatalog` entries it is, and the full
/// set of world tiles its footprint covers.
struct BuildingPlacementRecord: Equatable {
    /// The building footprint's lower-corner world tile — the same tile the
    /// row-major interior walk was standing on when this building was
    /// chosen.
    let lotTile: TileCoordinate
    /// Which of the 12 placeable buildings this is.
    let building: BuildingCatalog.Entry
    /// Every world tile this building's footprint covers: one tile for a
    /// 1x1 building, four for a 2x2.
    let footprintTiles: [TileCoordinate]
    /// The footprint's far corner: `lotTile` itself for a 1x1 building, the
    /// diagonally-opposite tile for a 2x2.
    let farCornerTile: TileCoordinate
}

/// Generates the building placed on each occupied lot of one block's 3x3
/// interior, deterministically from `(worldSeed, blockCoordinate,
/// lotCoordinate)`.
///
/// **Scope of this PR (`CYBERPUN-17-5-t1`):** pure logic only — no
/// SpriteKit, no rendering. `ChunkGenerator` is the sole production
/// consumer, aggregating this per block into a chunk's stored placement
/// records; a later story mounts them as actual sprites.
enum BuildingPlacement {
    /// Distinct salt XORed into `WorldSeed.rawValue` before hashing, so this
    /// decision's hash stream never coincides with
    /// `CityLatticeGenerator`'s own per-block "is this block empty" hash
    /// (`SeedMixer.bounded(seed:tileX: blockX, tileY: blockY, modulus: 4)`),
    /// even though both ultimately hash small integer coordinates against
    /// the same `WorldSeed`.
    private static let buildingSelectionSalt: UInt64 = 0xB1D9_1A11_5EED_0001

    /// Walks block `block`'s 3x3 interior in row-major order (`localY`
    /// outer, `localX` inner — the same "row-major order" convention
    /// `ChunkGenerator` documents for its own tile walk), placing one
    /// building per still-unclaimed lot.
    ///
    /// Honors the city lattice's own ~1-in-4 empty-block decision
    /// (`CityLatticeGenerator.isEmptyLotBlock`) by returning `[]` outright
    /// for an empty block: no building is ever placed on the tiles the
    /// lattice deliberately leaves as bare, walkable `.lot`.
    ///
    /// For a building block, every lot ends up covered by some building's
    /// footprint (the design brief: "buildings fill the 3x3 block
    /// interior"). Each still-unclaimed lot's seeded hash of
    /// `(worldSeed, lotTile)` — never the iteration index alone, so a lot's
    /// own result stays stable regardless of what an adjacent lot decides —
    /// picks one of the 12 `BuildingCatalog` entries. If that pick is a 2x2
    /// footprint that would not fit at this lot (crosses the interior edge,
    /// or overlaps a building already placed earlier in this same walk),
    /// the same hash is re-reduced over `BuildingCatalog.oneByOneEntries`
    /// instead, so the lot still gets *some* building rather than being
    /// skipped.
    static func generate(forBlock block: BlockCoordinate, seed: WorldSeed) -> [BuildingPlacementRecord] {
        guard !CityLatticeGenerator.isEmptyLotBlock(blockX: block.x, blockY: block.y, seed: seed) else {
            return []
        }

        let interiorOrigin = block.interiorOrigin
        let interiorSize = CityLatticeGenerator.blockSize
        var reservation = BuildingFootprintReservation()
        var records: [BuildingPlacementRecord] = []

        for localY in 0..<interiorSize {
            for localX in 0..<interiorSize {
                let lotTile = TileCoordinate(
                    tileX: interiorOrigin.tileX + localX,
                    tileY: interiorOrigin.tileY + localY
                )
                guard !reservation.isReserved(lotTile) else { continue }

                let hash = SeedMixer.hash(
                    seed: seed.rawValue ^ buildingSelectionSalt,
                    tileX: lotTile.tileX,
                    tileY: lotTile.tileY
                )
                let candidate = BuildingCatalog.entry(atIndex: Int(hash % UInt64(BuildingCatalog.entries.count)))

                let chosen: BuildingCatalog.Entry
                if candidate.footprintSize == .twoByTwo,
                   reservation.fitsWithinBlockInterior(
                       span: candidate.footprintSize.tileSpan,
                       at: lotTile,
                       blockInteriorOrigin: interiorOrigin,
                       interiorSize: interiorSize
                   ) {
                    chosen = candidate
                } else if candidate.footprintSize == .twoByTwo {
                    // Doesn't fit here — deterministically fall back to a
                    // 1x1 pick derived from the same hash, rather than
                    // leaving this lot without a building.
                    let fallbackEntries = BuildingCatalog.oneByOneEntries
                    chosen = fallbackEntries[Int(hash % UInt64(fallbackEntries.count))]
                } else {
                    chosen = candidate
                }

                let span = chosen.footprintSize.tileSpan
                reservation.reserve(
                    span: span,
                    at: lotTile,
                    blockInteriorOrigin: interiorOrigin,
                    interiorSize: interiorSize
                )
                let footprintTiles = reservation.coveredTiles(span: span, at: lotTile)
                let farCornerTile = TileCoordinate(
                    tileX: lotTile.tileX + span - 1,
                    tileY: lotTile.tileY + span - 1
                )

                records.append(
                    BuildingPlacementRecord(
                        lotTile: lotTile,
                        building: chosen,
                        footprintTiles: footprintTiles,
                        farCornerTile: farCornerTile
                    )
                )
            }
        }

        return records
    }

    /// Every block coordinate whose *entire* 3x3 interior lies within
    /// `chunkCoordinate`'s own 8x8 world-tile footprint — the same
    /// chunk-local discipline `Chunk.reservableFootprints(in:)` already
    /// applies to footprint reservation, and for the identical reason: a
    /// block interior straddling the chunk boundary is never resolved by
    /// looking at one side's chunk alone (`Chunk.size` (8) is not a
    /// multiple of `CityLatticeGenerator.period` (6)). `ChunkGenerator`
    /// uses this to decide which blocks it can safely call `generate` for
    /// on its own, without any cross-chunk lookup.
    static func blockCoordinates(fullyContainedInChunk chunkCoordinate: ChunkCoordinate) -> [BlockCoordinate] {
        let origin = chunkCoordinate.worldTileOrigin
        let xs = axisBlockCoordinates(chunkOriginAxis: origin.tileX)
        let ys = axisBlockCoordinates(chunkOriginAxis: origin.tileY)

        var result: [BlockCoordinate] = []
        for x in xs {
            for y in ys {
                result.append(BlockCoordinate(x: x, y: y))
            }
        }
        return result
    }

    /// The block coordinates, on a single axis, whose interior span
    /// (`[b*period, b*period + blockSize - 1]`) lies entirely within
    /// `[chunkOriginAxis, chunkOriginAxis + Chunk.size - 1]`.
    private static func axisBlockCoordinates(chunkOriginAxis: Int) -> [Int] {
        let period = CityLatticeGenerator.period
        let blockSize = CityLatticeGenerator.blockSize
        let lowerBound = floorDiv(chunkOriginAxis, period) - 1
        let upperBound = floorDiv(chunkOriginAxis + Chunk.size - 1, period) + 1

        var result: [Int] = []
        for candidate in lowerBound...upperBound {
            let interiorStart = candidate * period
            let interiorEnd = interiorStart + blockSize - 1
            if interiorStart >= chunkOriginAxis && interiorEnd <= chunkOriginAxis + Chunk.size - 1 {
                result.append(candidate)
            }
        }
        return result
    }

    /// Floor division — see `CityLatticeGenerator.floorDiv` / `ChunkCoordinate`'s
    /// own private copy for the identical reasoning; duplicated here rather
    /// than shared, matching this module's existing convention for this
    /// two-line integer-math primitive.
    private static func floorDiv(_ value: Int, _ divisor: Int) -> Int {
        let quotient = value / divisor
        let remainder = value % divisor
        if remainder != 0 && (remainder < 0) != (divisor < 0) {
            return quotient - 1
        }
        return quotient
    }
}
