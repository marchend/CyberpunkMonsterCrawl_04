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
/// **Who mounts this in a real build:** a later story
/// (`CYBERPUN-17-7`/onward mounts world content alongside the ground plane);
/// this PR's scope (`CYBERPUN-17-5-t2`) is the rendering + collision-data
/// primitive itself, matching `GroundTileRenderer`'s own precedent of
/// landing the factory ahead of its scene-graph mount.
///
/// **Anchor.** `anchorPoint = (0.5, 0)` \u2014 bottom-centre \u2014 placed at
/// `record.lotTile`'s screen point (the footprint's base/near corner, the
/// same tile `IsometricProjection.tileToScreen` already projects ground
/// tiles from), rounded to whole device pixels. A building's sprite extends
/// upward (and, for a 2x2 footprint, outward) from that point exactly the
/// way the shipped art was authored: the base of the sprite is its
/// footprint's ground-contact point, regardless of how tall the building is.
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
        let absoluteZ = IsometricDepthSorting.zPosition(forBuildingFarCornerTile: farCorner)
        node.zPosition = DepthModel.worldLayerRelativeZ(forAbsoluteZ: absoluteZ)

        // Finalizes filtering/mipmaps (already set above; idempotent) and
        // enforces whole-integer scale + whole-pixel position \u2014 the same
        // pass every other production sprite in this codebase goes through.
        PixelCrispness.apply(to: node)

        return node
    }
}
