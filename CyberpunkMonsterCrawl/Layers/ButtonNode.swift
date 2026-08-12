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
/// The button is an accessibility element with `.button` traits so XCUITest
/// (and VoiceOver) can find and tap it by its title.
final class ButtonNode: SKNode, TouchResponder {

    /// The label text, also the button's accessibility label.
    let title: String

    private let plate: SKSpriteNode
    private let label: SKLabelNode
    private let action: () -> Void

    init(title: String, size: CGSize, action: @escaping () -> Void) {
        self.title = title
        self.action = action
        self.plate = SKSpriteNode(color: UIColor(white: 0.12, alpha: 1.0), size: size)

        let label = SKLabelNode(text: title)
        label.fontName = "Menlo-Bold"
        label.fontSize = 26
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        self.label = label

        super.init()

        name = "button.\(title)"
        addChild(plate)
        addChild(label)

        isAccessibilityElement = true
        accessibilityLabel = title
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
