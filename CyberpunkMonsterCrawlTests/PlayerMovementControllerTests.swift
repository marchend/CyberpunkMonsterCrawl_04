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

    private let accuracy: CGFloat = 1e-9

    // MARK: - First frame: nil lastFrameTimestamp forces deltaTime == 0

    func test_firstUpdate_hasNilLastFrameTimestamp_andProducesZeroVelocity() {
        let controller = PlayerMovementController()
        XCTAssertNil(controller.lastFrameTimestamp)

        let deflected = StickState(direction: CGVector(dx: 0, dy: 1), magnitude: 1, isBeyondDeadZone: true)
        controller.update(stickState: deflected, currentTime: 100)

        XCTAssertEqual(controller.velocity, .zero, "deltaTime == 0 on the first frame must produce zero movement.")
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

    // MARK: - Velocity: direction/magnitude conversion through the isometric
    // projection, for all 8 headings

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

    func test_velocity_convertsEveryHeadingThroughTheIsometricProjection() {
        for direction in Self.headings {
            let controller = PlayerMovementController()
            // First call only establishes `lastFrameTimestamp`; its own
            // deltaTime is forced to 0, so it contributes no velocity.
            controller.update(
                stickState: StickState(direction: direction, magnitude: 1, isBeyondDeadZone: true),
                currentTime: 0
            )
            controller.update(
                stickState: StickState(direction: direction, magnitude: 1, isBeyondDeadZone: true),
                currentTime: 1
            )

            let tileDirection = IsometricProjection.screenToTile(CGPoint(x: direction.dx, y: direction.dy))
            let tileLength = hypot(tileDirection.x, tileDirection.y)
            let expectedDisplacement = PlayerMovementController.maxTilesPerSecond // magnitude 1, deltaTime 1
            let expectedDx = CGFloat(tileDirection.x / tileLength * expectedDisplacement)
            let expectedDy = CGFloat(tileDirection.y / tileLength * expectedDisplacement)

            XCTAssertEqual(controller.velocity.dx, expectedDx, accuracy: accuracy, "heading \(direction)")
            XCTAssertEqual(controller.velocity.dy, expectedDy, accuracy: accuracy, "heading \(direction)")
        }
    }

    func test_velocity_scalesWithMagnitude() {
        let controller = PlayerMovementController()
        let east = CGVector(dx: 1, dy: 0)
        controller.update(stickState: StickState(direction: east, magnitude: 0.5, isBeyondDeadZone: true), currentTime: 0)
        controller.update(stickState: StickState(direction: east, magnitude: 0.5, isBeyondDeadZone: true), currentTime: 1)

        let tileDirection = IsometricProjection.screenToTile(CGPoint(x: east.dx, y: east.dy))
        let tileLength = hypot(tileDirection.x, tileDirection.y)
        let expectedDisplacement = PlayerMovementController.maxTilesPerSecond * 0.5
        let expectedDx = CGFloat(tileDirection.x / tileLength * expectedDisplacement)
        let expectedDy = CGFloat(tileDirection.y / tileLength * expectedDisplacement)

        XCTAssertEqual(controller.velocity.dx, expectedDx, accuracy: accuracy)
        XCTAssertEqual(controller.velocity.dy, expectedDy, accuracy: accuracy)
    }

    func test_velocity_isZero_belowTheDeadZone() {
        let controller = PlayerMovementController()
        controller.update(stickState: .resting, currentTime: 0)
        controller.update(
            stickState: StickState(direction: CGVector(dx: 1, dy: 0), magnitude: 0.05, isBeyondDeadZone: false),
            currentTime: 1
        )

        XCTAssertEqual(controller.velocity, .zero)
    }

    func test_velocity_isZero_whenStickIsAtRest() {
        let controller = PlayerMovementController()
        controller.update(
            stickState: StickState(direction: CGVector(dx: 1, dy: 0), magnitude: 1, isBeyondDeadZone: true),
            currentTime: 0
        )
        controller.update(stickState: .resting, currentTime: 1)

        XCTAssertEqual(controller.velocity, .zero)
    }
}

private extension CGVector {
    var normalized: CGVector {
        let length = hypot(dx, dy)
        guard length > 0 else { return .zero }
        return CGVector(dx: dx / length, dy: dy / length)
    }
}
