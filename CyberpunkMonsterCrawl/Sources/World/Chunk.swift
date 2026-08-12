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
    /// coordinates — the same negative-axis discipline
    /// `CityLatticeGenerator`'s own `floorDiv` applies to block coordinates,
    /// re-derived here rather than reaching into that file's private helper.
    static func containing(tileX: Int, tileY: Int) -> ChunkCoordinate {
        ChunkCoordinate(x: floorDiv(tileX, Chunk.size), y: floorDiv(tileY, Chunk.size))
    }
}

/// Floor division: `floorDiv(-1, 8) == -1`, whereas Swift's truncating `/`
/// gives `0`. See `CityLatticeGenerator.floorDiv` for the identical
/// reasoning — duplicated here (rather than exposed from that file)
/// because it is a two-line integer-math primitive, not a shared contract.
private func floorDiv(_ value: Int, _ divisor: Int) -> Int {
    let quotient = value / divisor
    let remainder = value % divisor
    if remainder != 0 && (remainder < 0) != (divisor < 0) {
        return quotient - 1
    }
    return quotient
}

/// A world-tile coordinate, used by the footprint-reservation API below to
/// name a footprint's placement without ambiguity against a
/// `ChunkCoordinate` or a bare `(Int, Int)` tuple.
struct TileCoordinate: Hashable {
    let tileX: Int
    let tileY: Int
}

/// Building-footprint reservation state for the whole world, held **above**
/// the chunk cache.
///
/// Reservations used to live on the `Chunk` instance itself, which
/// `ChunkStreamingManager` throws away on eviction (`residentChunks
/// .removeValue`) and rebuilds from `ChunkGenerator.generate` on revisit. Tile
/// *content* survives that cycle for free because `classify` is a pure
/// function of `(tileX, tileY, seed)`, but a reservation is a **decision**,
/// not a derivation: regenerating the chunk brought it back with
/// `reservedTiles == []`, so a building placed by `CYBERPUN-17-5` would pop
/// out and could re-place somewhere else every time the player circled back.
/// "1x1/2x2 buildings can never collide" was therefore only true within a
/// single residency episode.
///
/// A decision needs an owner that outlives one residency episode, so this is
/// that owner: the streaming manager holds one store for the world and hands
/// the same instance to every chunk it generates, which makes reservation
/// survival independent of the eviction policy. A reference type for exactly
/// that reason — every chunk shares this one, it is never copied.
final class LotReservationStore {
    private var reserved: Set<TileCoordinate> = []

    /// Every reserved world tile, across every chunk, resident or not.
    var allReservedTiles: Set<TileCoordinate> { reserved }

    /// Whether `tile` is already claimed by a reserved footprint.
    func isReserved(_ tile: TileCoordinate) -> Bool {
        reserved.contains(tile)
    }

    /// The reserved tiles falling inside `chunk`'s own 8x8 world-tile
    /// footprint. Lets a `Chunk` expose chunk-local reservation state
    /// (`Chunk.reservedTiles`) while the storage itself stays global.
    func reservedTiles(inChunk chunk: ChunkCoordinate) -> Set<TileCoordinate> {
        let worldOrigin = chunk.worldTileOrigin
        let xRange = worldOrigin.tileX..<(worldOrigin.tileX + Chunk.size)
        let yRange = worldOrigin.tileY..<(worldOrigin.tileY + Chunk.size)
        return reserved.filter { xRange.contains($0.tileX) && yRange.contains($0.tileY) }
    }

    /// Claims `tiles`. Callers are expected to have validated them first
    /// (`Chunk.reserve` is the only intended caller, and it does).
    func reserve<Tiles: Sequence>(_ tiles: Tiles) where Tiles.Element == TileCoordinate {
        reserved.formUnion(tiles)
    }
}

/// The world-grid footprint size a placeable building reserves, per the
/// design brief's 1x1 / 2x2 building table (`BuildingSprite.Footprint`).
/// Kept as its own type here (rather than importing `BuildingSprite`'s
/// nested enum) because footprint reservation is a `World`-layer concern
/// that must stay independent of the `Assets` layer — the
/// building-placement story (`CYBERPUN-17-5`) is the piece that will
/// translate between the two.
enum BuildingFootprintSize: CaseIterable, Equatable {
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
/// Holds the tile grid produced by `ChunkGenerator.generate` plus the
/// building-footprint reservation state covering it, so a future
/// building-placement story (`CYBERPUN-17-5`) can claim footprints without a
/// second data structure. A reference type (not a value type) because
/// reservation state must be readable/mutable in place while the streaming
/// manager and any future renderer hold the same chunk — mirroring it
/// through a struct would silently desync copies.
final class Chunk {
    /// Tiles per side. The design brief's fixed chunk size
    /// (`docs/bootstrap.md`: "8x8 tile chunks").
    static let size = 8

    /// The one `TileKind` that building placement reserves against.
    ///
    /// Pinned as a named constant (rather than spelled inline in
    /// `canReserve`) because the polarity here is easy to get backwards and
    /// `CYBERPUN-17-5` builds directly on it:
    ///
    /// - `CityLatticeGenerator.blockInteriorTileKind` decides a whole 3x3
    ///   block interior at once. The ~3-in-4 blocks where buildings stand
    ///   come out `.buildingFootprint`; the ~1-in-4 blocks the brief
    ///   deliberately leaves **empty** come out `.lot`.
    /// - So the placement surface is `.buildingFootprint`, *not* `.lot`.
    ///   Reserving inside `.lot` would put buildings in exactly the blocks
    ///   the brief empties out, and would leave the building blocks
    ///   unreservable — the inverse of the brief ("buildings fill the 3x3
    ///   block interior; ~1-in-4 blocks are left as empty lots").
    ///
    /// This also settles how a reservation becomes **solid**, which is why
    /// `tiles` can stay `let`: the placement surface is already the
    /// not-walkable kind (`TileKind.buildingFootprint.isWalkable == false`)
    /// straight out of `classify`, so a reserved footprint collides by
    /// construction and no tile-kind transition is needed. Reservation
    /// answers "which building goes where" (so two placed buildings never
    /// share a tile); collision is settled by the lattice itself, and
    /// nothing that consults `TileKind.isWalkable` needs to know about
    /// `reservedTiles` at all. Conversely, an empty `.lot` stays walkable
    /// forever, because no building is ever placed on one.
    static let placementSurface: TileKind = .buildingFootprint

    /// This chunk's position in chunk space. Named `origin` (rather than
    /// `coordinate`) per the implementation plan — not to be confused with
    /// `worldTileOrigin` below, which is this same value expressed in world
    /// tile space.
    let origin: ChunkCoordinate

    /// The 8x8 tile grid, indexed `tiles[localX][localY]` with
    /// `localX, localY` both in `0..<Chunk.size`. Each entry's own
    /// `tileX`/`tileY` are in *world* tile space (`origin.worldTileOrigin`
    /// offset by the local index), so a `TileInfo` pulled out of a chunk is
    /// indistinguishable from one produced by calling `classify` directly.
    let tiles: [[TileInfo]]

    /// Where this chunk's footprint reservations actually live.
    ///
    /// Deliberately *not* per-instance state: the streaming manager evicts
    /// and regenerates `Chunk` instances as the camera roams, so state stored
    /// on the instance would silently vanish on eviction. Injected (with a
    /// fresh private store by default) so a standalone chunk — a test, or a
    /// one-off `ChunkGenerator.generate` call — still behaves like a
    /// self-contained object. See `LotReservationStore`.
    let reservations: LotReservationStore

    /// World tile coordinates *within this chunk* currently claimed by a
    /// reserved footprint. Reads through to `reservations`, so it survives
    /// this instance being evicted and regenerated. Tracked as a flat set
    /// (rather than only the per-footprint list) so overlap checks are
    /// O(footprint size) instead of O(reservation count).
    var reservedTiles: Set<TileCoordinate> {
        reservations.reservedTiles(inChunk: origin)
    }

    init(
        origin: ChunkCoordinate,
        tiles: [[TileInfo]],
        reservations: LotReservationStore = LotReservationStore()
    ) {
        precondition(tiles.count == Chunk.size, "Chunk must have exactly \(Chunk.size) columns, got \(tiles.count)")
        precondition(
            tiles.allSatisfy { $0.count == Chunk.size },
            "Chunk must have exactly \(Chunk.size) rows per column"
        )
        self.origin = origin
        self.tiles = tiles
        self.reservations = reservations
    }

    /// The tile at local grid position `(localX, localY)`, both expected in
    /// `0..<Chunk.size`.
    func tile(localX: Int, localY: Int) -> TileInfo {
        tiles[localX][localY]
    }

    // MARK: - Building-footprint reservation

    /// Every world-tile origin, within this chunk only, where a footprint of
    /// `size` could be reserved right now: every tile it would cover is
    /// classified `Chunk.placementSurface` (`.buildingFootprint` — see that
    /// constant for why the building blocks, and never the deliberately
    /// empty `.lot` blocks, are the placement surface) and not already
    /// reserved.
    ///
    /// Deliberately chunk-local — a footprint is never considered if it
    /// would cross into a neighbouring chunk, keeping this consistent with
    /// `ChunkGenerator`'s no-cross-chunk-lookups rule.
    ///
    /// **Known coverage limit of that rule:** `Chunk.size` (8) is not a
    /// multiple of the lattice's `CityLatticeGenerator.period` (6), so most
    /// 3x3 block interiors straddle a chunk boundary, and a `.twoByTwo`
    /// footprint that would sit across the seam is never offered by either
    /// side. Accepted deliberately: keeping generation and reservation
    /// strictly chunk-local is the stronger invariant (it is what makes AC2
    /// true by construction), and the placement story only needs *some*
    /// legal footprints per block, not all of them. `CYBERPUN-17-5` should
    /// treat this list as "footprints this chunk can offer on its own",
    /// not as "every footprint that geometrically fits in the city".
    func reservableFootprints(in size: BuildingFootprintSize) -> [TileCoordinate] {
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
    /// is `footprintOrigin`. Returns `false` (no mutation) if any covered
    /// tile is outside this chunk, is not `Chunk.placementSurface`, or is
    /// already reserved — this is the check that keeps 1x1/2x2 buildings
    /// from ever overlapping each other.
    ///
    /// The claim lands in `reservations`, which outlives this instance, so a
    /// reservation is not lost when the streaming manager evicts this chunk
    /// and regenerates it on revisit.
    @discardableResult
    func reserve(footprint size: BuildingFootprintSize, at footprintOrigin: TileCoordinate) -> Bool {
        guard canReserve(size, at: footprintOrigin) else { return false }
        reservations.reserve(coveredTiles(size, at: footprintOrigin))
        return true
    }

    /// Whether every tile a `size` footprint at `footprintOrigin` would
    /// cover is in-bounds for this chunk, classified
    /// `Chunk.placementSurface`, and not already reserved.
    private func canReserve(_ size: BuildingFootprintSize, at footprintOrigin: TileCoordinate) -> Bool {
        let covered = coveredTiles(size, at: footprintOrigin)
        guard covered.count == size.tileSpan * size.tileSpan else { return false }
        return covered.allSatisfy { tile in
            guard let info = tileInfo(atWorldTileX: tile.tileX, worldTileY: tile.tileY) else { return false }
            return info.kind == Chunk.placementSurface && !reservations.isReserved(tile)
        }
    }

    /// The set of world tile coordinates a `size` footprint at
    /// `footprintOrigin` would occupy. Empty if any covered tile falls
    /// outside this chunk.
    private func coveredTiles(_ size: BuildingFootprintSize, at footprintOrigin: TileCoordinate) -> [TileCoordinate] {
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
