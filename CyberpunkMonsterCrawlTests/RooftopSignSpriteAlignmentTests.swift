import CoreGraphics
import XCTest
@testable import CyberpunkMonsterCrawl

/// The measured basis for `RooftopSignRenderer`'s bottom-centre roofline
/// anchor (CYBERPUN-17-5-t3 AC7).
///
/// `RooftopSignRenderer.makeSignNode` places every sign at
/// `anchorPoint = (0.5, 0)` on `(0, buildingNode.size.height)` — the
/// roofline's top-centre in the building node's own local space. That only
/// *reads* correctly if the neon glyphs sit bottom-aligned and horizontally
/// centred inside their own 48×48 `sprite_signs` cell. `AtlasSheet.signs`
/// pins the sheet geometry (192×144px, 48×48 cells, 12 of them) and
/// `SpriteSheet.init`'s precondition measures that against the shipped PNG —
/// but neither says anything about *where the opaque pixels sit inside a
/// cell*. If a cell's glyphs were vertically centred, or carried a glow pad
/// below them, the sign would render floating above the roofline or clipped
/// into the roof, and every assertion in `RooftopSignRenderingTests` would
/// still pass: those check anchor/position values, which are self-consistent
/// by construction.
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
/// 3. each cell's content runs to the bottom of its own cell, with no
///    transparent padding below it — what makes `anchorPoint.y = 0` at
///    `buildingNode.size.height` put the sign's base *on* the roofline
///    instead of some pixels above it.
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

    /// **Fact 3 — `anchorPoint.y = 0` at the roofline.** The glyphs' base is
    /// the bottom row of their own cell: transparent padding below the
    /// silhouette would lift every sign off the roofline by exactly that many
    /// pixels — the visible-gap/floating-sign failure the brief calls out,
    /// and one nothing else in the pipeline would flag (the anchor and
    /// position assertions in `RooftopSignRenderingTests` are self-consistent
    /// by construction).
    ///
    /// Stated as "at most 4 rows" rather than exactly zero so a single-row
    /// authoring artifact or a faint glow row does not fail the suite; 4px of
    /// a 48px cell is under a tenth of the sign, while the failure this is
    /// aimed at — glyphs centred inside their cell, or a real glow pad — is
    /// 12px or more.
    func test_everySignCell_contentRunsToTheBottomOfItsCell_withNoTransparentPaddingBelow() throws {
        let pixels = try signSheetPixels()

        for index in 0..<AtlasCellIndex.signs.count {
            let measured = try measuredCell(atSignCellIndex: index, of: pixels)
            // `Pixels` is top-left-origin and row-major top row first, so the
            // *bottom* edge of the cell is `height` and the content's lowest
            // occupied row is `bounds.y.upperBound`.
            let transparentRowsBelowContent = measured.cell.height - measured.bounds.y.upperBound

            XCTAssertLessThanOrEqual(
                transparentRowsBelowContent, 4,
                "sprite_signs cell \(index) has \(transparentRowsBelowContent) fully transparent rows under "
                    + "its glyphs. RooftopSignRenderer anchors at (0.5, 0) on the building's roofline, i.e. "
                    + "the cell's bottom edge, so that padding would leave the sign floating that far above "
                    + "the roof."
            )
            XCTAssertGreaterThanOrEqual(
                transparentRowsBelowContent, 0,
                "sprite_signs cell \(index)'s content bounds fall outside its own cell."
            )
        }
    }
}
