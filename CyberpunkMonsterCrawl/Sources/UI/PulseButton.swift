import CoreGraphics
import SpriteKit
import UIKit

/// The HUD button for the player-triggered pulse ability (`CYBERPUN-17-10`
/// PR 2): a self-contained, presentation-only `TouchResponder` node with no
/// dependency on `PulseAbility` or `GameScene`. A later PR mounts this node
/// at `FloatingThumbstickNode.reservedPulseButtonSlot(forSize:safeAreaInsets:)`
/// (the slot that node already reserves directly above the movement stick),
/// drives `setCooldownProgress(_:)` from `PulseAbility.cooldownRemaining` /
/// `PulseAbility.cooldownSeconds` every frame, and triggers the real ability
/// from the `onPress` closure this type is initialized with.
///
/// **Product gate 1 -- "must respond to every press."** `handleTouch()`
/// unconditionally invokes `onPress`, on cooldown or not: this node never
/// gates a press on its own cooldown state. Deciding whether a press while
/// on cooldown should no-op is the wiring PR's call (it has `PulseAbility`
/// available to ask), not this presentation-only node's -- baking a gate in
/// here would make that decision unreachable from outside.
///
/// **Presentation-only, driven by an externally-supplied progress value.**
/// This node holds no timer and runs no per-frame update of its own;
/// `setCooldownProgress(_:)` is the only thing that ever changes its visual
/// cooldown state, called from whatever owns the real clock (a future
/// `GameScene` per-frame hook driving it from `PulseAbility.cooldownRemaining`).
/// That split mirrors `FloatingThumbstickNode` producing a `StickState` for
/// an external consumer to drive, just inverted: here the *node* is driven
/// by an external value rather than producing one.
///
/// **Touch-dispatch convention.** Like `ButtonNode`, this node deliberately
/// does **not** set `isUserInteractionEnabled`; `GameScene` is the sole touch
/// dispatcher (see `TouchResponder`), and conforming to `TouchResponder` is
/// the only supported way for a node in this scene graph to react to a
/// touch. `GameScene.nodesBypassingSceneTouchDispatch()` audits the graph
/// for violations.
final class PulseButton: SKNode, TouchResponder {

    // MARK: - Tunables

    /// Matches `FloatingThumbstickNode.pulseButtonSlotSize` exactly, so a
    /// future wiring PR that mounts this node in that reserved slot needs no
    /// extra scaling math. Not read from that type directly (`Sources/UI`
    /// has no import-order dependency between the two files) -- kept in sync
    /// by convention and by `PulseButtonTests` pinning the literal.
    static let size = CGSize(width: 72, height: 72)

    /// Alpha while the ability is ready to fire.
    static let readyAlpha: CGFloat = 1.0

    /// Alpha while the ability is on cooldown -- dimmed, but (like the
    /// thumbstick's own `restAlpha`) never `0`: the player should always be
    /// able to see where the button is, even mid-cooldown.
    static let cooldownAlpha: CGFloat = 0.45

    /// Fill color of the radial cooldown overlay -- a dark wedge swept away
    /// as the cooldown completes.
    static let cooldownOverlayColor = UIColor(white: 0, alpha: 0.65)

    // MARK: - Nodes

    private let plate = SKShapeNode(circleOfRadius: PulseButton.size.width / 2)
    private let icon = SKShapeNode(circleOfRadius: PulseButton.size.width / 2 * 0.4)
    private let cooldownOverlay = SKShapeNode()

    // MARK: - State

    private let onPress: () -> Void

    /// `1.0` == fully ready, `0.0` == a cooldown was just started. Starts at
    /// `1.0`: a fresh button reads as ready, matching `PulseAbility`'s own
    /// "ready immediately" convention (`cooldownRemaining` starts at `0`).
    private(set) var cooldownProgress: CGFloat = 1.0

    /// Exactly `cooldownProgress < 1.0`. Exposed so a caller (and
    /// `PulseButtonTests`) can assert the derived boolean state without
    /// recomputing the comparison itself.
    var isOnCooldown: Bool { cooldownProgress < 1.0 }

    // MARK: - Init

    /// - Parameter onPress: invoked, unconditionally, by every accepted
    ///   touch -- see this type's "product gate 1" doc note above.
    init(onPress: @escaping () -> Void) {
        self.onPress = onPress
        super.init()

        plate.fillColor = PixelGritPalette.plate
        plate.strokeColor = PixelGritPalette.neonSecondary
        plate.lineWidth = 2
        plate.name = "pulseButton.plate"

        icon.fillColor = PixelGritPalette.neonAccent
        icon.strokeColor = .clear
        icon.name = "pulseButton.icon"

        cooldownOverlay.fillColor = Self.cooldownOverlayColor
        cooldownOverlay.strokeColor = .clear
        cooldownOverlay.name = "pulseButton.cooldownOverlay"

        name = "pulseButton"
        addChild(plate)
        addChild(icon)
        addChild(cooldownOverlay)

        isAccessibilityElement = true
        accessibilityLabel = "Pulse ability"
        accessibilityIdentifier = "gameplay.pulseButton"
        accessibilityTraits = .button

        updateVisual()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - TouchResponder

    /// Called by `GameScene.dispatchTouch(atScenePoint:)`, never by UIKit
    /// directly. Fires `onPress` unconditionally -- see this type's
    /// "product gate 1" doc note.
    func handleTouch() {
        onPress()
    }

    // MARK: - Cooldown visual API

    /// Sets the cooldown visual state from an externally-tracked progress
    /// value, clamped to `0...1`. `1.0` is fully ready (the overlay is
    /// hidden and the button sits at `readyAlpha`); `0.0` is a cooldown that
    /// was just started (the overlay covers the full circle); values in
    /// between sweep the overlay away proportionally as the cooldown
    /// counts down.
    func setCooldownProgress(_ progress: CGFloat) {
        cooldownProgress = min(1, max(0, progress))
        updateVisual()
    }

    /// Convenience, coarser sibling of `setCooldownProgress(_:)`: snaps
    /// straight to the "just used" (`progress == 0`) or "ready"
    /// (`progress == 1`) boundary, for a caller that only has a boolean
    /// cooldown-gate reading (e.g. `PulseAbility.isOnCooldown`) rather than a
    /// fractional progress value.
    func setOnCooldown(_ onCooldown: Bool) {
        setCooldownProgress(onCooldown ? 0 : 1)
    }

    // MARK: - Visuals

    private func updateVisual() {
        alpha = isOnCooldown ? Self.cooldownAlpha : Self.readyAlpha

        guard isOnCooldown else {
            cooldownOverlay.isHidden = true
            cooldownOverlay.path = nil
            return
        }

        cooldownOverlay.isHidden = false
        cooldownOverlay.path = Self.radialOverlayPath(
            remainingFraction: 1 - cooldownProgress,
            radius: Self.size.width / 2
        )
    }

    /// A pie-wedge path (centered at the node's own origin, matching
    /// `plate`'s own circle) covering `remainingFraction` of the circle's
    /// area, swept clockwise from straight up. `remainingFraction == 0`
    /// yields a degenerate (empty) wedge; `updateVisual()` never calls this
    /// with `remainingFraction == 1` reaching an ambiguous full-circle arc,
    /// since it hides the overlay outright once ready.
    private static func radialOverlayPath(remainingFraction: CGFloat, radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        guard remainingFraction > 0 else { return path }

        let startAngle = CGFloat.pi / 2
        let endAngle = startAngle - remainingFraction * 2 * .pi
        path.move(to: .zero)
        path.addArc(center: .zero, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
        path.closeSubpath()
        return path
    }
}
