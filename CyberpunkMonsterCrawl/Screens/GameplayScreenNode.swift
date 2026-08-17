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
/// pins the removal by wording and
/// `ScreensTests.test_gameplayScreenNode_mountsOnlyTheContainerMarker_andNoTextAnywhere`
/// pins it structurally (exactly one child, no text anywhere in the
/// subtree), so neither the original label nor a reworded one can creep back
/// in. The wording gate is the durable invariant and must survive
/// CYBERPUN-17-7; the structural one is expected to be rewritten when real
/// HUD content lands.
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
/// // SCAFFOLDING(CYBERPUN-17-7): the container marker below is temporary,
/// and after CYBERPUN-17-5-t4 removed the placeholder label it is the *only*
/// scaffolding artifact left on this screen. CYBERPUN-17-7 ("Wire the
/// floating thumbstick, player movement, building collision and camera")
/// owns its removal.
///
/// **Status at head: the trigger has fired and the marker is still here.**
/// 17-7 has shipped the first in-run control (`GameScene.thumbstick`,
/// mounted in `uiLayer` and shown while `isRunActive`), so the condition
/// above is met. It is not a legal re-point target, though:
/// `FloatingThumbstickNode` deliberately sets `isAccessibilityElement =
/// false`, and no other durable in-run content exists until the HUD lands
/// with CYBERPUN-17-12. Deleting the marker today would therefore mean
/// deleting the two assertions below rather than re-pointing them, which
/// trades scaffolding for lost coverage of "PLAY landed on a real screen".
/// So the removal is recorded as **outstanding, not done and not dropped**:
/// the literal tags above and below stay greppable, and the removal is
/// tracked on the CYBERPUN-17-7 story, requested as a follow-up on this
/// PR's task (`CYBERPUN-17-7-t4`) rather than given an invented ticket ID
/// here -- the same convention `PlayerMovementController` and
/// `GameScene.spawnTilePosition()` follow. Whoever mounts durable HUD
/// content (CYBERPUN-17-12 at the latest) deletes the marker with it.
///
/// Deleting the marker alone turns two green assertions red, so 17-7's
/// definition of done is "delete the marker **and** re-point both
/// assertions" - see the marker's own comment for the pair. Removing the
/// node without them makes keeping the marker the path of least resistance,
/// which is exactly how scaffolding outlives the ticket meant to delete it.
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
    /// owns deleting this marker and re-pointing the assertions below at
    /// real content rather than keeping the marker alive to satisfy them.
    /// That removal has **not** happened yet: 17-7 shipped the thumbstick,
    /// but it sets `isAccessibilityElement = false` on purpose, so there is
    /// no durable re-point target until the HUD lands (CYBERPUN-17-12) --
    /// see this type's own doc comment above for the full status note.
    ///
    /// Two green assertions currently require this node to *exist*, and both
    /// are part of 17-7's definition of done, not just the node itself:
    ///
    /// 1. `ScreensTests.test_gameplayScreenNode_exposesAContainerAccessibilityAnchor`
    ///    (asserts the marker is an accessibility element labelled
    ///    "Gameplay"), and
    /// 2. `CyberpunkMonsterCrawlUITests.test_launchesIntoMenu_withAHittablePlayButton_thatStartsARun`,
    ///    which waits on `app.descendants(matching: .any)["Gameplay"]` to
    ///    prove PLAY landed on a real screen.
    ///
    /// A test that asserts a scaffolding node's presence is the usual
    /// mechanism by which scaffolding outlives its ticket: deleting the
    /// marker turns both red, so the cheap move in 17-7 is to keep it.
    /// Delete the marker and re-point both assertions at real HUD content
    /// together. Note this is *not* true of the no-text gates
    /// (`mountsNoComingSoonText` in particular): those pin a
    /// CYBERPUN-17-5-t4 invariant that must survive 17-7, not the marker.
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
