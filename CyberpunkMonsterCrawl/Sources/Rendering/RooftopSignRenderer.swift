import CoreGraphics
import SpriteKit

/// Turns a `RooftopSignRecord` into a distinct rooftop neon sign
/// `SKSpriteNode`, added as a **child** of the building node that carries it
/// (`CYBERPUN-17-5-t3`).
///
/// AC7 calls for a sign to render from its own `sprite_signs` atlas cell
/// rather than being baked into a building's own texture — this file is
/// what keeps that true in the mounted scene graph: the sign is always a
/// second, separate `SKSpriteNode`, never a pixel composited into the
/// building's `BuildingSprite` texture (`BuildingCatalog`/`TileFieldRenderer`
/// never touch this file, and this file never touches a building's
/// texture). Parenting it under the building node — rather than alongside
/// it in `worldLayer` — means it inherits the building's position and
/// depth automatically, and disappears for free when the building node is
/// removed on chunk eviction: `GroundPlaneStreamer.mountChunk`/
/// `synchroniseWithResidentChunks` add/remove building nodes as whole units,
/// and nothing separately tracks a sign node's own lifecycle.
///
/// **Anchor.** Bottom-centre (`anchorPoint = (0.5, 0)`, the same convention
/// `TileFieldRenderer` uses for the building itself), positioned at
/// `(0, buildingNode.size.height)` in the building node's *local*
/// coordinate space. Because the building node is itself anchored
/// bottom-centre (`TileFieldRenderer.configure`), that local point is
/// exactly the roofline's top-centre — a child node's position is offset
/// from its parent's own position, unaffected by the parent's anchor point —
/// so this holds regardless of the building's absolute screen position,
/// with no dependency on `IsometricProjection` or `DepthModel` of its own.
/// The sign then extends upward from the roofline rather than overlapping
/// the building's own art.
///
/// **Depth.** A small positive *child* `zPosition` (relative to
/// `buildingNode`'s own, since SpriteKit accumulates `zPosition` down the
/// tree) keeps the sign drawing in front of the roof it sits on; it carries
/// no absolute world-band value of its own — unlike `TileFieldRenderer`'s
/// building `zPosition`, which is derived from `IsometricDepthSorting` —
/// because a child's accumulated depth already inherits the building's
/// correctly-sorted absolute position in the world band.
enum RooftopSignRenderer {
    /// Name stamped on every produced sign node, so scene audits/tests can
    /// find a building's sign child without holding a separate reference —
    /// mirrors `TileFieldRenderer.buildingNodeName`'s convention.
    static let signNodeName = "rooftopSign"

    /// Builds the sign node for `record`, positions it at `buildingNode`'s
    /// roofline, and adds it as `buildingNode`'s child.
    ///
    /// Returns the created node so a caller can hold a direct reference if
    /// it needs one (tests inspect it directly), though removing
    /// `buildingNode` from its own parent already takes the sign off screen
    /// too, with no separate bookkeeping required.
    @discardableResult
    static func makeSignNode(for record: RooftopSignRecord, parent buildingNode: SKSpriteNode) -> SKSpriteNode {
        let node = SKSpriteNode()
        node.name = signNodeName

        // `AtlasCellIndex.signs` is the owning index list for the
        // `sprite_signs` family (`docs/bootstrap.md` \u00a72: "one owning index
        // list per family"); `record.signCellIndex` is a plain `Int` so the
        // `World` layer that produced it never imports `Sources/Assets`, and
        // this is the one place that translates it back into a `(col, row)`
        // cell via that owning list rather than re-deriving `index % 4` /
        // `index / 4` by hand.
        let cell = AtlasCellIndex.signs[record.signCellIndex]
        let texture = AtlasSheet.signs.sheet.texture(col: cell.col, row: cell.row)
        node.texture = texture
        node.size = texture.size()
        node.anchorPoint = CGPoint(x: 0.5, y: 0)
        node.position = CGPoint(x: 0, y: buildingNode.size.height.rounded())
        node.zPosition = 1

        // Finalizes `.nearest`/no-mipmap filtering and whole-integer
        // scale/whole-point position — the same pass every other production
        // sprite in this codebase goes through.
        PixelCrispness.apply(to: node)

        buildingNode.addChild(node)
        return node
    }
}
