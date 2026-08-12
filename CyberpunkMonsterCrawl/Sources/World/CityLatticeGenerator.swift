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
            kind = streetTileKind(xMod: xMod, yMod: yMod, isStreetX: isStreetX, isStreetY: isStreetY)
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
    /// This branch never consults `seed` \u2014 street tiles are 100%
    /// structural, which is precisely what guarantees the intersection
    /// rule and the lattice's seed-independent connectivity.
    private static func streetTileKind(xMod: Int, yMod: Int, isStreetX: Bool, isStreetY: Bool) -> TileKind {
        // Position within the 3-tile street band: 0 = edge nearest the
        // lower-index block, 1 = centre driving lane, 2 = edge nearest the
        // higher-index block. Only meaningful on an axis that is actually
        // inside the street band.
        let xBandPosition = isStreetX ? xMod - blockSize : -1
        let yBandPosition = isStreetY ? yMod - blockSize : -1

        if isStreetX && isStreetY {
            // Inside a lattice crossing: both axes' bands are street, so
            // this tile sits in the full 3x3 intersection area. The
            // crossing's own centre tile is clear asphalt; every other
            // tile in the crossing is the painted stop line.
            return (xBandPosition == 1 && yBandPosition == 1) ? .asphalt : .junctionStopLine
        }

        // Exactly one axis is in the street band: a straight corridor
        // segment. Its centre lane is asphalt, flanked by kerb sidewalk on
        // both edges.
        let bandPosition = isStreetX ? xBandPosition : yBandPosition
        return bandPosition == 1 ? .asphalt : .kerbSidewalk
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
