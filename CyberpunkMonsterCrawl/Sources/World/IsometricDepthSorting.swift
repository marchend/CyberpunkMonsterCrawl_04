import CoreGraphics

/// Building-specific entry point into `DepthModel`'s painter's-algorithm
/// depth scheme (`Sources/World/DepthModel.swift`).
///
/// `DepthModel` (`CYBERPUN-17-4-t1`) already reserves `buildingContentRange`
/// (`0..<3`, strictly below `actorOffsetRange`) for "building content (walls,
/// rooftop signs, etc.)" within a tile's own band, and its own doc comment on
/// `band(forTile:)` already states the painter's-algorithm ordering rule this
/// module leans on. This file adds nothing to that formula \u2014 it only names
/// the one extra decision building placement needs: *which* tile of a
/// (possibly multi-tile) footprint supplies the band. Every non-building
/// caller of `DepthModel` (ground tiles, actors) is untouched.
///
/// **AC4: depth keys off the far corner, never the base tile.** A building's
/// footprint can span more than one tile-sum band (a 2x2 building's near and
/// far corners differ by 2 in `tileX + tileY`), so a single building must
/// still pick one band to draw in. Keying off the *far* corner \u2014 the tile
/// with the greatest `tileX + tileY` across the whole footprint \u2014 is what
/// keeps a building from ever drawing over an actor standing anywhere in
/// front of any part of its footprint: `DepthModel.band(forTile:)` is
/// monotonically decreasing in `tileX + tileY`
/// (`DepthModelTests.test_bandFormula_isMonotonicallyDecreasing_asTileSumIncreases`),
/// so any tile with a *smaller* sum than the far corner resolves a strictly
/// greater band \u2014 and therefore a strictly greater zPosition once both
/// values pick up the same worldLayer-relative conversion \u2014 no matter how
/// close or far that tile actually is. Keying off the *base* tile (the
/// footprint's near corner) would not have this property: a building whose
/// footprint reaches farther than its base tile could then draw over an
/// actor standing on one of its own far tiles.
enum IsometricDepthSorting {
    /// The absolute zPosition a building sprite whose footprint's far corner
    /// is `(tileX, tileY)` should use: that tile's `DepthModel` band, placed
    /// at the *floor* of `DepthModel.buildingContentRange` (offset `0`) \u2014
    /// the same in-band slot the depth module already reserves for building
    /// content, so a building's own zPosition can never spill into
    /// `DepthModel.actorOffsetRange` within the same band.
    static func zPosition(forBuildingFarCornerTileX tileX: Int, tileY: Int) -> CGFloat {
        zPosition(forBuildingFarCornerTile: TileCoordinate(tileX: tileX, tileY: tileY))
    }

    /// Convenience overload for callers already holding a `TileCoordinate`.
    static func zPosition(forBuildingFarCornerTile tile: TileCoordinate) -> CGFloat {
        DepthModel.band(forTile: tile) + DepthModel.buildingContentRange.lowerBound
    }

    /// The far corner among `footprintTiles`: the tile with the greatest
    /// `tileX + tileY`. Re-derived from the raw tile list (rather than only
    /// trusting a caller's already-stored `BuildingPlacementRecord
    /// .farCornerTile`) so a caller \u2014 and `BuildingDepthAndAnchorTests` \u2014
    /// can confirm the depth key really is a function of the footprint
    /// tiles, not of the record's base tile.
    ///
    /// `nil` for an empty list; every real `BuildingPlacementRecord` produced
    /// by `BuildingPlacement.generate` has at least one footprint tile, so
    /// this is only reachable from a malformed fixture.
    static func farCornerTile(amongFootprintTiles footprintTiles: [TileCoordinate]) -> TileCoordinate? {
        footprintTiles.max { ($0.tileX + $0.tileY) < ($1.tileX + $1.tileY) }
    }
}
