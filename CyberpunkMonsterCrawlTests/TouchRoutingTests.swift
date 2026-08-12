import XCTest
import SpriteKit
import UIKit
@testable import CyberpunkMonsterCrawl

/// Proves `GameScene`'s UI-first touch routing decision (AC4): a UI node
/// must win over an overlapping world node at the same point, never the
/// reverse. `routeTouch(at:)` is exercised directly - it is the pure
/// function that decides *which* node a touch belongs to.
///
/// Routing is only half the story: `TouchDispatchTests` covers the other
/// half (the routed touch is actually delivered to a `TouchResponder`, and
/// no node bypasses the scene's dispatch), so deleting the delivery call in
/// `touchesBegan(_:with:)` cannot leave the suite green.
final class TouchRoutingTests: XCTestCase {

    private func makeScene() -> GameScene {
        GameScene(size: CGSize(width: 400, height: 800))
    }

    /// A hit-testable node: `SKSpriteNode`'s default anchor point (0.5, 0.5)
    /// means `position` is the geometric centre of its frame, so a touch at
    /// exactly `position` is always inside it regardless of `size`.
    private func makeHitTestableNode(at position: CGPoint) -> SKSpriteNode {
        let node = SKSpriteNode(color: .white, size: CGSize(width: 50, height: 50))
        node.position = position
        return node
    }

    func test_overlappingUIAndWorldNode_routesToUI_neverToWorld() {
        let scene = makeScene()
        let point = CGPoint(x: 200, y: 400)

        let worldNode = makeHitTestableNode(at: point)
        scene.worldLayer.addChild(worldNode)

        let uiNode = makeHitTestableNode(at: point)
        scene.uiLayer.addChild(uiNode)

        let hit = scene.routeTouch(at: point)

        XCTAssertTrue(hit === uiNode, "UI-first routing must return the UI node")
        XCTAssertFalse(hit === worldNode, "UI-first routing must never return the world node when UI overlaps it")
    }

    func test_touchOnlyOverWorldNode_fallsThroughToWorld() {
        let scene = makeScene()
        let point = CGPoint(x: 100, y: 100)

        let worldNode = makeHitTestableNode(at: point)
        scene.worldLayer.addChild(worldNode)

        let hit = scene.routeTouch(at: point)

        XCTAssertTrue(hit === worldNode)
    }

    func test_touchOverNeitherLayer_returnsNil() {
        let scene = makeScene()

        let hit = scene.routeTouch(at: CGPoint(x: 5, y: 5))

        XCTAssertNil(hit)
    }

    func test_uiNodeElsewhere_doesNotStealATouchOverWorldOnly() {
        let scene = makeScene()
        let worldPoint = CGPoint(x: 100, y: 100)

        let uiElsewhere = makeHitTestableNode(at: CGPoint(x: 350, y: 750))
        scene.uiLayer.addChild(uiElsewhere)

        let worldNode = makeHitTestableNode(at: worldPoint)
        scene.worldLayer.addChild(worldNode)

        let hit = scene.routeTouch(at: worldPoint)

        XCTAssertTrue(hit === worldNode, "a UI node that does not cover the touch point must not block the world hit")
    }
}
