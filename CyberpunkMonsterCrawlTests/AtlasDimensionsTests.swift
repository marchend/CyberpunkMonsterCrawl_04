import CoreGraphics
import XCTest
@testable import CyberpunkMonsterCrawl

/// CYBERPUN-17-1 AC 3: measured pixel dimensions must equal the contract's
/// declared dimensions for every sheet, and every uniform-grid sheet's
/// dimensions must divide evenly by its cell size.
final class AtlasDimensionsTests: XCTestCase {

    /// Reuses `SpriteSheet.measuredPixelSize(forImageNamed:)` — the exact
    /// function `SpriteSheet.init`'s precondition uses — so this test and the
    /// production check can never quietly drift apart.
    func test_measuredPixelSize_equalsDeclaredPixelSize_forEverySheet() {
        for sheetCase in AtlasSheet.allCases {
            let sheet = sheetCase.sheet
            let measured = SpriteSheet.measuredPixelSize(forImageNamed: sheet.imageID)

            XCTAssertEqual(
                measured,
                sheet.pixelSize,
                "\(sheet.imageID) measures \(measured) but AtlasSheet declares \(sheet.pixelSize)."
            )
        }
    }

    func test_pixelSize_dividesEvenlyByCellSize_forEveryUniformGridSheet() {
        var uniformGridSheetCount = 0
        for sheetCase in AtlasSheet.allCases {
            let sheet = sheetCase.sheet
            guard let cellSize = sheet.cellSize else { continue } // tileset_ground: non-uniform, no cellSize.
            uniformGridSheetCount += 1

            XCTAssertEqual(
                sheet.pixelSize.width.truncatingRemainder(dividingBy: cellSize.width),
                0,
                "\(sheet.imageID) width \(sheet.pixelSize.width) is not a whole multiple of "
                    + "cell width \(cellSize.width)."
            )
            XCTAssertEqual(
                sheet.pixelSize.height.truncatingRemainder(dividingBy: cellSize.height),
                0,
                "\(sheet.imageID) height \(sheet.pixelSize.height) is not a whole multiple of "
                    + "cell height \(cellSize.height)."
            )
        }

        // Guards this test against vacuously passing if every sheet lost its
        // cellSize. 9 of the 10 families declare a uniform grid; tileset_ground
        // is the one deliberate exception (see AtlasSheet.groundTiles).
        XCTAssertEqual(uniformGridSheetCount, 9)
    }

    func test_groundTiles_measuresAsDeclared_evenThoughItHasNoUniformCellSize() {
        let sheet = AtlasSheet.groundTiles.sheet

        XCTAssertNil(sheet.cellSize)
        XCTAssertEqual(
            SpriteSheet.measuredPixelSize(forImageNamed: sheet.imageID),
            CGSize(width: 592, height: 60)
        )
    }
}
