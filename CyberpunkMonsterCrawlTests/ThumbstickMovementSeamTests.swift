import CoreGraphics
import SpriteKit
import UIKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-7` PR 1: the **seam** between the story's two halves.
///
/// `FloatingThumbstickNodeTests` covers the producer in isolation and
/// `PlayerMovementControllerTests` covers the consumer in isolation, driven
/// entirely by hand-built `StickState` values. Neither can catch the two
/// halves *disagreeing*: if the node reported a y-down direction, or a raw
/// (un-normalized) offset instead of a unit vector, or flipped the
/// dead-zone comparison, both suites would stay green while a real drag
/// moved the player the wrong way or not at all. This file closes that gap
/// by driving a real, laid-out node through `beginTouch`/`updateTouch`/
/// `endTouch` and piping its own `stickState` straight into a real
/// `PlayerMovementController` -- no synthetic `StickState` anywhere.
///
/// The wiring into `GameScene` (mounting the node in `uiLayer`, routing
/// `touchesMoved`/`touchesEnded`, deleting `PlayerScaffoldingDriver` and the
/// debug camera pan) is still a later PR of this story; this file is the
/// coverage that stops the producer/consumer conventions from silently
/// drifting apart in the meantime.
final class ThumbstickMovementSeamTests: XCTestCase {

    private let sceneSize = CGSize(width: 390, height: 844)
    private let insets = UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0)

    /// Node-backed positions round through SpriteKit's own storage, so this
    /// file uses the looser accuracy `FloatingThumbstickNodeTests` uses
    /// rather than `PlayerMovementControllerTests`' exact `1e-9`.
    private let accuracy: CGFloat = 1e-6

    private let frameDelta: TimeInterval = 1.0 / 60.0

    private func makeStick() -> FloatingThumbstickNode {
        let stick = FloatingThumbstickNode()
        stick.layout(for: sceneSize, safeAreaInsets: insets)
        stick.isRunActive = true
        return stick
    }

    /// Runs one "frame" of the real pipeline: the node's current reading
    /// fed into the controller at `currentTime`.
    private func advance(
        _ controller: PlayerMovementController,
        with stick: FloatingThumbstickNode,
        to currentTime: TimeInterval
    ) {
        controller.update(stickState: stick.stickState, currentTime: currentTime)
    }

    /// The controller's tile-space output projected back to screen space,
    /// which is the only space in which the producer and consumer can be
    /// meaningfully compared: the node speaks screen space, the controller
    /// answers in tile space.
    private func onScreenDisplacement(of controller: PlayerMovementController) -> CGPoint {
        IsometricProjection.tileToScreen(
            TilePoint(x: Double(controller.frameDisplacement.dx), y: Double(controller.frameDisplacement.dy))
        )
    }

    // MARK: - A real drag moves the player the way the drag points

    /// The headline seam assertion: drag the real node up the screen and the
    /// player must actually move up the screen. A y-sign mismatch between
    /// the node's reported direction and the controller's projection input
    /// would send the player *down* here while both isolated suites stayed
    /// green.
    func test_draggingUp_movesThePlayerUpTheScreen_andFacesNorth() {
        let stick = makeStick()
        let controller = PlayerMovementController()
        let origin = stick.restPosition

        XCTAssertTrue(stick.beginTouch(at: origin))
        stick.updateTouch(at: CGPoint(x: origin.x, y: origin.y + FloatingThumbstickNode.maxRadius))

        advance(controller, with: stick, to: 0)
        advance(controller, with: stick, to: frameDelta)

        let onScreen = onScreenDisplacement(of: controller)

        XCTAssertEqual(onScreen.x, 0, accuracy: accuracy, "a straight-up drag must not drift sideways on screen")
        XCTAssertGreaterThan(onScreen.y, 0, "a straight-up drag must move the player up the screen")
        XCTAssertEqual(controller.facingVector.dx, 0, accuracy: accuracy)
        XCTAssertEqual(controller.facingVector.dy, 1, accuracy: accuracy)
        XCTAssertTrue(controller.isMoving)
    }

    func test_draggingRight_movesThePlayerRightOnScreen_andFacesEast() {
        let stick = makeStick()
        let controller = PlayerMovementController()
        let origin = stick.restPosition

        XCTAssertTrue(stick.beginTouch(at: origin))
        stick.updateTouch(at: CGPoint(x: origin.x + FloatingThumbstickNode.maxRadius, y: origin.y))

        advance(controller, with: stick, to: 0)
        advance(controller, with: stick, to: frameDelta)

        let onScreen = onScreenDisplacement(of: controller)

        XCTAssertGreaterThan(onScreen.x, 0, "a rightward drag must move the player right on screen")
        XCTAssertEqual(onScreen.y, 0, accuracy: accuracy, "a purely horizontal drag must not drift vertically")
        XCTAssertEqual(controller.facingVector.dx, 1, accuracy: accuracy)
        XCTAssertEqual(controller.facingVector.dy, 0, accuracy: accuracy)
    }

    // MARK: - The heading-independent speed holds through the real node too

    /// The screen-space speed fix asserted end-to-end rather than against a
    /// hand-built `StickState`: four real full-deflection drags, four equal
    /// on-screen distances. Under the old tile-space normalization the
    /// sideways drags came out exactly 2x the vertical ones.
    func test_fullDeflection_coversTheSameOnScreenDistance_inEveryDirection() {
        let radius = FloatingThumbstickNode.maxRadius
        let drags: [(name: String, offset: CGVector)] = [
            ("up", CGVector(dx: 0, dy: radius)),
            ("down", CGVector(dx: 0, dy: -radius)),
            ("right", CGVector(dx: radius, dy: 0)),
            ("left", CGVector(dx: -radius, dy: 0)),
        ]

        let expected = PlayerMovementController.maxPointsPerSecond * frameDelta

        for drag in drags {
            let stick = makeStick()
            let controller = PlayerMovementController()
            let origin = stick.restPosition

            XCTAssertTrue(stick.beginTouch(at: origin), "\(drag.name)")
            stick.updateTouch(at: CGPoint(x: origin.x + drag.offset.dx, y: origin.y + drag.offset.dy))

            advance(controller, with: stick, to: 0)
            advance(controller, with: stick, to: frameDelta)

            let onScreen = onScreenDisplacement(of: controller)
            let distance = hypot(Double(onScreen.x), Double(onScreen.y))

            XCTAssertEqual(
                distance, expected, accuracy: 1e-6,
                "a full deflection \(drag.name) must cover the same on-screen distance as every other direction"
            )
        }
    }

    // MARK: - Dead-zone semantics agree across the seam

    /// The node decides `isBeyondDeadZone`; the controller defines
    /// `isMoving` as exactly that value. A drag that the node considers
    /// inside its dead zone must therefore produce no movement at all --
    /// not merely a small one.
    func test_aDragInsideTheNodesDeadZone_producesNoMovement() {
        let stick = makeStick()
        let controller = PlayerMovementController()
        let origin = stick.restPosition
        let insideDeadZone = FloatingThumbstickNode.maxRadius * FloatingThumbstickNode.deadZoneFraction - 2

        XCTAssertTrue(stick.beginTouch(at: origin))
        stick.updateTouch(at: CGPoint(x: origin.x + insideDeadZone, y: origin.y))

        advance(controller, with: stick, to: 0)
        advance(controller, with: stick, to: frameDelta)

        XCTAssertFalse(stick.stickState.isBeyondDeadZone, "precondition: the node must consider this drag settled")
        XCTAssertFalse(controller.isMoving)
        XCTAssertEqual(controller.frameDisplacement, .zero)
    }

    func test_aDragJustBeyondTheNodesDeadZone_producesMovement() {
        let stick = makeStick()
        let controller = PlayerMovementController()
        let origin = stick.restPosition
        let beyondDeadZone = FloatingThumbstickNode.maxRadius * FloatingThumbstickNode.deadZoneFraction + 2

        XCTAssertTrue(stick.beginTouch(at: origin))
        stick.updateTouch(at: CGPoint(x: origin.x + beyondDeadZone, y: origin.y))

        advance(controller, with: stick, to: 0)
        advance(controller, with: stick, to: frameDelta)

        XCTAssertTrue(stick.stickState.isBeyondDeadZone, "precondition: the node must consider this drag deliberate")
        XCTAssertTrue(controller.isMoving)
        XCTAssertNotEqual(controller.frameDisplacement, .zero)
    }

    // MARK: - Magnitude carries across the seam

    /// A half-radius drag must move the player half as far as a full one --
    /// pinning that the node's `0...1` magnitude and the controller's speed
    /// scaling agree about what `1` means.
    func test_halfDeflection_movesHalfAsFarAsFullDeflection() {
        func screenDistance(forDragOffset offset: CGFloat) -> Double {
            let stick = makeStick()
            let controller = PlayerMovementController()
            let origin = stick.restPosition

            XCTAssertTrue(stick.beginTouch(at: origin))
            stick.updateTouch(at: CGPoint(x: origin.x + offset, y: origin.y))

            advance(controller, with: stick, to: 0)
            advance(controller, with: stick, to: frameDelta)

            let onScreen = onScreenDisplacement(of: controller)
            return hypot(Double(onScreen.x), Double(onScreen.y))
        }

        let full = screenDistance(forDragOffset: FloatingThumbstickNode.maxRadius)
        let half = screenDistance(forDragOffset: FloatingThumbstickNode.maxRadius / 2)

        XCTAssertEqual(half, full / 2, accuracy: 1e-6)
    }

    // MARK: - Release and run-end stop the player

    /// Releasing the stick returns it to `.resting`, which the controller
    /// must read as "stop moving" while *keeping* the last facing -- the
    /// idle-freezes-facing behaviour, asserted through the real node rather
    /// than a hand-built resting state.
    func test_releasingTheStick_stopsMovement_butKeepsTheLastFacing() {
        let stick = makeStick()
        let controller = PlayerMovementController()
        let origin = stick.restPosition

        XCTAssertTrue(stick.beginTouch(at: origin))
        stick.updateTouch(at: CGPoint(x: origin.x, y: origin.y + FloatingThumbstickNode.maxRadius))
        advance(controller, with: stick, to: 0)
        advance(controller, with: stick, to: frameDelta)

        stick.endTouch()
        advance(controller, with: stick, to: frameDelta * 2)

        XCTAssertFalse(controller.isMoving)
        XCTAssertEqual(controller.frameDisplacement, .zero)
        XCTAssertEqual(controller.facingVector.dy, 1, accuracy: accuracy, "facing must freeze at its last value")
    }

    /// A run ending mid-drag cancels the node's tracking, which the
    /// controller must immediately see as a stop -- no residual drift after
    /// the player is dead.
    func test_runEndingMidDrag_stopsThePlayerOnTheNextFrame() {
        let stick = makeStick()
        let controller = PlayerMovementController()
        let origin = stick.restPosition

        XCTAssertTrue(stick.beginTouch(at: origin))
        stick.updateTouch(at: CGPoint(x: origin.x + FloatingThumbstickNode.maxRadius, y: origin.y))
        advance(controller, with: stick, to: 0)
        advance(controller, with: stick, to: frameDelta)
        XCTAssertTrue(controller.isMoving, "precondition: the player is moving before the run ends")

        stick.isRunActive = false
        advance(controller, with: stick, to: frameDelta * 2)

        XCTAssertFalse(controller.isMoving)
        XCTAssertEqual(controller.frameDisplacement, .zero)
    }
}
