import SpriteKit
import UIKit

/// The `SKView` subclass the app hosts `GameScene` in, so that every
/// accessible UI node publishes a **correct screen-space
/// `accessibilityFrame`**.
///
/// ## The bug this exists to fix
///
/// `ButtonNode` already sets `isAccessibilityElement`, `accessibilityLabel`
/// and `.button` traits on the `SKNode` itself, and a *finger* tap on a
/// button's visible pixels has always worked: UIKit hands the touch to
/// `GameScene.touchesBegan(_:with:)`, which routes it UI-first through
/// `routeTouch(at:)` and delivers it to the button's `TouchResponder`.
///
/// What did **not** work is a tap driven by *accessibility element* - the way
/// XCUITest and the scripted runtime probe drive one. Such a driver resolves
/// an element's hittable point from its `accessibilityFrame`, and nothing in
/// this codebase computed one: SpriteKit's implicit `SKNode` accessibility
/// support has to derive a screen-space frame on its own, and it does not
/// resolve one correctly for a node sitting under a camera transform - which
/// every button does, because `GameScene.uiLayer` is parented to `cameraNode`
/// precisely so the UI stays camera-locked. The synthesized touch therefore
/// landed somewhere that was not the button, `touchesBegan(_:with:)` never
/// saw it, `stateMachine.transition(to: .gameplay)` never fired, and the
/// probe reported "tapped PLAY, screen stayed on the menu".
///
/// That is the "reachable in code review, unreachable by the actual driver"
/// trap in its purest form: the state machine, the screen registry, the
/// `onPlay` wiring and `startGroundPlane()` were all correct, and every unit
/// test stayed green throughout - because the tests call
/// `dispatchTouch(atScenePoint:)` directly and so never go anywhere near an
/// accessibility frame.
///
/// ## The fix
///
/// Publish the elements ourselves, with frames computed through the *same*
/// coordinate path `routeTouch(at:)` trusts for real touches:
///
/// 1. `GameScene.accessibilityFrameInScene(for:)` - the node's accumulated
///    frame converted up to scene space, which is the algebraic inverse of
///    the `uiLayer.convert(_:from: self)` + `atPoint(_:)` walk the scene
///    hit-tests with.
/// 2. `SKView.convert(_:from:)` - scene space to view space, the inverse of
///    the conversion SpriteKit uses to give `UITouch.location(in:)` its
///    value (and camera-aware, which is the step SpriteKit's implicit support
///    gets wrong).
/// 3. `convert(_:to: nil)` - view space to window space, the space
///    `accessibilityFrame` is documented in.
///
/// Because the published frame is derived from the inverse of the hit test,
/// an element-driven tap and the scene's own routing cannot disagree.
/// `AccessibleSKViewTests` pins that agreement directly - it is the real
/// regression guard, and it fails the moment the two paths drift apart
/// again.
///
/// Elements are rebuilt on every query rather than cached, so a screen swap
/// (`GameScene.transitionScreens(to:)`), a rotation (`didChangeSize(_:)`) or
/// a camera move can never leave a stale frame behind - a stale frame is the
/// same defect wearing a different hat.
final class AccessibleSKView: SKView {

    // MARK: - UIAccessibilityContainer

    /// The modern container hook, and the one XCUITest's snapshotting reads.
    ///
    /// Falls back to `super` when there is nothing of ours to publish (no
    /// `GameScene` presented yet, or an empty `uiLayer`) rather than
    /// returning an empty array, so a state this class does not understand
    /// leaves SpriteKit's own accessibility behaviour intact instead of
    /// blanking the tree.
    override var accessibilityElements: [Any]? {
        get {
            if let elements = publishedAccessibilityElements() {
                return elements
            }
            return super.accessibilityElements
        }
        set { super.accessibilityElements = newValue }
    }

    /// Overridden alongside `accessibilityElements` deliberately. `SKView`
    /// ships its own container implementation, and UIKit is free to reach for
    /// either the array above or this older count/index triplet; answering
    /// both from one source removes any question of which one wins - and with
    /// it the risk that this whole class ends up dead code because UIKit took
    /// the other branch.
    override func accessibilityElementCount() -> Int {
        guard let elements = publishedAccessibilityElements() else {
            return super.accessibilityElementCount()
        }
        return elements.count
    }

    override func accessibilityElement(at index: Int) -> Any? {
        guard let elements = publishedAccessibilityElements() else {
            return super.accessibilityElement(at: index)
        }
        guard elements.indices.contains(index) else { return nil }
        return elements[index]
    }

    override func index(ofAccessibilityElement element: Any) -> Int {
        guard let elements = publishedAccessibilityElements() else {
            return super.index(ofAccessibilityElement: element)
        }
        guard let candidate = element as? UIAccessibilityElement else { return NSNotFound }

        // Identity first, then identifier/label: the elements are rebuilt on
        // every query (see the class comment on why they are not cached), so
        // UIKit may hand back an instance produced by an earlier rebuild.
        // Matching on the stable identity the *node* supplies keeps VoiceOver
        // focus from being lost across a rebuild.
        let match = elements.firstIndex { published in
            if published === candidate { return true }
            if let identifier = published.accessibilityIdentifier,
               identifier == candidate.accessibilityIdentifier {
                return true
            }
            if let label = published.accessibilityLabel, label == candidate.accessibilityLabel {
                return true
            }
            return false
        }
        return match ?? NSNotFound
    }

    // MARK: - Element construction

    /// One `UIAccessibilityElement` per accessible node in the presented
    /// `GameScene`'s `uiLayer`, or `nil` when there is nothing to publish.
    ///
    /// Internal (not private) so `AccessibleSKViewTests` can assert on the
    /// published identifiers, labels, traits and frame sizes without a
    /// window or a live accessibility client.
    func publishedAccessibilityElements() -> [UIAccessibilityElement]? {
        guard let gameScene = scene as? GameScene, gameScene.view === self else { return nil }

        let elements: [UIAccessibilityElement] = gameScene.accessibleUINodes().compactMap { node in
            guard let sceneFrame = gameScene.accessibilityFrameInScene(for: node) else { return nil }
            let element = UIAccessibilityElement(accessibilityContainer: self)
            element.accessibilityFrame = self.windowFrame(forSceneRect: sceneFrame, in: gameScene)
            element.accessibilityIdentifier = node.accessibilityIdentifier
            element.accessibilityLabel = node.accessibilityLabel
            element.accessibilityTraits = node.accessibilityTraits
            return element
        }
        return elements.isEmpty ? nil : elements
    }

    /// Converts `sceneRect` (scene coordinates, y-up, origin bottom-left)
    /// into window coordinates (y-down, origin top-left) - the space
    /// `accessibilityFrame` is defined in.
    ///
    /// Internal so the conversion can be exercised directly by tests.
    func windowFrame(forSceneRect sceneRect: CGRect, in scene: SKScene) -> CGRect {
        // Two opposite corners rather than origin + size, because the
        // scene-to-view step flips the y axis: taking min/abs afterwards
        // rebuilds a well-formed rect whichever way round they land.
        let first = convert(CGPoint(x: sceneRect.minX, y: sceneRect.minY), from: scene)
        let second = convert(CGPoint(x: sceneRect.maxX, y: sceneRect.maxY), from: scene)
        let viewRect = CGRect(
            x: min(first.x, second.x),
            y: min(first.y, second.y),
            width: abs(second.x - first.x),
            height: abs(second.y - first.y)
        )
        return convert(viewRect, to: nil)
    }
}
