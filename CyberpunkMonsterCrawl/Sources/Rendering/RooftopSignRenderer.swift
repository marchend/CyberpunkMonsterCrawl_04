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
/// `(0, buildingNode.size.height - AtlasSignGlyphBand.bottomInset(...))` in
/// the building node's *local* coordinate space — the roofline, dropped by
/// the measured transparent pad below that cell's glyphs so the *glyphs'*
/// base lands on the roofline (see the glyph-band paragraph below). Because
/// the building node is itself anchored
/// bottom-centre (`TileFieldRenderer.configure`), that local point is
/// exactly the roofline's top-centre — a child node's position is offset
/// from its parent's own position, unaffected by the parent's anchor point —
/// so this holds regardless of the building's absolute screen position.
/// The sign then extends upward from the roofline rather than overlapping
/// the building's own art.
///
/// That anchor rests on *measured* facts about the shipped `sprite_signs`
/// art, not on an assumption inferred from the cell size — the same
/// treatment `TileFieldRenderer`'s anchor comment gives the building art via
/// `BuildingSpriteBaseAlignmentTests`. `AtlasSheet.signs` only pins the
/// *sheet* geometry (192x144px, 48x48 cells, 12 of them); it says nothing
/// about where the opaque pixels sit inside a cell, and glyphs centred in
/// their cell (or carrying a glow pad below them) would render the sign
/// floating above the roofline or clipped into the roof while every
/// anchor/position assertion in `RooftopSignRenderingTests` still passed,
/// because those are self-consistent by construction.
/// `RooftopSignSpriteAlignmentTests` therefore re-derives the layout from
/// the PNG's alpha channel at test time, for all 12 cells:
/// - each cell's opaque content is horizontally centred inside its own 48px
///   cell (measured to within 4px, a twelfth of the cell), which is what
///   makes `anchorPoint.x = 0.5` put the sign over the roof's centre;
/// - the art is *not* bottom-flush: each cell's glyphs sit in a vertically
///   centred band (cell 0 occupies rows 18..<30 of its 48-row cell), leaving
///   8-19 transparent rows below them. Those measured bands are declared in
///   `AtlasSignGlyphBand.glyphRows` and asserted equal to the re-derived
///   ones, which is what makes `bottomInset(forSignCellIndex:)` — the drop
///   applied below — land the *glyphs'* base on the roofline instead of the
///   cell's empty bottom edge;
/// - all 12 cells decode at that geometry with real opaque content, so
///   neither measurement can pass vacuously on an empty or mis-sliced
///   sheet.
///
/// **Depth.** `DepthModel.signContentOffset` — a small positive *child*
/// `zPosition` (relative to `buildingNode`'s own, since SpriteKit
/// accumulates `zPosition` down the tree) that keeps the sign drawing in
/// front of the roof it sits on. It carries no absolute world-band value of
/// its own — unlike `TileFieldRenderer`'s building `zPosition`, which is
/// derived from `IsometricDepthSorting` — because a child's accumulated
/// depth already inherits the building's correctly-sorted absolute position
/// in the world band. The offset is *not* a literal invented here:
/// `DepthModel` is the single source of truth for in-band offsets and its
/// `buildingContentRange` is documented as covering "building content
/// (walls, rooftop signs, etc.)", so the constant is owned there and
/// asserted against `DepthModel.isValidBuildingContentOffset` in DEBUG
/// below — the same pattern `TileFieldRenderer.configure` already follows
/// for its band check.
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
        // `sprite_signs` family (`docs/bootstrap.md` §2: "one owning index
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

        // The shipped art centres each sign's glyphs vertically inside its
        // 48x48 cell (measured in `AtlasSignGlyphBand`), so the cell's bottom
        // edge is *not* the glyphs' base: putting the raw cell bottom on the
        // roofline would leave this sign floating 8-19px above the roof.
        // Dropping the node by the measured pad below the glyphs puts the
        // glyph base on the roofline, while the crop stays the whole cell so
        // no sign art is clipped.
        let glyphBaseInset = AtlasSignGlyphBand.bottomInset(forSignCellIndex: record.signCellIndex)
        node.position = CGPoint(x: 0, y: (buildingNode.size.height - glyphBaseInset).rounded())

        #if DEBUG
        // The sign's *accumulated* in-band offset is the building's own
        // content-floor slot plus this child offset, so that sum - not the
        // child offset alone - is what has to stay inside
        // `buildingContentRange`. Asserting it here means narrowing that
        // range (or retuning `signContentOffset`) fails at the sign that
        // caused it rather than surfacing as a draw-order oddity on device.
        assert(
            DepthModel.isValidBuildingContentOffset(
                DepthModel.buildingContentRange.lowerBound + DepthModel.signContentOffset
            ),
            "DepthModel.signContentOffset (\(DepthModel.signContentOffset)) puts a rooftop sign at in-band "
                + "offset \(DepthModel.buildingContentRange.lowerBound + DepthModel.signContentOffset), "
                + "outside DepthModel.buildingContentRange (\(DepthModel.buildingContentRange)); the sign "
                + "would draw in a neighbouring content slot."
        )
        #endif
        node.zPosition = DepthModel.signContentOffset

        // Finalizes `.nearest`/no-mipmap filtering and whole-integer
        // scale/whole-point position — the same pass every other production
        // sprite in this codebase goes through.
        PixelCrispness.apply(to: node)

        buildingNode.addChild(node)
        return node
    }
}
