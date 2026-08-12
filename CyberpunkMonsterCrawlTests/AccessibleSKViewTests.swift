import XCTest
import SpriteKit
import UIKit
@testable import CyberpunkMonsterCrawl

/// The regression guard for the failure the runtime probe caught: "tapped
/// PLAY, screen stayed on the menu".
///
/// That was never a state-machine bug - `GameStateMachine`,
/// `MenuScreenNode.onPlay`, `GameViewController.makeGameScene` and
/// `GameScene.startGroundPlane()` were all correctly wired, and
/// `GameViewControllerCompositionTests` proved it by calling
/// `dispatchTouch(atScenePoint:)` directly. It was a touch-*targeting* bug:
/// the probe (like XCUITest, like VoiceOver) taps an accessibility *element*,
/// resolving the point to hit from that element's `accessibilityFrame`, and
/// nothing computed a correct one for a node living under `GameScene`'s
/// camera transform. So the synthesized touch missed the button, and every
/// unit test stayed green over an app whose PLAY button could not be pressed
/// by the only driver that was actually pressing it.
///
/// The tests below therefore assert the one fact the old suite could not see:
/// **the frame an element-driven tap aims at and the scene point
/// `routeTouch(at:)` hit-tests are the same place.** If those two paths ever
/// drift apart again, this file goes red instead of the demo.
final class AccessibleSKViewTests: XCTestCase {

    private let sceneSize = CGSize(width: 400, height: 800)

    /// The real composed scene (menu mounted, all four screens registered),
    /// so these tests measure what ships rather than a hand-built stand-in.
    private func makeMenuScene() -> GameScene {
        GameViewController().makeGameScene(size: sceneSize)
    }

    /// A presented `AccessibleSKView` with no window - enough for every
    /// conversion the class performs (scene size, view bounds, scale mode and
    /// camera are all it needs), and paused so no render loop can mutate the
    /// scene mid-assertion.
    private func makePresentedView(_ scene: GameScene) -> AccessibleSKView {
        let view = AccessibleSKView(frame: CGRect(origin: .zero, size: sceneSize))
        view.presentScene(scene)
        view.isPaused = true
        return view
    }

    // MARK: - The uiLayer walk

    func test_accessibleUINodes_findsTheMenusButtonsAndItsContainerMarker() throws {
        let scene = makeMenuScene()
        let menu = try XCTUnwrap(scene.activeScreen as? MenuScreenNode)

        let nodes = scene.accessibleUINodes()

        XCTAssertTrue(
            nodes.contains { $0 === menu.playButton },
            "the walk must find the PLAY button - it is the node an element-driven tap has to reach"
        )
        XCTAssertTrue(nodes.contains { $0 === menu.highScoresButton })

        let identifiers = Set(nodes.compactMap(\.accessibilityIdentifier))
        XCTAssertEqual(
            identifiers,
            ["menu.playButton", "menu.highScoresButton", "menu.container"],
            "every accessible node under uiLayer must be published, and nothing else"
        )
    }

    func test_accessibleUINodes_skipsNonAccessibleDecoration() {
        let scene = makeMenuScene()

        let decoration = SKSpriteNode(color: .white, size: CGSize(width: 10, height: 10))
        scene.uiLayer.addChild(decoration)

        XCTAssertFalse(
            scene.accessibleUINodes().contains { $0 === decoration },
            "a node that never opted into UIAccessibility must not be published as an element"
        )
    }

    func test_accessibleUINodes_followsTheActiveScreen_soAFrameCannotGoStale() {
        let scene = makeMenuScene()
        XCTAssertTrue(scene.stateMachine.transition(to: .highScores))

        let identifiers = Set(scene.accessibleUINodes().compactMap(\.accessibilityIdentifier))

        XCTAssertEqual(identifiers, ["highScores.backToMenuButton"])
        XCTAssertFalse(
            identifiers.contains("menu.playButton"),
            "a swapped-out screen must not leave its elements behind"
        )
    }

    // MARK: - The coordinate-agreement guard (the actual regression test)

    /// The centre of the frame an element-driven tap aims at must be a scene
    /// point that `routeTouch(at:)` resolves to the PLAY button - and, when
    /// dispatched, must actually start a run.
    func test_playButtonAccessibilityFrame_centre_isTheScenePointThatStartsARun() throws {
        let scene = makeMenuScene()
        let menu = try XCTUnwrap(scene.activeScreen as? MenuScreenNode)

        let frame = try XCTUnwrap(scene.accessibilityFrameInScene(for: menu.playButton))
        XCTAssertFalse(frame.isEmpty, "an empty frame is unhittable - the exact bug this guards")

        let centre = CGPoint(x: frame.midX, y: frame.midY)

        let hit = try XCTUnwrap(
            scene.routeTouch(at: centre),
            "the accessibility frame's centre must land on a node the scene hit-tests"
        )
        XCTAssertTrue(
            scene.touchResponder(for: hit) === menu.playButton,
            "the accessibility frame and the touch dispatcher must resolve to the same button"
        )

        scene.dispatchTouch(atScenePoint: centre)

        XCTAssertEqual(
            scene.stateMachine.currentState,
            .gameplay,
            "tapping where the published accessibility frame points must start a run"
        )
    }

    func test_highScoresButtonAccessibilityFrame_centre_resolvesToThatButton() throws {
        let scene = makeMenuScene()
        let menu = try XCTUnwrap(scene.activeScreen as? MenuScreenNode)

        let frame = try XCTUnwrap(scene.accessibilityFrameInScene(for: menu.highScoresButton))
        XCTAssertFalse(frame.isEmpty)

        let centre = CGPoint(x: frame.midX, y: frame.midY)
        let hit = try XCTUnwrap(scene.routeTouch(at: centre))

        XCTAssertTrue(scene.touchResponder(for: hit) === menu.highScoresButton)
    }

    /// Cross-checks the frame against the *other* scene point the suite
    /// already trusts: `GameViewControllerCompositionTests` taps
    /// `menu.playButton.position`, so the frame's centre must be that same
    /// point converted into scene space. Two independently derived numbers
    /// agreeing is what makes this a guard rather than a tautology.
    func test_accessibilityFrameCentre_matchesTheButtonsOwnScenePosition() throws {
        let scene = makeMenuScene()
        let menu = try XCTUnwrap(scene.activeScreen as? MenuScreenNode)
        let button = menu.playButton

        let frame = try XCTUnwrap(scene.accessibilityFrameInScene(for: button))
        let buttonParent = try XCTUnwrap(button.parent)
        let expected = scene.convert(button.position, from: buttonParent)

        XCTAssertEqual(frame.midX, expected.x, accuracy: 1e-3)
        XCTAssertEqual(frame.midY, expected.y, accuracy: 1e-3)

        let accumulated = button.calculateAccumulatedFrame()
        XCTAssertEqual(frame.width, accumulated.width, accuracy: 1e-3)
        XCTAssertEqual(frame.height, accumulated.height, accuracy: 1e-3)
    }

    func test_accessibilityFrameInScene_isNilForAnUnparentedNode() {
        let scene = makeMenuScene()

        XCTAssertNil(scene.accessibilityFrameInScene(for: SKNode()))
    }

    // MARK: - What the view actually publishes

    func test_publishedElements_carryTheIdentifiersLabelsAndTraitsADriverMatchesOn() throws {
        let scene = makeMenuScene()
        let view = makePresentedView(scene)

        let elements = try XCTUnwrap(
            view.publishedAccessibilityElements(),
            "the hosting view must publish the menu's elements itself, not leave it to SpriteKit"
        )

        let play = try XCTUnwrap(elements.first { $0.accessibilityIdentifier == "menu.playButton" })
        XCTAssertEqual(play.accessibilityLabel, "PLAY", "the probe and XCUITest both match on the label too")
        // Bit-tested rather than `contains(_:)` so the assertion depends only
        // on `UIAccessibilityTraits`' raw value, which is the one thing the
        // trait type is guaranteed to expose.
        XCTAssertNotEqual(
            play.accessibilityTraits.rawValue & UIAccessibilityTraits.button.rawValue,
            0,
            "the element must carry .button, or a driver will not treat it as tappable"
        )
        XCTAssertFalse(play.accessibilityFrame.isEmpty, "a zero frame is exactly what made PLAY untappable")

        let highScores = try XCTUnwrap(
            elements.first { $0.accessibilityIdentifier == "menu.highScoresButton" }
        )
        XCTAssertEqual(highScores.accessibilityLabel, "HIGH SCORES")

        let container = try XCTUnwrap(elements.first { $0.accessibilityIdentifier == "menu.container" })
        XCTAssertEqual(container.accessibilityLabel, "Menu")

        XCTAssertEqual(view.accessibilityElementCount(), elements.count)
    }

    /// The published frame must be the button's real size, not a guess: the
    /// scene is presented 1:1 (`.resizeFill`, scene size == view size), so the
    /// element's frame must measure the same as the node's accumulated frame.
    func test_publishedElementFrame_measuresTheButton() throws {
        let scene = makeMenuScene()
        let view = makePresentedView(scene)
        let menu = try XCTUnwrap(scene.activeScreen as? MenuScreenNode)

        let elements = try XCTUnwrap(view.publishedAccessibilityElements())
        let play = try XCTUnwrap(elements.first { $0.accessibilityIdentifier == "menu.playButton" })

        let accumulated = menu.playButton.calculateAccumulatedFrame()
        XCTAssertEqual(play.accessibilityFrame.width, accumulated.width, accuracy: 1e-3)
        XCTAssertEqual(play.accessibilityFrame.height, accumulated.height, accuracy: 1e-3)
    }

    /// The end-to-end shape of the fix: take the frame a driver would aim at,
    /// convert its centre back through the view into scene space, dispatch
    /// there, and land in `.gameplay`.
    ///
    /// The view has no window in a unit test, so window space and view space
    /// coincide here; on device the app's single full-bleed window makes them
    /// coincide too, which is why `AccessibleSKView` uses
    /// `convert(_:to: nil)`. Round-tripping through the view is therefore the
    /// honest inverse of what the class published.
    func test_publishedPlayElement_pointsAtASceneLocationThatStartsARun() throws {
        let scene = makeMenuScene()
        let view = makePresentedView(scene)
        let menu = try XCTUnwrap(scene.activeScreen as? MenuScreenNode)

        let elements = try XCTUnwrap(view.publishedAccessibilityElements())
        let play = try XCTUnwrap(elements.first { $0.accessibilityIdentifier == "menu.playButton" })
        let centreInWindow = CGPoint(x: play.accessibilityFrame.midX, y: play.accessibilityFrame.midY)

        let scenePoint = view.convert(centreInWindow, to: scene)

        let hit = try XCTUnwrap(
            scene.routeTouch(at: scenePoint),
            "the published frame must point at the button, not into empty space"
        )
        XCTAssertTrue(scene.touchResponder(for: hit) === menu.playButton)

        scene.dispatchTouch(atScenePoint: scenePoint)

        XCTAssertEqual(scene.stateMachine.currentState, .gameplay)
    }

    /// `AccessibleSKView` recomputes its elements on every query, so a screen
    /// swap can never leave a stale frame pointing at a button that is no
    /// longer mounted (a stale frame is the same defect wearing a different
    /// hat).
    func test_publishedElements_areRebuiltAfterAScreenSwap() throws {
        let scene = makeMenuScene()
        let view = makePresentedView(scene)

        let before = try XCTUnwrap(view.publishedAccessibilityElements())
        let beforeIdentifiers = Set(before.compactMap(\.accessibilityIdentifier))
        XCTAssertTrue(beforeIdentifiers.contains("menu.playButton"))

        XCTAssertTrue(scene.stateMachine.transition(to: .highScores))

        let after = try XCTUnwrap(view.publishedAccessibilityElements())
        let afterIdentifiers = Set(after.compactMap(\.accessibilityIdentifier))
        XCTAssertEqual(afterIdentifiers, ["highScores.backToMenuButton"])
    }

    /// `AccessibleSKView`'s scene-to-view step is only unambiguous because
    /// `GameScene` keeps the camera on the scene centre once presented. Pin
    /// it: if the camera ever stopped being centred, camera-locked UI frames
    /// and the view's own conversion could disagree again.
    func test_presentedScene_keepsTheCameraOnTheSceneCentre() {
        let scene = makeMenuScene()
        let view = makePresentedView(scene)

        XCTAssertNotNil(view.scene, "the scene must really be presented, or this assertion is vacuous")
        XCTAssertEqual(scene.cameraNode.position.x, scene.size.width / 2, accuracy: 1e-3)
        XCTAssertEqual(scene.cameraNode.position.y, scene.size.height / 2, accuracy: 1e-3)
    }

    func test_windowFrame_flipsTheYAxis_andPreservesSize() {
        let scene = makeMenuScene()
        let view = makePresentedView(scene)

        // The scene's origin is its bottom-left (y up); UIKit's is its
        // top-left (y down), so a rect hugging the scene's *bottom* edge must
        // come back with a *large* y - the flip `windowFrame(forSceneRect:in:)`
        // is responsible for.
        let bottomLeft = CGRect(x: 0, y: 0, width: 40, height: 20)
        let converted = view.windowFrame(forSceneRect: bottomLeft, in: scene)

        XCTAssertEqual(converted.width, bottomLeft.width, accuracy: 1e-3)
        XCTAssertEqual(converted.height, bottomLeft.height, accuracy: 1e-3)
        XCTAssertGreaterThan(
            converted.midY,
            scene.size.height / 2,
            "the scene's bottom edge must map to the lower half of a y-down coordinate space"
        )
    }
}
