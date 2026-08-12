import CoreGraphics
import SpriteKit

/// Turns a world-generator `TileKind` at a `TileCoordinate` into a
/// pixel-crisp, correctly depth-sorted ground `SKSpriteNode`.
///
/// This is the first production consumer of both `GroundTileCatalog`
/// (`Sources/Rendering/`) and `DepthModel` (`CYBERPUN-17-4-t1`) —
/// `DepthModel.worldLayerRelativeZ(forAbsoluteZ:)`'s own doc comment names
/// this task as its first caller. Every produced node is meant to be added
/// as a **direct child of `GameScene.worldLayer`**, so `zPosition` is set to
/// the *relative* value that conversion produces, not the absolute one —
/// SpriteKit accumulates `zPosition` down the tree, and `worldLayer` already
/// carries its own offset.
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
        let groundKind = groundTileKind(for: tileKind, at: tileCoordinate)
        let pixelRect = GroundTileCatalog.pixelRect(for: groundKind)
        let texture = AtlasSheet.groundTiles.sheet.texture(forPixelRect: pixelRect)

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
