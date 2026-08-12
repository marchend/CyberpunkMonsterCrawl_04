import CoreGraphics
import SpriteKit

/// Turns a world-generator `TileKind` at a `TileCoordinate` into a
/// pixel-crisp, correctly depth-sorted ground `SKSpriteNode`.
///
/// This is the first production consumer of both `GroundTileCatalog`
/// (`Sources/Rendering/`) and `DepthModel` (`CYBERPUN-17-4-t1`) —
/// `DepthModel.worldLayerRelativeZ(forAbsoluteZ:)`'s own doc comment names
/// this task as its first caller. Every produced node is added as a
/// **direct child of `GameScene.worldLayer`**, so `zPosition` is set to the
/// *relative* value that conversion produces, not the absolute one —
/// SpriteKit accumulates `zPosition` down the tree, and `worldLayer` already
/// carries its own offset.
///
/// **Who calls this in a real build:** `GroundPlaneStreamer`
/// (`Sources/World/GroundPlaneStreamer.swift`), which walks
/// `ChunkStreamingManager`'s resident window and parents one node per
/// resident tile straight into `worldLayer`; `GameScene` starts it on entry
/// to `.gameplay`. A factory with no production caller is exactly the shape
/// of feature that never gets switched on, so the mount is wired here rather
/// than deferred: tapping PLAY in the shipped app shows the generated city,
/// which is the story's headline AC.
///
/// `TileKind` alone does not distinguish the two street-corridor
/// orientations the sheet ships as separate diamonds
/// (`GroundTileKind.asphaltEastWest` / `.asphaltNorthSouth`), so this file
/// re-derives that one piece of orientation from the tile coordinate using
/// `CityLatticeGenerator`'s public `period`/`blockSize` constants — the same
/// two-line integer-math duplication pattern `ChunkCoordinate`'s private
/// `floorDiv` already uses instead of reaching into another file's private
/// helper (`Sources/World/Chunk.swift`). This never needs a seed: which axis
/// a street corridor runs along is 100% structural, exactly like
/// `CityLatticeGenerator.streetTileKind`'s own street sub-classification.
enum GroundTileRenderer {
    /// Builds the finished ground node for `tileKind` at `tileCoordinate`:
    /// crops the matching `GroundTileCatalog` rect, positions it at the
    /// tile's screen location, sets its `zPosition` from `DepthModel`'s
    /// ground offset (converted to worldLayer-relative), and finalizes it
    /// with `PixelCrispness`.
    static func node(for tileKind: TileKind, at tileCoordinate: TileCoordinate) -> SKSpriteNode {
        #if DEBUG
        // `DepthModel.isWithinSupportedDepthRange(forTile:)` asks consumers
        // placing nodes far from the origin to assert on it in DEBUG; this is
        // the first such consumer. Beyond the supported range the depth
        // scheme has run out of band and the layer-band audit
        // (`GameScene.nodesEscapingTheirLayerBand()`) would trip on the node
        // produced here — better to fail at the tile that caused it.
        assert(
            DepthModel.isWithinSupportedDepthRange(forTile: tileCoordinate),
            "Ground tile \(tileCoordinate) has |tileX + tileY| past "
                + "DepthModel.maxSupportedTileSumMagnitude "
                + "(\(DepthModel.maxSupportedTileSumMagnitude)); its zPosition would escape the world band."
        )
        #endif

        let groundKind = groundTileKind(for: tileKind, at: tileCoordinate)
        let pixelRect = GroundTileCatalog.pixelRect(for: groundKind)
        let texture = AtlasSheet.groundTiles.sheet.texture(forPixelRect: pixelRect)

        // The node keeps SpriteKit's default `anchorPoint` (0.5, 0.5), which
        // is what puts the diamond's centre on the tile's screen point. That
        // stays correct for `.buildingFootprint` even though its
        // `overhangLot` crop is 112px wide rather than 96px, because
        // `AtlasGroundDiamondTests
        // .test_groundDiamonds_everySubRectHoldsItsOwnDiamond_measuredFromPixelAlpha`
        // measures that sub-rect's content as *centred* in its rect — the
        // extra 16px of overhang is split evenly, so the crop's midpoint is
        // still the diamond's midpoint. Alignment depends on that measured
        // fact, not on an assumption about where the overhang sits.
        let node = SKSpriteNode(texture: texture)
        node.position = IsometricProjection.tileToScreen(
            tileX: Double(tileCoordinate.tileX),
            tileY: Double(tileCoordinate.tileY)
        )

        let absoluteZ = DepthModel.groundZPosition(forTile: tileCoordinate)
        node.zPosition = DepthModel.worldLayerRelativeZ(forAbsoluteZ: absoluteZ)

        PixelCrispness.apply(to: node)
        return node
    }

    /// The `GroundTileCatalog` entry `tileKind` (at `tileCoordinate`) maps
    /// to. Every `TileKind` case maps to exactly one `GroundTileKind`,
    /// except `.asphalt`, which needs the tile coordinate to pick a
    /// corridor orientation.
    static func groundTileKind(for tileKind: TileKind, at tileCoordinate: TileCoordinate) -> GroundTileKind {
        switch tileKind {
        case .asphalt:
            return asphaltOrientation(at: tileCoordinate)
        case .junctionStopLine:
            return .junctionStopLine
        case .kerbSidewalk:
            return .kerbSidewalk
        case .lot:
            return .lot
        case .buildingFootprint:
            return .buildingFootprint
        }
    }

    /// Which lane diamond an `.asphalt` tile at `tileCoordinate` should use.
    ///
    /// A straight corridor segment has exactly one axis inside the street
    /// band (`CityLatticeGenerator.streetTileKind`'s `isStreetX`/
    /// `isStreetY`): if the *X* axis is the band, the corridor's tiles share
    /// a fixed `xMod` while `y` is unconstrained, so the corridor itself
    /// runs along the Y axis — north-south. Symmetrically, the Y axis being
    /// the band means the corridor runs along X — east-west.
    ///
    /// A lattice crossing's own centre tile (`xIsLane && yIsLane` in
    /// `streetTileKind`) is the one case where *both* axes are in the
    /// street band and the tile is still `.asphalt`; there is no seventh
    /// diamond for a four-way crossing, so that single ambiguous tile
    /// defaults to `.asphaltEastWest` — either lane's texture reads fine at
    /// a crossing's own centre.
    ///
    /// The centre tile deliberately does **not** take
    /// `GroundTileKind.junctionStopLine`'s art, and that is not this file's
    /// call to make: `CityLatticeGenerator.streetTileKind` already pins which
    /// tiles of a 3x3 crossing carry junction paint — the four lane *mouths*
    /// are `TileKind.junctionStopLine` ("this is literally where a stop line
    /// is painted, across the lane at the mouth of the junction"), the centre
    /// is plain `.asphalt`, and the four corners continue the kerb ring. The
    /// ground plane renders the kind it is handed; moving junction paint onto
    /// the crossing centre would mean changing that lattice decision (and its
    /// tests), not the crop table.
    private static func asphaltOrientation(at tileCoordinate: TileCoordinate) -> GroundTileKind {
        let xMod = mod(tileCoordinate.tileX, CityLatticeGenerator.period)
        let yMod = mod(tileCoordinate.tileY, CityLatticeGenerator.period)
        let isStreetX = xMod >= CityLatticeGenerator.blockSize
        let isStreetY = yMod >= CityLatticeGenerator.blockSize

        if isStreetX && !isStreetY {
            return .asphaltNorthSouth
        }
        return .asphaltEastWest
    }

    /// The mathematical modulus (always `0..<modulus`), duplicated in
    /// miniature rather than reaching into `CityLatticeGenerator`'s private
    /// `mod` — see the type-level doc comment for why this small duplication
    /// is the codebase's sanctioned pattern here.
    private static func mod(_ value: Int, _ modulus: Int) -> Int {
        let remainder = value % modulus
        return remainder >= 0 ? remainder : remainder + modulus
    }
}
