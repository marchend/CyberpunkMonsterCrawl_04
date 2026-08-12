import CoreGraphics
import XCTest
@testable import CyberpunkMonsterCrawl

/// CYBERPUN-17-1 AC 4: every cell index the game will reference must fall
/// inside its sheet's measured grid — player 4×8, weapons 8×3, raccoon walk
/// 4×8, raccoon attack 4×8, bullets 3, pickups 2, pulse 8, hit puff 4,
/// signs 12, plus the six ground diamonds.
final class AtlasCellIndexTests: XCTestCase {

    private func assertAllIndicesInBounds(
        _ indices: [AtlasCellIndex.CellIndex],
        sheet: SpriteSheet,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(indices.isEmpty, "\(sheet.imageID) owns no cell indices.", file: file, line: line)
        for index in indices {
            XCTAssertTrue(
                index.col >= 0 && index.col < sheet.columns,
                "\(sheet.imageID) column \(index.col) falls outside 0..<\(sheet.columns).",
                file: file,
                line: line
            )
            XCTAssertTrue(
                index.row >= 0 && index.row < sheet.rows,
                "\(sheet.imageID) row \(index.row) falls outside 0..<\(sheet.rows).",
                file: file,
                line: line
            )
        }
    }

    func test_playerWalk_allIndicesFallWithinTheMeasuredGrid() {
        assertAllIndicesInBounds(AtlasCellIndex.playerWalk, sheet: AtlasSheet.playerWalk.sheet)
    }

    func test_playerWeapons_allIndicesFallWithinTheMeasuredGrid() {
        assertAllIndicesInBounds(AtlasCellIndex.playerWeapons, sheet: AtlasSheet.playerWeapons.sheet)
    }

    func test_raccoonWalk_allIndicesFallWithinTheMeasuredGrid() {
        assertAllIndicesInBounds(AtlasCellIndex.raccoonWalk, sheet: AtlasSheet.raccoonWalk.sheet)
    }

    func test_raccoonAttack_allIndicesFallWithinTheMeasuredGrid() {
        assertAllIndicesInBounds(AtlasCellIndex.raccoonAttack, sheet: AtlasSheet.raccoonAttack.sheet)
    }

    func test_bullets_allIndicesFallWithinTheMeasuredGrid() {
        assertAllIndicesInBounds(AtlasCellIndex.bullets, sheet: AtlasSheet.bullets.sheet)
    }

    func test_pickups_allIndicesFallWithinTheMeasuredGrid() {
        assertAllIndicesInBounds(AtlasCellIndex.pickups, sheet: AtlasSheet.pickups.sheet)
    }

    func test_pulse_allIndicesFallWithinTheMeasuredGrid() {
        assertAllIndicesInBounds(AtlasCellIndex.pulse, sheet: AtlasSheet.pulse.sheet)
    }

    func test_hitPuff_allIndicesFallWithinTheMeasuredGrid() {
        assertAllIndicesInBounds(AtlasCellIndex.hitPuff, sheet: AtlasSheet.hitPuff.sheet)
    }

    func test_signs_allIndicesFallWithinTheMeasuredGrid() {
        assertAllIndicesInBounds(AtlasCellIndex.signs, sheet: AtlasSheet.signs.sheet)
    }

    /// The six ground diamonds are not `(col, row)` cells, so they are
    /// checked against the full sheet bounds directly instead of through
    /// `assertAllIndicesInBounds`.
    func test_groundDiamonds_allSixSubRectsFallWithinTheSheetBounds() {
        let sheet = AtlasSheet.groundTiles.sheet
        let sheetBounds = CGRect(origin: .zero, size: sheet.pixelSize)

        XCTAssertEqual(AtlasCellIndex.groundDiamonds.count, 6)
        for diamond in AtlasCellIndex.groundDiamonds {
            XCTAssertTrue(
                sheetBounds.contains(diamond.pixelRect),
                "\(diamond) rect \(diamond.pixelRect) falls outside tileset_ground bounds \(sheetBounds)."
            )
        }
    }

    /// Pins each family's owned cell count to the story's table, so a change
    /// to `AtlasCellIndex` that silently drops or duplicates cells is caught
    /// even though the bounds check above would still pass on a subset.
    func test_everyFamilysOwnedCellCount_matchesTheStoryTable() {
        XCTAssertEqual(AtlasCellIndex.playerWalk.count, 32)
        XCTAssertEqual(AtlasCellIndex.playerWeapons.count, 24)
        XCTAssertEqual(AtlasCellIndex.raccoonWalk.count, 32)
        XCTAssertEqual(AtlasCellIndex.raccoonAttack.count, 32)
        XCTAssertEqual(AtlasCellIndex.bullets.count, 3)
        XCTAssertEqual(AtlasCellIndex.pickups.count, 2)
        XCTAssertEqual(AtlasCellIndex.pulse.count, 8)
        XCTAssertEqual(AtlasCellIndex.hitPuff.count, 4)
        XCTAssertEqual(AtlasCellIndex.signs.count, 12)
        XCTAssertEqual(AtlasCellIndex.groundDiamonds.count, 6)
    }
}
