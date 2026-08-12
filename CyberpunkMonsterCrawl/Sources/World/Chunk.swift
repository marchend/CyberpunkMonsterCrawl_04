import Foundation

/// A chunk-space integer coordinate: one unit here is one `Chunk.size` x
/// `Chunk.size` block of world tiles, not one tile.
///
/// Kept distinct from a raw `(Int, Int)` tile pair for the same reason
/// `TilePoint` is kept distinct from a screen-space `CGPoint`
/// (`IsometricProjection.swift`): a chunk coordinate and a tile coordinate
/// are both "two ints" but must never be silently interchangeable, or a
/// caller could feed a chunk coordinate straight into `classify` and get a
/// silently-plausible (wrong) tile back.
struct ChunkCoordinate: Hashable {
    let x: Int
    let y: Int

    /// This chunk's local `(0, 0)` tile, in world-tile space.
    var worldTileOrigin: (tileX: Int, tileY: Int) {
        (tileX: x * Chunk.size, tileY: y * Chunk.size)
    }

    /// The chunk coordinate that owns world tile `(tileX, tileY)`.
    ///
    /// Uses floor division (not truncating `/`) so tile coordinates on the
    /// negative side of the origin fall into monotonically decreasing chunk
    /// coordinates \u2014 the same negative-axis discipline
    /// `CityLatticeGenerator`'s own `floorDiv` applies to block coordinates,
    /// re-derived here rather than reaching into that file's private helper.
    static func containing(tileX: Int, tileY: Int) -> ChunkCoordinate {
        ChunkCoordinate(x: floorDiv(tileX, Chunk.size), y: floorDiv(tileY, Chunk.size))
    }
}

/// Floor division: `floorDiv(-1, 8) == -1`, whereas Swift's truncating `/`
/// gives `0`. See `CityLatticeGenerator.floorDiv` for the identical
/// reasoning \u2014 duplicated here (rather than exposed from that file)
/// because it is a two-line integer-math primitive, not a shared contract.
private func floorDiv(_ value: Int, _ divisor: Int) -> Int {
    let quotient = value / divisor
    let remainder = value % divisor
    if remainder != 0 && (remainder < 0) != (divisor < 0) {
        return quotient - 1
    }
    return quotient
}

/// A world-tile coordinate, used by the lot-reservation API below to name a
/// footprint's placement without ambiguity against a `ChunkCoordinate` or a
/// bare `(Int, Int)` tuple.
struct TileCoordinate: Hashable {
    let tileX: Int
    let tileY: Int
}

/// The world-grid footprint size a placeable building reserves, per the
/// design brief's 1x1 / 2x2 building table (`BuildingSprite.Footprint`).
/// Kept as its own type here (rather than importing `BuildingSprite`'s
/// nested enum) because lot reservation is a `World`-layer concern that must
/// stay independent of the `Assets` layer \u2014 the building-placement story
/// (`CYBERPUN-17-5`) is the piece that will translate between the two.
enum LotFootprintSize: CaseIterable, Equatable {
    case oneByOne
    case twoByTwo

    /// Footprint width/height, in tiles, on each axis.
    var tileSpan: Int {
        switch self {
        case .oneByOne: return 1
        case .twoByTwo: return 2
        }
    }
}

/// An 8x8-tile data container: one chunk of the streamed world.
///
/// Holds the tile grid produced by `ChunkGenerator.generate` plus this
/// chunk's own lot-reservation state, so a future building-placement story
/// (`CYBERPUN-17-5`) can claim footprints without a second data structure.
/// A reference type (not a value type) because reservation state must be
/// mutated in place while the streaming manager and any future renderer
/// hold the same chunk \u2014 mirroring it through a struct would silently
/// desync copies.
final class Chunk {
    /// Tiles per side. The design brief's fixed chunk size
    /// (`docs/bootstrap.md`: "8x8 tile chunks").
    static let size = 8

    /// This chunk's position in chunk space. Named `origin` (rather than
    /// `coordinate`) per the implementation plan \u2014 not to be confused with
    /// `worldTileOrigin` below, which is this same value expressed in world
    /// tile space.
    let origin: ChunkCoordinate

    /// The 8x8 tile grid, indexed `tiles[localX][localY]` with
    /// `localX, localY` both in `0..<Chunk.size`. Each entry's own
    /// `tileX`/`tileY` are in *world* tile space (`origin.worldTileOrigin`
    /// offset by the local index), so a `TileInfo` pulled out of a chunk is
    /// indistinguishable from one produced by calling `classify` directly.
    let tiles: [[TileInfo]]

    /// World tile coordinates currently claimed by a reserved footprint.
    /// Tracked as a flat set (rather than only the per-footprint list)
    /// so overlap checks are O(footprint size) instead of O(reservation
    /// count).
    private(set) var reservedTiles: Set<TileCoordinate> = []

    init(origin: ChunkCoordinate, tiles: [[TileInfo]]) {
        precondition(tiles.count == Chunk.size, "Chunk must have exactly \(Chunk.size) columns, got \(tiles.count)")
        precondition(
            tiles.allSatisfy { $0.count == Chunk.size },
            "Chunk must have exactly \(Chunk.size) rows per column"
        )
        self.origin = origin
        self.tiles = tiles
    }

    /// The tile at local grid position `(localX, localY)`, both expected in
    /// `0..<Chunk.size`.
    func tile(localX: Int, localY: Int) -> TileInfo {
        tiles[localX][localY]
    }

    // MARK: - Lot reservation

    /// Every world-tile origin, within this chunk only, where a footprint of
    /// `size` could be reserved right now: every tile it would cover is
    /// classified `.lot` (the design brief: a placed building's footprint
    /// tiles come from lot tiles, never street or an already-occupied
    /// footprint) and not already reserved.
    ///
    /// Deliberately chunk-local \u2014 a footprint is never considered if it
    /// would cross into a neighbouring chunk, keeping this consistent with
    /// `ChunkGenerator`'s no-cross-chunk-lookups rule.
    func reservableFootprints(in size: LotFootprintSize) -> [TileCoordinate] {
        let span = size.tileSpan
        let worldOrigin = origin.worldTileOrigin
        var candidates: [TileCoordinate] = []

        guard Chunk.size - span >= 0 else { return candidates }

        for localX in 0...(Chunk.size - span) {
            for localY in 0...(Chunk.size - span) {
                let candidate = TileCoordinate(tileX: worldOrigin.tileX + localX, tileY: worldOrigin.tileY + localY)
                if canReserve(size, at: candidate) {
                    candidates.append(candidate)
                }
            }
        }
        return candidates
    }

    /// Attempts to reserve a `size` footprint whose lower-corner world tile
    /// is `origin`. Returns `false` (no mutation) if any covered tile is
    /// outside this chunk, is not `.lot`, or is already reserved \u2014 this is
    /// the check that keeps 1x1/2x2 buildings from ever overlapping.
    @discardableResult
    func reserve(footprint size: LotFootprintSize, at footprintOrigin: TileCoordinate) -> Bool {
        guard canReserve(size, at: footprintOrigin) else { return false }
        for tile in coveredTiles(size, at: footprintOrigin) {
            reservedTiles.insert(tile)
        }
        return true
    }

    /// Whether every tile a `size` footprint at `footprintOrigin` would
    /// cover is in-bounds for this chunk, classified `.lot`, and not
    /// already reserved.
    private func canReserve(_ size: LotFootprintSize, at footprintOrigin: TileCoordinate) -> Bool {
        let covered = coveredTiles(size, at: footprintOrigin)
        guard covered.count == size.tileSpan * size.tileSpan else { return false }
        return covered.allSatisfy { tile in
            guard let info = tileInfo(atWorldTileX: tile.tileX, worldTileY: tile.tileY) else { return false }
            return info.kind == .lot && !reservedTiles.contains(tile)
        }
    }

    /// The set of world tile coordinates a `size` footprint at
    /// `footprintOrigin` would occupy. Empty if any covered tile falls
    /// outside this chunk.
    private func coveredTiles(_ size: LotFootprintSize, at footprintOrigin: TileCoordinate) -> [TileCoordinate] {
        let span = size.tileSpan
        var result: [TileCoordinate] = []
        for dx in 0..<span {
            for dy in 0..<span {
                let tile = TileCoordinate(tileX: footprintOrigin.tileX + dx, tileY: footprintOrigin.tileY + dy)
                guard tileInfo(atWorldTileX: tile.tileX, worldTileY: tile.tileY) != nil else { return [] }
                result.append(tile)
            }
        }
        return result
    }

    /// Looks up a tile by world coordinate, translating into this chunk's
    /// local grid. `nil` if the coordinate falls outside this chunk.
    private func tileInfo(atWorldTileX worldTileX: Int, worldTileY: Int) -> TileInfo? {
        let worldOrigin = origin.worldTileOrigin
        let localX = worldTileX - worldOrigin.tileX
        let localY = worldTileY - worldOrigin.tileY
        guard (0..<Chunk.size).contains(localX), (0..<Chunk.size).contains(localY) else { return nil }
        return tiles[localX][localY]
    }
}
