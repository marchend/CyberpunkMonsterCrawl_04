import CoreGraphics
import XCTest
@testable import CyberpunkMonsterCrawl

/// The measured basis for `RooftopSignRenderer`'s bottom-centre roofline
/// anchor (CYBERPUN-17-5-t3 AC7).
///
/// `RooftopSignRenderer.makeSignNode` places every sign at
/// `anchorPoint = (0.5, 0)` on
/// `(0, buildingNode.size.height - AtlasSignGlyphBand.bottomInset(...))` —
/// the roofline's top-centre in the building node's own local space, dropped
/// by the transparent pad the shipped art carries *below* its glyphs. That
/// only reads correctly if the glyphs are horizontally centred in their own
/// 48×48 `sprite_signs` cell, and if that pad is the measured one rather
/// than a guess. `AtlasSheet.signs` pins the sheet geometry (192×144px,
/// 48×48 cells, 12 of them) and `SpriteSheet.init`'s precondition measures
/// that against the shipped PNG — but neither says anything about *where the
/// opaque pixels sit inside a cell*, and the shipped art turns out **not**
/// to be bottom-flush: its glyphs sit in a vertically centred band, which is
/// exactly why the renderer cannot simply mount the raw cell at the
/// roofline. Get that pad wrong and the sign renders floating above the roof
/// or clipped into it, while every assertion in `RooftopSignRenderingTests`
/// still passes: those check anchor/position values, which are
/// self-consistent by construction.
///
/// This file gives the sign anchor the same treatment
/// `BuildingSpriteBaseAlignmentTests` gives `TileFieldRenderer`'s building
/// anchor (itself modelled on `AtlasGroundDiamondTests`): re-derive the fact
/// from the image's alpha channel at test time, for all 12 cells, so the
/// anchor rests on a measurement rather than on a belief about how the art
/// was authored.
///
/// Three facts, one per test below:
/// 1. every one of the 12 cells decodes at the declared 48×48 geometry and
///    holds real opaque content — the anti-vacuity guard, without which the
///    two measurements below would pass on an empty or mis-sliced sheet;
/// 2. each cell's opaque content is horizontally centred inside that cell —
///    what makes `anchorPoint.x = 0.5` put the sign over the roof's centre
///    rather than off one side of it;
/// 3. each cell's glyph band is exactly the one `AtlasSignGlyphBand.glyphRows`
///    declares, so `bottomInset(forSignCellIndex:)` — the drop that puts the
///    *glyphs'* base on the roofline rather than the cell's empty bottom
///    edge — is the measured pad and not a stale number. Art re-authored
///    bottom-flush, or re-cut on a different grid, fails here instead of
///    silently un-tuning the renderer.
final class RooftopSignSpriteAlignmentTests: XCTestCase {

    /// Re-derived from the sheet manifest rather than re-typed, so a change
    /// to `sprite_signs`' declared geometry cannot leave this file asserting
    /// against a stale 48.
    private static var cellSize: CGSize {
        guard let cellSize = AtlasSheet.signs.sheet.cellSize else {
            preconditionFailure("sprite_signs is a uniform grid; its SpriteSheet must declare a cellSize.")
        }
        return cellSize
    }

    /// Decoded `sprite_signs` pixels, or an explicit failure — never a quiet
    /// skip, which would let every measurement below pass vacuously on an
    /// image that failed to decode.
    private func signSheetPixels(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> ImagePixelSampling.Pixels {
        let imageID = AtlasSheet.signs.imageID
        return try XCTUnwrap(
            ImagePixelSampling.pixels(ofImageNamed: imageID),
            "\(imageID) could not be decoded from Assets.xcassets.",
            file: file,
            line: line
        )
    }

    /// One 48×48 cell of the decoded sheet, lifted into its own `Pixels` so
    /// `ImagePixelSampling`'s bounding-box helper measures *within the cell*
    /// rather than across the whole 192×144 sheet — the same per-cell slice
    /// `PlayerSpriteSheetTests` takes for the mirroring measurement.
    private func cellPixels(
        col: Int,
        row: Int,
        of pixels: ImagePixelSampling.Pixels
    ) -> ImagePixelSampling.Pixels {
        let cellWidth = Int(Self.cellSize.width)
        let cellHeight = Int(Self.cellSize.height)

        var bytes: [UInt8] = []
        bytes.reserveCapacity(cellWidth * cellHeight * 4)
        for y in (row * cellHeight)..<((row + 1) * cellHeight) {
            for x in (col * cellWidth)..<((col + 1) * cellWidth) {
                let base = (y * pixels.width + x) * 4
                bytes.append(contentsOf: pixels.rgba[base..<(base + 4)])
            }
        }
        return ImagePixelSampling.Pixels(width: cellWidth, height: cellHeight, rgba: bytes)
    }

    /// The opaque content bounding box of the cell owned by
    /// `AtlasCellIndex.signs[index]` — addressed through the owning index
    /// list, exactly as `RooftopSignRenderer` addresses it, rather than
    /// re-deriving `index % 4` / `index / 4` here.
    private func measuredCell(
        atSignCellIndex index: Int,
        of pixels: ImagePixelSampling.Pixels,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> (cell: ImagePixelSampling.Pixels, bounds: (x: Range<Int>, y: Range<Int>)) {
        let cellIndex = AtlasCellIndex.signs[index]
        let cell = cellPixels(col: cellIndex.col, row: cellIndex.row, of: pixels)
        let bounds = try XCTUnwrap(
            cell.contentBounds(inColumns: 0..<cell.width),
            "sprite_signs cell \(index) (col \(cellIndex.col), row \(cellIndex.row)) holds no opaque pixels "
                + "at all — RooftopSignRenderer would mount an invisible sign for that variant.",
            file: file,
            line: line
        )
        return (cell, bounds)
    }

    /// **Fact 1 — anti-vacuity.** The sheet decodes at its declared size, the
    /// owning index list really addresses 12 cells, and each of those cells
    /// carries real opaque content inside its own 48×48 rect.
    func test_everySignCell_decodesAtTheDeclaredGridGeometry_withOpaqueContent() throws {
        let pixels = try signSheetPixels()
        let sheet = AtlasSheet.signs.sheet

        XCTAssertEqual(
            CGSize(width: pixels.width, height: pixels.height), sheet.pixelSize,
            "sprite_signs decoded \(pixels.width)x\(pixels.height) but AtlasSheet declares \(sheet.pixelSize)."
        )
        XCTAssertEqual(Self.cellSize, CGSize(width: 48, height: 48))
        XCTAssertEqual(
            AtlasCellIndex.signs.count, 12,
            "sprite_signs is a 4x3 grid of 12 rooftop sign variants."
        )

        for index in 0..<AtlasCellIndex.signs.count {
            let measured = try measuredCell(atSignCellIndex: index, of: pixels)
            XCTAssertEqual(measured.cell.width, Int(Self.cellSize.width))
            XCTAssertEqual(measured.cell.height, Int(Self.cellSize.height))
            XCTAssertGreaterThan(measured.bounds.x.count, 0)
            XCTAssertGreaterThan(measured.bounds.y.count, 0)
        }
    }

    /// **Fact 2 — `anchorPoint.x = 0.5`.** Each cell's glyphs sit centred in
    /// their own 48px cell, so anchoring at the sprite's horizontal midpoint
    /// puts the sign over the centre of the roof it stands on.
    ///
    /// The 4px tolerance is scaled to the cell the way
    /// `BuildingSpriteBaseAlignmentTests` scales its 8px to a building PNG:
    /// loose enough to survive an asymmetric neon lip or a one-sided glow,
    /// far tighter than the misalignment that matters (half a 48px cell is
    /// 24px).
    func test_everySignCell_opaqueContentIsHorizontallyCentredInIts48pxCell() throws {
        let pixels = try signSheetPixels()

        for index in 0..<AtlasCellIndex.signs.count {
            let measured = try measuredCell(atSignCellIndex: index, of: pixels)
            let contentCentre = CGFloat(measured.bounds.x.lowerBound + measured.bounds.x.upperBound) / 2
            let cellCentre = CGFloat(measured.cell.width) / 2

            XCTAssertEqual(
                contentCentre, cellCentre, accuracy: 4,
                "sprite_signs cell \(index)'s opaque content spans columns \(measured.bounds.x) of its "
                    + "\(measured.cell.width)px cell — centred at x:\(contentCentre), not x:\(cellCentre). "
                    + "RooftopSignRenderer anchors signs at (0.5, 0) over the roof's centre, so off-centre "
                    + "art hangs off one side of the roofline."
            )
        }
    }

    /// **Fact 3 — the roofline drop is the *measured* pad.** The shipped
    /// glyphs are not flush with their cell's bottom edge: they sit in a
    /// vertically centred band, so mounting the raw cell at the roofline
    /// would leave every sign floating above the roof it stands on — the
    /// visible-gap failure the brief calls out, and one nothing else in the
    /// pipeline would flag (the anchor and position assertions in
    /// `RooftopSignRenderingTests` are self-consistent by construction).
    ///
    /// `RooftopSignRenderer` compensates with
    /// `AtlasSignGlyphBand.bottomInset(forSignCellIndex:)`. This test is what
    /// keeps those declared bands honest: each is re-derived from the alpha
    /// channel here and asserted equal to the declaration, so re-authored or
    /// re-cut art turns the suite red rather than quietly un-tuning the
    /// renderer's offset.
    func test_everySignCellsDeclaredGlyphBand_matchesTheMeasuredAlphaBand() throws {
        let pixels = try signSheetPixels()

        XCTAssertEqual(
            AtlasSignGlyphBand.glyphRows.count, AtlasCellIndex.signs.count,
            "AtlasSignGlyphBand must declare one measured glyph band per sprite_signs cell."
        )

        for index in 0..<AtlasCellIndex.signs.count {
            let measured = try measuredCell(atSignCellIndex: index, of: pixels)
            // `Pixels` is top-left-origin and row-major top row first, so the
            // content's own row band is directly comparable to the declared
            // one and the *bottom* pad is `height - bounds.y.upperBound`.
            XCTAssertEqual(
                measured.bounds.y, AtlasSignGlyphBand.glyphRows[index],
                "sprite_signs cell \(index)'s glyphs occupy rows \(measured.bounds.y) of its "
                    + "\(measured.cell.height)-row cell, but AtlasSignGlyphBand declares "
                    + "\(AtlasSignGlyphBand.glyphRows[index]). RooftopSignRenderer drops the sign by the "
                    + "declared pad to put the glyph base on the roofline, so a stale band mounts every "
                    + "sign of this variant off the roof."
            )

            let measuredPadBelowGlyphs = CGFloat(measured.cell.height - measured.bounds.y.upperBound)
            XCTAssertEqual(
                AtlasSignGlyphBand.bottomInset(forSignCellIndex: index), measuredPadBelowGlyphs,
                accuracy: 1e-9,
                "bottomInset for sprite_signs cell \(index) must equal the measured "
                    + "\(measuredPadBelowGlyphs) transparent rows below its glyphs — that inset is exactly "
                    + "the distance the sign has to drop for its glyph base to rest on the roofline."
            )
            XCTAssertGreaterThanOrEqual(
                measuredPadBelowGlyphs, 0,
                "sprite_signs cell \(index)'s content bounds fall outside its own cell."
            )
        }
    }
}
