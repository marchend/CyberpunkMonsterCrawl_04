import CoreGraphics
import XCTest
@testable import CyberpunkMonsterCrawl

/// CYBERPUN-17-6 PR 1: the player's row/mirror table, anchor point and
/// hitbox geometry.
final class PlayerSpriteSheetTests: XCTestCase {

    private let accuracy: CGFloat = 1e-9

    // MARK: - Sheet geometry, delegated to AtlasSheet.playerWalk

    func test_sheetGeometry_matchesTheDeclaredAtlasContract() {
        XCTAssertEqual(PlayerSpriteSheet.pixelSize, CGSize(width: 144, height: 320))
        XCTAssertEqual(PlayerSpriteSheet.cellSize, CGSize(width: 36, height: 40))
        XCTAssertEqual(PlayerSpriteSheet.columns, 4)
        XCTAssertEqual(PlayerSpriteSheet.rows, 8)
    }

    // MARK: - Row/mirror table: the 5 directly-authored facings

    func test_directlyAuthoredFacings_mapToRowsZeroThroughFour_unmirrored() {
        let expected: [(Direction8, Int)] = [
            (.south, 0),
            (.southeast, 1),
            (.east, 2),
            (.northeast, 3),
            (.north, 4),
        ]

        for (direction, row) in expected {
            let mapping = PlayerSpriteSheet.rowMapping(for: direction)
            XCTAssertEqual(mapping.row, row, "\(direction) should map to row \(row).")
            XCTAssertFalse(mapping.mirrored, "\(direction) should not be mirrored.")
        }
    }

    // MARK: - Row/mirror table: the 3 mirrored facings

    /// Each mirrored facing reuses the row of the directly-authored facing
    /// that shares its vertical component \u2014 southwest/southeast both move
    /// down, west/east are both purely lateral, northwest/northeast both
    /// move up. Mirroring across any other pairing would show the wrong
    /// vertical pose.
    func test_mirroredFacings_reuseTheRowOfTheMatchingVerticalComponent_andAreMirrored() {
        let southwest = PlayerSpriteSheet.rowMapping(for: .southwest)
        XCTAssertEqual(southwest.row, PlayerSpriteSheet.rowMapping(for: .southeast).row)
        XCTAssertTrue(southwest.mirrored)

        let west = PlayerSpriteSheet.rowMapping(for: .west)
        XCTAssertEqual(west.row, PlayerSpriteSheet.rowMapping(for: .east).row)
        XCTAssertTrue(west.mirrored)

        let northwest = PlayerSpriteSheet.rowMapping(for: .northwest)
        XCTAssertEqual(northwest.row, PlayerSpriteSheet.rowMapping(for: .northeast).row)
        XCTAssertTrue(northwest.mirrored)
    }

    func test_rowMapping_isExhaustiveOverEveryDirection8Case() {
        for direction in Direction8.allCases {
            // Would trap via preconditionFailure if any case were missing.
            _ = PlayerSpriteSheet.rowMapping(for: direction)
        }
    }

    // MARK: - Negative x-scale on mirrored facings

    func test_xScale_isNegativeOneForMirroredFacings_positiveOneOtherwise() {
        for direction in Direction8.allCases {
            let expectedMirrored = PlayerSpriteSheet.rowMapping(for: direction).mirrored
            let scale = PlayerSpriteSheet.xScale(for: direction)
            if expectedMirrored {
                XCTAssertEqual(scale, -1, "\(direction) is mirrored; expected xScale -1.")
            } else {
                XCTAssertEqual(scale, 1, "\(direction) is not mirrored; expected xScale 1.")
            }
        }
    }

    // MARK: - Anchor pixel math

    func test_anchorPixel_isHorizontalCenterAndCellBottom() {
        XCTAssertEqual(PlayerSpriteSheet.anchorPixel, CGPoint(x: 18, y: 40))
    }

    func test_anchorPointNormalized_isBottomCenterOfTheCell() {
        let anchor = PlayerSpriteSheet.anchorPointNormalized
        XCTAssertEqual(anchor.x, 0.5, accuracy: accuracy)
        XCTAssertEqual(anchor.y, 0, accuracy: accuracy)
    }

    // MARK: - Hitbox geometry

    func test_hitboxSize_is14By10() {
        XCTAssertEqual(PlayerSpriteSheet.hitboxSize, CGSize(width: 14, height: 10))
    }

    func test_hitboxRect_isCenteredOnTheAnchoredPosition() {
        let position = CGPoint(x: 100, y: 200)
        let rect = PlayerSpriteSheet.hitboxRect(anchoredAt: position)

        XCTAssertEqual(rect.width, 14, accuracy: accuracy)
        XCTAssertEqual(rect.height, 10, accuracy: accuracy)
        XCTAssertEqual(rect.midX, position.x, accuracy: accuracy)
        XCTAssertEqual(rect.midY, position.y, accuracy: accuracy)
    }

    func test_hitboxRect_atOrigin_isSymmetricAroundZero() {
        let rect = PlayerSpriteSheet.hitboxRect(anchoredAt: .zero)
        XCTAssertEqual(rect.minX, -7, accuracy: accuracy)
        XCTAssertEqual(rect.maxX, 7, accuracy: accuracy)
        XCTAssertEqual(rect.minY, -5, accuracy: accuracy)
        XCTAssertEqual(rect.maxY, 5, accuracy: accuracy)
    }

    // MARK: - The mirroring claim, measured off the shipped pixels

    /// The table above is only checked against a hand-written copy of itself
    /// by the tests further up, which guards typos and nothing else - the
    /// same gap `GroundTileSemanticsTests`' header calls out for the lane
    /// pair. This is the discriminating measurement.
    ///
    /// `AtlasSheet.playerWalk` measures a 144x320 sheet (8 real rows) and
    /// `AtlasCellIndex.playerWalk` declares all 32 cells valid, while
    /// `rowMappingTable` only ever reads rows 0-4. That is safe *only* if
    /// the three rows it never reads carry no art of their own. Sheet rows
    /// 5/6/7 continue the compass sweep past due-north (northwest, west,
    /// southwest), so each pairs with the directly-authored row sharing its
    /// vertical component - 5 with 3 (northeast), 6 with 2 (east), 7 with 1
    /// (southeast) - which is exactly the pairing `rowMappingTable` mirrors.
    ///
    /// So for each of those rows the art must be either empty (mirroring is
    /// *required*) or the horizontal flip of its source row (mirroring is
    /// *equivalent*). If instead a row holds authored west-side art -
    /// asymmetric detail such as a weapon hand would make the flip visibly
    /// wrong - the player renders mirrored east art for half the compass and
    /// 12 shipped cells are dead, which no assertion in this file could
    /// currently see.
    ///
    /// **If this fails, do not loosen it.** Either the art authors the west
    /// side (point `.southwest`/`.west`/`.northwest` at rows 7/6/5 with
    /// `mirrored: false`) or the sheet ships three rows that need
    /// re-exporting. The failure message reports the measured numbers so the
    /// reader can tell which.
    func test_theRowsTheTableNeverReads_carryNoArtBeyondTheMirrorOfTheirSourceRow() throws {
        let pixels = try playerWalkPixels()

        XCTAssertEqual(
            CGSize(width: CGFloat(pixels.width), height: CGFloat(pixels.height)),
            PlayerSpriteSheet.pixelSize,
            "the decoded sheet must match the declared atlas geometry, or every cell crop below "
                + "addresses the wrong pixels"
        )

        let rowsTheTableReads = Set(Direction8.allCases.map { PlayerSpriteSheet.rowMapping(for: $0).row })
        XCTAssertEqual(
            rowsTheTableReads, Set(0...4),
            "this measurement assumes the table reads rows 0-4 and leaves 5-7 unread; it measured "
                + "\(rowsTheTableReads.sorted()) instead, so the pairing below is stale."
        )

        // (unread sheet row, the row `rowMappingTable` mirrors in its place).
        let mirrorPairs: [(unread: Int, facing: Direction8)] = [
            (5, .northwest),
            (6, .west),
            (7, .southwest),
        ]

        for pair in mirrorPairs {
            let sourceRow = PlayerSpriteSheet.rowMapping(for: pair.facing).row
            var opaquePixelsInUnreadRow = 0
            var cellsEqualToTheMirroredSource = 0
            var cellsWithTheMirroredSilhouette = 0

            for column in 0..<PlayerSpriteSheet.columns {
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
            let rowIsTheMirrorOfItsSource = cellsWithTheMirroredSilhouette == PlayerSpriteSheet.columns

            XCTAssertTrue(
                rowIsEmpty || rowIsTheMirrorOfItsSource,
                "PlayerSpriteSheet mirrors row \(sourceRow) into .\(pair.facing) and never reads sheet "
                    + "row \(pair.unread), but row \(pair.unread) measures \(opaquePixelsInUnreadRow) "
                    + "opaque pixels that are not the horizontal flip of row \(sourceRow) "
                    + "(\(cellsWithTheMirroredSilhouette)/\(PlayerSpriteSheet.columns) cells match the "
                    + "flipped silhouette, \(cellsEqualToTheMirroredSource)/\(PlayerSpriteSheet.columns) "
                    + "match it pixel-for-pixel). The west side of the sheet is authored, so the table "
                    + "is discarding real art and rendering a mirrored east pose for .\(pair.facing)."
            )
        }
    }

    // MARK: - Pixel measurement helpers

    private func playerWalkPixels() throws -> ImagePixelSampling.Pixels {
        let imageID = AtlasSheet.playerWalk.imageID
        return try XCTUnwrap(
            ImagePixelSampling.pixels(ofImageNamed: imageID),
            "\(imageID) could not be decoded from Assets.xcassets - the mirroring measurement would "
                + "otherwise pass vacuously on an empty image."
        )
    }

    /// One cell of the decoded sheet, lifted into its own `Pixels` so
    /// `ImagePixelSampling`'s fingerprint/mirror helpers apply to it
    /// directly.
    ///
    /// Per *cell* rather than per whole row on purpose: a mirrored facing is
    /// drawn as a negative x-scale on the node showing one frame, which
    /// flips that frame only. Flipping a whole 4-frame row would also
    /// reverse the walk-cycle order and compare frame 0 against frame 3.
    private func cell(column: Int, row: Int, of pixels: ImagePixelSampling.Pixels) -> ImagePixelSampling.Pixels {
        let cellWidth = Int(PlayerSpriteSheet.cellSize.width)
        let cellHeight = Int(PlayerSpriteSheet.cellSize.height)

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

    private func opaquePixelCount(of cell: ImagePixelSampling.Pixels) -> Int {
        cell.width * cell.height - cell.fullyTransparentPixelCount
    }

    /// The cell's opaque/transparent mask, row-major. Silhouette rather than
    /// full RGBA is what decides the assertion: an authored west-side pose
    /// (a weapon moved to the other hand, a different arm swing) changes the
    /// outline, while a re-export of the same mirrored art can shift a byte
    /// of colour without changing which pixels are drawn.
    private func opaqueSilhouette(of cell: ImagePixelSampling.Pixels) -> [Bool] {
        var mask: [Bool] = []
        mask.reserveCapacity(cell.width * cell.height)
        for y in 0..<cell.height {
            for x in 0..<cell.width {
                mask.append(cell.isOpaque(x: x, y: y))
            }
        }
        return mask
    }

    private func mirroredOpaqueSilhouette(of cell: ImagePixelSampling.Pixels) -> [Bool] {
        var mask: [Bool] = []
        mask.reserveCapacity(cell.width * cell.height)
        for y in 0..<cell.height {
            for x in 0..<cell.width {
                mask.append(cell.isOpaque(x: cell.width - 1 - x, y: y))
            }
        }
        return mask
    }
}
