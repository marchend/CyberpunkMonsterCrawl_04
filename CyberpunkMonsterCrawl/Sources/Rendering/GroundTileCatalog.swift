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
/// The six-way mapping itself, from the story's asset contract. Every kind
/// takes the diamond that carries its own name — `.asphaltEastWest` takes
/// `laneEastWest`, `.asphaltNorthSouth` takes `laneNorthSouth` — and which
/// crop each of those names is bound to was **measured** off the shipped
/// pixels rather than read off the sheet's left-to-right order: the pack ships
/// the featureless bare-ground diamond first (`plainLot`, the crop at **x:0**,
/// the one asphalt-toned crop with no paint on it), the north-south lane
/// second (`laneNorthSouth`, at **x:96**, its dash on the tile-Y diagonal) and
/// the east-west lane third (`laneEastWest`, at **x:192**, its dash on the
/// tile-X diagonal), so `AtlasGroundDiamond` names them that way round (every
/// number here read off `AtlasGroundDiamond.pixelRect` in
/// `Sources/Assets/AtlasSheet.swift`, which stays the one source of truth for
/// the pixel arithmetic).
///
/// That pairing is not left as prose either.
/// `GroundTileSemanticsTests
/// .test_eachLaneCrop_carriesPaintElongatedAlongTheAxisItsCaseNameClaims`
/// re-measures the shipped pixels and fails if the two are swapped. Its
/// measurement is comparative rather than a fixed pixel count: the crop
/// `diamond(for: .asphaltEastWest)` returns must carry paint whose
/// brightness-weighted spread along tile X exceeds its spread along tile Y
/// (`elongationRatio > 1`), and `.asphaltNorthSouth`'s crop the reverse.
/// That test's failure messages print the measured `alongTileX`/`alongTileY`
/// numbers for both crops, so a red run reports which crop is which instead
/// of leaving the reader to re-measure by hand.
///
/// **If it does go red, fix the assignment — never edit this comment to
/// match the art.** It has gone red once already: the lane pair was
/// originally bound the other way round (`laneEastWest` naming the x:0
/// crop), the measurement showed that crop's paint running along tile *Y*,
/// and the fix was to re-bind `AtlasGroundDiamond`'s two lane cases to the
/// crops they actually hold rather than to soften the test. The mapping is
/// the thing under test, and prose disagreeing with the pixels is how a
/// later reader ends up inverting every street in the city:
/// - `.asphaltNorthSouth` -> `AtlasGroundDiamond.laneNorthSouth` (x:0,   96x60)
/// - `.asphaltEastWest`   -> `AtlasGroundDiamond.laneEastWest`   (x:96,  96x60)
/// - `.lot`               -> `AtlasGroundDiamond.plainLot`       (x:192, 96x60)
/// - `.junctionStopLine`  -> `AtlasGroundDiamond.intersection`   (x:288, 96x60)
/// - `.kerbSidewalk`      -> `AtlasGroundDiamond.kerbTransition` (x:384, 96x60)
/// - `.buildingFootprint` -> `AtlasGroundDiamond.overhangLot`    (x:480, 112x60)
///
/// ## Geometry is measured; *meaning* is what this table adds
///
/// `AtlasGroundDiamondTests` measures geometry only — 592x60, the content
/// bounding box, the `5x96 + 112` partition, and that each sub-rect's
/// content is non-empty and centred. None of that says the crop at `x:0`
/// depicts an **east-west** lane rather than a north-south one, so a table
/// like the one above, checked only against a copy of itself, would guard
/// typos and nothing else: swapping the two lane rows would leave every
/// `GroundTileCatalogTests` assertion green while every corridor in the
/// city rendered with its lane markings running *across* the direction of
/// travel.
///
/// `GroundTileSemanticsTests` is therefore the pin for the semantic axis,
/// and it re-measures the shipped pixels at test time rather than comparing
/// this table to a second copy of itself:
/// - **all six assignments**: each crop must hold art distinct from the
///   other five (a fingerprint over the crop's decoded RGBA), so no two
///   kinds can be pointed at the same diamond and no kind can be pointed at
///   a duplicate.
/// - **the two lane assignments**: the painted marking on each lane crop
///   must be elongated along the tile axis its case name claims. The two
///   corridor axes project to the two *opposite* screen diagonals
///   (`IsometricProjection.tileToScreen`: tile +X runs up-and-right, tile +Y
///   up-and-left), so "which diagonal is this crop's paint stretched along"
///   is a measurable question with a two-valued answer, and a swapped pair
///   fails it.
/// - **`.junctionStopLine` -> `.intersection`**: which tiles of a crossing
///   carry junction paint is not this file's decision at all —
///   `CityLatticeGenerator.streetTileKind` already pins it (the four lane
///   *mouths* of a 3x3 crossing are `.junctionStopLine`, the centre is plain
///   `.asphalt`, the four corners continue the `kerbSidewalk` ring). This
///   catalog only names the art for a kind the lattice has already decided;
///   moving junction paint onto the crossing centre would mean changing the
///   lattice, not the crop table. See `GroundTileRenderer
///   .asphaltOrientation(at:)` for the crossing-centre case.
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
