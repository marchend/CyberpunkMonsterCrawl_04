import CoreGraphics

/// Single source of truth for the world layer's painter's-algorithm depth
/// rules (`docs/bootstrap.md` §4).
///
/// Every world-space node (ground plane, building sprite, actor) picks its
/// `zPosition` from here rather than computing depth ad hoc at each call
/// site. That matters because the painter's-algorithm illusion (things
/// "south-east" on the isometric grid must draw over things "north-west" of
/// them) depends on every layer agreeing on the same numeric scheme; a
/// single call site that invents its own offset silently breaks draw order
/// for exactly the tiles/actors near that boundary.
///
/// Depth is organised as a **band per diagonal** of the tile grid
/// (`tileX + tileY` constant along a band), with a fixed-width slot inside
/// each band for the different kinds of content that can occupy it (ground,
/// building content, actors). Bands never overlap because the in-band
/// ranges below are all strictly narrower than `bandSpacing`.
enum DepthModel {

    // MARK: - Band formula

    /// The zPosition spacing between adjacent diagonal bands. Chosen wide
    /// enough (10) that every in-band range below (`buildingContentRange`,
    /// `actorOffsetRange`) fits inside a single band with room to spare,
    /// so content offsets from one band can never bleed into the next.
    static let bandSpacing: CGFloat = 10

    /// The depth band for world tile `(tileX, tileY)`: `-(tileX + tileY) *
    /// 10`, per the design brief's fixed formula.
    ///
    /// This is monotonically **decreasing** as `tileX + tileY` increases:
    /// tile `(2, 2)` (sum 4) gets a smaller (more negative) band than tile
    /// `(1, 1)` (sum 2). Combined with SpriteKit's y-up axis and this
    /// game's isometric screen transform (`IsometricProjection
    /// .tileToScreen`, `docs/bootstrap.md` \u00a74), that ordering is what
    /// produces correct painter's-algorithm draw order along the world's
    /// diagonals \u2014 do not flip the sign without re-deriving that mapping,
    /// and see `DepthModelTests
    /// .test_bandFormula_isMonotonicallyDecreasing_asTileSumIncreases` for
    /// the pinned direction. Every band this formula can produce for the
    /// tile ranges a streamed chunk radius actually reaches stays
    /// comfortably inside `LayerConstants.worldMinZ...LayerConstants
    /// .worldMaxZ`.
    static func band(forTile tile: TileCoordinate) -> CGFloat {
        -CGFloat(tile.tileX + tile.tileY) * bandSpacing
    }

    // MARK: - Ground

    /// The ground plane sits `5000` below *every* band, unconditionally.
    /// This constant is the entire ground rule \u2014 do not special-case any
    /// band's ground offset without updating `groundOffset` itself, and
    /// never move this value without re-checking
    /// `DepthModelTests.test_groundZPosition_isAlwaysBandMinusFiveThousand`,
    /// which sweeps a wide range of bands to pin the invariant.
    static let groundOffset: CGFloat = -5000

    /// The ground plane's zPosition for a given band: `band + groundOffset`
    /// (equivalently `band - 5000`). Kept as a function of `band` (rather
    /// than a fixed constant) because the ground tile drawn under a
    /// particular `(tileX, tileY)` still needs to sit strictly below that
    /// tile's own band-content \u2014 and below every other band's ground too,
    /// since ground tiles from different bands can be visually adjacent on
    /// screen and must never fight each other for draw order. `-5000` is
    /// comfortably wider than any gap between bands actually reachable by a
    /// streamed chunk radius, so ground never has to compete with band
    /// content from a *different* band either.
    static func groundZPosition(forBand band: CGFloat) -> CGFloat {
        band + groundOffset
    }

    /// Convenience overload for callers that only have the tile, not an
    /// already-computed band.
    static func groundZPosition(forTile tile: TileCoordinate) -> CGFloat {
        groundZPosition(forBand: band(forTile: tile))
    }

    // MARK: - In-band content ranges

    /// The zPosition offset range, relative to a tile's own `band`, that
    /// building content (walls, rooftop signs, etc.) may occupy.
    ///
    /// Strictly `< 3` so building content can never reach into
    /// `actorOffsetRange` (`6.5...9.9`), which starts well past the next
    /// integer boundary below `bandSpacing` (10) \u2014 i.e. building content
    /// always draws behind an actor standing in front of it within the same
    /// band, and never spills into the next band up (`+bandSpacing`).
    static let buildingContentRange: Range<CGFloat> = 0..<3

    /// The zPosition offset range, relative to a tile's own `band`, that
    /// actors (player, raccoons) may occupy. Deliberately starts above
    /// `buildingContentRange` (so an actor always draws in front of
    /// building content in the same band) and stays strictly below
    /// `bandSpacing` (10), so an actor offset can never cross into the next
    /// band.
    static let actorOffsetRange: ClosedRange<CGFloat> = 6.5...9.9

    /// Whether `offset` is a legal building-content offset within a band.
    /// A small validator other modules can call in debug builds rather than
    /// re-deriving `buildingContentRange`'s bound inline.
    static func isValidBuildingContentOffset(_ offset: CGFloat) -> Bool {
        buildingContentRange.contains(offset)
    }

    /// Whether `offset` is a legal actor offset within a band.
    static func isValidActorOffset(_ offset: CGFloat) -> Bool {
        actorOffsetRange.contains(offset)
    }

    // MARK: - Actor band resolution (rounded, not continuous)

    /// The band an actor standing at a fractional tile-space `position`
    /// (`IsometricProjection.TilePoint`) draws in.
    ///
    /// This rounds `position` to its nearest whole tile
    /// (`IsometricProjection.tile(containing:)` \u2014 the same pinned
    /// `floor(coordinate + 0.5)` rule buildings use to decide their own base
    /// tile, so an actor's depth snaps to the same seam a building's does)
    /// and feeds *that* into `band(forTile:)`.
    ///
    /// This is **intentionally discontinuous**: an actor's zPosition jumps
    /// once per tile crossed rather than sliding smoothly with its
    /// fractional position. Do not "improve" this to continuous depth (e.g.
    /// interpolating `band` by fractional `tileX + tileY`) \u2014 painter's-
    /// algorithm draw order in this game is decided per discrete diagonal,
    /// matching how buildings themselves are placed on whole tiles; a
    /// continuous actor depth would let an actor's zPosition drift across a
    /// building's band boundary before it has actually crossed the
    /// corresponding tile edge, producing a visible pop/flicker against
    /// building content that never moves continuously.
    static func band(forActorAt position: TilePoint) -> CGFloat {
        let owningTile = IsometricProjection.tile(containing: position)
        return band(forTile: TileCoordinate(tileX: owningTile.tileX, tileY: owningTile.tileY))
    }

    // MARK: - Cross-reference with the UI layer

    /// Documentation-only note (per this PR's scope \u2014 there is no runtime
    /// check here against UI code that doesn't exist yet): the world
    /// layer's zPosition ceiling is `LayerConstants.worldMaxZ` (`-1_000`,
    /// `Layers/LayerConstants.swift`), referenced directly (not duplicated)
    /// so the two constants can never drift apart. Every band this module
    /// can produce for the tile ranges a streamed chunk radius actually
    /// reaches (plus `actorOffsetRange`'s `+9.9` at most) must stay
    /// strictly below that ceiling, which in turn is strictly below
    /// `LayerConstants.uiMinZ` (`1_000`) \u2014 `LayerOrderingTests` pins
    /// `worldMaxZ < uiMinZ` on the UI-layer side of that boundary.
    static let worldLayerCeilingCrossReference: CGFloat = LayerConstants.worldMaxZ
}
