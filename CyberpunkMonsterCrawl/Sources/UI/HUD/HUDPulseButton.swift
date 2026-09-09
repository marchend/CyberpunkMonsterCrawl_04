import CoreGraphics
import SpriteKit
import UIKit

/// The HUD's cooldown button for the player-triggered pulse ability.
///
/// **Naming note.** This type is `HUDPulseButton`, distinct from
/// `Sources/UI/PulseButton.swift`'s `final class PulseButton`, which is a
/// **live, wired production dependency** of `GameScene` (`CYBERPUN-17-10`'s
/// bottom-left ability button -- see that file's doc comment and
/// `GameScene.pulseButton`). Two top-level types named `PulseButton` in the
/// same module would be a compile error, and this PR's own scope is
/// explicitly "no scene wiring, no composition root" -- it cannot retire the
/// old type's production call sites (that is a later PR's job, once the
/// rest of this HUD is wired in). Reusing the class name here would either
/// fail to compile or silently require touching `GameScene`, both outside
/// this PR's stated scope, so this HUD element is named distinctly instead.
/// This file is likewise named `HUDPulseButton.swift` (matching the type),
/// not `PulseButton.swift` -- Swift's module-internal file-scoped
/// declarations use the filename to disambiguate, so a target cannot
/// contain two files sharing a basename regardless of the class names
/// declared inside them. **This type is now the visible one.** PR #63's
/// review decision (`CYBERPUN-17-12` PR 2) made this button's bottom-right
/// slot -- the placement the ticket asks for, settling the old
/// bottom-left-vs-bottom-right note recorded on `CYBERPUN-17-10` -- the
/// run's only visible ability control, and `GameScene` now hides the older
/// `PulseButton` mount in every state. That older type is still
/// constructed and wired to the same `handlePulsePress()`; *deleting* it
/// once nothing references it is `CYBERPUN-17-14`'s work.
///
/// Construct + `update(cooldownFraction:isReady:)` only -- no positioning
/// logic (`HUDLayout` owns where this mounts). Conforms to `TouchResponder`
/// like every other interactive node in this codebase (`ButtonNode`, the
/// old `PulseButton`): it never sets `isUserInteractionEnabled`, so
/// `GameScene.nodesBypassingSceneTouchDispatch()` stays clean once this node
/// is actually mounted.
///
/// **Press-suppression while on cooldown.** `update(cooldownFraction:
/// isReady:)` takes `isReady` as an explicit, separate flag rather than
/// deriving "may this press emit?" from `cooldownFraction` itself, because
/// a caller may have its own reasons a fractional progress and a hard
/// ready/not-ready gate disagree (e.g. a final visual "topping off" frame
/// that should still read as not-yet-usable). `handleTouch()` invokes
/// `onPress` only while `isReady`; a press while not ready is **not**
/// silently dropped -- it plays a brief, visible "denied" feedback
/// animation (a quick scale pulse on the plate) and increments
/// `deniedPressCount`, so a caller/test can observe that the press was
/// felt without the ability itself ever firing.
///
/// **Custom hit-test / accessibility frame through the camera-pinned
/// chain.** `hitTestFrame(in:)` converts this node's own known geometry
/// (`Self.size`, centred on its local origin) into `scene`'s coordinate
/// space via `SKNode.convert(_:to:)` -- the same node-to-node conversion
/// `GameScene.routeTouch(at:)` relies on to hit-test a real touch once this
/// node is mounted under the camera-pinned `uiLayer`. That is a different
/// (and reliable) mechanism from the one `AccessibleSKView`'s doc comment
/// describes as broken: `SKNode.convert(_:to:)` walks the *real* parent
/// chain, camera included, and is exactly what a manual, explicit
/// coordinate conversion (as opposed to UIKit's *implicit*
/// `UIAccessibilityElement` vending for `SKNode`, which is the thing that
/// does not resolve a camera-parented node's frame correctly) has always
/// done correctly in this engine. `PulseButtonHitTestTests` proves the
/// agreement directly: the frame this method returns, fed back through
/// `scene.atPoint(_:)`, resolves to this same node, at more than one
/// camera position.
final class HUDPulseButton: SKNode, TouchResponder {

    // MARK: - Tunables

    static let size = HUDLayout.pulseButtonSize

    static let readyAlpha: CGFloat = 1.0
    static let cooldownAlpha: CGFloat = 0.45
    static let cooldownOverlayColor = UIColor(white: 0, alpha: 0.65)

    // MARK: - Nodes

    private let plate = SKShapeNode(circleOfRadius: HUDPulseButton.size.width / 2)
    private let icon = SKShapeNode(circleOfRadius: HUDPulseButton.size.width / 2 * 0.4)
    private let cooldownOverlay = SKShapeNode()

    // MARK: - State

    private let onPress: () -> Void

    /// `0` = no cooldown elapsed at all (just triggered), `1` = fully
    /// recovered. Starts at `1`: a fresh button reads as fully recovered.
    private(set) var cooldownFraction: CGFloat = 1.0

    /// Whether a press is currently allowed to invoke `onPress`. Starts
    /// `true`, matching `cooldownFraction`'s own "fresh button is ready"
    /// default.
    private(set) var isReady: Bool = true

    /// Count of presses received while `isReady == false` -- i.e. presses
    /// that produced feedback but never invoked `onPress`. Exposed purely
    /// for test/observation purposes.
    private(set) var deniedPressCount: Int = 0

    // MARK: - Init

    init(onPress: @escaping () -> Void) {
        self.onPress = onPress
        super.init()

        plate.fillColor = PixelGritPalette.plate
        plate.strokeColor = PixelGritPalette.neonSecondary
        plate.lineWidth = 2
        plate.name = "hudPulseButton.plate"

        icon.fillColor = PixelGritPalette.neonAccent
        icon.strokeColor = .clear
        icon.name = "hudPulseButton.icon"

        cooldownOverlay.fillColor = Self.cooldownOverlayColor
        cooldownOverlay.strokeColor = .clear
        cooldownOverlay.name = "hudPulseButton.cooldownOverlay"

        name = "hudPulseButton"
        addChild(plate)
        addChild(icon)
        addChild(cooldownOverlay)

        isAccessibilityElement = true
        accessibilityLabel = "Pulse ability"
        accessibilityIdentifier = "gameplay.hudPulseButton"
        accessibilityTraits = .button

        updateVisual()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - TouchResponder

    /// Called by `GameScene.dispatchTouch(atScenePoint:)` once this node is
    /// mounted, never by UIKit directly. Invokes `onPress` only while
    /// `isReady`; otherwise plays denied-press feedback and leaves the
    /// ability untouched.
    func handleTouch() {
        guard isReady else {
            deniedPressCount += 1
            playDeniedPressFeedback()
            return
        }
        onPress()
    }

    // MARK: - Update

    /// Sets both the cooldown fill and the ready/not-ready gate from an
    /// externally-tracked ability state, clamping `cooldownFraction` to
    /// `0...1`.
    func update(cooldownFraction: CGFloat, isReady: Bool) {
        self.cooldownFraction = min(1, max(0, cooldownFraction))
        self.isReady = isReady
        updateVisual()
    }

    // MARK: - Hit test / accessibility frame

    /// This node's own known extent (`Self.size`, centred on its local
    /// origin) converted into `scene`'s coordinate space through the real
    /// parent chain -- camera included, if this node has been mounted under
    /// one. See this type's own doc comment for why that is the same
    /// mechanism a real touch dispatch resolves through, not the mechanism
    /// `AccessibleSKView` exists to work around.
    func hitTestFrame(in scene: SKScene) -> CGRect {
        let halfWidth = Self.size.width / 2
        let halfHeight = Self.size.height / 2
        let first = convert(CGPoint(x: -halfWidth, y: -halfHeight), to: scene)
        let second = convert(CGPoint(x: halfWidth, y: halfHeight), to: scene)
        return CGRect(
            x: min(first.x, second.x),
            y: min(first.y, second.y),
            width: abs(second.x - first.x),
            height: abs(second.y - first.y)
        )
    }

    // MARK: - Visuals

    private func updateVisual() {
        alpha = isReady ? Self.readyAlpha : Self.cooldownAlpha

        guard !isReady || cooldownFraction < 1 else {
            cooldownOverlay.isHidden = true
            cooldownOverlay.path = nil
            return
        }

        cooldownOverlay.isHidden = false
        cooldownOverlay.path = Self.radialOverlayPath(
            remainingFraction: 1 - cooldownFraction,
            radius: Self.size.width / 2
        )
    }

    private static let deniedFeedbackActionKey = "hudPulseButton.deniedFeedback"

    /// A quick, visible scale-pulse -- the button is felt to respond to the
    /// touch even though `onPress` never fires.
    private func playDeniedPressFeedback() {
        removeAction(forKey: Self.deniedFeedbackActionKey)
        let shrink = SKAction.scale(to: 0.9, duration: 0.05)
        let restore = SKAction.scale(to: 1.0, duration: 0.05)
        run(.sequence([shrink, restore]), withKey: Self.deniedFeedbackActionKey)
    }

    /// A pie-wedge path (centred at the node's own origin, matching
    /// `plate`'s own circle) covering `remainingFraction` of the circle's
    /// area, swept clockwise from straight up -- see the original
    /// `Sources/UI/PulseButton.swift`'s own doc comment for why the two
    /// boundary cases (`0` and `>= 1`) are special-cased rather than swept
    /// as an ordinary arc.
    private static func radialOverlayPath(remainingFraction: CGFloat, radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        guard remainingFraction > 0 else { return path }

        guard remainingFraction < 1 else {
            path.addEllipse(in: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2))
            return path
        }

        let startAngle = CGFloat.pi / 2
        let endAngle = startAngle - remainingFraction * 2 * .pi
        path.move(to: .zero)
        path.addArc(center: .zero, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
        path.closeSubpath()
        return path
    }
}
