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
}
