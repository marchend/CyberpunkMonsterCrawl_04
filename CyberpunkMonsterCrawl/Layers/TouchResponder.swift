import SpriteKit

/// A node (or node-owning object) that consumes a touch `GameScene` routed
/// to it.
///
/// **The scene is the sole touch dispatcher.** No node in the scene graph
/// may set `isUserInteractionEnabled = true`: UIKit delivers a touch to such
/// a node *before* `SKScene.touchesBegan(_:with:)` runs, which bypasses
/// `GameScene.routeTouch(at:)` and therefore bypasses the UI-first ordering
/// this feature exists to guarantee. Conforming to `TouchResponder` is the
/// only supported way to react to a touch;
/// `GameScene.nodesBypassingSceneTouchDispatch()` audits the graph for
/// violations and `GameScene.enforceSceneInvariants()` reports them in every
/// build configuration - `assert` in DEBUG, a non-fatal `os.Logger` fault in
/// Release (`CYBERPUN-17-4-t6`).
///
/// Because `SKNode.atPoint(_:)` returns the *deepest* descendant under a
/// point (for a button, that is usually its label rather than the button
/// itself), `GameScene` walks up from the hit node to the nearest ancestor
/// conforming to this protocol before delivering.
protocol TouchResponder: AnyObject {
    /// Called by `GameScene` when this responder is the nearest responder at
    /// or above the node UI-first routing selected for a touch.
    func handleTouch()
}
