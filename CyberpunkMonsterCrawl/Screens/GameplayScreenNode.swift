import SpriteKit
import UIKit

/// Skeleton `.gameplay` screen: an accessibility anchor over live world
/// content, and no content of its own.
///
/// CYBERPUN-17-2's own scope explicitly excludes "final HUD content" (see
/// the story's "Out of scope" section) - the real in-run HUD lands with
/// CYBERPUN-17-7 (floating thumbstick) and CYBERPUN-17-12 (the in-run HUD).
/// What the player actually sees on entry to `.gameplay` is the *world*:
/// `GameScene.updateWorldContent(for:)` starts the streamed ground plane
/// with its building and rooftop-sign nodes (CYBERPUN-17-5) and mounts the
/// player actor (CYBERPUN-17-6) into `worldLayer`.
///
/// **This screen therefore mounts no text of its own.** It used to carry a
/// neon "GAMEPLAY - WORLD COMING SOON" placeholder label, from the days when
/// `worldLayer` was genuinely empty on entry. Now that the city and the
/// player really do render, a label announcing "no world here yet" sits on
/// top of the very content it denies - which reads as "feature not
/// delivered" to anyone (or any screenshot-driven verification) looking at
/// the screen, however correct the rendering behind it is. It was removed in
/// CYBERPUN-17-5-t4; `ScreensTests.test_gameplayScreenNode_mountsNoComingSoonText`
/// pins the removal so it cannot creep back in.
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
/// // SCAFFOLDING(CYBERPUN-17-7): the container marker below is temporary.
/// CYBERPUN-17-7 ("Wire the floating thumbstick, player movement, building
/// collision and camera") adds the first real HUD content this screen gains
/// and should delete the marker then (see the marker's own comment).
final class GameplayScreenNode: ScreenNode {

    let node = SKNode()

    /// Non-visual accessibility anchor identifying "gameplay is mounted",
    /// so a UI test can assert the PLAY -> gameplay transition landed
    /// somewhere real instead of only observing the menu disappear.
    ///
    /// // SCAFFOLDING(CYBERPUN-17-7): this marker is a diagnostic hook, not a
    /// durable accessibility contract - it exists only because the skeleton
    /// screen mounts no HUD content of its own for
    /// `CyberpunkMonsterCrawlUITests` to assert against yet. CYBERPUN-17-7
    /// adds the first real HUD content and should delete this marker then,
    /// re-pointing the UI test's assertion at that content rather than
    /// keeping the marker alive to satisfy it.
    private let containerMarker = SKNode()

    init() {
        containerMarker.name = "gameplayScreen.container"
        containerMarker.isAccessibilityElement = true
        containerMarker.accessibilityIdentifier = "gameplay.container"
        containerMarker.accessibilityLabel = "Gameplay"

        node.name = "gameplayScreen"
        node.addChild(containerMarker)
    }

    func willEnter() {}

    func willExit() {}

    /// Intentionally a no-op: the only thing mounted here is the non-visual
    /// `containerMarker`, which is positioned at the screen's origin and has
    /// nothing to re-lay out. The requirement stays satisfied by having no
    /// size-dependent content at all rather than by re-deriving positions,
    /// so rotation (AC5) cannot clip or strand anything on this screen. The
    /// real HUD content CYBERPUN-17-7 / CYBERPUN-17-12 add will need a real
    /// implementation here.
    func layout(for size: CGSize, safeAreaInsets: UIEdgeInsets) {}
}
