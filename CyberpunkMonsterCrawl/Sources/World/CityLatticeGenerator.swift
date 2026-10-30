import Foundation

/// The result of classifying a single world tile: its coordinate and its
/// `TileKind`. A plain value type \u2014 no identity, no mutable state \u2014 so it
/// can be compared for equality (determinism tests) and passed freely
/// across threads (concurrency tests).
struct TileInfo: Equatable {
    let tileX: Int
    let tileY: Int
    let kind: TileKind

    /// Convenience passthrough \u2014 callers that only care about
    /// walkability (collision, pathfinding, the flood-fill connectivity
    /// tests) don't need to know about `TileKind` at all.
    var isWalkable: Bool { kind.isWalkable }
}

/// The pure, seeded city-lattice generator.
///
/// This is the load-bearing piece of the story: the design brief calls the
/// lattice "a hard rule, not a look" \u2014 *"Because every block is ringed by
/// a 3-tile street, those streets form one connected lattice and the
/// player and the raccoon swarm ALWAYS have a path."* `classify` is the
/// single function that must uphold that rule for every tile, under every
/// seed, forever.
///
/// **Scope of this PR (`CYBERPUN-17-3-t2`):** the pure per-tile function
/// and its invariants only \u2014 no chunking, no streaming. Wrapping this into
/// 8x8 chunks with lot reservation and camera-driven streaming is
/// `CYBERPUN-17-3-t3`; that PR's boundary-agreement test calls straight
/// into `classify` to prove a chunk-embedded tile matches the tile
/// generated standalone, so `classify` itself must never consult anything
/// but its own three inputs.
///
/// **Design (period 6, per the brief):**
/// - The world tiles into a repeating 6x6 period on each axis.
/// - Tiles `0, 1, 2` (mod 6) on *both* axes together are the 3x3 block
///   interior.
/// - Any tile where *either* axis's coordinate is `3, 4, 5` (mod 6) is
///   street \u2014 this is structural, decided purely from the coordinate, so
///   no seed input can ever turn a street tile into anything else. That is
///   what makes "every intersection tile is street under every seed" true
///   by construction rather than by seed-decision luck, and it is also
///   why the street lattice's connectivity never depends on the seed: only
///   block interiors (never street tiles) are seed-driven.
/// - A block interior tile's fate (`.lot` vs `.buildingFootprint`) is
///   decided once *per block* (not per tile) via `SeedMixer`, so every
///   tile inside one block interior agrees.
/// - A street tile's *sub-kind* at a band edge follows the block it
///   borders (`CYBERPUN-17-22`): an edge beside a built block kerbs it as
///   `.kerbSidewalk`, an edge beside an empty `.lot` has nothing to kerb
///   and stays `.asphalt`. Street-ness itself is never seed-driven, so
///   this changes what an edge *reads* as, never whether it is street.
enum CityLatticeGenerator {
    /// Tiles per repeating period, along each axis: a 3-tile building
    /// block plus the 3-tile street corridor that rings it.
    static let period = 6
    /// Width, in tiles, of the block interior on each axis.
    static let blockSize = 3
    /// Width, in tiles, of the street corridor on each axis.
    static let streetWidth = 3

    /// Denominator of the seed-driven empty-lot decision: ~1 block in 4 is
    /// left empty (the brief: "~1-in-4 blocks are left as empty lots,
    /// chosen by seed").
    private static let emptyLotModulus: UInt64 = 4

    /// Classifies a single world tile. Pure function of its three inputs
    /// only \u2014 no chunk, no neighbour, no cached/global state \u2014 so it is
    /// safe to call from any thread, in any order, any number of times,
    /// and always get the same answer back (proven by
    /// `ConcurrencyDeterminismTests` and the determinism test in
    /// `CityLatticeGeneratorTests`).
    static func classify(tileX: Int, tileY: Int, seed: WorldSeed) -> TileInfo {
        let xMod = mod(tileX, period)
        let yMod = mod(tileY, period)

        let isStreetX = xMod >= blockSize
        let isStreetY = yMod >= blockSize

        let kind: TileKind
        if isStreetX || isStreetY {
            kind = streetTileKind(
                tileX: tileX, tileY: tileY, xMod: xMod, yMod: yMod,
                isStreetX: isStreetX, isStreetY: isStreetY, seed: seed
            )
        } else {
            kind = blockInteriorTileKind(tileX: tileX, tileY: tileY, seed: seed)
        }

        return TileInfo(tileX: tileX, tileY: tileY, kind: kind)
    }

    /// Whether the block containing `(tileX, tileY)` was chosen (by seed)
    /// to be an empty lot. Exposed so future stories (building placement,
    /// lot reservation) can ask "is this block empty?" without re-deriving
    /// the block-interior decision from a specific tile inside it.
    static func isEmptyLotBlock(blockX: Int, blockY: Int, seed: WorldSeed) -> Bool {
        SeedMixer.bounded(seed: seed.rawValue, tileX: blockX, tileY: blockY, modulus: emptyLotModulus) == 0
    }

    // MARK: - Street sub-classification

    /// Sub-classifies a tile already known to be street (i.e.
    /// `isStreetX || isStreetY`) into asphalt / stop-line / kerb-sidewalk.
    ///
    /// This consults `seed` for exactly one purpose: a street-band edge
    /// tile (band position 0 or 2 on a straight corridor, or one of the
    /// four corners of a lattice crossing) only reads as `.kerbSidewalk`
    /// when the specific block interior it borders actually has a
    /// building edge to kerb (`.buildingFootprint`); an edge bordering an
    /// empty `.lot` interior has nothing to kerb and reads as `.asphalt`
    /// instead. That lookup (`isEmptyLotBlock`) is itself a pure function
    /// of block coordinates derived from `tileX`/`tileY` plus `seed` \u2014 the
    /// same three inputs `classify` already takes \u2014 so this stays a pure
    /// function of its inputs and the chunk-boundary agreement
    /// (`CYBERPUN-17-3-t3`) still holds. The *structural* decisions \u2014
    /// which tiles are street at all, and the lane/stop-line/corner
    /// layout within a crossing \u2014 remain 100% seed-independent, which is
    /// what guarantees the intersection rule and the lattice's
    /// seed-independent connectivity. (A corner/edge tile's *kind* is not
    /// part of that structural layout: which of a crossing's nine
    /// positions is a corner never changes, but whether a given corner
    /// reads as `.kerbSidewalk` or `.asphalt` follows the one block
    /// interior it borders.)
    private static func streetTileKind(
        tileX: Int, tileY: Int, xMod: Int, yMod: Int, isStreetX: Bool, isStreetY: Bool, seed: WorldSeed
    ) -> TileKind {
        // Position within the 3-tile street band: 0 = edge nearest the
        // lower-index block, 1 = centre driving lane, 2 = edge nearest the
        // higher-index block. Only meaningful on an axis that is actually
        // inside the street band.
        let xBandPosition = isStreetX ? xMod - blockSize : -1
        let yBandPosition = isStreetY ? yMod - blockSize : -1

        if isStreetX && isStreetY {
            // Inside a lattice crossing: both axes' bands are street, so
            // this tile sits in the full 3x3 intersection area. The three
            // roles within that 3x3 are distinct, and the ground-plane
            // renderer cannot recover them later, so they are pinned here:
            //
            //   corner  mouth   corner      corner = both axes on a band
            //   mouth   centre  mouth       edge (band position 0 or 2)
            //   corner  mouth   corner      mouth  = one axis is the lane
            //
            // - Centre (both axes on the driving lane): clear asphalt.
            // - Lane mouth (one axis is the centre lane, the other a band
            //   edge): this is literally where a stop line is painted,
            //   across the lane at the mouth of the junction.
            // - Corner (both axes on a band edge): the continuation of the
            //   `kerbSidewalk` band running down each corridor \u2014 but only
            //   where the one block interior this specific corner borders
            //   (`blockBorderedByEdge`) actually has a building to kerb;
            //   otherwise it continues as `.asphalt`, since an empty lot
            //   has no building edge for the sidewalk to serve.
            let xIsLane = xBandPosition == 1
            let yIsLane = yBandPosition == 1
            if xIsLane && yIsLane {
                return .asphalt
            }
            if xIsLane || yIsLane {
                return .junctionStopLine
            }
            return blockBorderedByEdge(
                tileX: tileX, tileY: tileY, xBandPosition: xBandPosition, yBandPosition: yBandPosition, seed: seed
            ) == .buildingFootprint ? .kerbSidewalk : .asphalt
        }

        // Exactly one axis is in the street band: a straight corridor
        // segment. Its centre lane is asphalt; its two edges kerb only the
        // block interior they actually border, and only when that
        // interior has a building edge to kerb.
        let bandPosition = isStreetX ? xBandPosition : yBandPosition
        if bandPosition == 1 {
            return .asphalt
        }
        return blockBorderedByEdge(
            tileX: tileX, tileY: tileY, xBandPosition: xBandPosition, yBandPosition: yBandPosition, seed: seed
        ) == .buildingFootprint ? .kerbSidewalk : .asphalt
    }

    /// The block-interior kind (`.lot` or `.buildingFootprint`) bordered by
    /// a street-band edge/corner tile at `(tileX, tileY)`.
    ///
    /// Band position 0 borders the block in the *current* period on that
    /// axis; band position 2 borders the *next* period's block (one block
    /// index higher). An axis not in the street band (`bandPosition ==
    /// -1`, the corridor case's cross-axis) contributes no offset, since
    /// that axis already sits inside the one block interior the edge runs
    /// alongside. Combining both axes' offsets is what singles out the one
    /// block a lattice-crossing corner borders, out of the four blocks
    /// that physically meet at that corner.
    private static func blockBorderedByEdge(
        tileX: Int, tileY: Int, xBandPosition: Int, yBandPosition: Int, seed: WorldSeed
    ) -> TileKind {
        let blockX = floorDiv(tileX, period) + (xBandPosition == 2 ? 1 : 0)
        let blockY = floorDiv(tileY, period) + (yBandPosition == 2 ? 1 : 0)
        return isEmptyLotBlock(blockX: blockX, blockY: blockY, seed: seed) ? .lot : .buildingFootprint
    }

    // MARK: - Block-interior sub-classification

    /// Sub-classifies a tile already known to be a block interior (i.e.
    /// `!isStreetX && !isStreetY`) into lot / building-footprint, via a
    /// single seed decision for the whole block.
    private static func blockInteriorTileKind(tileX: Int, tileY: Int, seed: WorldSeed) -> TileKind {
        let blockX = floorDiv(tileX, period)
        let blockY = floorDiv(tileY, period)
        return isEmptyLotBlock(blockX: blockX, blockY: blockY, seed: seed) ? .lot : .buildingFootprint
    }

    // MARK: - Negative-safe integer arithmetic

    /// Swift's `%` returns a result with the same sign as the dividend, so
    /// `-1 % 6 == -1`, not `5`. The lattice's period math needs the
    /// mathematical modulus (always in `0..<modulus`) so negative tile
    /// coordinates fall into the same band pattern as positive ones,
    /// symmetric across the origin.
    private static func mod(_ value: Int, _ modulus: Int) -> Int {
        let remainder = value % modulus
        return remainder >= 0 ? remainder : remainder + modulus
    }

    /// Floor division: `floorDiv(-1, 6) == -1` (block index -1), whereas
    /// Swift's truncating `/` gives `0`. Needed so block coordinates
    /// increase monotonically with world position across the origin \u2014
    /// otherwise two adjacent negative-axis blocks could collide on the
    /// same block coordinate.
    private static func floorDiv(_ value: Int, _ divisor: Int) -> Int {
        let quotient = value / divisor
        let remainder = value % divisor
        if remainder != 0 && (remainder < 0) != (divisor < 0) {
            return quotient - 1
        }
        return quotient
    }
}
