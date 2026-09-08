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

        // Points spread across the viewport. Since CYBERPUN-17-5-t4 the
        // gameplay screen mounts nothing with a frame at all (its former
        // centred placeholder label is gone), so no point on screen is
        // covered by UI - but the assertion is written to hold for any
        // future HUD too, hence points away from the centre. The camera stays
        // at the origin in a view-less test scene, so scene coordinates map
        // straight through to uiLayer.
        //
        // `worldLayer` is a different story: entering `.gameplay` above
        // also runs `CameraController.update(focus:viewportSize:)`, which
        // (per that type's own doc comment) repositions `worldLayer` itself
        // to `viewportCentre - projected(focus)` so the spawn point lands
        // centred on screen. That offset is essentially never `.zero` (the
        // spawn tile practically never projects exactly onto the viewport
        // centre), so a stand-in node meant to occupy `worldPoint` *in
        // scene space* must be positioned at `worldPoint` converted into
        // `worldLayer`'s own (now-shifted) local space - the same
        // conversion `GameScene.routeTouch(at:)` itself performs
        // (`worldLayer.convert(scenePoint, from: self)`) before hit-testing
        // - rather than at `worldPoint` taken as a `worldLayer`-local
        // position directly, which would silently drift off the intended
        // scene point by exactly that camera offset.
        for worldPoint in [CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 400), CGPoint(x: 350, y: 700)] {
            let worldLocalPoint = scene.worldLayer.convert(worldPoint, from: scene)
            let worldNode = makeHitTestableNode(at: worldLocalPoint)
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

    // MARK: - Grouping nodes are transparent to routing (`CYBERPUN-17-12`)

    /// The unit-level statement of what
    /// `test_mountedGameplayScreen_doesNotBlockWorldTouches` caught against
    /// the real scene: SpriteKit hit-tests a node that draws nothing of its
    /// own against the *union* of its children's frames, so a group whose
    /// children sit in opposite corners reports a hit across everything
    /// between them. `HUDLayer` is exactly that shape (HP bar top-left,
    /// pulse button bottom-right), so before the fix mounting the HUD
    /// blanketed the viewport: `routeTouch(at:)` returned the group,
    /// `dispatchTouch` found no `TouchResponder` above it, and the touch was
    /// swallowed instead of reaching the world.
    func test_groupingNodeWithFarApartChildren_doesNotCaptureATouchBetweenThem() {
        let scene = makeScene()
        let gapPoint = CGPoint(x: 200, y: 400)

        let group = SKNode()
        group.addChild(makeHitTestableNode(at: CGPoint(x: 40, y: 40)))
        group.addChild(makeHitTestableNode(at: CGPoint(x: 360, y: 760)))
        scene.uiLayer.addChild(group)

        // Anti-vacuity: the group really does cover the point as far as
        // SpriteKit's hit-testing is concerned - otherwise this test would
        // pass for the wrong reason and the regression could walk straight
        // back in.
        XCTAssertTrue(
            group.calculateAccumulatedFrame().contains(gapPoint),
            "precondition: the grouping node's accumulated frame must span the gap point"
        )

        let worldNode = makeHitTestableNode(at: gapPoint)
        scene.worldLayer.addChild(worldNode)

        XCTAssertTrue(
            scene.routeTouch(at: gapPoint) === worldNode,
            "a UI group that paints nothing at the touch point must let the touch fall through to the world"
        )
    }

    /// The other half of the rule above: skipping the group must not skip
    /// the group's own children. A touch that lands *on* a grouped element
    /// still routes to that element (this is how the HUD's pulse button
    /// keeps working while its parent `HUDLayer` is transparent to routing).
    func test_touchOnAGroupedChild_stillRoutesToThatChild() {
        let scene = makeScene()
        let childPoint = CGPoint(x: 360, y: 760)

        let group = SKNode()
        let child = makeHitTestableNode(at: childPoint)
        group.addChild(makeHitTestableNode(at: CGPoint(x: 40, y: 40)))
        group.addChild(child)
        scene.uiLayer.addChild(group)

        let worldNode = makeHitTestableNode(at: childPoint)
        scene.worldLayer.addChild(worldNode)

        let hit = scene.routeTouch(at: childPoint)

        XCTAssertTrue(hit === child, "a touch on a grouped UI element must route to that element")
        XCTAssertFalse(hit === worldNode, "UI-first routing still wins wherever the UI actually paints")
    }

    /// A painted UI node underneath a grouping node must still win, rather
    /// than the touch falling through to the world: the group is skipped,
    /// not treated as an opaque lid. This is what keeps `DeathScreenNode`'s
    /// RUN AGAIN button reachable while the HUD - mounted but hidden
    /// outside a run - overlaps it.
    func test_paintedUINodeUnderAGroupingNode_stillWinsOverTheWorld() {
        let scene = makeScene()
        let point = CGPoint(x: 200, y: 400)

        let worldNode = makeHitTestableNode(at: point)
        scene.worldLayer.addChild(worldNode)

        let uiNode = makeHitTestableNode(at: point)
        scene.uiLayer.addChild(uiNode)

        // Added last, so this group is the frontmost node over the point.
        let group = SKNode()
        group.addChild(makeHitTestableNode(at: CGPoint(x: 40, y: 40)))
        group.addChild(makeHitTestableNode(at: CGPoint(x: 360, y: 760)))
        scene.uiLayer.addChild(group)

        let hit = scene.routeTouch(at: point)

        XCTAssertTrue(hit === uiNode, "a painted UI node shadowed by a grouping node must still take the touch")
        XCTAssertFalse(hit === worldNode, "the touch must not fall through past painted UI content")
    }

    /// A node the player cannot see must not capture their touch. Stated
    /// directly rather than left to SpriteKit's own hit-testing, because
    /// the HUD stays *mounted* over the menu / death / high-scores screens
    /// and is only hidden.
    func test_hiddenUINode_doesNotCaptureATouch() {
        let scene = makeScene()
        let point = CGPoint(x: 200, y: 400)

        let hiddenUINode = makeHitTestableNode(at: point)
        hiddenUINode.isHidden = true
        scene.uiLayer.addChild(hiddenUINode)

        let worldNode = makeHitTestableNode(at: point)
        scene.worldLayer.addChild(worldNode)

        XCTAssertTrue(
            scene.routeTouch(at: point) === worldNode,
            "a hidden UI node must not swallow a touch over live world content"
        )
    }
}
