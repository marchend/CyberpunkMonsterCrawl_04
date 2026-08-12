import ObjectiveC
import SpriteKit

/// `SKNode` exposes `isAccessibilityElement`, `accessibilityLabel`,
/// `accessibilityHint`, etc. (SpriteKit added real UIAccessibility
/// forwarding for these starting iOS 15), but it does **not** expose
/// `accessibilityIdentifier` \u2014 that property belongs to
/// `UIAccessibilityIdentification`, which `SKNode` never adopts. Several
/// screens (`ButtonNode`, `MenuScreenNode`, `GameplayScreenNode`, ...) were
/// written assuming it existed and fail to compile without it.
///
/// This extension backs the property with an associated object so those
/// call sites \u2014 and the unit tests that assert against
/// `node.accessibilityIdentifier` \u2014 keep working. It is a Swift-side
/// bookkeeping value only; it does not (and cannot) change what UIKit's
/// real accessibility system reports for a non-`UIView` node.
extension SKNode {

    private static var accessibilityIdentifierAssociationKey: UInt8 = 0

    var accessibilityIdentifier: String? {
        get {
            objc_getAssociatedObject(self, &Self.accessibilityIdentifierAssociationKey) as? String
        }
        set {
            objc_setAssociatedObject(
                self,
                &Self.accessibilityIdentifierAssociationKey,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
}
