import CoreGraphics
import SpriteKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// CYBERPUN-17-7-t3: the *integration* this story exists to deliver -- a
/// stick drag actually moving the player in a live scene.
///
/// Every half of the pipeline already had its own suite before this file
/// existed (`FloatingThumbstickNodeTests`, `PlayerMovementControllerTests`,
/// `CollisionResolverTests`, `CameraControllerTests`,
/// `ThumbstickMovementSeamTests`), and what was missing was precisely that
/// *nothing in a live scene called them*. That is v1's failure mode exactly:
/// green units over a build whose controls did nothing. So these tests drive
/// `GameScene.update(_:)` -- the production per-frame entry point -- and
/// assert on the scene's own state rather than on any component's.
///
/// Headless throughout (no `SKView`), which the scene supports by design:
/// `commonInit()` lays the thumbstick out with the scene's own size so the
/// "layout must have run before a touch is asked about" precondition holds,
/// and `deviceScale` falls back to `1`.
final class ThumbstickSceneWiringTests: XCTestCase {

    private let sceneSize = CGSize(width: 400, height: 800)

    /// A scene already in `.gameplay`: ground plane started, player mounted
    /// at the run's spawn tile, thumbstick shown.
    private func makeGameplayScene() -> GameScene {
        let scene = GameScene(size: sceneSize)
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))
        return scene
    }

    /// Pushes the stick to full deflection towards screen-right, starting
    /// from its own rest position.
    ///
    /// Points are in `uiLayer`'s coordinate space -- the space
    /// `GameScene.touchesBegan(_:with:)` converts a scene point into before
    /// offering it to the stick, and the only space
    /// `FloatingThumbstickNode` accepts (a `UITouch` cannot be constructed
    /// with a location in a unit test, so the touch *routing* itself is
    /// pinned by `TouchDispatchTests`/`TouchRoutingTests`; what is pinned
    /// here is everything downstream of the stick receiving the drag).
    @discardableResult
    private func pushStickRight(_ scene: GameScene) -> Bool {
        let rest = scene.thumbstick.restPosition
        let began = scene.thumbstick.beginTouch(at: rest)
        scene.thumbstick.updateTouch(
            at: CGPoint(x: rest.x + FloatingThumbstickNode.maxRadius, y: rest.y)
        )
        return began
    }

    /// Drives `count` production frames at 60fps from `start`.
    ///
    /// Two is the minimum that can move anything: `PlayerMovementController`
    /// (like `GameScene`'s own `lastFrameTime`) reports a `0` delta on its
    /// very first call rather than inventing one against an arbitrary
    /// process clock, so the first frame only establishes the clock.
    private func advanceFrames(_ scene: GameScene, count: Int = 2, startingAt start: TimeInterval = 1) {
        for frame in 0..<count {
            scene.update(start + TimeInterval(frame) / 60)
        }
    }

    // MARK: - The gate itself: the stick moves the player

    func test_stickDrag_movesThePlayer_alongTheProjectedAxis() throws {
        let scene = makeGameplayScene()
        let spawn = try XCTUnwrap(scene.playerWorldPosition, "entering .gameplay must place the player")

        XCTAssertTrue(pushStickRight(scene), "the stick must accept a touch at its own rest position")
        advanceFrames(scene, count: 3)

        let moved = try XCTUnwrap(scene.playerWorldPosition)
        // Screen-right on a 2:1 isometric projection is tile-space
        // (+x, -y) -- `IsometricProjection.screenToTile` of a purely
        // horizontal screen step. Asserting the *shape* of the step, not
        // just "something changed", is what catches a y-sign flip between
        // the stick and the projection.
        XCTAssertGreaterThan(moved.x, spawn.x, "a rightward push must increase tile x")
        XCTAssertLessThan(moved.y, spawn.y, "a rightward push must decrease tile y")
        XCTAssertEqual(
            moved.x - spawn.x, spawn.y - moved.y, accuracy: 1e-9,
            "a purely horizontal screen push must project to an equal-and-opposite tile-axis step"
        )
    }

    func test_stickAtRest_leavesThePlayerWhereItSpawned() throws {
        let scene = makeGameplayScene()
        let spawn = try XCTUnwrap(scene.playerWorldPosition)

        advanceFrames(scene, count: 5)

        let after = try XCTUnwrap(scene.playerWorldPosition)
        XCTAssertEqual(after.x, spawn.x, accuracy: 1e-12, "an untouched stick must not drift the player")
        XCTAssertEqual(after.y, spawn.y, accuracy: 1e-12)
    }

    func test_releasingTheStick_stopsThePlayer() throws {
        let scene = makeGameplayScene()

        pushStickRight(scene)
        advanceFrames(scene, count: 3)
        let whileMoving = try XCTUnwrap(scene.playerWorldPosition)

        scene.thumbstick.endTouch()
        advanceFrames(scene, count: 5, startingAt: 2)

        let afterRelease = try XCTUnwrap(scene.playerWorldPosition)
        XCTAssertEqual(
            afterRelease.x, whileMoving.x, accuracy: 1e-12,
            "a released stick must stop the player, not coast"
        )
        XCTAssertEqual(afterRelease.y, whileMoving.y, accuracy: 1e-12)
    }

    // MARK: - The two positions cannot drift apart

    /// `playerWorldPosition` is the single source of truth and the mounted
    /// node's screen position is *derived* from it (projected, then snapped
    /// to the device pixel grid). Asserting the derivation each frame is
    /// what stops the two from becoming independent state that disagrees.
    func test_theMountedPlayersScreenPosition_isDerivedFromPlayerWorldPosition() throws {
        let scene = makeGameplayScene()
        let player = try XCTUnwrap(scene.player)

        pushStickRight(scene)

        for frame in 0..<4 {
            scene.update(1 + TimeInterval(frame) / 60)

            let worldPosition = try XCTUnwrap(scene.playerWorldPosition)
            // `deviceScale` is `1` for a headless scene, so the snap is to a
            // whole point.
            let expected = PixelCrispness.snappedPosition(
                for: IsometricProjection.tileToScreen(worldPosition),
                scale: 1
            )
            XCTAssertEqual(player.position.x, expected.x, accuracy: 1e-9, "frame \(frame)")
            XCTAssertEqual(player.position.y, expected.y, accuracy: 1e-9, "frame \(frame)")

            let expectedZ = DepthModel.worldLayerRelativeZ(
                forAbsoluteZ: DepthBanding.playerZPosition(at: worldPosition)
            )
            XCTAssertEqual(player.zPosition, expectedZ, accuracy: 0.01, "frame \(frame)")
        }
    }

    /// The same resolved position drives the camera, so the player stays on
    /// screen centre while the world scrolls under it. `CameraController`
    /// moves `worldLayer` (never `cameraNode`) and snaps the offset, and the
    /// player's own position is snapped too, so the honest tolerance is one
    /// whole point per axis at the headless `@1x` scale.
    func test_theCameraFollowsTheResolvedPosition_keepingThePlayerCentred() throws {
        let scene = makeGameplayScene()
        let player = try XCTUnwrap(scene.player)

        pushStickRight(scene)
        advanceFrames(scene, count: 4)

        let playerInScene = scene.convert(player.position, from: scene.worldLayer)
        XCTAssertEqual(playerInScene.x, scene.size.width / 2, accuracy: 1.01)
        XCTAssertEqual(playerInScene.y, scene.size.height / 2, accuracy: 1.01)
    }

    // MARK: - The stick's lifetime follows the run

    func test_enteringGameplayShowsTheStick_andLeavingARunHidesIt() {
        let scene = makeGameplayScene()

        XCTAssertTrue(scene.thumbstick.isRunActive, "a run must show the stick")
        XCTAssertFalse(scene.thumbstick.isHidden)
        XCTAssertTrue(scene.thumbstick.parent === scene.uiLayer, "the stick is camera-pinned UI")

        XCTAssertTrue(scene.stateMachine.transition(to: .death))

        XCTAssertFalse(scene.thumbstick.isRunActive, "there is nothing to move outside a run")
        XCTAssertTrue(scene.thumbstick.isHidden)
        XCTAssertFalse(
            scene.thumbstick.beginTouch(at: scene.thumbstick.restPosition),
            "no touch may engage the stick once the run is over"
        )
    }

    /// A run ending mid-drag must not leave the player coasting on the last
    /// stick reading once RUN AGAIN starts the next one.
    func test_aRunEndingMidDrag_leavesTheNextRunStationary() throws {
        let scene = makeGameplayScene()

        pushStickRight(scene)
        advanceFrames(scene, count: 3)
        XCTAssertTrue(scene.stateMachine.transition(to: .death))
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))

        let restarted = try XCTUnwrap(scene.playerWorldPosition)
        advanceFrames(scene, count: 4, startingAt: 5)

        let after = try XCTUnwrap(scene.playerWorldPosition)
        XCTAssertEqual(
            after.x, restarted.x, accuracy: 1e-12,
            "the in-flight drag must have been cancelled with the run, not carried into the next one"
        )
        XCTAssertEqual(after.y, restarted.y, accuracy: 1e-12)
    }

    // MARK: - Structural invariants still hold with the stick mounted

    func test_theMountedStick_keepsTheScenesLayerAndDispatchInvariantsIntact() {
        let scene = makeGameplayScene()

        XCTAssertTrue(
            scene.nodesEscapingTheirLayerBand().isEmpty,
            "The mounted thumbstick escaped its layer band: \(scene.layerBandViolationReport())"
        )
        XCTAssertTrue(
            scene.nodesBypassingSceneTouchDispatch().isEmpty,
            "The thumbstick opted into UIKit touch delivery and would bypass the scene's UI-first dispatch."
        )
    }
}
