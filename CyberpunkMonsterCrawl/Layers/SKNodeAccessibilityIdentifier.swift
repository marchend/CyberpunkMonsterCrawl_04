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
/// **Scope: this is Swift-side bookkeeping only, and XCUITest cannot see
/// it.** The value lives in an associated object on the `SKNode`; it never
/// reaches the accessibility element `SKView` synthesises for the node, so
/// UIKit's accessibility system does not report it and an XCUITest
/// subscript query like `app.descendants(matching: .any)["gameplay.container"]`
/// can **never** match a value set here. Only the properties SpriteKit
/// genuinely forwards - `isAccessibilityElement`, `accessibilityLabel`,
/// `accessibilityHint`, `accessibilityTraits` - are visible to XCUITest.
///
/// Consequences, so nobody re-learns this the hard way:
/// - **A UI test must match on `accessibilityLabel`, not on an identifier
///   set through this extension.** `ButtonNode` sets both (`accessibilityLabel
///   = title`), which is why `app.descendants(matching: .any)["PLAY"]`
///   resolves; the screen container markers in `MenuScreenNode` /
///   `GameplayScreenNode` likewise carry `accessibilityLabel` values
///   ("Menu" / "Gameplay") for exactly this reason, and
///   `CyberpunkMonsterCrawlUITests` queries those labels.
/// - A unit-test assertion on `node.accessibilityIdentifier` only proves
///   this extension stored and returned a string. It is a bookkeeping
///   assertion, not evidence that anything is reachable from a UI test, so
///   pair it with an `accessibilityLabel` assertion when the value is meant
///   to be externally observable.
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
