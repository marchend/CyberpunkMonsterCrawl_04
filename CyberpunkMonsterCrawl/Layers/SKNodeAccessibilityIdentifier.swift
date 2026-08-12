import ObjectiveC
import SpriteKit

/// A stable, immutable key for the associated object backing
/// `SKNode.accessibilityIdentifier`.
///
/// Associated-object keys are only ever compared by pointer value - the
/// runtime never dereferences them - so any distinct, process-stable
/// address works. The previous form took `&someStaticVar` on a `private
/// static var`, which relies on the address of a *mutable* static being
/// stable (Swift does not guarantee that, and it is a `static var`
/// data-race diagnostic under the Swift 6 language mode). A single
/// immutable pointer constant has neither problem.
private enum AccessibilityIdentifierAssociation {
    /// Any non-zero constant works; a distinctive one keeps the key from
    /// colliding with other code that reaches for the same trick.
    static let key = UnsafeRawPointer(bitPattern: 0x434D_4341)!
}

/// `SKNode` exposes `isAccessibilityElement`, `accessibilityLabel`,
/// `accessibilityHint`, etc. (SpriteKit added real UIAccessibility
/// forwarding for these starting iOS 15), but it does **not** expose
/// `accessibilityIdentifier` - that property belongs to
/// `UIAccessibilityIdentification`, which `SKNode` never adopts. Several
/// screens (`ButtonNode`, `MenuScreenNode`, `GameplayScreenNode`, ...) were
/// written assuming it existed and fail to compile without it.
///
/// **Scope: storing a value here is Swift-side bookkeeping. It becomes
/// visible to XCUITest only because `AccessibleSKView` deliberately carries
/// it across.** The value lives in an associated object on the `SKNode`, and
/// it never reaches the accessibility element SpriteKit synthesises on its
/// own - of the node's accessibility properties, only the ones SpriteKit
/// genuinely forwards (`isAccessibilityElement`, `accessibilityLabel`,
/// `accessibilityHint`, `accessibilityTraits`) travel that route.
///
/// What closes the gap is `AccessibleSKView.publishedAccessibilityElements()`,
/// which builds the `UIAccessibilityElement`s itself and copies
/// `node.accessibilityIdentifier` onto each one. That is what makes an
/// XCUITest subscript query like
/// `app.descendants(matching: .any)["menu.playButton"]` resolve, and
/// `AppLaunchAndRotationUITests` relies on exactly that.
///
/// Consequences, so nobody re-learns this the hard way:
/// - **The reach of an identifier is conditional, not universal.** It is
///   visible to a driver only while the node lives under `GameScene.uiLayer`
///   in a scene hosted by an `AccessibleSKView` - that is the only subtree
///   the view walks. A `worldLayer`/`effectsLayer` node's identifier is
///   still invisible to XCUITest, so a UI test must not query one.
/// - `accessibilityLabel` remains the belt-and-braces match, and setting
///   both stays the house style. `ButtonNode` sets `accessibilityLabel =
///   title`, which is why `app.descendants(matching: .any)["PLAY"]` also
///   resolves; the screen container markers in `MenuScreenNode` /
///   `GameplayScreenNode` likewise carry `accessibilityLabel` values
///   ("Menu" / "Gameplay").
/// - A unit-test assertion on `node.accessibilityIdentifier` still only
///   proves this extension stored and returned a string. Evidence that the
///   value is reachable by a driver comes from `AccessibleSKViewTests`
///   asserting on `publishedAccessibilityElements()`, so pin it there when
///   the value is meant to be externally observable.
/// - If `AccessibleSKView` is ever swapped back out for a plain `SKView`,
///   every identifier-based UI-test query goes dark again. That swap is
///   guarded by `GameViewControllerCompositionTests`.
///
/// Kept because the call sites above (and their unit tests) depend on the
/// property existing. If SpriteKit ever adopts
/// `UIAccessibilityIdentification`, delete this file and the notes above
/// with it.
extension SKNode {

    var accessibilityIdentifier: String? {
        get {
            objc_getAssociatedObject(self, AccessibilityIdentifierAssociation.key) as? String
        }
        set {
            objc_setAssociatedObject(
                self,
                AccessibilityIdentifierAssociation.key,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
}
