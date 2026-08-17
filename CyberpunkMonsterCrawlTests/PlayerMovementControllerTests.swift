import CoreGraphics
import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-7` PR 1: `PlayerMovementController` is the input *consumer*
/// half of the floating-thumbstick story -- a pure, `SKNode`-free type
/// driven directly with synthetic `StickState` values (rather than through a
/// live `FloatingThumbstickNode`), which is exactly what its own doc comment
/// promises: exhaustive unit-testability without a scene.
///
/// All quantities here are plain `CGVector`/`CGFloat`/`Double` arithmetic --
/// no `SKNode`-backed storage is involved anywhere in this file -- so exact
/// (`1e-9`) accuracy is appropriate throughout, unlike
/// `FloatingThumbstickNodeTests`, which reads values that round-trip through
/// SpriteKit's own node storage.
final class PlayerMovementControllerTests: XCTestCase {

    /// A representative in-budget frame step. Deliberately below
    /// `PlayerMovementController.maxFrameDelta` so these tests exercise the
    /// conversion math rather than the stall clamp, which
    /// `test_deltaTime_isClampedAtMaxFrameDelta_soAStallCannotTunnel` owns.
    private let frameDelta: TimeInterval = 1.0 / 60.0

    // MARK: - First frame: nil lastFrameTimestamp forces deltaTime == 0

    func test_firstUpdate_hasNilLastFrameTimestamp_andProducesZeroDisplacement() {
        let controller = PlayerMovementController()
        XCTAssertNil(controller.lastFrameTimestamp)

        let deflected = StickState(direction: CGVector(dx: 0, dy: 1), magnitude: 1, isBeyondDeadZone: true)
        controller.update(stickState: deflected, currentTime: 100)

        XCTAssertEqual(controller.frameDisplacement, .zero, "deltaTime == 0 on the first frame must produce zero movement.")
        XCTAssertEqual(controller.lastFrameTimestamp, 100)
    }

    // MARK: - isMoving toggles exactly at the dead-zone boundary

    func test_isMoving_matchesStickState_isBeyondDeadZone_exactly() {
        let controller = PlayerMovementController()

        controller.update(
            stickState: StickState(direction: .zero, magnitude: 0.15, isBeyondDeadZone: false),
            currentTime: 0
        )
        XCTAssertFalse(controller.isMoving)

        controller.update(
            stickState: StickState(direction: CGVector(dx: 1, dy: 0), magnitude: 0.16, isBeyondDeadZone: true),
            currentTime: 1
        )
        XCTAssertTrue(controller.isMoving)

        controller.update(
            stickState: StickState(direction: .zero, magnitude: 0, isBeyondDeadZone: false),
            currentTime: 2
        )
        XCTAssertFalse(controller.isMoving)
    }

    // MARK: - Facing tracks the movement stick only, and freezes when idle

    func test_facing_followsStickDirection_whileBeyondDeadZone() {
        let controller = PlayerMovementController()
        let east = CGVector(dx: 1, dy: 0)

        controller.update(stickState: StickState(direction: east, magnitude: 1, isBeyondDeadZone: true), currentTime: 0)

        XCTAssertEqual(controller.facingVector, east)
    }

    func test_facing_staysAtItsLastValue_whileInsideTheDeadZone() {
        let controller = PlayerMovementController()
        let north = CGVector(dx: 0, dy: 1)
        controller.update(
            stickState: StickState(direction: north, magnitude: 1, isBeyondDeadZone: true),
            currentTime: 0
        )

        controller.update(stickState: .resting, currentTime: 1)

        XCTAssertEqual(
            controller.facingVector, north,
            "Idle must keep the last facing, matching PlayerNode's own idle behaviour."
        )
    }

    func test_facing_defaultsSouth_beforeAnyDeflection() {
        let controller = PlayerMovementController()
        XCTAssertEqual(controller.facingVector, CGVector(dx: 0, dy: -1))
    }

    // MARK: - Frame displacement: direction/magnitude conversion through the
    // isometric projection, for all 8 headings

    private static let headings: [CGVector] = [
        CGVector(dx: 0, dy: -1), // south
        CGVector(dx: 1, dy: -1).normalized, // southeast
        CGVector(dx: 1, dy: 0), // east
        CGVector(dx: 1, dy: 1).normalized, // northeast
        CGVector(dx: 0, dy: 1), // north
        CGVector(dx: -1, dy: 1).normalized, // northwest
        CGVector(dx: -1, dy: 0), // west
        CGVector(dx: -1, dy: -1).normalized, // southwest
    ]

    /// Deliberately asserted in **screen** space, via `tileToScreen`, rather
    /// than by recomputing the production expression as its own expectation.
    /// The previous version of this test rebuilt `tileDirection / tileLength
    /// * maxTilesPerSecond` as its expected value, so it asserted the
    /// implementation against a copy of itself and stayed green whether the
    /// speed was pinned in tile space or screen space -- exactly the bug it
    /// should have caught. Projecting the result back to screen space and
    /// pinning its *length* distinguishes the two behaviours: under the old
    /// tile-space normalization the east heading came out 2x longer on
    /// screen than the north one.
    func test_frameDisplacement_hasTheSameOnScreenLength_forEveryHeading() {
        let expectedScreenDistance = PlayerMovementController.maxPointsPerSecond * frameDelta

        for direction in Self.headings {
            let controller = PlayerMovementController()
            // First call only establishes `lastFrameTimestamp`; its own
            // deltaTime is forced to 0, so it contributes no displacement.
            controller.update(
                stickState: StickState(direction: direction, magnitude: 1, isBeyondDeadZone: true),
                currentTime: 0
            )
            controller.update(
                stickState: StickState(direction: direction, magnitude: 1, isBeyondDeadZone: true),
                currentTime: frameDelta
            )

            let onScreen = IsometricProjection.tileToScreen(
                TilePoint(x: Double(controller.frameDisplacement.dx), y: Double(controller.frameDisplacement.dy))
            )
            let screenDistance = hypot(Double(onScreen.x), Double(onScreen.y))

            XCTAssertEqual(
                screenDistance, expectedScreenDistance, accuracy: 1e-9,
                "heading \(direction) must cover the same on-screen distance as every other heading"
            )
        }
    }

    /// The companion to the length test above: equal *lengths* alone would
    /// also be satisfied by a controller that ignored the stick and always
    /// moved in one direction, so pin the projected screen *direction* back
    /// to the stick's own heading too.
    func test_frameDisplacement_pointsBackAtTheStickHeading_onceProjectedToScreen() {
        for direction in Self.headings {
            let controller = PlayerMovementController()
            controller.update(
                stickState: StickState(direction: direction, magnitude: 1, isBeyondDeadZone: true),
                currentTime: 0
            )
            controller.update(
                stickState: StickState(direction: direction, magnitude: 1, isBeyondDeadZone: true),
                currentTime: frameDelta
            )

            let onScreen = IsometricProjection.tileToScreen(
                TilePoint(x: Double(controller.frameDisplacement.dx), y: Double(controller.frameDisplacement.dy))
            )
            let length = hypot(onScreen.x, onScreen.y)

            XCTAssertEqual(onScreen.x / length, direction.dx, accuracy: 1e-9, "heading \(direction)")
            XCTAssertEqual(onScreen.y / length, direction.dy, accuracy: 1e-9, "heading \(direction)")
        }
    }

    func test_frameDisplacement_scalesWithMagnitude() {
        let controller = PlayerMovementController()
        let east = CGVector(dx: 1, dy: 0)
        controller.update(stickState: StickState(direction: east, magnitude: 0.5, isBeyondDeadZone: true), currentTime: 0)
        controller.update(
            stickState: StickState(direction: east, magnitude: 0.5, isBeyondDeadZone: true),
            currentTime: frameDelta
        )

        let onScreen = IsometricProjection.tileToScreen(
            TilePoint(x: Double(controller.frameDisplacement.dx), y: Double(controller.frameDisplacement.dy))
        )
        let screenDistance = hypot(Double(onScreen.x), Double(onScreen.y))

        XCTAssertEqual(
            screenDistance,
            PlayerMovementController.maxPointsPerSecond * 0.5 * frameDelta,
            accuracy: 1e-9
        )
    }

    // MARK: - Stall clamp on the upper end of deltaTime

    /// A backgrounded app, a debugger pause or the `.gameplay`-entry chunk
    /// generation stall can hand `update` a multi-second gap. Uncapped, that
    /// is a single frame worth many tiles of displacement -- which becomes a
    /// tunnelling bug the moment a collision resolver tests the destination
    /// tile. Pin the cap here, where the delta is derived, so the resolver
    /// can be written against the guarantee rather than around it.
    func test_deltaTime_isClampedAtMaxFrameDelta_soAStallCannotTunnel() {
        let controller = PlayerMovementController()
        let east = CGVector(dx: 1, dy: 0)
        controller.update(stickState: StickState(direction: east, magnitude: 1, isBeyondDeadZone: true), currentTime: 0)

        // A 12-second stall -- far beyond any real frame.
        controller.update(stickState: StickState(direction: east, magnitude: 1, isBeyondDeadZone: true), currentTime: 12)

        let onScreen = IsometricProjection.tileToScreen(
            TilePoint(x: Double(controller.frameDisplacement.dx), y: Double(controller.frameDisplacement.dy))
        )
        let screenDistance = hypot(Double(onScreen.x), Double(onScreen.y))

        XCTAssertEqual(
            screenDistance,
            PlayerMovementController.maxPointsPerSecond * PlayerMovementController.maxFrameDelta,
            accuracy: 1e-9,
            "a multi-second stall must be capped to one maxFrameDelta of travel"
        )
        XCTAssertEqual(
            controller.lastFrameTimestamp, 12,
            "clamping the delta must not desynchronise the stored timestamp from the render clock"
        )
    }

    /// The clamp must not disturb ordinary frames: a normal 60fps step is
    /// well inside the budget and must be passed through untouched.
    func test_deltaTime_isNotClampedForAnOrdinaryFrame() {
        let controller = PlayerMovementController()
        let east = CGVector(dx: 1, dy: 0)
        controller.update(stickState: StickState(direction: east, magnitude: 1, isBeyondDeadZone: true), currentTime: 0)
        controller.update(
            stickState: StickState(direction: east, magnitude: 1, isBeyondDeadZone: true),
            currentTime: frameDelta
        )

        let onScreen = IsometricProjection.tileToScreen(
            TilePoint(x: Double(controller.frameDisplacement.dx), y: Double(controller.frameDisplacement.dy))
        )
        let screenDistance = hypot(Double(onScreen.x), Double(onScreen.y))

        XCTAssertEqual(
            screenDistance,
            PlayerMovementController.maxPointsPerSecond * frameDelta,
            accuracy: 1e-9
        )
    }

    /// A clock that goes backwards (the lower end `max(0, ...)` already
    /// guarded) must still produce no movement, not negative displacement.
    func test_deltaTime_isFlooredAtZero_forANonMonotonicClock() {
        let controller = PlayerMovementController()
        let east = CGVector(dx: 1, dy: 0)
        controller.update(stickState: StickState(direction: east, magnitude: 1, isBeyondDeadZone: true), currentTime: 10)
        controller.update(stickState: StickState(direction: east, magnitude: 1, isBeyondDeadZone: true), currentTime: 4)

        XCTAssertEqual(controller.frameDisplacement, .zero)
    }

    func test_frameDisplacement_isZero_belowTheDeadZone() {
        let controller = PlayerMovementController()
        controller.update(stickState: .resting, currentTime: 0)
        controller.update(
            stickState: StickState(direction: CGVector(dx: 1, dy: 0), magnitude: 0.05, isBeyondDeadZone: false),
            currentTime: 1
        )

        XCTAssertEqual(controller.frameDisplacement, .zero)
    }

    func test_frameDisplacement_isZero_whenStickIsAtRest() {
        let controller = PlayerMovementController()
        controller.update(
            stickState: StickState(direction: CGVector(dx: 1, dy: 0), magnitude: 1, isBeyondDeadZone: true),
            currentTime: 0
        )
        controller.update(stickState: .resting, currentTime: 1)

        XCTAssertEqual(controller.frameDisplacement, .zero)
    }
}

private extension CGVector {
    var normalized: CGVector {
        let length = hypot(dx, dy)
        guard length > 0 else { return .zero }
        return CGVector(dx: dx / length, dy: dy / length)
    }
}
