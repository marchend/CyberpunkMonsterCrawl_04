import XCTest
import SpriteKit
import UIKit
@testable import CyberpunkMonsterCrawl

/// Proves the routed touch is actually *delivered*, not computed and thrown
/// away. `TouchRoutingTests` covers the pure `routeTouch(at:)` decision; this
/// suite drives `dispatchTouch(atScenePoint:)` - the entire body of
/// `GameScene.touchesBegan(_:with:)` apart from unwrapping the `UITouch`
/// (which cannot be constructed with a location in a unit test) - so a
/// regression that stops delivering touches turns the suite red.
///
/// Also pins the "scene is the sole dispatcher" contract: nothing in the
/// graph may set `isUserInteractionEnabled`, because UIKit hands such a node
/// the touch before `SKScene.touchesBegan(_:with:)` runs and so bypasses
/// UI-first routing entirely.
final class TouchDispatchTests: XCTestCase {

    private func makeScene() -> GameScene {
        GameScene(size: CGSize(width: 400, height: 800))
    }

    /// A `TouchResponder` whose node is a hit-testable sprite.
    private final class SpyResponderNode: SKSpriteNode, TouchResponder {
        private(set) var handledCount = 0

        func handleTouch() {
            handledCount += 1
        }
    }

    private func makeSpy(at position: CGPoint) -> SpyResponderNode {
        let spy = SpyResponderNode(color: .white, size: CGSize(width: 60, height: 60))
        spy.position = position
        return spy
    }

    // MARK: - Delivery

    func test_dispatch_deliversTheTouchToTheResponderUnderThePoint() {
        let scene = makeScene()
        let point = CGPoint(x: 200, y: 400)
        let spy = makeSpy(at: point)
        scene.uiLayer.addChild(spy)

        let responder = scene.dispatchTouch(atScenePoint: point)

        XCTAssertEqual(spy.handledCount, 1, "the routed touch must be delivered, not discarded")
        XCTAssertTrue(responder === spy)
    }

    func test_dispatch_deliversToTheButton_notToItsDeepestDescendant() {
        // atPoint(_:) returns the deepest descendant - for a ButtonNode that
        // is its label/plate, which is not the responder.
        let scene = makeScene()
        var tapped = 0
        let button = ButtonNode(title: "PLAY", size: CGSize(width: 200, height: 60)) { tapped += 1 }
        button.position = CGPoint(x: 200, y: 400)
        scene.uiLayer.addChild(button)

        let responder = scene.dispatchTouch(atScenePoint: button.position)

        XCTAssertEqual(tapped, 1, "the touch must walk up to the nearest TouchResponder ancestor")
        XCTAssertTrue(responder === button)
    }

    func test_dispatch_prefersUIResponder_overAnOverlappingWorldResponder() {
        let scene = makeScene()
        let point = CGPoint(x: 200, y: 400)
        let worldSpy = makeSpy(at: point)
        scene.worldLayer.addChild(worldSpy)
        let uiSpy = makeSpy(at: point)
        scene.uiLayer.addChild(uiSpy)

        scene.dispatchTouch(atScenePoint: point)

        XCTAssertEqual(uiSpy.handledCount, 1, "the UI responder must consume the touch")
        XCTAssertEqual(worldSpy.handledCount, 0, "an overlapped world responder must never see the touch")
    }

    func test_dispatch_overEmptySpace_deliversToNobody() {
        let scene = makeScene()
        let spy = makeSpy(at: CGPoint(x: 350, y: 750))
        scene.uiLayer.addChild(spy)

        let responder = scene.dispatchTouch(atScenePoint: CGPoint(x: 5, y: 5))

        XCTAssertNil(responder)
        XCTAssertEqual(spy.handledCount, 0)
    }

    func test_dispatch_onANonRespondingNode_isANoOp() {
        let scene = makeScene()
        let point = CGPoint(x: 100, y: 100)
        let inert = SKSpriteNode(color: .white, size: CGSize(width: 40, height: 40))
        inert.position = point
        scene.uiLayer.addChild(inert)

        XCTAssertNil(scene.dispatchTouch(atScenePoint: point))
    }

    // MARK: - Sole-dispatcher contract

    func test_freshScene_andMenuScreen_haveNoNodesBypassingSceneDispatch() {
        let scene = makeScene()
        XCTAssertTrue(scene.nodesBypassingSceneTouchDispatch().isEmpty)

        scene.register(MenuScreen(onPlay: {}), for: .menu)

        XCTAssertTrue(
            scene.nodesBypassingSceneTouchDispatch().isEmpty,
            "MenuScreen/ButtonNode must not set isUserInteractionEnabled: UIKit would deliver the "
                + "touch before the scene's touchesBegan and bypass UI-first routing"
        )
    }

    func test_nodeOptingIntoUIKitDelivery_isReportedAsBypassingSceneDispatch() {
        let scene = makeScene()
        let thief = SKSpriteNode(color: .white, size: CGSize(width: 40, height: 40))
        thief.name = "touchThief"
        thief.isUserInteractionEnabled = true
        scene.uiLayer.addChild(thief)

        XCTAssertTrue(
            scene.nodesBypassingSceneTouchDispatch().contains { $0 === thief },
            "the audit must catch a node that steals touch delivery from the scene"
        )
    }

    func test_worldNodeOptingIntoUIKitDelivery_isAlsoReported() {
        let scene = makeScene()
        let thief = SKSpriteNode(color: .white, size: CGSize(width: 40, height: 40))
        thief.isUserInteractionEnabled = true
        scene.worldLayer.addChild(thief)

        XCTAssertTrue(scene.nodesBypassingSceneTouchDispatch().contains { $0 === thief })
    }

    // MARK: - Menu flow through the scene

    func test_tappingMenuPlayButton_transitionsTheStateMachineToGameplay() {
        let scene = makeScene()
        let menu = MenuScreen { [weak scene] in
            scene?.stateMachine.transition(to: .gameplay)
        }
        scene.register(menu, for: .menu)

        // Registration laid the screen out for the scene size; the camera is
        // at the origin in a view-less test scene, so uiLayer coordinates map
        // straight through to scene coordinates.
        scene.dispatchTouch(atScenePoint: menu.playButton.position)

        XCTAssertEqual(scene.stateMachine.currentState, .gameplay, "PLAY must start a run")
        XCTAssertNil(scene.activeScreen, "the menu unmounts; .gameplay has no screen until CYBERPUN-17-2-t3")
        XCTAssertNil(menu.node.parent)
    }
}
