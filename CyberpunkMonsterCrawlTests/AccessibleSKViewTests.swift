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

    /// The root view `makePresentedView(_:viewSize:)` builds, retained for the
    /// lifetime of the test so the sibling pair below cannot be torn down
    /// mid-assertion.
    private var hostView: UIView!

    /// The plain `UIView` the elements are actually vended from - the class
    /// UIKit asks both "what elements are there?" and "which element is at
    /// this point?", now that the container has moved off `SKView` (see
    /// `AccessibleSKView`, "part 3").
    private var containerView: SceneAccessibilityContainerView!

    override func tearDown() {
        hostView = nil
        containerView = nil
        super.tearDown()
    }

    /// The real composed scene (menu mounted, all four screens registered),
    /// so these tests measure what ships rather than a hand-built stand-in.
    private func makeMenuScene() -> GameScene {
        GameViewController().makeGameScene(size: sceneSize)
    }

    /// A presented `AccessibleSKView` with no window, wired to a
    /// `SceneAccessibilityContainerView` sibling exactly as
    /// `GameViewController` wires them - enough for every conversion the
    /// classes perform (scene size, view bounds, scale mode and camera are
    /// all they need), and paused so no render loop can mutate the scene
    /// mid-assertion.
    ///
    /// The container is reachable as `containerView` rather than returned,
    /// so the tests that only care about published geometry stay unchanged.
    ///
    /// `viewSize` defaults to the scene size (the 1:1 case) but can be given
    /// a different value so the scale factor the conversion depends on is
    /// actually exercised - see
    /// `test_halfScaleView_publishedPlayElement_stillPointsAtTheButton`.
    private func makePresentedView(_ scene: GameScene, viewSize: CGSize? = nil) -> AccessibleSKView {
        let bounds = CGRect(origin: .zero, size: viewSize ?? sceneSize)
        let host = UIView(frame: bounds)
        let view = AccessibleSKView(frame: bounds)
        host.addSubview(view)

        let container = SceneAccessibilityContainerView(sceneView: view)
        container.frame = bounds
        host.addSubview(container)

        view.presentScene(scene)
        view.isPaused = true

        hostView = host
        containerView = container
        return view
    }

    /// Every element the container currently publishes, in z-order (bottom
    /// first), refreshed beforehand so the list is the one an accessibility
    /// snapshot would see.
    ///
    /// The published objects are **real invisible subviews**
    /// (`SceneAccessibilityMirrorView`), not synthesized
    /// `UIAccessibilityElement`s: that swap is the fix (see
    /// `AccessibleSKView`, "part 2"), so the assertions below read the very
    /// views UIKit resolves rather than objects we vend by hand.
    private func publishedMirrors() -> [SceneAccessibilityMirrorView] {
        containerView.refreshAccessibilityMirrors()
        return containerView.subviews.compactMap { $0 as? SceneAccessibilityMirrorView }
    }

    /// The published element a driver would resolve for `identifier`.
    private func publishedElement(_ identifier: String) throws -> SceneAccessibilityMirrorView {
        try XCTUnwrap(
            publishedMirrors().first { $0.accessibilityIdentifier == identifier },
            "no published element carries the identifier \(identifier)"
        )
    }

    /// The centre of `element`'s published frame, in container coordinates -
    /// the point a driver resolves from the frame the app publishes.
    private func publishedCentre(of element: SceneAccessibilityMirrorView) -> CGPoint {
        CGPoint(x: element.frame.midX, y: element.frame.midY)
    }

    /// The element UIKit's point lookup lands on for `point` (container
    /// coordinates), resolved the way a driver resolves it: by hit-testing
    /// **from the root view** with no event, which is the walk
    /// `accessibilityHitTest(_:)` - and with it XCUITest's `isHittable` - is
    /// built on.
    ///
    /// Starting at the root rather than at the container is load-bearing:
    /// `UIView.hitTest(_:with:)` returns `nil` for a non-interactive view and
    /// never descends into its subviews, so an overlay that opted out of
    /// interaction was skipped entirely and the point resolved to the
    /// (accessibility-silenced) `SKView` underneath - PLAY findable,
    /// `isHittable == false`. A helper that began the walk inside the
    /// container could not see that, so this one begins where a driver does.
    private func elementResolved(atContainerPoint point: CGPoint) throws -> SceneAccessibilityMirrorView {
        _ = publishedMirrors()
        let root = try XCTUnwrap(hostView, "the presented host view is what a driver walks from")
        let pointInRoot = root.convert(point, from: containerView)

        let resolved = try XCTUnwrap(
            root.hitTest(pointInRoot, with: nil),
            "no view at all resolves at \(point) - the accessibility point lookup would answer nothing"
        )
        return try XCTUnwrap(
            resolved as? SceneAccessibilityMirrorView,
            "the point lookup at \(point) resolved to \(type(of: resolved)) instead of a mirror - the "
                + "overlay is not taking part in hit-testing, which is what makes PLAY un-hittable"
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
        _ = makePresentedView(scene)

        let elements = publishedMirrors()
        XCTAssertFalse(
            elements.isEmpty,
            "the container must publish the menu's elements itself, not leave it to SpriteKit"
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
        XCTAssertFalse(play.frame.isEmpty, "a zero frame is exactly what made PLAY untappable")
        XCTAssertTrue(
            play.isAccessibilityElement,
            "a mirror must be a leaf element, or a driver resolves the container instead of the button"
        )

        let highScores = try XCTUnwrap(
            elements.first { $0.accessibilityIdentifier == "menu.highScoresButton" }
        )
        XCTAssertEqual(highScores.accessibilityLabel, "HIGH SCORES")

        let container = try XCTUnwrap(elements.first { $0.accessibilityIdentifier == "menu.container" })
        XCTAssertEqual(container.accessibilityLabel, "Menu")

        // The elements UIKit reads are the container view's own subviews, not
        // anything the SKView vends - that move is the fix, so assert it
        // where UIKit looks.
        XCTAssertEqual(containerView.mirrorViews.count, elements.count)
        XCTAssertFalse(
            containerView.isAccessibilityElement,
            "a container that reports itself as an element collapses everything it vends"
        )
    }

    // MARK: - The container has to be the plain UIView, not the SKView

    /// The entry-point wiring for the hit-test half of the fix.
    ///
    /// `SKView` ships its own camera-unaware accessibility implementation and
    /// the accessibility server keeps consulting *that* one for an `SKView`,
    /// whatever this app overrides on it - which is why PLAY resolved by
    /// label yet `isHittable` stayed `false`. So the elements are vended from
    /// a plain `UIView` sibling *above* the `SKView`, and SpriteKit's
    /// competing tree is silenced. Both halves of that are load-bearing and
    /// invisible to every other test in this file, so they are pinned here.
    func test_compositionRoot_vendsTheElementsFromAPlainViewAboveTheSKView() throws {
        let controller = GameViewController()
        controller.loadViewIfNeeded()

        let container = try XCTUnwrap(
            controller.accessibilityContainerView,
            "the composition root must install the plain-UIView accessibility container"
        )
        XCTAssertFalse(
            container is SKView,
            "the container must not be an SKView - SpriteKit's own implementation answers for those"
        )
        XCTAssertTrue(container.superview === controller.view)
        XCTAssertTrue(
            controller.skView.superview === controller.view,
            "the two must be siblings: accessibilityElementsHidden on the SKView would hide a child"
        )

        let subviews = controller.view.subviews
        let skViewIndex = try XCTUnwrap(subviews.firstIndex { $0 === controller.skView })
        let containerIndex = try XCTUnwrap(subviews.firstIndex { $0 === container })
        XCTAssertGreaterThan(
            containerIndex,
            skViewIndex,
            "the container must sit above the SKView, or the accessibility walk reaches SpriteKit first"
        )

        XCTAssertTrue(
            controller.skView.accessibilityElementsHidden,
            "SpriteKit's competing accessibility tree must be silenced, or it answers the hit test"
        )
        XCTAssertFalse(container.accessibilityElementsHidden)

        // The overlay must take part in hit-testing (a non-interactive view
        // answers nil for every point and hides its subtree from the
        // accessibility point lookup, which is what left PLAY un-hittable)...
        XCTAssertTrue(
            container.isUserInteractionEnabled,
            "an overlay that opts out of interaction is skipped by the hit-test walk the "
                + "accessibility point lookup is built on"
        )

        // ...while still never taking a touch away from the SKView
        // underneath: a hit test carrying a real event resolves to nothing.
        let centre = CGPoint(x: container.bounds.midX, y: container.bounds.midY)
        XCTAssertNil(
            container.hitTest(centre, with: UIEvent()),
            "a real touch must fall straight through to the SKView - the scene is the sole dispatcher"
        )
    }

    /// Every element must live in the container's own view hierarchy: an
    /// element inside the `SKView` is read back through SpriteKit's tree,
    /// which is the arrangement that failed.
    func test_publishedElements_areOwnedByTheContainerView() throws {
        let scene = makeMenuScene()
        let view = makePresentedView(scene)

        let elements = publishedMirrors()
        XCTAssertFalse(elements.isEmpty)

        for element in elements {
            XCTAssertTrue(
                element.superview === containerView,
                "\(element.accessibilityIdentifier ?? "?") must be vended by the container view"
            )
            XCTAssertFalse(
                element.isDescendant(of: view),
                "an element inside the SKView is answered for by SpriteKit's own tree"
            )
            XCTAssertTrue(
                element.isUserInteractionEnabled,
                "a non-interactive mirror is skipped by the hit-test walk the accessibility point "
                    + "lookup is built on, which is what made PLAY findable but un-hittable"
            )

            // Interactive, yet still never the target of a real touch: the
            // container hands every event-carrying hit test back to the
            // SKView, so the finger the scene is waiting for still arrives.
            let centre = publishedCentre(of: element)
            XCTAssertNil(
                containerView.hitTest(centre, with: UIEvent()),
                "a real touch at \(element.accessibilityIdentifier ?? "?") must fall through to the SKView"
            )
        }
    }

    /// The published frame must be the button's real size, not a guess: the
    /// scene is presented 1:1 (`.resizeFill`, scene size == view size), so the
    /// element's frame must measure the same as the node's accumulated frame.
    func test_publishedElementFrame_measuresTheButton() throws {
        let scene = makeMenuScene()
        _ = makePresentedView(scene)
        let menu = try XCTUnwrap(scene.activeScreen as? MenuScreenNode)

        let play = try publishedElement("menu.playButton")

        let accumulated = menu.playButton.calculateAccumulatedFrame()
        XCTAssertEqual(play.frame.width, accumulated.width, accuracy: 1e-3)
        XCTAssertEqual(play.frame.height, accumulated.height, accuracy: 1e-3)
    }

    /// The end-to-end shape of the fix: take the frame a driver would aim at,
    /// convert its centre back through the view into scene space, dispatch
    /// there, and land in `.gameplay`.
    ///
    /// A mirror's `frame` is the node's camera-aware rect in the container's
    /// coordinate space; UIKit takes it the rest of the way to the screen
    /// coordinates a driver aims at, from the view's own geometry. So the
    /// honest inverse of what the app published is: container -> view ->
    /// scene, which is what this round trip walks.
    func test_publishedPlayElement_pointsAtASceneLocationThatStartsARun() throws {
        let scene = makeMenuScene()
        let view = makePresentedView(scene)
        let menu = try XCTUnwrap(scene.activeScreen as? MenuScreenNode)

        let play = try publishedElement("menu.playButton")
        let centreInView = view.convert(publishedCentre(of: play), from: containerView)

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
        _ = makePresentedView(scene)

        let beforeIdentifiers = Set(publishedMirrors().compactMap(\.accessibilityIdentifier))
        XCTAssertTrue(beforeIdentifiers.contains("menu.playButton"))

        XCTAssertTrue(scene.stateMachine.transition(to: .highScores))

        // Read through the property UIKit itself consults once per
        // accessibility snapshot - no explicit refresh - because that is the
        // hook that has to rebuild the mirrors for a real driver.
        _ = containerView.accessibilityElements

        let after = containerView.mirrorViews
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
    ///
    /// Asked of the *container view*: the `SKView` cannot answer this
    /// question, because SpriteKit's own accessibility implementation is what
    /// the accessibility server consults for one - which is why the container
    /// moved onto a plain `UIView` (see `AccessibleSKView`, "part 3").
    func test_accessibilityHitTest_atThePublishedPlayFrameCentre_returnsThatElement() throws {
        let scene = makeMenuScene()
        _ = makePresentedView(scene)

        let play = try publishedElement("menu.playButton")

        let hit = try elementResolved(atContainerPoint: publishedCentre(of: play))

        XCTAssertTrue(
            hit === play,
            "hit-testing the published frame's centre must return that very element - identity is what "
                + "isHittable compares, so an equal-but-different object is still a failure"
        )
    }

    /// `menu.container` is a size-less marker published at a synthesised 1pt
    /// rect. Answering the marker where a button is would make that button
    /// unhittable just as surely as answering nothing at all, so two
    /// independent guarantees keep it harmless: `MenuScreenNode` parks the
    /// marker clear of every button, and `SceneAccessibilityContainerView`
    /// keeps markers at the bottom of the z-order, where UIKit's
    /// topmost-sibling rule makes a real-sized element win any point the two
    /// ever did share.
    func test_publishedMarker_staysClearOfTheButtons_andBelowThemInTheZOrder() throws {
        let scene = makeMenuScene()
        _ = makePresentedView(scene)

        let mirrors = publishedMirrors()
        let play = try publishedElement("menu.playButton")
        let highScores = try publishedElement("menu.highScoresButton")
        let marker = try publishedElement("menu.container")

        XCTAssertFalse(
            play.frame.intersects(marker.frame),
            "the size-less marker must not overlap PLAY - two elements sharing a point is the "
                + "ambiguity that can make PLAY report isHittable == false"
        )
        XCTAssertFalse(highScores.frame.intersects(marker.frame))

        // Published subview order *is* the z-order UIKit resolves a point
        // with, so the marker coming first is what makes a real element win.
        let markerIndex = try XCTUnwrap(mirrors.firstIndex { $0 === marker })
        let playIndex = try XCTUnwrap(mirrors.firstIndex { $0 === play })
        XCTAssertLessThan(
            markerIndex,
            playIndex,
            "a marker must sit below every real element, or it can answer a point a button owns"
        )

        // ...and it still owns its own point, so it stays findable.
        let hit = try elementResolved(atContainerPoint: publishedCentre(of: marker))
        XCTAssertTrue(hit === marker)
    }

    /// The other button, so the hit test is picking an element rather than
    /// always answering the same one.
    func test_accessibilityHitTest_atTheHighScoresFrameCentre_returnsThatElement() throws {
        let scene = makeMenuScene()
        _ = makePresentedView(scene)

        let highScores = try publishedElement("menu.highScoresButton")

        let hit = try elementResolved(atContainerPoint: publishedCentre(of: highScores))

        XCTAssertTrue(hit === highScores)
    }

    /// A point no published element covers must not be attributed to one of
    /// them - a container that claims every point is as wrong as one that
    /// claims none.
    func test_accessibilityHitTest_outsideEveryPublishedFrame_returnsNoneOfOurElements() throws {
        let scene = makeMenuScene()
        _ = makePresentedView(scene)

        let elements = publishedMirrors()
        XCTAssertFalse(elements.isEmpty, "this test is only meaningful while something is published")

        let corner = CGPoint(x: 1, y: 1)
        for element in elements {
            XCTAssertFalse(
                element.frame.contains(corner),
                "this test is only meaningful while the corner really is empty"
            )
        }

        XCTAssertNil(
            publishedMirrors().last { $0.frame.contains(corner) },
            "an empty corner must fall through to the view underneath, not resolve to a published element"
        )
    }

    /// Hit testing republishes, so it follows a screen swap exactly as a
    /// query does - the stale-frame defect wearing its hit-test hat.
    func test_accessibilityHitTest_followsAScreenSwap() throws {
        let scene = makeMenuScene()
        _ = makePresentedView(scene)

        let play = try publishedElement("menu.playButton")
        let hitBefore = try elementResolved(atContainerPoint: publishedCentre(of: play))
        XCTAssertTrue(hitBefore === play)

        XCTAssertTrue(scene.stateMachine.transition(to: .highScores))

        let back = try publishedElement("highScores.backToMenuButton")
        let hitAfter = try elementResolved(atContainerPoint: publishedCentre(of: back))

        XCTAssertTrue(hitAfter === back)
        XCTAssertFalse(hitAfter === play)
    }

    /// With the camera off-centre the published frame is unmoved (the pixels
    /// did not move), so the hit test must still resolve there - the two
    /// halves of the container contract have to agree in the configuration
    /// the original defect needed.
    func test_offCentreCamera_accessibilityHitTest_stillResolvesToThePlayElement() throws {
        let scene = makeMenuScene()
        _ = makePresentedView(scene)

        moveCameraOffCentre(scene)

        let play = try publishedElement("menu.playButton")

        let hit = try elementResolved(atContainerPoint: publishedCentre(of: play))

        XCTAssertTrue(hit === play)
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
        _ = makePresentedView(scene)
        let menu = try XCTUnwrap(scene.activeScreen as? MenuScreenNode)

        let publishedBefore = try publishedElement("menu.playButton").frame
        let sceneFrameBefore = try XCTUnwrap(scene.accessibilityFrameInScene(for: menu.playButton))

        moveCameraOffCentre(scene)

        let publishedAfter = try publishedElement("menu.playButton").frame
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

        let play = try publishedElement("menu.playButton")
        let centreInView = view.convert(publishedCentre(of: play), from: containerView)
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

        let play = try publishedElement("menu.playButton")
        let accumulated = menu.playButton.calculateAccumulatedFrame()

        XCTAssertEqual(
            play.frame.width,
            accumulated.width * 0.5,
            accuracy: 1e-2,
            "a half-scale view must publish a half-size frame, or a driver aims at the wrong pixels"
        )
        XCTAssertEqual(play.frame.height, accumulated.height * 0.5, accuracy: 1e-2)

        let centreInView = view.convert(publishedCentre(of: play), from: containerView)
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

        let play = try publishedElement("menu.playButton")
        let centreInView = view.convert(publishedCentre(of: play), from: containerView)
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
    /// are reached through the window - and this suite runs off-window,
    /// where a view has no screen mapping at all. That is exactly why the app
    /// no longer computes a screen rect itself: a mirror carries the node's
    /// camera-aware rect as its own `frame`, in the container's coordinate
    /// space, and UIKit derives the screen-space `accessibilityFrame` from
    /// that real view's geometry once there *is* a window.
    ///
    /// Pinning the conversion is what keeps every frame assertion in this
    /// file meaningful: what a mirror publishes is precisely
    /// `viewRect(forSceneRect:in:)` carried into container space, never a
    /// degenerate off-window rect.
    func test_publishedMirrorFrame_isTheViewSpaceRectInContainerSpace() throws {
        let scene = makeMenuScene()
        let view = makePresentedView(scene)
        XCTAssertNil(view.window, "this test is about the off-window path")

        let menu = try XCTUnwrap(scene.activeScreen as? MenuScreenNode)
        let sceneRect = try XCTUnwrap(scene.accessibilityFrameInScene(for: menu.playButton))
        let expected = containerView.convert(
            view.viewRect(forSceneRect: sceneRect, in: scene),
            from: view
        )

        let play = try publishedElement("menu.playButton")

        XCTAssertEqual(play.frame.minX, expected.minX, accuracy: 1e-6)
        XCTAssertEqual(play.frame.minY, expected.minY, accuracy: 1e-6)
        XCTAssertEqual(play.frame.width, expected.width, accuracy: 1e-6)
        XCTAssertEqual(play.frame.height, expected.height, accuracy: 1e-6)
    }
}
