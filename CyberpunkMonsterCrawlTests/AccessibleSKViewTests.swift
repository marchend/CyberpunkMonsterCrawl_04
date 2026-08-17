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
    ///
    /// `viewSize` defaults to the scene size (the 1:1 case) but can be given
    /// a different value so the scale factor the conversion depends on is
    /// actually exercised - see
    /// `test_halfScaleView_publishedPlayElement_stillPointsAtTheButton`.
    private func makePresentedView(_ scene: GameScene, viewSize: CGSize? = nil) -> AccessibleSKView {
        let view = AccessibleSKView(frame: CGRect(origin: .zero, size: viewSize ?? sceneSize))
        view.presentScene(scene)
        view.isPaused = true
        return view
    }

    /// The published element a driver would resolve for `identifier`.
    private func publishedElement(
        _ identifier: String,
        in view: AccessibleSKView
    ) throws -> UIAccessibilityElement {
        let elements = try XCTUnwrap(view.publishedAccessibilityElements())
        return try XCTUnwrap(
            elements.first { $0.accessibilityIdentifier == identifier },
            "no published element carries the identifier \(identifier)"
        )
    }

    /// Moves the camera somewhere that is emphatically *not* the scene
    /// centre, which is the only configuration in which scene -> view stops
    /// being the identity map.
    private func moveCameraOffCentre(_ scene: GameScene) {
        scene.cameraNode.position = CGPoint(
            x: scene.size.width / 2 + 137,
            y: scene.size.height / 2 - 289
        )
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

    /// `routeTouch(at:)` resolves through `SKNode.atPoint(_:)`, which never
    /// returns a hidden node. Publishing one anyway would hand a driver a
    /// frame to aim at that the scene then refuses to route - the original
    /// defect wearing another hat - so the walk filters on visibility and
    /// the two paths stay in agreement even for a node nothing hides today.
    func test_accessibleUINodes_skipsHiddenAndFullyTransparentNodes() {
        let scene = makeMenuScene()

        let hidden = SKSpriteNode(color: .white, size: CGSize(width: 40, height: 20))
        hidden.isAccessibilityElement = true
        hidden.accessibilityIdentifier = "menu.hiddenButton"
        hidden.isHidden = true
        scene.uiLayer.addChild(hidden)

        let transparent = SKSpriteNode(color: .white, size: CGSize(width: 40, height: 20))
        transparent.isAccessibilityElement = true
        transparent.accessibilityIdentifier = "menu.transparentButton"
        transparent.alpha = 0
        scene.uiLayer.addChild(transparent)

        let identifiers = Set(scene.accessibleUINodes().compactMap(\.accessibilityIdentifier))

        XCTAssertFalse(
            identifiers.contains("menu.hiddenButton"),
            "a hidden node is unreachable by atPoint(_:), so it must not be published as tappable"
        )
        XCTAssertFalse(identifiers.contains("menu.transparentButton"))
        XCTAssertTrue(identifiers.contains("menu.playButton"), "the visible buttons must survive the filter")
    }

    /// Hiding a parent hides everything under it, so the filter has to skip
    /// the whole subtree rather than just the node it is applied to.
    func test_accessibleUINodes_skipsAccessibleChildrenOfAHiddenParent() {
        let scene = makeMenuScene()

        let hiddenContainer = SKNode()
        hiddenContainer.isHidden = true
        let child = SKSpriteNode(color: .white, size: CGSize(width: 40, height: 20))
        child.isAccessibilityElement = true
        child.accessibilityIdentifier = "menu.childOfHiddenContainer"
        hiddenContainer.addChild(child)
        scene.uiLayer.addChild(hiddenContainer)

        let identifiers = Set(scene.accessibleUINodes().compactMap(\.accessibilityIdentifier))

        XCTAssertFalse(identifiers.contains("menu.childOfHiddenContainer"))
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
    /// The view has no window in a unit test, so `screenFrame(forSceneRect:in:)`
    /// stops after the scene -> view step (there is no window through which
    /// to reach screen space, see the guard in `AccessibleSKView`), and the
    /// published frame is in view coordinates. Round-tripping through the
    /// view is therefore the honest inverse of what the class published.
    func test_publishedPlayElement_pointsAtASceneLocationThatStartsARun() throws {
        let scene = makeMenuScene()
        let view = makePresentedView(scene)
        let menu = try XCTUnwrap(scene.activeScreen as? MenuScreenNode)

        let play = try publishedElement("menu.playButton", in: view)
        let centreInView = CGPoint(x: play.accessibilityFrame.midX, y: play.accessibilityFrame.midY)

        let scenePoint = view.convert(centreInView, to: scene)

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

    // MARK: - The hit-test half of the container contract

    /// Publishing a correct frame is only half of what an out-of-process
    /// driver needs. XCUITest's `isHittable` resolves an element's activation
    /// point from that frame, asks the app *which accessibility element is at
    /// this point*, and requires the same element back - so a container that
    /// answers the query but not the hit test leaves PLAY findable and
    /// un-hittable (`CyberpunkMonsterCrawlUITests` failed on exactly that
    /// assertion, one line after finding the element). Hit-testing the centre
    /// of the frame we published must return the element we published.
    func test_accessibilityHitTest_atThePublishedPlayFrameCentre_returnsThatElement() throws {
        let scene = makeMenuScene()
        let view = makePresentedView(scene)

        let play = try publishedElement("menu.playButton", in: view)
        let centre = CGPoint(x: play.accessibilityFrame.midX, y: play.accessibilityFrame.midY)

        let hit = try XCTUnwrap(
            view.accessibilityHitTest(centre, event: nil),
            "the view must answer the hit test itself; SKView's inherited answer knows nothing "
                + "about the elements we publish"
        )

        XCTAssertTrue(
            hit as AnyObject === play,
            "hit-testing the published frame's centre must return that very element - identity is what "
                + "isHittable compares, so an equal-but-different object is still a failure"
        )
    }

    /// `menu.container` is a size-less marker published at a synthesised 1pt
    /// rect, and it sits at the menu's centre - i.e. *inside* the PLAY
    /// button. Answering the marker there would make PLAY unhittable just as
    /// surely as answering nothing, so a real-sized element must win.
    func test_accessibilityHitTest_prefersTheButtonOverTheMarkerSharingThePoint() throws {
        let scene = makeMenuScene()
        let view = makePresentedView(scene)

        let play = try publishedElement("menu.playButton", in: view)
        let marker = try publishedElement("menu.container", in: view)
        XCTAssertTrue(
            play.accessibilityFrame.contains(
                CGPoint(x: marker.accessibilityFrame.midX, y: marker.accessibilityFrame.midY)
            ),
            "this test is only meaningful while the marker really does sit inside the button"
        )

        let hit = try XCTUnwrap(
            view.accessibilityHitTest(
                CGPoint(x: marker.accessibilityFrame.midX, y: marker.accessibilityFrame.midY),
                event: nil
            )
        )

        XCTAssertTrue(hit as AnyObject === play)
        XCTAssertFalse(hit as AnyObject === marker)
    }

    /// The other button, so the hit test is picking an element rather than
    /// always answering the same one.
    func test_accessibilityHitTest_atTheHighScoresFrameCentre_returnsThatElement() throws {
        let scene = makeMenuScene()
        let view = makePresentedView(scene)

        let highScores = try publishedElement("menu.highScoresButton", in: view)
        let centre = CGPoint(
            x: highScores.accessibilityFrame.midX,
            y: highScores.accessibilityFrame.midY
        )

        XCTAssertTrue(view.accessibilityHitTest(centre, event: nil) as AnyObject === highScores)
    }

    /// A point no published element covers must not be attributed to one of
    /// them - a container that claims every point is as wrong as one that
    /// claims none.
    func test_accessibilityHitTest_outsideEveryPublishedFrame_returnsNoneOfOurElements() throws {
        let scene = makeMenuScene()
        let view = makePresentedView(scene)

        let elements = try XCTUnwrap(view.publishedAccessibilityElements())
        let corner = CGPoint(x: 1, y: 1)
        for element in elements {
            XCTAssertFalse(
                element.accessibilityFrame.contains(corner),
                "this test is only meaningful while the corner really is empty"
            )
        }

        let hit = view.accessibilityHitTest(corner, event: nil)

        XCTAssertFalse(
            elements.contains { $0 === (hit as AnyObject) },
            "an empty corner must fall through to super, not resolve to a published element"
        )
    }

    /// Hit testing republishes, so it follows a screen swap exactly as a
    /// query does - the stale-frame defect wearing its hit-test hat.
    func test_accessibilityHitTest_followsAScreenSwap() throws {
        let scene = makeMenuScene()
        let view = makePresentedView(scene)

        let play = try publishedElement("menu.playButton", in: view)
        let centre = CGPoint(x: play.accessibilityFrame.midX, y: play.accessibilityFrame.midY)
        XCTAssertTrue(view.accessibilityHitTest(centre, event: nil) as AnyObject === play)

        XCTAssertTrue(scene.stateMachine.transition(to: .highScores))

        let back = try publishedElement("highScores.backToMenuButton", in: view)
        let backCentre = CGPoint(x: back.accessibilityFrame.midX, y: back.accessibilityFrame.midY)

        XCTAssertTrue(view.accessibilityHitTest(backCentre, event: nil) as AnyObject === back)
        XCTAssertFalse(view.accessibilityHitTest(backCentre, event: nil) as AnyObject === play)
    }

    /// With the camera off-centre the published frame is unmoved (the pixels
    /// did not move), so the hit test must still resolve there - the two
    /// halves of the container contract have to agree in the configuration
    /// the original defect needed.
    func test_offCentreCamera_accessibilityHitTest_stillResolvesToThePlayElement() throws {
        let scene = makeMenuScene()
        let view = makePresentedView(scene)

        moveCameraOffCentre(scene)

        let play = try publishedElement("menu.playButton", in: view)
        let centre = CGPoint(x: play.accessibilityFrame.midX, y: play.accessibilityFrame.midY)

        XCTAssertTrue(view.accessibilityHitTest(centre, event: nil) as AnyObject === play)
    }

    // MARK: - Off-centre camera (the configuration the bug actually needed)

    /// Every other test in this file runs with the camera parked on the
    /// scene centre and the view frame equal to the scene size, where
    /// scene -> view is the *identity map* - so the conversion could be a
    /// no-op and the suite would stay green. The camera transform is the
    /// precise thing SpriteKit's implicit accessibility support got wrong,
    /// and `CYBERPUN-17-7` is about to start moving it every frame via
    /// camera-follow, so it has to be exercised off-centre.
    ///
    /// `uiLayer` is parented to `cameraNode`, so moving the camera moves the
    /// button *with* it: the button's scene-space frame shifts by exactly
    /// the camera delta while its position on screen does not move at all.
    /// A conversion that ignored the camera would publish a frame that slid
    /// off the button by the camera delta - which is the original defect,
    /// exactly.
    func test_offCentreCamera_keepsTheCameraLockedButtonWhereItIsOnScreen() throws {
        let scene = makeMenuScene()
        let view = makePresentedView(scene)
        let menu = try XCTUnwrap(scene.activeScreen as? MenuScreenNode)

        let publishedBefore = try publishedElement("menu.playButton", in: view).accessibilityFrame
        let sceneFrameBefore = try XCTUnwrap(scene.accessibilityFrameInScene(for: menu.playButton))

        moveCameraOffCentre(scene)

        let publishedAfter = try publishedElement("menu.playButton", in: view).accessibilityFrame
        let sceneFrameAfter = try XCTUnwrap(scene.accessibilityFrameInScene(for: menu.playButton))

        // The camera-locked button really did move in scene space...
        XCTAssertEqual(sceneFrameAfter.midX, sceneFrameBefore.midX + 137, accuracy: 1e-3)
        XCTAssertEqual(sceneFrameAfter.midY, sceneFrameBefore.midY - 289, accuracy: 1e-3)

        // ...and the published frame must nonetheless be unmoved, because
        // the pixels under the user's finger did not move.
        XCTAssertEqual(publishedAfter.midX, publishedBefore.midX, accuracy: 1e-3)
        XCTAssertEqual(publishedAfter.midY, publishedBefore.midY, accuracy: 1e-3)
        XCTAssertEqual(publishedAfter.width, publishedBefore.width, accuracy: 1e-3)
        XCTAssertEqual(publishedAfter.height, publishedBefore.height, accuracy: 1e-3)
    }

    /// The full round trip in the configuration that can actually fail: with
    /// the camera off-centre, take the frame a driver aims at, convert its
    /// centre back into scene space, and dispatch there. This is the
    /// assertion that would have caught the original defect.
    func test_offCentreCamera_publishedPlayElement_stillStartsARun() throws {
        let scene = makeMenuScene()
        let view = makePresentedView(scene)
        let menu = try XCTUnwrap(scene.activeScreen as? MenuScreenNode)

        moveCameraOffCentre(scene)

        let play = try publishedElement("menu.playButton", in: view)
        let centreInView = CGPoint(x: play.accessibilityFrame.midX, y: play.accessibilityFrame.midY)
        let scenePoint = view.convert(centreInView, to: scene)

        let hit = try XCTUnwrap(
            scene.routeTouch(at: scenePoint),
            "with the camera off-centre the published frame must still point at the button"
        )
        XCTAssertTrue(scene.touchResponder(for: hit) === menu.playButton)

        scene.dispatchTouch(atScenePoint: scenePoint)

        XCTAssertEqual(scene.stateMachine.currentState, .gameplay)
    }

    /// The other identity-map assumption: a view frame equal to the scene
    /// size. Presenting the 400x800 scene `.aspectFit` into a 200x400 view
    /// gives a scale factor of 0.5, so scene -> view is a real scale as well
    /// as a y-flip. The published frame must shrink with it and still point
    /// at the button.
    func test_halfScaleView_publishedPlayElement_stillPointsAtTheButton() throws {
        let scene = makeMenuScene()
        scene.scaleMode = .aspectFit
        let view = makePresentedView(scene, viewSize: CGSize(width: 200, height: 400))
        let menu = try XCTUnwrap(scene.activeScreen as? MenuScreenNode)

        let play = try publishedElement("menu.playButton", in: view)
        let accumulated = menu.playButton.calculateAccumulatedFrame()

        XCTAssertEqual(
            play.accessibilityFrame.width,
            accumulated.width * 0.5,
            accuracy: 1e-2,
            "a half-scale view must publish a half-size frame, or a driver aims at the wrong pixels"
        )
        XCTAssertEqual(play.accessibilityFrame.height, accumulated.height * 0.5, accuracy: 1e-2)

        let centreInView = CGPoint(x: play.accessibilityFrame.midX, y: play.accessibilityFrame.midY)
        let scenePoint = view.convert(centreInView, to: scene)

        let hit = try XCTUnwrap(scene.routeTouch(at: scenePoint))
        XCTAssertTrue(scene.touchResponder(for: hit) === menu.playButton)

        scene.dispatchTouch(atScenePoint: scenePoint)

        XCTAssertEqual(scene.stateMachine.currentState, .gameplay)
    }

    /// Both blind spots at once: off-centre camera *and* a scaled view.
    func test_halfScaleViewWithOffCentreCamera_publishedPlayElement_stillStartsARun() throws {
        let scene = makeMenuScene()
        scene.scaleMode = .aspectFit
        let view = makePresentedView(scene, viewSize: CGSize(width: 200, height: 400))
        let menu = try XCTUnwrap(scene.activeScreen as? MenuScreenNode)

        moveCameraOffCentre(scene)

        let play = try publishedElement("menu.playButton", in: view)
        let centreInView = CGPoint(x: play.accessibilityFrame.midX, y: play.accessibilityFrame.midY)
        let scenePoint = view.convert(centreInView, to: scene)

        let hit = try XCTUnwrap(scene.routeTouch(at: scenePoint))
        XCTAssertTrue(scene.touchResponder(for: hit) === menu.playButton)

        scene.dispatchTouch(atScenePoint: scenePoint)

        XCTAssertEqual(scene.stateMachine.currentState, .gameplay)
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

    func test_viewRect_flipsTheYAxis_andPreservesSize() {
        let scene = makeMenuScene()
        let view = makePresentedView(scene)

        // The scene's origin is its bottom-left (y up); UIKit's is its
        // top-left (y down), so a rect hugging the scene's *bottom* edge must
        // come back with a *large* y - the flip `viewRect(forSceneRect:in:)`
        // is responsible for.
        let bottomLeft = CGRect(x: 0, y: 0, width: 40, height: 20)
        let converted = view.viewRect(forSceneRect: bottomLeft, in: scene)

        XCTAssertEqual(converted.width, bottomLeft.width, accuracy: 1e-3)
        XCTAssertEqual(converted.height, bottomLeft.height, accuracy: 1e-3)
        XCTAssertGreaterThan(
            converted.midY,
            scene.size.height / 2,
            "the scene's bottom edge must map to the lower half of a y-down coordinate space"
        )
    }

    /// `accessibilityFrame` is documented in **screen** coordinates, which
    /// are reached through the window - so an off-window view has no screen
    /// mapping and `screenFrame(forSceneRect:in:)` falls back to the
    /// view-space rect rather than publishing the degenerate rect UIKit
    /// would answer with. Pinning that keeps every windowless assertion in
    /// this file meaningful instead of accidentally asserting on zeroes.
    func test_screenFrame_withoutAWindow_fallsBackToTheViewSpaceRect() {
        let scene = makeMenuScene()
        let view = makePresentedView(scene)
        XCTAssertNil(view.window, "this test is about the off-window path")

        let sceneRect = CGRect(x: 40, y: 60, width: 120, height: 30)

        XCTAssertEqual(
            view.screenFrame(forSceneRect: sceneRect, in: scene),
            view.viewRect(forSceneRect: sceneRect, in: scene)
        )
    }
}
