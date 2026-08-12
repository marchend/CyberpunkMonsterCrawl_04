import CoreGraphics

/// The ground-plane's own vocabulary of "what to draw on this tile",
/// separate from `TileKind` (the world generator's walkability/lattice
/// vocabulary) because `TileKind.asphalt` alone does not say which way the
/// street corridor runs, and the ground plane needs that to pick between
/// the sheet's two lane diamonds. `GroundTileRenderer` is the one place
/// that maps a `TileKind` (plus its tile coordinate, for asphalt's
/// orientation) onto one of these six cases.
///
/// This intentionally covers exactly the sheet's six diamonds — no more,
/// no fewer — so `GroundTileCatalogTests` can assert a 1:1, exhaustive
/// correspondence with `AtlasGroundDiamond.allCases`.
enum GroundTileKind: CaseIterable {
    /// A street corridor running east–west (the corridor's band sits on
    /// the tile-Y axis; every tile in the band shares the same `yMod` while
    /// `x` is unconstrained).
    case asphaltEastWest
    /// A street corridor running north–south (the corridor's band sits on
    /// the tile-X axis).
    case asphaltNorthSouth
    /// The painted stop-line dash at a lattice crossing's lane mouths.
    case junctionStopLine
    /// The kerb/sidewalk band bordering a street corridor (including a
    /// crossing's four sidewalk corners).
    case kerbSidewalk
    /// A seed-chosen empty block interior: bare walkable ground.
    case lot
    /// A block interior reserved for a building: ground drawn *under* the
    /// building sprite, using the sheet's overhang-lot diamond so the
    /// building's base overhang reads correctly against the tile beneath
    /// it (`CYBERPUN-17-5` places the building itself; this PR only wires
    /// the ground tile that sits underneath).
    case buildingFootprint
}

/// Maps each `GroundTileKind` to its measured sub-rect on `tileset_ground`.
///
/// **This does not re-measure or re-derive the six pixel rects.** The
/// authoritative measurement — sheet dimensions (592x60px), the alpha-scan
/// content bounding box, and the `5x96 + 112` partition across the sheet's
/// width — is already recorded once, in `AtlasSheet.swift`'s
/// `AtlasGroundDiamond` doc comment, and pinned at test time by
/// `AtlasGroundDiamondTests`. Restating those six `CGRect` literals here
/// would create a second copy that could silently drift from the measured
/// one; instead this catalog is a pure semantic relabeling — "ground tile
/// kind" (what the world generator/renderer cares about) onto "diamond
/// index" (what the sheet measurement is keyed by) — so `AtlasSheet.swift`
/// stays the single source of truth for the pixel arithmetic.
///
/// The six-way mapping itself, from the story's asset contract:
/// - `.asphaltEastWest`   -> `AtlasGroundDiamond.laneEastWest`   (x:0,   96x60)
/// - `.asphaltNorthSouth` -> `AtlasGroundDiamond.laneNorthSouth` (x:96,  96x60)
/// - `.lot`               -> `AtlasGroundDiamond.plainLot`       (x:192, 96x60)
/// - `.junctionStopLine`  -> `AtlasGroundDiamond.intersection`   (x:288, 96x60)
/// - `.kerbSidewalk`      -> `AtlasGroundDiamond.kerbTransition` (x:384, 96x60)
/// - `.buildingFootprint` -> `AtlasGroundDiamond.overhangLot`    (x:480, 112x60)
enum GroundTileCatalog {
    /// The `AtlasGroundDiamond` backing `kind`.
    static func diamond(for kind: GroundTileKind) -> AtlasGroundDiamond {
        switch kind {
        case .asphaltEastWest:
            return .laneEastWest
        case .asphaltNorthSouth:
            return .laneNorthSouth
        case .junctionStopLine:
            return .intersection
        case .kerbSidewalk:
            return .kerbTransition
        case .lot:
            return .plainLot
        case .buildingFootprint:
            return .overhangLot
        }
    }

    /// The measured top-left-origin pixel rect for `kind`, ready to pass to
    /// `SpriteSheet.texture(forPixelRect:)` via `AtlasSheet.groundTiles`.
    static func pixelRect(for kind: GroundTileKind) -> CGRect {
        diamond(for: kind).pixelRect
    }
}
