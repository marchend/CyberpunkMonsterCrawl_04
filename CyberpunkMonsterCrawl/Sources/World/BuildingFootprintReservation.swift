import Foundation

/// A local, per-block reservation grid for building-footprint placement:
/// tracks which world tiles within one block's 3x3 interior are already
/// claimed by a placed building, so `BuildingPlacement.generate` can ask
/// "would this footprint fit and is it free" before committing.
///
/// Deliberately independent of `LotReservationStore` (`Chunk.swift`): that
/// store is scoped to the whole world's lifetime, owned above the chunk
/// cache, and exists to survive a chunk being evicted and regenerated.
/// `BuildingFootprintReservation` is scoped to a single
/// `BuildingPlacement.generate` call — one block, one walk over its 3x3
/// interior — mirroring `LotReservationStore`'s no-overlap contract at a
/// smaller grain, using the same `TileCoordinate` currency so a caller that
/// later folds these decisions into the world-lifetime store never has to
/// translate coordinate spaces.
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
