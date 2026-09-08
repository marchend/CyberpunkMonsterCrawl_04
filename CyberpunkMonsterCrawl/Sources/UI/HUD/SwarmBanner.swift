import CoreGraphics
import SpriteKit
import UIKit

/// Transient HUD banner (e.g. "SWARM INCOMING"): `show(message:duration:)`,
/// `dismiss()`, auto-dismiss via `SKAction`. No positioning logic
/// (`HUDLayout` owns where this mounts).
///
/// **Never intercepts touches.** `isUserInteractionEnabled` is left at its
/// default `false` and set explicitly in `init` anyway, as a documented
/// invariant rather than an accident of the default: this node sits above
/// gameplay content in `uiLayer`'s stacking order while visible, and
/// `GameScene.nodesBypassingSceneTouchDispatch()` would flag it graph-wide
/// if that ever flipped, but the explicit set-to-`false` here is what makes
/// "this banner cannot ever swallow a touch" a stated fact of this file
/// rather than a property of whatever the graph-wide default happens to be.
final class SwarmBanner: SKNode {

    // MARK: - Tunables

    static let bannerSize = HUDLayout.swarmBannerSize

    private static let autoDismissActionKey = "swarmBanner.autoDismiss"

    // MARK: - Nodes

    private let plate: SKSpriteNode
    private let label: SKLabelNode

    // MARK: - State

    private(set) var isShowing = false
    private(set) var currentMessage: String?

    // MARK: - Init

    override init() {
        plate = SKSpriteNode(color: PixelGritPalette.plate, size: Self.bannerSize)
        plate.name = "swarmBanner.plate"

        let label = SKLabelNode(text: "")
        label.fontName = "Menlo-Bold"
        label.fontSize = 18
        label.fontColor = PixelGritPalette.neonSecondary
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        self.label = label

        super.init()

        name = "swarmBanner"

        // Deliberately **not** an accessibility element, on this node and
        // on both drawn children -- see `HPSegmentBar`'s own rationale.
        // The same reasoning as `isUserInteractionEnabled = false` below,
        // one layer up: a published element becomes a real, interactive
        // `SceneAccessibilityMirrorView` over this banner's rect, which
        // would swallow touches over the middle of the screen for the
        // whole of the `swarmEscalationDuration` a transient notification
        // is up. This banner is a notification, not a control.
        isAccessibilityElement = false
        plate.isAccessibilityElement = false
        label.isAccessibilityElement = false

        addChild(plate)
        addChild(label)

        isUserInteractionEnabled = false
        alpha = 0
        isHidden = true
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Show / dismiss

    /// Shows `message` and schedules an automatic `dismiss()` after
    /// `duration` seconds via a keyed `SKAction`, so a second `show(...)`
    /// call replaces (never stacks with) an already-pending dismissal.
    func show(message: String, duration: TimeInterval) {
        currentMessage = message
        label.text = message
        isShowing = true
        isHidden = false
        alpha = 1

        removeAction(forKey: Self.autoDismissActionKey)
        let sequence = SKAction.sequence([
            .wait(forDuration: duration),
            .run { [weak self] in self?.dismiss() }
        ])
        run(sequence, withKey: Self.autoDismissActionKey)
    }

    /// Hides the banner immediately and cancels any pending auto-dismiss.
    /// Idempotent: calling this while already dismissed is a no-op beyond
    /// re-affirming the hidden state.
    func dismiss() {
        removeAction(forKey: Self.autoDismissActionKey)
        isShowing = false
        isHidden = true
        alpha = 0
        currentMessage = nil
    }

    /// The scheduled auto-dismiss action, if any -- exposed so a test can
    /// assert its presence/duration without needing to pump real wall-clock
    /// time through a live `SKView` (this codebase's existing convention;
    /// see `HitEffectsTests` asserting `action(forKey:)` presence rather
    /// than waiting for an animation to complete).
    var pendingAutoDismissAction: SKAction? {
        action(forKey: Self.autoDismissActionKey)
    }
}
