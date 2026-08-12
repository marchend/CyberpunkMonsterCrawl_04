import CoreGraphics
import XCTest
@testable import CyberpunkMonsterCrawl

/// `IsometricProjection.screenToTile` must be the exact algebraic inverse of
/// `tileToScreen` on tile centers, over a large sweep of tile coordinates
/// including negative values (world tiles extend in every direction from the
/// origin, so a transform that only round-trips for non-negative tiles would
/// silently break every negative-axis tile in the generated city).
///
/// Round-tripping tile centers is the easy half — the algebra guarantees it.
/// The production use of `screenToTile` is the opposite: mapping an
/// arbitrary touch/camera point to *which tile it lands in*. The
/// `tile(containing:)` cases below cover that path, including points sitting
/// exactly on a diamond seam, where `round()` and `floor()` disagree.
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

    /// Pins the origin as the transform's fixed point only. Note this says
    /// nothing about the 48/24 half-diamond constants — `(0, 0) → (0, 0)`
    /// holds for *any* half-width/half-height, so swapping them to 64/32
    /// would leave this assertion green. The constants are pinned by
    /// `test_tileToScreen_matchesDocumentedFormula_forASingleKnownTile`.
    func test_tileToScreen_originIsScreenOrigin() {
        let screen = IsometricProjection.tileToScreen(tileX: 0, tileY: 0)

        XCTAssertEqual(Double(screen.x), 0, accuracy: accuracy)
        XCTAssertEqual(Double(screen.y), 0, accuracy: accuracy)
    }

    /// This is the assertion that actually pins the 48/24 half-diamond
    /// constants: a non-symmetric tile whose expected screen point changes
    /// if either constant drifts.
    func test_tileToScreen_matchesDocumentedFormula_forASingleKnownTile() {
        let screen = IsometricProjection.tileToScreen(tileX: 3, tileY: 5)

        // screenX = (3 - 5) * 48 = -96, screenY = (3 + 5) * 24 = 192
        XCTAssertEqual(Double(screen.x), -96, accuracy: accuracy)
        XCTAssertEqual(Double(screen.y), 192, accuracy: accuracy)
    }

    /// The typed convenience pair: `TilePoint` in, `CGPoint` out, and back.
    /// The types are what keep the two spaces apart — a screen-space
    /// `CGPoint` can no longer be handed to the forward transform.
    func test_tilePointConvenienceOverloads_roundTrip() {
        let tile = TilePoint(x: -17, y: 23)
        let screen = IsometricProjection.tileToScreen(tile)
        let roundTripped = IsometricProjection.screenToTile(screen)

        XCTAssertEqual(roundTripped.x, tile.x, accuracy: accuracy)
        XCTAssertEqual(roundTripped.y, tile.y, accuracy: accuracy)
    }

    // MARK: - tile(containing:) — the off-centre / ownership path

    /// Every exact tile center must be owned by its own tile, over a sweep
    /// that includes negatives.
    func test_tileContaining_returnsOwnTile_forEveryTileCentreInSweep() {
        for tileX in stride(from: -25, through: 25, by: 1) {
            for tileY in stride(from: -25, through: 25, by: 1) {
                let screen = IsometricProjection.tileToScreen(tileX: Double(tileX), tileY: Double(tileY))
                let owner = IsometricProjection.tile(containing: screen)

                XCTAssertEqual(owner.tileX, tileX, "Centre of (\(tileX), \(tileY)) escaped its tile on x")
                XCTAssertEqual(owner.tileY, tileY, "Centre of (\(tileX), \(tileY)) escaped its tile on y")
            }
        }
    }

    /// Points just inside the (0, 0) diamond — near each of its four corners
    /// — still belong to (0, 0). The diamond is 96×48, so its corners sit at
    /// (±48, 0) and (0, ±24) in screen space.
    func test_tileContaining_pointsJustInsideOriginDiamond_belongToOrigin() {
        let insidePoints = [
            CGPoint(x: 47.9, y: 0),     // just inside the right corner
            CGPoint(x: -47.9, y: 0),    // just inside the left corner
            CGPoint(x: 0, y: 23.9),     // just inside the top corner
            CGPoint(x: 0, y: -23.9),    // just inside the bottom corner
            CGPoint(x: 0, y: 0)         // the centre itself
        ]

        for point in insidePoints {
            let owner = IsometricProjection.tile(containing: point)

            XCTAssertEqual(owner.tileX, 0, "Point \(point) should be owned by tile (0, 0)")
            XCTAssertEqual(owner.tileY, 0, "Point \(point) should be owned by tile (0, 0)")
        }
    }

    /// A matched pair straddling the (0, 0) / (1, 0) seam: the seam runs
    /// from screen (48, 0) to (0, 24), so its midpoint is (24, 12). A point
    /// a hair short of it is still (0, 0); a hair past it is (1, 0).
    func test_tileContaining_pointsEitherSideOfSeam_landInAdjacentTiles() {
        let justInsideOrigin = IsometricProjection.tile(containing: CGPoint(x: 23.9, y: 11.95))
        XCTAssertEqual(justInsideOrigin.tileX, 0)
        XCTAssertEqual(justInsideOrigin.tileY, 0)

        let justAcrossSeam = IsometricProjection.tile(containing: CGPoint(x: 24.1, y: 12.05))
        XCTAssertEqual(justAcrossSeam.tileX, 1)
        XCTAssertEqual(justAcrossSeam.tileY, 0)
    }

    /// The seam tie-break itself, which is the whole reason
    /// `tile(containing:)` exists rather than each call site picking
    /// `round()` or `floor()`. Ownership is half-open — the seam belongs to
    /// the higher-index tile — and that must hold identically on both sides
    /// of the origin. `rounded(.toNearestOrAwayFromZero)` would fail the
    /// negative case by handing (-24, -12) to tile (-1, 0).
    func test_tileContaining_pointsExactlyOnSeam_belongToHigherIndexTile_onBothSidesOfOrigin() {
        // Tile-space (0.5, 0.0): the seam between tiles (0, 0) and (1, 0).
        let positiveSeam = IsometricProjection.tile(containing: CGPoint(x: 24, y: 12))
        XCTAssertEqual(positiveSeam.tileX, 1, "Seam should be owned by the higher-index tile")
        XCTAssertEqual(positiveSeam.tileY, 0)

        // Tile-space (-0.5, 0.0): the seam between tiles (-1, 0) and (0, 0).
        let negativeSeam = IsometricProjection.tile(containing: CGPoint(x: -24, y: -12))
        XCTAssertEqual(negativeSeam.tileX, 0, "Seam rule must not flip sign across the origin")
        XCTAssertEqual(negativeSeam.tileY, 0)
    }

    /// Off-centre points deep in negative tile space resolve to the right
    /// tile too — the case a `floor()`-vs-`round()` mix-up breaks first.
    func test_tileContaining_offCentrePointInNegativeTile_resolvesToThatTile() {
        // Centre of (-3, -2) is screen (-48, -120); nudge off-centre.
        let owner = IsometricProjection.tile(containing: CGPoint(x: -38, y: -115))

        XCTAssertEqual(owner.tileX, -3)
        XCTAssertEqual(owner.tileY, -2)
    }

    // MARK: - tile(containing:) — the tile-space overload

    /// The tile-space overload must answer with the *same* pinned rule as the
    /// screen-space one, so a caller holding a world position (e.g. the
    /// streaming camera) cannot end up on a different tile than a caller
    /// holding the equivalent screen point.
    func test_tileContainingTilePoint_agreesWithScreenSpaceOverload_acrossOffCentreSweep() {
        for xTenths in stride(from: -75, through: 75, by: 1) {
            for yTenths in stride(from: -30, through: 30, by: 3) {
                let tilePoint = TilePoint(x: Double(xTenths) / 10, y: Double(yTenths) / 10)
                let fromTileSpace = IsometricProjection.tile(containing: tilePoint)
                let fromScreenSpace = IsometricProjection.tile(
                    containing: IsometricProjection.tileToScreen(tilePoint)
                )

                XCTAssertEqual(fromTileSpace.tileX, fromScreenSpace.tileX, "Disagreement on x at \(tilePoint)")
                XCTAssertEqual(fromTileSpace.tileY, fromScreenSpace.tileY, "Disagreement on y at \(tilePoint)")
            }
        }
    }

    /// The specific disagreement that motivated exposing this overload: a
    /// call site rolling its own `rounded(.down)` puts tile-space `7.6` in
    /// tile 7, while the pinned `floor(coord + 0.5)` rule says tile 8.
    func test_tileContainingTilePoint_upperHalfOfTile_belongsToTheNextTile_notFloor() {
        XCTAssertEqual(IsometricProjection.tile(containing: TilePoint(x: 7.6, y: 0)).tileX, 8)
        XCTAssertEqual(IsometricProjection.tile(containing: TilePoint(x: 7.4, y: 0)).tileX, 7)

        // Seam and negative-axis behaviour matches the screen-space rule:
        // the seam belongs to the higher-index tile on both sides of zero.
        XCTAssertEqual(IsometricProjection.tile(containing: TilePoint(x: 0.5, y: 0)).tileX, 1)
        XCTAssertEqual(IsometricProjection.tile(containing: TilePoint(x: -0.5, y: 0)).tileX, 0)
        XCTAssertEqual(IsometricProjection.tile(containing: TilePoint(x: -0.6, y: 0)).tileX, -1)
    }
}
