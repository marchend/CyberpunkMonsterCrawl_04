import CoreGraphics
import SpriteKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-12` PR 1: `HUDPulseButton`'s custom hit-test frame through
/// the camera-pinned coordinate chain, and its cooldown press-suppression.
///
/// Cooldown *rendering* (the overlay wedge/alpha) is covered by
/// `HUDElementUpdateTests`; this file covers the two things this ticket's
/// acceptance criteria specifically call out: coordinate agreement between
/// `hitTestFrame(in:)` and real touch dispatch, and a press during cooldown
/// producing feedback without ever invoking `onPress`.
final class PulseButtonHitTestTests: XCTestCase {

    /// Mirrors `GameScene.commonInit()`'s own camera-pinned `uiLayer`
    /// convention: a camera added to the scene, a container parented to
    /// *that* camera (never to the scene directly), and this HUD button
    /// mounted inside the container at `buttonLocalPosition` -- exactly the
    /// tree shape `GameScene.routeTouch(at:)` hit-tests through once this
    /// node is actually wired in. `cameraPosition` simulates world-camera
    /// scrolling: `GameScene.advanceMovementAndCamera(currentTime:)` moves
    /// `cameraNode.position` every frame while UI content parented under it
    /// stays fixed in camera-local space.
    private func makeCameraPinnedScene(
        cameraPosition: CGPoint,
        buttonLocalPosition: CGPoint
    ) -> (scene: SKScene, button: HUDPulseButton) {
        let scene = SKScene(size: CGSize(width: 390, height: 844))
        let camera = SKCameraNode()
        camera.position = cameraPosition
        scene.addChild(camera)
        scene.camera = camera

        let uiLayer = SKNode()
        camera.addChild(uiLayer)

        let button = HUDPulseButton(onPress: {})
        button.position = buttonLocalPosition
        uiLayer.addChild(button)

        return (scene, button)
    }

    // MARK: - Coordinate agreement through the camera transform

    /// The centre of the computed hit-test frame, fed back through
    /// `scene.atPoint(_:)` (the same primitive `GameScene.routeTouch(at:)`
    /// hit-tests a real touch with), must resolve to this button -- proving
    /// the frame `hitTestFrame(in:)` reports agrees with where a real touch
    /// would actually land.
    func test_hitTestFrame_agreesWithRealTouchDispatch_withTheCameraAtTheOrigin() {
        let (scene, button) = makeCameraPinnedScene(
            cameraPosition: .zero,
            buttonLocalPosition: CGPoint(x: 100, y: -300)
        )

        let frame = button.hitTestFrame(in: scene)
        let hit = scene.atPoint(CGPoint(x: frame.midX, y: frame.midY))

        XCTAssertTrue(hit === button || hit.inParentHierarchy(button))
    }

    /// The same agreement must hold once the camera has panned away from
    /// the origin -- otherwise the frame would only be correct in the
    /// (untypical) case where the world camera never moves.
    func test_hitTestFrame_agreesWithRealTouchDispatch_afterTheCameraPans() {
        let (scene, button) = makeCameraPinnedScene(
            cameraPosition: CGPoint(x: 480, y: -220),
            buttonLocalPosition: CGPoint(x: 100, y: -300)
        )

        let frame = button.hitTestFrame(in: scene)
        let hit = scene.atPoint(CGPoint(x: frame.midX, y: frame.midY))

        XCTAssertTrue(hit === button || hit.inParentHierarchy(button))
    }

    /// A point outside the reported frame must *not* resolve to this
    /// button -- otherwise the "agreement" above would hold trivially for
    /// any frame, correct or not.
    func test_hitTestFrame_aPointOutsideTheFrame_doesNotResolveToTheButton() {
        let (scene, button) = makeCameraPinnedScene(
            cameraPosition: CGPoint(x: 480, y: -220),
            buttonLocalPosition: CGPoint(x: 100, y: -300)
        )

        let frame = button.hitTestFrame(in: scene)
        let farAway = CGPoint(x: frame.midX + 10_000, y: frame.midY + 10_000)
        let hit = scene.atPoint(farAway)

        XCTAssertFalse(hit === button || hit.inParentHierarchy(button))
    }

    /// The frame must actually track the camera transform rather than
    /// staying fixed in scene space -- the regression this whole file
    /// exists to catch (the `AccessibleSKView` bug this codebase already
    /// hit once for buttons under a camera transform, see that type's own
    /// doc comment).
    func test_hitTestFrame_movesWithTheCamera_ratherThanStayingFixedInSceneSpace() {
        let (originScene, originButton) = makeCameraPinnedScene(
            cameraPosition: .zero,
            buttonLocalPosition: CGPoint(x: 100, y: -300)
        )
        let frameAtOrigin = originButton.hitTestFrame(in: originScene)

        let (pannedScene, pannedButton) = makeCameraPinnedScene(
            cameraPosition: CGPoint(x: 480, y: -220),
            buttonLocalPosition: CGPoint(x: 100, y: -300)
        )
        let framePanned = pannedButton.hitTestFrame(in: pannedScene)

        XCTAssertNotEqual(frameAtOrigin.origin, framePanned.origin)
    }

    // MARK: - Cooldown press suppression

    func test_handleTouch_whileReady_invokesOnPress() {
        var pressCount = 0
        let button = HUDPulseButton(onPress: { pressCount += 1 })

        button.handleTouch()

        XCTAssertEqual(pressCount, 1)
        XCTAssertEqual(button.deniedPressCount, 0)
    }

    /// The acceptance criterion this test exists to pin: a press during
    /// cooldown must produce visible feedback (the denied-press action) but
    /// must never invoke `onPress` -- the ability's own emit path.
    func test_handleTouch_whileOnCooldown_producesFeedbackButNeverInvokesOnPress() {
        var pressCount = 0
        let button = HUDPulseButton(onPress: { pressCount += 1 })
        button.update(cooldownFraction: 0.5, isReady: false)

        button.handleTouch()

        XCTAssertEqual(pressCount, 0, "onPress must never fire while on cooldown")
        XCTAssertEqual(button.deniedPressCount, 1)
        XCTAssertNotNil(
            button.action(forKey: "hudPulseButton.deniedFeedback"),
            "a denied press must still play visible feedback"
        )
    }

    func test_handleTouch_whileOnCooldown_repeatedPresses_accumulateDeniedCount_neverFiringOnPress() {
        var pressCount = 0
        let button = HUDPulseButton(onPress: { pressCount += 1 })
        button.update(cooldownFraction: 0, isReady: false)

        button.handleTouch()
        button.handleTouch()
        button.handleTouch()

        XCTAssertEqual(pressCount, 0)
        XCTAssertEqual(button.deniedPressCount, 3)
    }

    func test_handleTouch_resumesInvokingOnPress_onceReadyReturns() {
        var pressCount = 0
        let button = HUDPulseButton(onPress: { pressCount += 1 })
        button.update(cooldownFraction: 0, isReady: false)
        button.handleTouch()
        XCTAssertEqual(pressCount, 0)

        button.update(cooldownFraction: 1.0, isReady: true)
        button.handleTouch()

        XCTAssertEqual(pressCount, 1, "a press must fire onPress again once isReady returns")
        XCTAssertEqual(button.deniedPressCount, 1, "the earlier denied press must not be retroactively counted")
    }
}
