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
///
/// ## Absolute cumulative z, anchored at `worldBaseZ`
///
/// Every zPosition this module returns is an **absolute cumulative**
/// zPosition \u2014 the value `GameScene.nodesEscapingTheirLayerBand()` audits
/// after SpriteKit has accumulated `zPosition` down the node tree \u2014 and it
/// is anchored at `worldBaseZ`, the midpoint of `LayerConstants.worldBand`.
/// The brief's band formula on its own is a *relative ordering rule*, not a
/// zPosition: unanchored, `band((0, 0))` is `0`, which sits above
/// `LayerConstants.worldMaxZ` (`-1_000`) and, once `tileX + tileY` drops
/// past `-100`, above `LayerConstants.uiMinZ` too \u2014 world content
/// out-painting the UI, which is precisely the v1 failure `LayerConstants`
/// and `SceneInvariants` exist to make impossible.
///
/// Because these are absolute values and `GameScene.worldLayer` already sits
/// at `LayerConstants.worldLayerZ` (`== worldMinZ`), a node parented
/// **directly** under `worldLayer` must be given
/// `worldLayerRelativeZ(forAbsoluteZ:)` rather than the absolute value;
/// assigning the absolute value to a child would double-count the
/// container's own offset and drop the node clean through the band floor.
/// `isWithinWorldBand(_:)` and `maxSupportedTileSumMagnitude` state the
/// range this scheme is valid over, and `DepthModelTests` sweeps it rather
/// than asserting it in prose.
enum DepthModel {

    // MARK: - Band formula

    /// The zPosition spacing between adjacent diagonal bands. Chosen wide
    /// enough (10) that every in-band range below (`buildingContentRange`,
    /// `actorOffsetRange`) fits inside a single band with room to spare,
    /// so content offsets from one band can never bleed into the next.
    static let bandSpacing: CGFloat = 10

    /// The anchor every value this module returns is offset from: the
    /// midpoint of `LayerConstants.worldBand`.
    ///
    /// Parked in the *middle* of the band rather than at either end so the
    /// band formula gets equal headroom in both directions (`49_500` each
    /// way at today's constants) \u2014 the world is endless and `classify` /
    /// `ChunkStreamingManager` handle negative tiles fine, so a player
    /// heading north-west drives `tileX + tileY` negative (bands climbing
    /// *up*) exactly as readily as south-east drives it positive (bands and
    /// their ground planes heading *down*). `maxSupportedTileSumMagnitude`
    /// is what that headroom buys, and it is symmetric for this reason.
    static let worldBaseZ: CGFloat = (LayerConstants.worldMinZ + LayerConstants.worldMaxZ) / 2

    /// The raw band *offset* for world tile `(tileX, tileY)`:
    /// `-(tileX + tileY) * 10`, per the design brief's fixed formula.
    ///
    /// This is the brief's ordering rule on its own, before anchoring. It is
    /// exposed (and pinned by
    /// `DepthModelTests.test_bandOffsetFormula_matchesNegatedSumTimesTen`)
    /// so the formula stays literally checkable against the brief, but no
    /// call site should assign it to a `zPosition` \u2014 use `band(forTile:)`,
    /// which anchors it inside `LayerConstants.worldBand`.
    static func bandOffset(forTile tile: TileCoordinate) -> CGFloat {
        -CGFloat(tile.tileX + tile.tileY) * bandSpacing
    }

    /// The depth band for world tile `(tileX, tileY)`: `worldBaseZ +
    /// bandOffset(forTile:)`, i.e. the brief's `-(tileX + tileY) * 10`
    /// anchored to an absolute zPosition inside `LayerConstants.worldBand`.
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
    /// the pinned direction.
    ///
    /// Range: every value this returns \u2014 together with the deepest ground
    /// offset below it and the highest actor offset above it \u2014 stays inside
    /// `LayerConstants.worldBand` for every tile whose
    /// `|tileX + tileY| <= maxSupportedTileSumMagnitude`. That is a swept,
    /// asserted fact (`DepthModelTests
    /// .test_depthOutputs_stayInsideWorldBand_acrossEverySupportedTileSum`),
    /// checked through the same inclusive containment rule the runtime audit
    /// uses, not a prose claim. Outside that range the model has simply run
    /// out of band; `isWithinSupportedDepthRange(forTile:)` reports it so a
    /// consumer can trip an assertion, rather than clamping (which would
    /// silently collapse two diagonals into one draw order).
    static func band(forTile tile: TileCoordinate) -> CGFloat {
        worldBaseZ + bandOffset(forTile: tile)
    }

    // MARK: - Ground

    /// The ground plane sits `5000` below its *own* band, unconditionally.
    /// This constant is the entire ground rule \u2014 do not special-case any
    /// band's ground offset without updating `groundOffset` itself, and
    /// never move this value without re-checking
    /// `DepthModelTests.test_groundZPosition_isAlwaysBandMinusFiveThousand`,
    /// which sweeps a wide range of bands to pin the invariant.
    static let groundOffset: CGFloat = -5000

    /// How many whole bands `groundOffset` clears: `5000 / 10 == 500`.
    ///
    /// This is the honest scope of "ground draws below band content": ground
    /// is *band-relative*, so a ground tile sits below another tile's band
    /// content only while the two tiles' `tileX + tileY` differ by at most
    /// this many bands. It holds with a wide margin inside the resident
    /// window \u2014 whose widest possible tile-sum spread is derived from
    /// `ChunkStreamingManager.residentRadius * Chunk.size` and asserted
    /// against this constant by `DepthModelTests
    /// .test_groundClearance_exceedsWidestResidentTileSumSpread`, so the
    /// headroom is a checked fact rather than derived-in-prose.
    static var bandsClearedByGroundOffset: Int {
        Int((-groundOffset / bandSpacing).rounded(.down))
    }

    /// The ground plane's zPosition for a given band: `band + groundOffset`
    /// (equivalently `band - 5000`). Kept as a function of `band` (rather
    /// than a fixed constant) because the ground tile drawn under a
    /// particular `(tileX, tileY)` still needs to sit strictly below that
    /// tile's own band-content \u2014 and below every other band's ground too,
    /// since ground tiles from different bands can be visually adjacent on
    /// screen and must never fight each other for draw order. `-5000` clears
    /// `bandsClearedByGroundOffset` (500) whole bands, which is far more than
    /// the widest tile-sum spread two simultaneously-resident tiles can have,
    /// so ground never has to compete with band content from a *different*
    /// resident band either \u2014 see `bandsClearedByGroundOffset` for the test
    /// that pins that headroom against the streaming window instead of
    /// asserting it here in prose.
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

    // MARK: - World-band containment

    /// Whether `absoluteZ` is inside the world layer's zPosition band.
    ///
    /// Delegates to `LayerConstants.worldBand`, the same inclusive range
    /// `GameScene.nodesEscapingTheirLayerBand()` tests cumulative zPositions
    /// against, so this module's unit tests and the runtime audit cannot
    /// disagree about where the band ends. (A ceiling check written as its
    /// own `<` comparison here would be exactly the kind of second opinion
    /// that lets a violation pass one gate and fail the other.)
    static func isWithinWorldBand(_ absoluteZ: CGFloat) -> Bool {
        LayerConstants.worldBand.contains(absoluteZ)
    }

    /// The `zPosition` to assign a node parented **directly** under
    /// `GameScene.worldLayer` so that its *cumulative* zPosition comes out
    /// at `absoluteZ`.
    ///
    /// SpriteKit accumulates `zPosition` down the tree and `worldLayer`
    /// itself already sits at `LayerConstants.worldLayerZ`, so a direct child
    /// carries only the difference. This is the conversion the first renderer
    /// consumer (`CYBERPUN-17-4-t2` / `CYBERPUN-17-5`) needs: pick the
    /// absolute depth from this module, hand the node the relative value.
    static func worldLayerRelativeZ(forAbsoluteZ absoluteZ: CGFloat) -> CGFloat {
        absoluteZ - LayerConstants.worldLayerZ
    }

    /// The largest `|tileX + tileY|` whose *whole* band \u2014 from its ground
    /// plane (`groundOffset`) up to the top of `actorOffsetRange` \u2014 still
    /// fits inside `LayerConstants.worldBand` once anchored at `worldBaseZ`.
    ///
    /// Derived rather than hard-coded, so it tracks any change to the band,
    /// the anchor, `bandSpacing`, `groundOffset` or `actorOffsetRange`. At
    /// today's constants it is `4_450` in each direction, which is roughly
    /// two orders of magnitude beyond the tile sums a resident streaming
    /// window spans, but it is a real bound and not a comfort claim: the
    /// world is endless, so a consumer that walks far enough must check
    /// `isWithinSupportedDepthRange(forTile:)` instead of assuming.
    static var maxSupportedTileSumMagnitude: Int {
        let headroomBelowAnchor = worldBaseZ - LayerConstants.worldMinZ
        let headroomAboveAnchor = LayerConstants.worldMaxZ - worldBaseZ
        // Positive tile sums push bands (and their ground planes) down;
        // negative sums push bands (and the actor ceiling) up.
        let bandsBelow = (headroomBelowAnchor + groundOffset) / bandSpacing
        let bandsAbove = (headroomAboveAnchor - actorOffsetRange.upperBound) / bandSpacing
        return Int(min(bandsBelow, bandsAbove).rounded(.down))
    }

    /// Whether every depth this model can hand out for `tile` (ground plane
    /// through actor ceiling) lands inside `LayerConstants.worldBand`.
    ///
    /// Consumers placing nodes far from the origin should assert on this in
    /// DEBUG; beyond it the depth scheme has run out of band and the
    /// layer-band audit would trip on the resulting node.
    static func isWithinSupportedDepthRange(forTile tile: TileCoordinate) -> Bool {
        abs(tile.tileX + tile.tileY) <= maxSupportedTileSumMagnitude
    }
}
