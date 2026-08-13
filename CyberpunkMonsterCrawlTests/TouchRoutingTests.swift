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

    /// The inverse failure of `test_overlappingUIAndWorldNode_routesToUI_neverToWorld`,
    /// and the one the story's AC4 words as "untouched events fall through
    /// to the world": a *mounted screen* must not blanket the viewport with
    /// an inert (non-`TouchResponder`) node. `routeTouch(at:)` returns any
    /// non-`uiLayer` hit under `uiLayer` before it looks at `worldLayer`, so
    /// a full-bleed backdrop on the gameplay screen would swallow every
    /// touch on screen - `dispatchTouch` would then return `nil` because the
    /// backdrop has no `TouchResponder` ancestor - and would paint over
    /// `worldLayer` once CYBERPUN-17-3+ renders world content.
    /// `test_uiNodeElsewhere_doesNotStealATouchOverWorldOnly` only covers a
    /// UI node that does *not* cover the point, so this drives the real
    /// screen instead of a stand-in.
    func test_mountedGameplayScreen_doesNotBlockWorldTouches() {
        let scene = makeScene()
        let gameplay = GameplayScreenNode()
        scene.register(gameplay, for: .gameplay)
        scene.stateMachine.transition(to: .gameplay)

        XCTAssertTrue(
            scene.activeScreen === gameplay,
            "precondition: the gameplay screen must actually be mounted and laid out"
        )

        // Points spread across the viewport, all clear of the small centred
        // placeholder label. The camera stays at the origin in a view-less
        // test scene, so scene coordinates map straight through to uiLayer.
        for worldPoint in [CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 400), CGPoint(x: 350, y: 700)] {
            let worldNode = makeHitTestableNode(at: worldPoint)
            // Entering `.gameplay` above also starts the real streamed ground
            // plane (`GameScene.updateWorldContent(for:)`), so `worldLayer`
            // already holds real ground tiles under these points by the time
            // this loop runs. Ground's zPosition (`DepthModel.groundOffset`,
            // always *below* its own band) is real world content and must
            // stay reachable too - it is simply not what this assertion is
            // about. Give this synthetic node the *ceiling of the world
            // band itself*, expressed as a relative offset off `worldLayer`:
            // `worldMaxZ - worldLayerZ` puts its cumulative zPosition
            // exactly on `LayerConstants.worldMaxZ`, which is strictly above
            // every legitimate ground/building/actor offset (the actor band
            // offsets this story adds sit well inside the band) yet still
            // *inside* `LayerConstants.worldBand`, which is closed on both
            // bounds. One step higher would land on `effectsMinZ` and make
            // this node exactly the escape `SceneInvariants` /
            // `GameScene.nodesEscapingTheirLayerBand()` /
            // `DepthModel.isWithinWorldBand(_:)` audit for - a bad precedent
            // to seed for the actor z-work in the follow-up PRs. So the hit
            // test still prefers this stand-in "on top of the ground" node -
            // exactly like a real actor, which always draws in front of the
            // ground beneath it - rather than depending on incidental
            // z-order against whatever ground tile shares the point.
            worldNode.zPosition = LayerConstants.worldMaxZ - LayerConstants.worldLayerZ
            scene.worldLayer.addChild(worldNode)

            XCTAssertTrue(
                DepthModel.isWithinWorldBand(scene.worldLayer.zPosition + worldNode.zPosition),
                "the stand-in world node's cumulative zPosition "
                    + "(\(scene.worldLayer.zPosition + worldNode.zPosition)) must stay inside "
                    + "LayerConstants.worldBand: a routing test that seeds a node in the effects "
                    + "band models the very escape SceneInvariants audits against."
            )

            XCTAssertTrue(
                scene.routeTouch(at: worldPoint) === worldNode,
                "a mounted gameplay screen must not blanket the viewport: the touch at "
                    + "\(worldPoint) has to fall through to the world node"
            )

            worldNode.removeFromParent()
        }
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
