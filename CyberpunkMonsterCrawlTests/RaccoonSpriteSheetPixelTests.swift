import CoreGraphics
import XCTest
@testable import CyberpunkMonsterCrawl

/// CYBERPUN-17-8-t1: the raccoon's *measured* sheet facts, re-read off the
/// shipped `sprite_raccoon_walk` / `sprite_raccoon_attack` pixels at test
/// time.
///
/// **Why this file exists.** `RaccoonAnimationControllerTests` asserts the
/// row/mirror table against a hand-written copy of itself
/// (`.southwest.row == .southeast.row`), which guards typos and nothing
/// else: it stays green whether or not either sheet's rows 5-7 hold
/// authored west-side art, and it never looks at the attack sheet at all.
/// Both raccoon sheets are 4x8 and `AtlasCellIndex.raccoonWalk` /
/// `.raccoonAttack` declare all 32 cells of each valid, so the table reads
/// 20 of 32 cells per sheet on a claim about the art that only the art can
/// settle -- the same gap `PlayerSpriteSheetTests`
/// `.test_theRowsTheTableNeverReads_carryNoArtBeyondTheMirrorOfTheirSourceRow`
/// closes for the player. That scan is ported here and run over **both**
/// sheets, alongside the two raccoon-specific measurements that do not
/// reduce to cell arithmetic the way the player's `(18, 40)` anchor does:
/// where the anchor sits, and how wide the ground footprint under the
/// shadow really is.
final class RaccoonSpriteSheetPixelTests: XCTestCase {

    /// Both sheets `RaccoonAnimationController` drives. The attack sheet is
    /// measured separately rather than assumed to match the walk sheet: it
    /// is a different image and could have been cut on a different row
    /// order or drawn with a different stance.
    private let sheets: [AtlasSheet] = [.raccoonWalk, .raccoonAttack]

    /// Sheet rows `rowMappingTable` never reads, each paired with the facing
    /// whose row is mirrored in its place. Rows 5/6/7 continue the compass
    /// sweep past due-north (northwest, west, southwest), so each pairs with
    /// the directly-authored row sharing its vertical component -- 5 with 3
    /// (northeast), 6 with 2 (east), 7 with 1 (southeast).
    private let mirrorPairs: [(unread: Int, facing: Direction8)] = [
        (5, .northwest),
        (6, .west),
        (7, .southwest),
    ]

    /// How many pixel rows at the bottom of a cell's silhouette count as its
    /// ground-contact band. Three, on a 28px-tall cell: enough to catch the
    /// paws where they meet the ground, few enough not to climb into the
    /// body and measure the raccoon's widest point instead of its stance.
    private let groundContactBandHeight = 3

    /// Tolerance, in cell pixels, on the anchor measurements below. Two: one
    /// pixel of rounding for an odd-width silhouette's centre, plus one for
    /// per-frame paw variation across a walk cycle. Anything looser stops
    /// discriminating -- the defect this measurement exists to catch (an
    /// anchor 8px off the feet, on a 28px cell) is four times this.
    private let anchorTolerance: CGFloat = 2

    // MARK: - The decode itself

    func test_bothSheets_decodeAtTheDeclaredAtlasGeometry() throws {
        for atlasSheet in sheets {
            let pixels = try self.pixels(of: atlasSheet)
            XCTAssertEqual(
                CGSize(width: CGFloat(pixels.width), height: CGFloat(pixels.height)),
                atlasSheet.sheet.pixelSize,
                "\(atlasSheet.imageID) decoded at \(pixels.width)x\(pixels.height), not the geometry "
                    + "AtlasSheet declares - every cell crop in this file would address the wrong pixels."
            )
        }
    }

    // MARK: - The mirroring claim, measured off both shipped sheets

    /// The discriminating measurement behind
    /// `RaccoonAnimationController.rowMappingTable`.
    ///
    /// The table reads rows 0-4 and mirrors three of them for the west side,
    /// which is safe *only* if the three rows it never reads carry no art of
    /// their own. So for each of those rows the art must be either empty
    /// (mirroring is *required*) or the horizontal flip of its source row
    /// (mirroring is *equivalent*). Authored west-side art -- a third result
    /// -- means the table discards real art and renders a mirrored east pose
    /// for half the compass, on both sheets, with every other raccoon test
    /// still green.
    ///
    /// **If this fails, do not loosen it.** Either the art authors the west
    /// side (point `.southwest`/`.west`/`.northwest` at rows 7/6/5 with
    /// `mirrored: false`) or the sheet ships three rows that need
    /// re-exporting. The failure message reports the measured numbers so the
    /// reader can tell which.
    func test_theRowsTheTableNeverReads_carryNoArtBeyondTheMirrorOfTheirSourceRow_onBothSheets() throws {
        let rowsTheTableReads = Set(Direction8.allCases.map { RaccoonAnimationController.rowMapping(for: $0).row })
        XCTAssertEqual(
            rowsTheTableReads, Set(0...4),
            "this measurement assumes the table reads rows 0-4 and leaves 5-7 unread; it measured "
                + "\(rowsTheTableReads.sorted()) instead, so the pairing below is stale."
        )

        for atlasSheet in sheets {
            let pixels = try self.pixels(of: atlasSheet)

            for pair in mirrorPairs {
                let sourceRow = RaccoonAnimationController.rowMapping(for: pair.facing).row
                var opaquePixelsInUnreadRow = 0
                var cellsWithTheMirroredSilhouette = 0
                var cellsEqualToTheMirroredSource = 0

                for column in 0..<RaccoonAnimationController.frameCount {
                    let unread = cell(column: column, row: pair.unread, of: pixels)
                    let source = cell(column: column, row: sourceRow, of: pixels)

                    opaquePixelsInUnreadRow += opaquePixelCount(of: unread)
                    if unread.fingerprint == source.mirroredFingerprint {
                        cellsEqualToTheMirroredSource += 1
                    }
                    if opaqueSilhouette(of: unread) == mirroredOpaqueSilhouette(of: source) {
                        cellsWithTheMirroredSilhouette += 1
                    }
                }

                let rowIsEmpty = opaquePixelsInUnreadRow == 0
                let rowIsTheMirrorOfItsSource = cellsWithTheMirroredSilhouette == RaccoonAnimationController.frameCount

                XCTAssertTrue(
                    rowIsEmpty || rowIsTheMirrorOfItsSource,
                    "\(atlasSheet.imageID): RaccoonAnimationController mirrors row \(sourceRow) into "
                        + ".\(pair.facing) and never reads sheet row \(pair.unread), but row "
                        + "\(pair.unread) measures \(opaquePixelsInUnreadRow) opaque pixels that are not "
                        + "the horizontal flip of row \(sourceRow) "
                        + "(\(cellsWithTheMirroredSilhouette)/\(RaccoonAnimationController.frameCount) cells "
                        + "match the flipped silhouette, "
                        + "\(cellsEqualToTheMirroredSource)/\(RaccoonAnimationController.frameCount) match it "
                        + "pixel-for-pixel). The west side of this sheet is authored, so the table is "
                        + "discarding real art and rendering a mirrored east pose for .\(pair.facing)."
                )
            }
        }
    }

    // MARK: - The anchor, measured off both shipped sheets

    /// `RaccoonAnimationController.anchorPixel` is a claim about where this
    /// raccoon's feet are drawn inside its 48x28 cell, and it is what every
    /// raccoon's shadow position and depth sample hang off -- so it is
    /// measured here rather than restated from the ticket table. It had to
    /// be: the ticket's `(23, 20)` measured 4px above the south facing's
    /// feet (silhouette rows 8..<24), and the constant is now the measured
    /// `(23, 24)`.
    ///
    /// Both sheets are checked against the same anchor on purpose: the two
    /// share one `anchorPointNormalized`, so if their south-facing feet sat
    /// on different rows a raccoon would visibly hop the moment it switched
    /// from walking to attacking.
    func test_anchorPixel_sitsAtTheMeasuredGroundContactCentreOfBothSheets() throws {
        let anchor = RaccoonAnimationController.anchorPixel

        for atlasSheet in sheets {
            let pixels = try self.pixels(of: atlasSheet)
            let bounds = try XCTUnwrap(
                unionContentBounds(row: 0, of: pixels),
                "\(atlasSheet.imageID) row 0 (the south facing) holds no opaque pixels at all, so this "
                    + "anchor measurement would otherwise pass vacuously."
            )

            let measuredCentreX = CGFloat(bounds.x.lowerBound + bounds.x.upperBound) / 2
            let measuredGroundLine = CGFloat(bounds.y.upperBound)

            XCTAssertEqual(
                anchor.x, measuredCentreX, accuracy: anchorTolerance,
                "\(atlasSheet.imageID): anchorPixel.x is \(anchor.x), but the south facing's silhouette "
                    + "spans x \(bounds.x.lowerBound)..<\(bounds.x.upperBound), centred at "
                    + "\(measuredCentreX). Every raccoon's shadow and depth sample would sit off-centre "
                    + "by the difference."
            )
            XCTAssertEqual(
                anchor.y, measuredGroundLine, accuracy: anchorTolerance,
                "\(atlasSheet.imageID): anchorPixel.y is \(anchor.y), but the south facing's silhouette "
                    + "ends on row \(bounds.y.upperBound - 1), i.e. a ground-contact line of "
                    + "\(measuredGroundLine) (silhouette rows \(bounds.y.lowerBound)..<"
                    + "\(bounds.y.upperBound) of a \(Int(RaccoonAnimationController.cellSize.height))px "
                    + "cell). Pin anchorPixel to the measured line rather than widening this tolerance."
            )
        }
    }

    // MARK: - The ground footprint under the shadow

    /// `RaccoonAnimationController.groundFootprintWidth` is what
    /// `RaccoonNode.shadowWidth(forTier:)` hands `ActorShadowNode`, which
    /// takes no default width precisely so that number comes from a
    /// measurement of the actor rather than from nowhere. This is that
    /// measurement: the widest paw-to-paw span the shipped south-facing walk
    /// frames draw in their ground-contact band.
    func test_groundFootprintWidth_equalsTheMeasuredGroundContactSpan() throws {
        let pixels = try self.pixels(of: .raccoonWalk)

        // Every directly-authored facing, not just the south one: a shadow
        // is a single ellipse fixed at construction, so it has to cover the
        // widest stance the raccoon ever plants, whichever way it faces.
        var widestPerRow: [Int: Int] = [:]
        for row in 0...4 {
            for column in 0..<RaccoonAnimationController.frameCount {
                guard let span = groundContactSpan(of: cell(column: column, row: row, of: pixels)) else { continue }
                widestPerRow[row] = Swift.max(widestPerRow[row] ?? 0, span.count)
            }
        }

        let widest = try XCTUnwrap(
            widestPerRow.values.max(),
            "sprite_raccoon_walk's authored rows hold no opaque ground-contact pixels, so this footprint "
                + "measurement would otherwise pass vacuously."
        )

        XCTAssertEqual(
            RaccoonAnimationController.groundFootprintWidth, CGFloat(widest), accuracy: 1,
            "groundFootprintWidth is \(RaccoonAnimationController.groundFootprintWidth), but the widest "
                + "ground-contact span the shipped walk art draws is \(widest)px "
                + "(widest per authored row: \(widestPerRow.sorted { $0.key < $1.key })). Pin the "
                + "constant to the measurement - the shadow's width is only honest while it matches the "
                + "paw span the art actually draws."
        )

        XCTAssertLessThan(
            RaccoonAnimationController.groundFootprintWidth,
            RaccoonAnimationController.cellSize.width,
            "A footprint as wide as the whole \(RaccoonAnimationController.cellSize.width)pt cell means "
                + "the shadow ellipse spans the raccoon's entire drawn width, reading as a puddle rather "
                + "than a ground contact."
        )
    }

    // MARK: - Pixel measurement helpers

    private func pixels(of atlasSheet: AtlasSheet) throws -> ImagePixelSampling.Pixels {
        try XCTUnwrap(
            ImagePixelSampling.pixels(ofImageNamed: atlasSheet.imageID),
            "\(atlasSheet.imageID) could not be decoded from Assets.xcassets - every measurement in "
                + "this file would otherwise pass vacuously on an empty image."
        )
    }

    /// One cell of the decoded sheet, lifted into its own `Pixels` so
    /// `ImagePixelSampling`'s fingerprint/mirror helpers apply to it
    /// directly.
    ///
    /// Per *cell* rather than per whole row, for the same reason
    /// `PlayerSpriteSheetTests` does it that way: a mirrored facing is drawn
    /// as a negative x-scale on the node showing one frame, so flipping a
    /// whole 4-frame row would also reverse the cycle order and compare
    /// frame 0 against frame 3.
    private func cell(column: Int, row: Int, of pixels: ImagePixelSampling.Pixels) -> ImagePixelSampling.Pixels {
        let cellWidth = Int(RaccoonAnimationController.cellSize.width)
        let cellHeight = Int(RaccoonAnimationController.cellSize.height)

        var bytes: [UInt8] = []
        bytes.reserveCapacity(cellWidth * cellHeight * 4)
        for y in (row * cellHeight)..<((row + 1) * cellHeight) {
            for x in (column * cellWidth)..<((column + 1) * cellWidth) {
                let base = (y * pixels.width + x) * 4
                bytes.append(contentsOf: pixels.rgba[base..<(base + 4)])
            }
        }
        return ImagePixelSampling.Pixels(width: cellWidth, height: cellHeight, rgba: bytes)
    }

    /// The opaque-content bounding box of `row`'s four frames unioned
    /// together -- the facing's silhouette across its whole cycle, rather
    /// than whichever single frame happens to reach furthest.
    private func unionContentBounds(
        row: Int,
        of pixels: ImagePixelSampling.Pixels
    ) -> (x: Range<Int>, y: Range<Int>)? {
        var union: (x: Range<Int>, y: Range<Int>)?

        for column in 0..<RaccoonAnimationController.frameCount {
            let cellPixels = cell(column: column, row: row, of: pixels)
            guard let bounds = cellPixels.contentBounds(inColumns: 0..<cellPixels.width) else { continue }
            guard let current = union else {
                union = bounds
                continue
            }
            let minX = Swift.min(current.x.lowerBound, bounds.x.lowerBound)
            let maxX = Swift.max(current.x.upperBound, bounds.x.upperBound)
            let minY = Swift.min(current.y.lowerBound, bounds.y.lowerBound)
            let maxY = Swift.max(current.y.upperBound, bounds.y.upperBound)
            union = (x: minX..<maxX, y: minY..<maxY)
        }

        return union
    }

    /// The horizontal span of opaque pixels in the bottom
    /// `groundContactBandHeight` rows of this cell's silhouette -- where the
    /// paws meet the ground, which is what a shadow is a shadow *of*.
    private func groundContactSpan(of cellPixels: ImagePixelSampling.Pixels) -> Range<Int>? {
        guard let bounds = cellPixels.contentBounds(inColumns: 0..<cellPixels.width) else { return nil }

        let bandTop = Swift.max(bounds.y.lowerBound, bounds.y.upperBound - groundContactBandHeight)
        var minX = Int.max
        var maxX = Int.min

        for y in bandTop..<bounds.y.upperBound {
            for x in 0..<cellPixels.width where cellPixels.isOpaque(x: x, y: y) {
                minX = Swift.min(minX, x)
                maxX = Swift.max(maxX, x)
            }
        }

        guard minX <= maxX else { return nil }
        return minX..<(maxX + 1)
    }

    private func opaquePixelCount(of cellPixels: ImagePixelSampling.Pixels) -> Int {
        cellPixels.width * cellPixels.height - cellPixels.fullyTransparentPixelCount
    }

    /// The cell's opaque/transparent mask, row-major. Silhouette rather than
    /// full RGBA decides the mirroring assertion: an authored west-side pose
    /// changes the outline, while a re-export of the same mirrored art can
    /// shift a byte of colour without changing which pixels are drawn.
    private func opaqueSilhouette(of cellPixels: ImagePixelSampling.Pixels) -> [Bool] {
        var mask: [Bool] = []
        mask.reserveCapacity(cellPixels.width * cellPixels.height)
        for y in 0..<cellPixels.height {
            for x in 0..<cellPixels.width {
                mask.append(cellPixels.isOpaque(x: x, y: y))
            }
        }
        return mask
    }

    private func mirroredOpaqueSilhouette(of cellPixels: ImagePixelSampling.Pixels) -> [Bool] {
        var mask: [Bool] = []
        mask.reserveCapacity(cellPixels.width * cellPixels.height)
        for y in 0..<cellPixels.height {
            for x in 0..<cellPixels.width {
                mask.append(cellPixels.isOpaque(x: cellPixels.width - 1 - x, y: y))
            }
        }
        return mask
    }
}
