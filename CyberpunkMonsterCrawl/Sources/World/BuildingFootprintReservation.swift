import Foundation

/// A local, per-block reservation grid for building-footprint placement:
/// tracks which world tiles within one block's 3x3 interior are already
/// claimed by a placed building, so `BuildingPlacement.generate` can ask
/// "would this footprint fit and is it free" before committing.
///
/// A *scratch* grid, not a second source of truth. It is scoped to a single
/// `BuildingPlacement.generate` call — one block, one walk over its 3x3
/// interior — and is thrown away when that call returns;
/// `LotReservationStore` (`Chunk.swift`) remains the world's one owner of
/// "which tiles are occupied", scoped to the whole world's lifetime and
/// held above the chunk cache so it survives eviction and regeneration.
///
/// The two are joined, not independent: `ChunkGenerator.generate` folds
/// every resulting `BuildingPlacementRecord.footprintTiles` into that
/// world-lifetime store. That fold is what keeps the two systems from
/// disagreeing — without it `chunk.reservedTiles` would stay empty even for
/// a chunk full of buildings, and `Chunk.reservableFootprints(in:)` would
/// offer tile origins a placed building is standing on. The fold is
/// idempotent: placement is a pure function of `(block, seed)` and
/// `LotReservationStore.reserve` is a set union, so re-generating an evicted
/// chunk re-folds exactly the same tiles and changes nothing.
///
/// This type exists because the store cannot answer the *mid-walk* question
/// — "has the lot two steps back in this same interior already claimed this
/// tile?" — before the block's decisions are committed. It mirrors
/// `LotReservationStore`'s no-overlap contract at that smaller grain, in the
/// same `TileCoordinate` currency, so the fold needs no coordinate
/// translation.
struct BuildingFootprintReservation: Equatable {
    private var reserved: Set<TileCoordinate> = []

    init() {}

    /// Every tile already claimed by a reservation made through this value.
    var reservedTiles: Set<TileCoordinate> { reserved }

    /// Whether `tile` is already claimed.
    func isReserved(_ tile: TileCoordinate) -> Bool {
        reserved.contains(tile)
    }

    /// Whether a `span` x `span` footprint whose lower-corner world tile is
    /// `origin` would (a) lie entirely within the block interior whose own
    /// lower-corner world tile is `blockInteriorOrigin` and spans
    /// `interiorSize` tiles on each axis, and (b) claim no tile already
    /// reserved.
    ///
    /// The explicit query `BuildingPlacement.generate` calls before ever
    /// committing a reservation — never inferred from a failed `reserve`.
    func fitsWithinBlockInterior(
        span: Int,
        at origin: TileCoordinate,
        blockInteriorOrigin: TileCoordinate,
        interiorSize: Int = CityLatticeGenerator.blockSize
    ) -> Bool {
        guard span > 0 else { return false }
        guard origin.tileX >= blockInteriorOrigin.tileX, origin.tileY >= blockInteriorOrigin.tileY else {
            return false
        }
        guard
            origin.tileX + span <= blockInteriorOrigin.tileX + interiorSize,
            origin.tileY + span <= blockInteriorOrigin.tileY + interiorSize
        else {
            return false
        }
        return coveredTiles(span: span, at: origin).allSatisfy { !reserved.contains($0) }
    }

    /// Attempts to reserve a `span` x `span` footprint at `origin`. A no-op
    /// (returns `false`, no mutation) unless `fitsWithinBlockInterior` would
    /// already agree — callers that skip the query and call this directly
    /// still only ever get a full reservation or a full refusal, never a
    /// partial one.
    @discardableResult
    mutating func reserve(
        span: Int,
        at origin: TileCoordinate,
        blockInteriorOrigin: TileCoordinate,
        interiorSize: Int = CityLatticeGenerator.blockSize
    ) -> Bool {
        guard fitsWithinBlockInterior(
            span: span,
            at: origin,
            blockInteriorOrigin: blockInteriorOrigin,
            interiorSize: interiorSize
        ) else {
            return false
        }
        reserved.formUnion(coveredTiles(span: span, at: origin))
        return true
    }

    /// The tiles a `span` x `span` footprint at `origin` would cover, with
    /// no bounds/overlap checking of its own — callers that already
    /// validated via `fitsWithinBlockInterior` use this to build a
    /// placement record's `footprintTiles`.
    func coveredTiles(span: Int, at origin: TileCoordinate) -> [TileCoordinate] {
        guard span > 0 else { return [] }
        var result: [TileCoordinate] = []
        result.reserveCapacity(span * span)
        for dx in 0..<span {
            for dy in 0..<span {
                result.append(TileCoordinate(tileX: origin.tileX + dx, tileY: origin.tileY + dy))
            }
        }
        return result
    }
}
