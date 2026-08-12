import SpriteKit
import UIKit

/// Minimal tappable UI button: a filled plate with a centred label, wired to
/// an action closure and delivered to via `TouchResponder`.
///
/// Deliberately does **not** set `isUserInteractionEnabled`. `GameScene` is
/// the sole touch dispatcher (see `TouchResponder`); a node that opts into
/// UIKit delivery would receive the touch before the scene's
/// `touchesBegan(_:with:)` runs and so escape UI-first routing entirely.
/// `GameScene.nodesBypassingSceneTouchDispatch()` trips the DEBUG assertions
/// if any node in the graph ever does that.
///
/// The button is an accessibility element with `.button` traits and an
/// explicit `accessibilityIdentifier` (falling back to `title` when none is
/// supplied) so XCUITest (and VoiceOver) can find and tap it reliably by
/// either identifier or its visible title.
final class ButtonNode: SKNode, TouchResponder {

    /// The label text, also the button's default accessibility label /
    /// identifier.
    let title: String

    private let accentFrame: SKSpriteNode?
    private let plate: SKSpriteNode
    private let label: SKLabelNode
    private let action: () -> Void

    /// - Parameters:
    ///   - accentColor: when supplied, draws a thin neon frame behind the
    ///     plate and tints the label to match \u2014 the "Pixel Grit" direction's
    ///     hot-neon-accent treatment reserved for primary actions (e.g. PLAY).
    ///     `nil` (the default) keeps the plain dark-plate styling used by
    ///     secondary buttons (RUN AGAIN, back-to-menu, HIGH SCORES).
    ///   - accessibilityIdentifier: explicit identifier for UI tests; defaults
    ///     to `title` when omitted.
    init(
        title: String,
        size: CGSize,
        accentColor: UIColor? = nil,
        accessibilityIdentifier: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.action = action
        self.plate = SKSpriteNode(color: PixelGritPalette.plate, size: size)

        if let accentColor = accentColor {
            let frame = SKSpriteNode(
                color: accentColor,
                size: CGSize(width: size.width + 8, height: size.height + 8)
            )
            frame.name = "button.\(title).accentFrame"
            self.accentFrame = frame
        } else {
            self.accentFrame = nil
        }

        let label = SKLabelNode(text: title)
        label.fontName = "Menlo-Bold"
        label.fontSize = 26
        label.fontColor = accentColor ?? .white
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        self.label = label

        super.init()

        name = "button.\(title)"
        if let accentFrame = accentFrame {
            addChild(accentFrame)
        }
        addChild(plate)
        addChild(label)

        isAccessibilityElement = true
        self.accessibilityLabel = title
        self.accessibilityIdentifier = accessibilityIdentifier ?? title
        accessibilityTraits = .button
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// `TouchResponder`: run the button's action. Called by
    /// `GameScene.dispatchTouch(atScenePoint:)`, never by UIKit directly.
    func handleTouch() {
        action()
    }
}
