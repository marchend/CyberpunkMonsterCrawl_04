import SpriteKit
import UIKit

/// A screen `GameScene` swaps into `uiLayer` per `GameState`.
///
/// `node` is the root `SKNode` `GameScene` adds to / removes from `uiLayer`
/// on activation/deactivation \u2014 a plain property (rather than constraining
/// the protocol itself to `SKNode`) so a conforming type is free to be an
/// `SKNode` subclass whose `node` is `self`, or a plain coordinating object
/// that owns/builds its root node however it likes.
///
/// Concrete real screens (menu / gameplay HUD / death / high scores) land in
/// PR 3, which registers them with `GameScene.register(_:for:)`. This PR
/// ships only the contract and `PlaceholderScreenNode`, the test double
/// `GameSceneScreenSwitchingTests` uses to exercise the registry swap logic
/// without any real screen content.
protocol ScreenNode: AnyObject {
    /// The root node `GameScene` mounts under `uiLayer` while this screen is
    /// active.
    var node: SKNode { get }

    /// Called after `node` has been added to `uiLayer` and this screen has
    /// become the active screen (including the very first activation, which
    /// has no prior `willExit()`).
    func willEnter()

    /// Called on the outgoing screen, while `node` is still mounted in
    /// `uiLayer`, immediately before `GameScene` removes it as part of a
    /// swap.
    func willExit()

    /// Recompute this screen's layout for the given scene size / safe-area
    /// insets. Called once on activation and again on every
    /// `GameScene.didChangeSize(_:)`, so rotation support exists at the
    /// architecture level even though no concrete screen consumes it yet.
    func layout(for size: CGSize, safeAreaInsets: UIEdgeInsets)
}

/// Test double used only by this PR's tests
/// (`GameSceneScreenSwitchingTests`, `LayerOrderingTests`) to prove the
/// state-driven registry swap without any real screen content. Not
/// referenced by production code \u2014 concrete screens (PR 3) are their own
/// `SKNode` subclasses conforming to `ScreenNode` in their own right.
final class PlaceholderScreenNode: ScreenNode {
    /// Identifies which registered slot this double stands in for, purely
    /// to make test failure messages readable.
    let label: String

    let node: SKNode = SKNode()

    private(set) var enterCount = 0
    private(set) var exitCount = 0
    private(set) var lastLayoutSize: CGSize?
    private(set) var lastLayoutSafeAreaInsets: UIEdgeInsets?

    init(label: String) {
        self.label = label
    }

    func willEnter() {
        enterCount += 1
    }

    func willExit() {
        exitCount += 1
    }

    func layout(for size: CGSize, safeAreaInsets: UIEdgeInsets) {
        lastLayoutSize = size
        lastLayoutSafeAreaInsets = safeAreaInsets
    }
}
