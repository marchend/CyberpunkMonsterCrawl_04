import SpriteKit
import UIKit

/// Skeleton `.gameplay` screen.
///
/// CYBERPUN-17-2's own scope explicitly excludes "final HUD content" (see
/// the story's "Out of scope" section) \u2014 real gameplay content (world
/// rendering, the player actor, the raccoon swarm, auto-fire/XP HUD) lands
/// across CYBERPUN-17-3 through CYBERPUN-17-9. This screen exists purely so
/// `.gameplay` has a mounted, observable `ScreenNode` today: tapping PLAY on
/// the menu visibly lands somewhere real instead of an empty `uiLayer`.
///
/// **Deliberately mounts no full-bleed backdrop.** The menu / death /
/// high-scores screens each carry an opaque, scene-sized `SKSpriteNode`
/// precisely because they are meant to hide the world behind them; the
/// gameplay screen is the one screen the world must show *through*. `node`
/// is mounted in `GameScene.uiLayer`, and `routeTouch(at:)` returns any
/// non-`uiLayer` hit under `uiLayer` before it ever looks at `worldLayer`,
/// so a backdrop that blankets the viewport here would (a) make every point
/// on screen hit an inert sprite, so untouched events could no longer fall
/// through to the world (AC4), and (b) paint over `worldLayer` the moment
/// CYBERPUN-17-3+ renders anything into it. The scene's own
/// `backgroundColor` supplies the dark "Pixel Grit" base instead, so there
/// is no lighter SpriteKit default showing through.
/// `TouchRoutingTests.test_mountedGameplayScreen_doesNotBlockWorldTouches`
/// pins the fall-through against a real, laid-out instance of this screen.
///
/// // SCAFFOLDING(CYBERPUN-17-7): the placeholder label and the container
/// marker below are temporary. CYBERPUN-17-7 ("Wire the floating thumbstick,
/// player movement, building collision and camera") adds the first real HUD
/// content this screen gains and should replace this placeholder wholesale.
final class GameplayScreenNode: ScreenNode {

    let node = SKNode()

    // SCAFFOLDING(CYBERPUN-17-7): placeholder label only; no real HUD yet.
    private let placeholderLabel = SKLabelNode(text: "GAMEPLAY \u{2014} WORLD COMING SOON")

    /// Non-visual accessibility anchor identifying "gameplay is mounted",
    /// so a UI test can assert the PLAY -> gameplay transition landed
    /// somewhere real instead of only observing the menu disappear.
    ///
    /// // SCAFFOLDING(CYBERPUN-17-7): this marker is a diagnostic hook, not a
    /// durable accessibility contract \u2014 it exists only because the skeleton
    /// screen has no real content for `CyberpunkMonsterCrawlUITests` to
    /// assert against yet. CYBERPUN-17-7 replaces the placeholder wholesale
    /// and should delete this marker and re-point the UI test's assertion at
    /// real HUD content rather than keeping the marker alive to satisfy it.
    private let containerMarker = SKNode()

    init() {
        placeholderLabel.fontName = "Menlo-Bold"
        placeholderLabel.fontSize = 18
        placeholderLabel.fontColor = PixelGritPalette.neonSecondary
        placeholderLabel.verticalAlignmentMode = .center
        placeholderLabel.horizontalAlignmentMode = .center

        containerMarker.name = "gameplayScreen.container"
        containerMarker.isAccessibilityElement = true
        containerMarker.accessibilityIdentifier = "gameplay.container"
        containerMarker.accessibilityLabel = "Gameplay"

        node.name = "gameplayScreen"
        node.addChild(containerMarker)
        node.addChild(placeholderLabel)
    }

    func willEnter() {}

    func willExit() {}

    func layout(for size: CGSize, safeAreaInsets: UIEdgeInsets) {
        placeholderLabel.position = CGPoint(x: 0, y: (safeAreaInsets.bottom - safeAreaInsets.top) / 2)
    }
}
