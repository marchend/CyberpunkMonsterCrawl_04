import SpriteKit

/// A `uiLayer` node that publishes **nothing** to UIAccessibility -- not
/// itself, and not any descendant of it.
///
/// `GameScene.accessibleUINodes()`'s walk skips a conformer's whole subtree
/// outright. That is the mirror image of the rule that walk already applies
/// in the other direction: a node with `isAccessibilityElement == true` is a
/// *leaf* whose subtree collapses into the one element. Conform a passive
/// read-out -- one that draws text or sprites but has no activation of its
/// own -- so nothing inside it can ever be published.
///
/// **Why the per-node `isAccessibilityElement = false` opt-out is not
/// enough on its own.** `CYBERPUN-17-12` PR 2 first tried exactly that: the
/// five passive HUD elements *and* every drawn child of theirs set the flag
/// to `false` explicitly. Measured, that did not hold -- with those
/// assignments in place,
/// `AccessibleSKViewTests.test_duringARun_theHUDPublishesOnlyItsPulseButton`
/// still found the three *visible* `SKLabelNode`s (the level/XP bar's
/// `LV` caption, the run clock, the kill count) published during a real
/// run, while the plates/segments/fill `SKSpriteNode`s stayed unpublished.
/// The banner's label escaped only because the banner is invisible for most
/// of a run, so the visibility filter masked it. In other words SpriteKit's
/// own implicit element-ness for a label node wins over an explicit `false`
/// -- each of those labels also has its `text` re-set after `init` by its
/// own `update(...)`, which is the likeliest moment the value is
/// re-derived, but that mechanism is *not* verified here and nothing in
/// this design rests on it.
///
/// A subtree rule does not care which of those it is: the walk never
/// consults a descendant's flag at all, so no per-class default and no
/// later mutation can reintroduce a published element inside a conformer.
/// That matters because `AccessibleSKView` publishes one real, interactive
/// `SceneAccessibilityMirrorView` per published node, and a mirror wins
/// UIKit's hit test for its rect while forwarding only the `.began` phase
/// into `dispatchTouch(atScenePoint:)` -- never `beginTouch(at:)`. The HP
/// and level/XP bars sit inside `FloatingThumbstickNode.leftRegion`, the
/// floating stick's touch-acceptance box, which `HUDThumbstickOverlapTests`
/// documents passive read-outs as being *allowed* to occupy precisely so no
/// dead input patch appears there; a mirror over a 220x28 bar is exactly
/// the dead patch that allowance exists to prevent.
///
/// Conforming does not change anything about touch routing: a passive
/// read-out is not a `TouchResponder`, so `routeTouch(at:)` already walks
/// past it to whatever painted UI or world content is underneath.
protocol AccessibilityOpaqueNode: AnyObject {}
