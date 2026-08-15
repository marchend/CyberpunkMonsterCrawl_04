import CoreGraphics
import SpriteKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// CYBERPUN-17-6-t3: `PixelCrispness` gains a camera-aware snapping entry
/// point (`snappedPosition(for:scale:)`) and a standalone integer-scale
/// predicate (`isIntegerScale(_:)`), on top of the existing `apply(to:)`
/// whole-*point* finalizer other tests already cover.
///
/// Every case here is simulated at explicit `@2x`/`@3x` device scales
/// (never a live `UIScreen`), per the type's own contract: it is a pure
/// function of an explicit scale, testable headlessly.
final class PixelCrispnessTests: XCTestCase {

    // MARK: - isIntegerScale(_:)

    func test_isIntegerScale_true_forWholeScales_includingSimulatedDeviceScales() {
        // `@1x`/`@2x`/`@3x` device scales are always whole integers -- the
        // exact values `GameScene.deviceScale` reads off a live `SKView`.
        XCTAssertTrue(PixelCrispness.isIntegerScale(1))
        XCTAssertTrue(PixelCrispness.isIntegerScale(2))
        XCTAssertTrue(PixelCrispness.isIntegerScale(3))
    }

    func test_isIntegerScale_true_forNegativeWholeScales() {
        // A mirrored sprite's `xScale` is negative but still whole --
        // `apply(to:)` preserves that sign, so the predicate must accept it.
        XCTAssertTrue(PixelCrispness.isIntegerScale(-1))
        XCTAssertTrue(PixelCrispness.isIntegerScale(-2))
    }

    func test_isIntegerScale_false_forFractionalScales() {
        XCTAssertFalse(PixelCrispness.isIntegerScale(1.5))
        XCTAssertFalse(PixelCrispness.isIntegerScale(2.01))
        XCTAssertFalse(PixelCrispness.isIntegerScale(-2.5))
    }

    func test_isIntegerScale_true_forZero() {
        // Not a scale any consumer should ever carry (`apply(to:)` floors
        // magnitude at 1), but `0` is a whole integer and the predicate is a
        // pure arithmetic fact, not a "is this legal" check.
        XCTAssertTrue(PixelCrispness.isIntegerScale(0))
    }

    // MARK: - snappedPosition(for:scale:) at simulated @2x

    func test_snappedPosition_atSimulated2x_landsOnAWholeDevicePixel() {
        let scale: CGFloat = 2
        let position = CGPoint(x: 10.24, y: -5.26)

        let snapped = PixelCrispness.snappedPosition(for: position, scale: scale)

        assertIsWholeDevicePixel(snapped, scale: scale)
    }

    // MARK: - snappedPosition(for:scale:) at simulated @3x

    func test_snappedPosition_atSimulated3x_landsOnAWholeDevicePixel() {
        let scale: CGFloat = 3
        let position = CGPoint(x: 100.10, y: 200.02)

        let snapped = PixelCrispness.snappedPosition(for: position, scale: scale)

        assertIsWholeDevicePixel(snapped, scale: scale)
    }

    // MARK: - Already-aligned input is a no-op (idempotent)

    func test_snappedPosition_alreadyPixelAligned_isUnchanged() {
        for scale: CGFloat in [1, 2, 3] {
            // Half-point positions are exactly on the pixel grid at @2x/@3x
            // (and whole points always are), so snapping must not move them.
            let position = CGPoint(x: 12, y: -7)
            let snapped = PixelCrispness.snappedPosition(for: position, scale: scale)
            XCTAssertEqual(snapped, position, "Scale \(scale): an already-aligned position must not move.")
        }
    }

    func test_snappedPosition_isIdempotent() {
        let scale: CGFloat = 3
        let position = CGPoint(x: 41.777, y: -13.333)

        let snappedOnce = PixelCrispness.snappedPosition(for: position, scale: scale)
        let snappedTwice = PixelCrispness.snappedPosition(for: snappedOnce, scale: scale)

        XCTAssertEqual(snappedOnce, snappedTwice)
    }

    // MARK: - Whole-integer screen positions across a sequence of simulated camera moves

    func test_snappedPosition_acrossASequenceOfSimulatedCameraMoves_alwaysStaysPixelAligned() {
        // A camera-driven position is re-derived every move (never assigned
        // once); this simulates that by repeatedly nudging a running
        // position by a fractional amount, at both device scales this game
        // ships at, and checking every single stop along the way.
        let moves: [CGVector] = [
            CGVector(dx: 4.33, dy: -1.1),
            CGVector(dx: -7.9, dy: 2.6),
            CGVector(dx: 12.05, dy: 12.05),
            CGVector(dx: -0.013, dy: -0.007),
            CGVector(dx: 0.501, dy: -0.499),
        ]

        for scale: CGFloat in [2, 3] {
            var runningPosition = CGPoint.zero
            for move in moves {
                runningPosition = CGPoint(x: runningPosition.x + move.dx, y: runningPosition.y + move.dy)
                let snapped = PixelCrispness.snappedPosition(for: runningPosition, scale: scale)
                assertIsWholeDevicePixel(snapped, scale: scale)
            }
        }
    }

    // MARK: - Non-positive scale is a safe no-op, never a division by zero

    func test_snappedPosition_nonPositiveScale_returnsPositionUnchanged() {
        let position = CGPoint(x: 3.7, y: -9.2)
        XCTAssertEqual(PixelCrispness.snappedPosition(for: position, scale: 0), position)
        XCTAssertEqual(PixelCrispness.snappedPosition(for: position, scale: -2), position)
    }

    // MARK: - Helpers

    /// Asserts `point`, multiplied by `scale`, lands on a whole number in
    /// both axes -- i.e. `point` sits exactly on a device pixel boundary at
    /// that scale.
    private func assertIsWholeDevicePixel(_ point: CGPoint, scale: CGFloat, file: StaticString = #filePath, line: UInt = #line) {
        let scaledX = point.x * scale
        let scaledY = point.y * scale
        XCTAssertEqual(scaledX, scaledX.rounded(), accuracy: 1e-6, "x (\(point.x)) is not pixel-aligned at scale \(scale).", file: file, line: line)
        XCTAssertEqual(scaledY, scaledY.rounded(), accuracy: 1e-6, "y (\(point.y)) is not pixel-aligned at scale \(scale).", file: file, line: line)
    }
}
