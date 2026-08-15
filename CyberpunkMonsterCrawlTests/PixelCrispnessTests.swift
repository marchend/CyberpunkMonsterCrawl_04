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

    func test_snappedPosition_atSimulated2x_landsOnTheExpectedWholeDevicePixel() {
        let scale: CGFloat = 2
        let position = CGPoint(x: 10.24, y: -5.26)

        let snapped = PixelCrispness.snappedPosition(for: position, scale: scale)

        // The *exact* expected pixel, not merely "some aligned point":
        // 10.24 * 2 = 20.48 -> 20 -> 10.0, and -5.26 * 2 = -10.52 -> -11 ->
        // -5.5. Asserting alignment alone would also pass for an
        // implementation returning `.zero`, flooring instead of rounding, or
        // ignoring `scale` entirely.
        assertSnappedPosition(snapped, equals: CGPoint(x: 10.0, y: -5.5))
        assertIsWholeDevicePixel(snapped, scale: scale)
    }

    // MARK: - snappedPosition(for:scale:) at simulated @3x

    func test_snappedPosition_atSimulated3x_landsOnTheExpectedWholeDevicePixel() {
        let scale: CGFloat = 3
        let position = CGPoint(x: 100.10, y: 200.02)

        let snapped = PixelCrispness.snappedPosition(for: position, scale: scale)

        // 100.10 * 3 = 300.3 -> 300 -> 100.0, and 200.02 * 3 = 600.06 -> 600
        // -> 200.0.
        assertSnappedPosition(snapped, equals: CGPoint(x: 100.0, y: 200.0))
        assertIsWholeDevicePixel(snapped, scale: scale)
    }

    // MARK: - The snap is to the nearest *device pixel*, not the nearest point

    func test_snappedPosition_roundsToNearestDevicePixel_notToAWholePoint() {
        // 10.3 at `@2x` is 20.6 device pixels: the nearest whole device
        // pixel is 21, i.e. 10.5 points -- a half point, which a
        // whole-*point* rounder (`apply(to:)`'s rule) would instead flatten
        // to 10.0. This case is what separates the two, and is exactly the
        // sub-pixel drift `GameScene.startPlayer()` relies on this entry
        // point to remove.
        let snappedAt2x = PixelCrispness.snappedPosition(for: CGPoint(x: 10.3, y: -10.3), scale: 2)
        assertSnappedPosition(snappedAt2x, equals: CGPoint(x: 10.5, y: -10.5))

        // Same input at `@3x`: 30.9 -> 31 device pixels -> 31/3 points, a
        // value that is neither a whole nor a half point -- so the result
        // provably depends on `scale`.
        let snappedAt3x = PixelCrispness.snappedPosition(for: CGPoint(x: 10.3, y: -10.3), scale: 3)
        assertSnappedPosition(snappedAt3x, equals: CGPoint(x: 31.0 / 3.0, y: -31.0 / 3.0))
    }

    // MARK: - Already-aligned input is a no-op (idempotent)

    func test_snappedPosition_wholePointPosition_isUnchangedAtEveryScale() {
        for scale: CGFloat in [1, 2, 3] {
            // A whole point is a whole number of device pixels at every
            // integer scale (1, 2 or 3 of them), so snapping must not move
            // it.
            let position = CGPoint(x: 12, y: -7)
            let snapped = PixelCrispness.snappedPosition(for: position, scale: scale)
            XCTAssertEqual(snapped, position, "Scale \(scale): an already-aligned position must not move.")
        }
    }

    func test_snappedPosition_halfPointPosition_isOnTheGridAt2x_butNotAt3x() {
        // A half point is exactly one device pixel at `@2x` (0.5 * 2 = 1),
        // so it is already aligned and must not move...
        let halfPoint = CGPoint(x: 12.5, y: -7.5)
        assertSnappedPosition(
            PixelCrispness.snappedPosition(for: halfPoint, scale: 2),
            equals: halfPoint
        )

        // ...but at `@3x` it is 1.5 device pixels -- *not* on the grid -- so
        // it must be moved to the nearest whole pixel: 37.5 -> 38 and
        // -22.5 -> -23 (rounding half away from zero, symmetrically).
        assertSnappedPosition(
            PixelCrispness.snappedPosition(for: halfPoint, scale: 3),
            equals: CGPoint(x: 38.0 / 3.0, y: -23.0 / 3.0)
        )
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
                // ...and it is the *nearest* such pixel, so the position the
                // camera derived is preserved to within half a device pixel
                // rather than being replaced by some other aligned value.
                assertIsNearestDevicePixel(snapped, to: runningPosition, scale: scale)
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

    /// Asserts `point` is the exact expected value in both axes. `accuracy`
    /// covers the one floating-point division `snappedPosition` performs,
    /// nothing looser -- these are exact-value expectations, not
    /// "somewhere near" ones.
    private func assertSnappedPosition(_ point: CGPoint, equals expected: CGPoint, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(point.x, expected.x, accuracy: 1e-9, "x: expected \(expected.x), got \(point.x).", file: file, line: line)
        XCTAssertEqual(point.y, expected.y, accuracy: 1e-9, "y: expected \(expected.y), got \(point.y).", file: file, line: line)
    }

    /// Asserts `point` is the *nearest* device pixel to `original` at
    /// `scale` -- i.e. it moved by at most half a device pixel in each axis.
    /// Alignment alone is satisfied by any number of wrong answers (`.zero`
    /// among them); this pins that the snapped value is still the position
    /// the caller asked about.
    private func assertIsNearestDevicePixel(_ point: CGPoint, to original: CGPoint, scale: CGFloat, file: StaticString = #filePath, line: UInt = #line) {
        let tolerance = 0.5 / scale + 1e-9
        XCTAssertLessThanOrEqual(abs(point.x - original.x), tolerance, "x moved further than half a device pixel.", file: file, line: line)
        XCTAssertLessThanOrEqual(abs(point.y - original.y), tolerance, "y moved further than half a device pixel.", file: file, line: line)
    }

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
