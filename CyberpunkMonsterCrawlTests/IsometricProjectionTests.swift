import CoreGraphics
import XCTest
@testable import CyberpunkMonsterCrawl

/// `IsometricProjection.screenToTile` must be the exact algebraic inverse of
/// `tileToScreen` on tile centers, over a large sweep of tile coordinates
/// including negative values (world tiles extend in every direction from the
/// origin, so a transform that only round-trips for non-negative tiles would
/// silently break every negative-axis tile in the generated city).
final class IsometricProjectionTests: XCTestCase {

    /// Double-precision arithmetic round-trips within a tiny epsilon; any
    /// larger drift would indicate the inverse formula doesn't match the
    /// forward transform algebraically.
    private let accuracy = 1e-9

    func test_screenToTile_invertsTileToScreen_overLargeSweepIncludingNegatives() {
        for tileX in stride(from: -50, through: 50, by: 1) {
            for tileY in stride(from: -50, through: 50, by: 1) {
                let screen = IsometricProjection.tileToScreen(tileX: Double(tileX), tileY: Double(tileY))
                let roundTripped = IsometricProjection.screenToTile(
                    screenX: Double(screen.x),
                    screenY: Double(screen.y)
                )

                XCTAssertEqual(
                    roundTripped.tileX,
                    Double(tileX),
                    accuracy: accuracy,
                    "Round-trip tileX mismatch at (\(tileX), \(tileY))"
                )
                XCTAssertEqual(
                    roundTripped.tileY,
                    Double(tileY),
                    accuracy: accuracy,
                    "Round-trip tileY mismatch at (\(tileX), \(tileY))"
                )
            }
        }
    }

    /// Pins the forward transform's exact constants (48/24 half-diamond) so
    /// a future edit to the world tile size can't silently drift without a
    /// failing test at a well-known tile.
    func test_tileToScreen_originIsScreenOrigin() {
        let screen = IsometricProjection.tileToScreen(tileX: 0, tileY: 0)

        XCTAssertEqual(Double(screen.x), 0, accuracy: accuracy)
        XCTAssertEqual(Double(screen.y), 0, accuracy: accuracy)
    }

    func test_tileToScreen_matchesDocumentedFormula_forASingleKnownTile() {
        let screen = IsometricProjection.tileToScreen(tileX: 3, tileY: 5)

        // screenX = (3 - 5) * 48 = -96, screenY = (3 + 5) * 24 = 192
        XCTAssertEqual(Double(screen.x), -96, accuracy: accuracy)
        XCTAssertEqual(Double(screen.y), 192, accuracy: accuracy)
    }

    func test_cgPointConvenienceOverloads_roundTrip() {
        let tile = CGPoint(x: -17, y: 23)
        let screen = IsometricProjection.tileToScreen(tile: tile)
        let roundTripped = IsometricProjection.screenToTile(screen: screen)

        XCTAssertEqual(Double(roundTripped.x), Double(tile.x), accuracy: accuracy)
        XCTAssertEqual(Double(roundTripped.y), Double(tile.y), accuracy: accuracy)
    }
}
