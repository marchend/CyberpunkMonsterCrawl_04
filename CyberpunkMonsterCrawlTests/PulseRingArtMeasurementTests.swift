import CoreGraphics
import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-10-t3` (PR #48 review): pins `AtlasPulseRingContent`'s
/// measured ring geometry to the shipped `sprite_pulse` pixels.
///
/// `AtlasSheet.pulse` only pins the *sheet* geometry (256×32px, 8 × 32×32
/// cells), and `SpriteSheet.init`'s measurement precondition only checks
/// that -- which says nothing about where the opaque pixels sit *inside* a
/// cell. `PulseRingNode`'s scale-to-radius transform depends on exactly
/// that: it divides the projected ellipse's extent by the ring's own
/// measured pixel size, because scaling an `SKSpriteNode` scales the whole
/// cell rather than just the ring drawn in it. Left unmeasured, art
/// re-authored with a smaller ring inside the same cell (or re-exported
/// already squashed onto the isometric plane) would silently un-tune that
/// transform with every test still green.
///
/// So this suite re-runs the alpha scan at test time, the same way
/// `AtlasGroundDiamondTests` re-derives `AtlasGroundDiamond`'s partition and
/// `RooftopSignSpriteAlignmentTests` re-derives `AtlasSignGlyphBand`'s
/// bands, and fails on any drift between the declared measurement and the
/// shipped pixels.
final class PulseRingArtMeasurementTests: XCTestCase {

    private static let sheetImageID = AtlasSheet.pulse.imageID

    private func pulsePixels() throws -> ImagePixelSampling.Pixels {
        try XCTUnwrap(
            ImagePixelSampling.pixels(ofImageNamed: Self.sheetImageID),
            "\(Self.sheetImageID) could not be decoded from Assets.xcassets — the alpha scan below "
                + "would otherwise measure nothing and pass vacuously."
        )
    }

    private func cellWidth() throws -> Int {
        let cellSize = try XCTUnwrap(
            AtlasSheet.pulse.sheet.cellSize,
            "AtlasSheet.pulse must declare a uniform cellSize."
        )
        return Int(cellSize.width)
    }

    /// The opaque-content bounding box inside `column`'s cell, in
    /// **cell-local** pixels, or `nil` when that cell holds no opaque pixel
    /// at all (which every caller treats as a hard failure, never a pass).
    private func measuredContentSize(ofColumn column: Int, in pixels: ImagePixelSampling.Pixels) throws -> CGSize? {
        let width = try cellWidth()
        let columns = (column * width)..<((column + 1) * width)
        guard let bounds = pixels.contentBounds(inColumns: columns) else { return nil }
        return CGSize(width: CGFloat(bounds.x.count), height: CGFloat(bounds.y.count))
    }

    // MARK: - Anti-vacuity: the scan really sees the shipped shockwave

    func test_spritePulse_decodesAtItsDeclaredSheetGeometry_withRealPixelsInEveryFrame() throws {
        let pixels = try pulsePixels()

        XCTAssertEqual(pixels.width, 256)
        XCTAssertEqual(pixels.height, 32)

        for column in 0..<AtlasCellIndex.pulse.count {
            let size = try measuredContentSize(ofColumn: column, in: pixels)
            XCTAssertNotNil(
                size,
                "sprite_pulse frame \(column) holds no opaque pixels at all — the alpha scan below would "
                    + "measure nothing and every assertion here would pass vacuously."
            )
        }
    }

    // MARK: - The declared widest frame really is the widest

    func test_widestFrameColumn_isTheFrameTheShockwaveActuallyPeaksOn() throws {
        let pixels = try pulsePixels()

        var widestColumn = 0
        var widestWidth: CGFloat = 0
        var measuredWidths: [CGFloat] = []

        for column in 0..<AtlasCellIndex.pulse.count {
            let size = try XCTUnwrap(
                measuredContentSize(ofColumn: column, in: pixels),
                "sprite_pulse frame \(column) holds no opaque pixels."
            )
            measuredWidths.append(size.width)
            if size.width > widestWidth {
                widestWidth = size.width
                widestColumn = column
            }
        }

        XCTAssertEqual(
            widestColumn, AtlasPulseRingContent.widestFrameColumn,
            "AtlasPulseRingContent declares frame \(AtlasPulseRingContent.widestFrameColumn) as the "
                + "shockwave's widest, but the alpha scan measures frame \(widestColumn) "
                + "(per-frame content widths: \(measuredWidths)). PulseRingNode calibrates its "
                + "scale-to-radius transform against that frame — fix whichever of the art or the "
                + "declaration is wrong, never loosen this assertion."
        )
    }

    // MARK: - The declared content size really is the measured one

    func test_widestFrameContentSize_equalsTheMeasuredOpaqueBoundingBox() throws {
        let pixels = try pulsePixels()
        let column = AtlasPulseRingContent.widestFrameColumn

        let measured = try XCTUnwrap(
            measuredContentSize(ofColumn: column, in: pixels),
            "sprite_pulse frame \(column) holds no opaque pixels at all."
        )

        XCTAssertEqual(
            measured, AtlasPulseRingContent.widestFrameContentSize,
            "sprite_pulse frame \(column)'s ring measures \(measured) but AtlasPulseRingContent declares "
                + "\(AtlasPulseRingContent.widestFrameContentSize). PulseRingNode divides the pulse's "
                + "projected screen extent by this size to pick its per-axis scale, so a stale value "
                + "draws the ring the wrong size on every trigger."
        )
    }

    func test_widestFrameContentSize_fitsInsideItsOwnCell() throws {
        let cellSize = try XCTUnwrap(AtlasSheet.pulse.sheet.cellSize)
        let declared = AtlasPulseRingContent.widestFrameContentSize

        XCTAssertGreaterThan(declared.width, 0, "a zero-width ring would make the scale-to-radius divisor degenerate.")
        XCTAssertGreaterThan(declared.height, 0)
        XCTAssertLessThanOrEqual(
            declared.width, cellSize.width,
            "the measured ring cannot be wider than the cell it is cut from."
        )
        XCTAssertLessThanOrEqual(declared.height, cellSize.height)
    }
}
