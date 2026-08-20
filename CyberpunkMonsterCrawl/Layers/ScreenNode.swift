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
/// `MenuScreenNode`, `GameplayScreenNode`, `DeathScreenNode` and
/// `HighScoresScreenNode` are the concrete conformers, registered by
/// `GameViewController` for their respective `GameState`s.
/// `PlaceholderScreenNode` below stands in for a screen in
/// `GameSceneScreenSwitchingTests`, independent of the concrete screens.
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

/// The vertical stacking both content screens (`DeathScreenNode`,
/// `HighScoresScreenNode`) lay themselves out with, shared rather than
/// restated so the two cannot drift apart.
///
/// The naive "even-space every item across the available height" scheme it
/// replaces ignored each item's own height, which is fine for a column of
/// identically-short labels and wrong the moment a 64pt button joins them:
/// on an 852x393 landscape, eleven evenly spaced items leave ~32.7pt
/// between centres, so a 64pt-tall (72pt with its accent frame) RUN AGAIN
/// and a 48pt BACK TO MENU overlapped by ~23pt -- and overlapping
/// `ButtonNode`s also make `GameScene.routeTouch(at:)`'s `atPoint(_:)`
/// result ambiguous in the shared region, so part of the lower button was
/// not reliably tappable.
///
/// Instead the tall items get a reserved, height-aware block pinned to the
/// bottom, and the flexible items (title + rows) even-space across whatever
/// remains above it: the buttons keep their real geometry in every
/// orientation, and it is the rows -- which have slack -- that compress.
enum ScreenStackLayout {

    /// Gap left between two stacked pinned items, and between the pinned
    /// block and the flexible items above it.
    static let pinnedSpacing: CGFloat = 12

    /// - Parameters:
    ///   - flexibleItems: laid out top-down, evenly spaced across the space
    ///     left over above the pinned block. Positioned by centre, so short
    ///     labels are what absorbs a cramped height.
    ///   - pinnedToBottom: laid out bottom-up in reverse order (the last
    ///     element sits lowest), each reserving its own
    ///     `calculateAccumulatedFrame().height` -- the accumulated frame,
    ///     not the plate size, so a `ButtonNode`'s accent frame counts.
    ///   - topLimit: safe-area-adjusted top edge, in the screen node's own
    ///     (origin-centred) coordinate space.
    ///   - bottomLimit: safe-area-adjusted bottom edge.
    static func position(
        flexibleItems: [SKNode],
        pinnedToBottom: [SKNode],
        topLimit: CGFloat,
        bottomLimit: CGFloat
    ) {
        let availableHeight = max(0, topLimit - bottomLimit)
        let margin = availableHeight * 0.06

        var pinnedBlockTop = bottomLimit + margin
        for item in pinnedToBottom.reversed() {
            let height = item.calculateAccumulatedFrame().height
            item.position = CGPoint(x: 0, y: pinnedBlockTop + height / 2)
            pinnedBlockTop += height + pinnedSpacing
        }

        let flexibleTop = topLimit - margin
        let flexibleBottom = pinnedToBottom.isEmpty ? bottomLimit + margin : pinnedBlockTop
        let flexibleHeight = max(0, flexibleTop - flexibleBottom)
        let step = flexibleItems.count > 1 ? flexibleHeight / CGFloat(flexibleItems.count - 1) : 0

        for (index, item) in flexibleItems.enumerated() {
            item.position = CGPoint(x: 0, y: flexibleTop - step * CGFloat(index))
        }
    }
}

/// Test double used only by the tests (`GameSceneScreenSwitchingTests`,
/// `LayerOrderingTests`) to prove the state-driven registry swap without any
/// real screen content. Not referenced by production code - the concrete
/// screens (`MenuScreenNode`, `GameplayScreenNode`, `DeathScreenNode`,
/// `HighScoresScreenNode`) conform to `ScreenNode` in their own right.
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
