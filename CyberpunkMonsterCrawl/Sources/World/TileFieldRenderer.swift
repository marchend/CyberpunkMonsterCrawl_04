import CoreGraphics
import SpriteKit

/// Turns a `BuildingPlacementRecord` into a correctly anchored, correctly
/// depth-sorted building `SKSpriteNode`.
///
/// The building-placement counterpart of `GroundTileRenderer`
/// (`Sources/World/GroundTileRenderer.swift`): same "pure `(record) ->
/// SKSpriteNode` factory, testable without a live `SKScene`" shape, same
/// "parent directly under `GameScene.worldLayer`, so `zPosition` must be the
/// *worldLayer-relative* value" contract. `docs/bootstrap.md`: "Whole
/// pre-rendered building sprites, never assembled in code" \u2014 this file
/// never constructs building geometry piece by piece; it only positions and
/// depth-sorts one of the 12 `BuildingCatalog` sprites, loaded whole via
/// `BuildingSprite.texture`.
///
/// **Who mounts this in a real build:** `GroundPlaneStreamer`
/// (`Sources/World/GroundPlaneStreamer.swift`), which walks
/// `ChunkStreamingManager`'s resident window and parents one node per
/// `Chunk.buildingPlacements` record straight into `worldLayer`, alongside
/// that chunk's ground nodes and dropping both together on eviction;
/// `GameScene` starts it on entry to `.gameplay`. A factory with no
/// production caller is exactly the shape of feature that never gets
/// switched on, so the mount is wired here rather than deferred - that is
/// `GroundTileRenderer`/`GroundPlaneStreamer`'s stated precedent ("a factory
/// with no caller renders nothing in a real build"), and it is what makes
/// product gate 4 ("the city reads as a city ... building sprites placed
/// across the blocks") observable by tapping PLAY rather than only in a unit
/// test that calls `makeBuildingNode` directly.
///
/// **Anchor.** `anchorPoint = (0.5, 0)` \u2014 bottom-centre \u2014 placed at
/// `record.lotTile`'s screen point (the footprint's base/near corner, the
/// same tile `IsometricProjection.tileToScreen` already projects ground
/// tiles from), rounded to whole device pixels.
///
/// That anchor rests on *measured* facts about the shipped art, not on an
/// assumption about how it was authored - the same treatment
/// `GroundTileRenderer`'s anchor comment gives the 112px `overhangLot` crop.
/// `BuildingSpriteBaseAlignmentTests` re-derives all three from pixel alpha,
/// for all 12 buildings:
/// - the opaque content is horizontally centred inside its own PNG, which is
///   what makes `anchorPoint.x = 0.5` put the base on the tile's screen x;
/// - the content runs to the PNG's bottom edge with no transparent padding
///   below it, so `anchorPoint.y = 0` puts the art's ground-contact row on
///   the node's position rather than somewhere above it;
/// - a `.twoByTwo` building's art measures wider than one 96px tile while a
///   `.oneByOne` building's does not, which is the "extends outward for a
///   2x2 footprint" claim stated as a measurement instead of a belief.
///
/// **Which tile of a multi-tile footprint the sprite anchors to** is a
/// separate decision, and the one a 1x1-only test suite cannot see: the base
/// tile (`record.lotTile`), never the merged footprint's centre. A 2x2
/// footprint's merged diamond is centred at tile-space `(lotX + 0.5,
/// lotY + 0.5)`, i.e. `+24px` in screen Y from `lotTile`, so anchoring there
/// instead would shift `building_08`/`building_09`/`building_11` half a tile
/// up the screen. `BuildingDepthAndAnchorTests`'s 2x2 case pins the base-tile
/// convention against exactly that alternative.
///
/// **Depth.** Delegates to `IsometricDepthSorting`, which keys off the
/// footprint's *far* corner rather than `lotTile` \u2014 see that type's doc
/// comment for why the far corner (not the base tile) is what keeps a
/// building from ever drawing over an actor standing in front of it.
enum TileFieldRenderer {
    /// Name stamped on every produced building node, so scene audits and a
    /// future movement/collision consumer can find building nodes among
    /// `worldLayer`'s children without holding a reference to whatever
    /// mounted them \u2014 mirrors `GroundPlaneStreamer.nodeName`'s convention.
    static let buildingNodeName = "building"

    /// Builds the finished building node for `record`: whole-sprite texture
    /// from `BuildingCatalog`/`BuildingSprite`, `.nearest` filtering, no
    /// mipmaps, bottom-centre anchor at `record.lotTile`'s screen point, and
    /// a `DepthModel`/`IsometricDepthSorting` zPosition converted to be
    /// relative to `GameScene.worldLayer`.
    static func makeBuildingNode(for record: BuildingPlacementRecord) -> SKSpriteNode {
        let node = SKSpriteNode()
        configure(node, for: record)
        return node
    }

    /// Reconfigures an existing sprite node in place to render `record`,
    /// exactly as `makeBuildingNode(for:)` builds a fresh one: same texture,
    /// size, anchor, position, zPosition and `PixelCrispness` finalization.
    ///
    /// This is what lets `GroundPlaneStreamer` recycle a building node freed
    /// by a chunk that just streamed out instead of allocating a new
    /// `SKSpriteNode` per placement per mount - the same `node(for:at:)` /
    /// `configure(_:for:at:)` split `GroundTileRenderer` already carries for
    /// the ground plane, for the same reason.
    static func configure(_ node: SKSpriteNode, for record: BuildingPlacementRecord) {
        node.name = buildingNodeName

        guard let sprite = BuildingSprite(rawValue: record.building.index) else {
            preconditionFailure(
                "BuildingCatalog index \(record.building.index) has no matching BuildingSprite case - "
                    + "the two manifests must stay index-for-index in sync (see BuildingCatalogTests)."
            )
        }

        // `BuildingSprite.texture` already resolves through `TextureLoading`
        // (nearest-filtered, no mipmaps) and walks its measured-vs-declared
        // precondition on the way through \u2014 the same guarantee
        // `GroundTileRenderer` gets from `AtlasSheet...texture(forPixelRect:)`.
        let texture = sprite.texture
        node.texture = texture
        node.size = texture.size()
        node.anchorPoint = CGPoint(x: 0.5, y: 0)

        let screenPoint = IsometricProjection.tileToScreen(
            tileX: Double(record.lotTile.tileX),
            tileY: Double(record.lotTile.tileY)
        )
        node.position = CGPoint(x: screenPoint.x.rounded(), y: screenPoint.y.rounded())

        let farCorner = IsometricDepthSorting.farCornerTile(amongFootprintTiles: record.footprintTiles)
            ?? record.farCornerTile

        #if DEBUG
        // `DepthModel.isWithinSupportedDepthRange(forTile:)` asks consumers
        // placing nodes far from the origin to assert on it in DEBUG, and
        // `GroundTileRenderer.configure` is the existing consumer that does.
        // Buildings are the taller-z content, so this matters at least as
        // much here: past the supported range the zPosition below lands
        // outside `LayerConstants.worldBand` and would surface only as a
        // `GameScene.nodesEscapingTheirLayerBand()` hit at runtime, far from
        // the tile that caused it. Better to fail at that tile.
        assert(
            DepthModel.isWithinSupportedDepthRange(forTile: farCorner),
            "Building footprint far corner \(farCorner) has |tileX + tileY| past "
                + "DepthModel.maxSupportedTileSumMagnitude "
                + "(\(DepthModel.maxSupportedTileSumMagnitude)); its zPosition would escape the world band."
        )
        #endif

        let absoluteZ = IsometricDepthSorting.zPosition(forBuildingFarCornerTile: farCorner)
        node.zPosition = DepthModel.worldLayerRelativeZ(forAbsoluteZ: absoluteZ)

        // Finalizes filtering/mipmaps (already set above; idempotent) and
        // enforces whole-integer scale + whole-pixel position \u2014 the same
        // pass every other production sprite in this codebase goes through.
        PixelCrispness.apply(to: node)
    }
}
