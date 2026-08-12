import SpriteKit
import UIKit

/// Skeleton `.highScores` screen.
///
/// The back-to-menu navigation is real \u2014 wired straight to the shared
/// `GameStateMachine` \u2014 but the actual scores list is explicitly out of
/// scope for CYBERPUN-17-2: local high-score persistence is deferred work
/// (see CLAUDE.md "Deferred work"), so there is nothing real to render yet.
///
/// // SCAFFOLDING(CYBERPUN-17-16): the placeholder background + label below
/// stand in for the scores list. Integration checkpoint #2 exercises the
/// full menu -> highScores loop end to end and is expected to drive the real
/// scores content (once local persistence lands) that replaces this
/// placeholder.
final class HighScoresScreenNode: ScreenNode {

    let node = SKNode()

    /// Exposed for tests: proves high scores has a reachable path back to
    /// the menu.
    let backToMenuButton: ButtonNode

    private let background: SKSpriteNode
    // SCAFFOLDING(CYBERPUN-17-16): placeholder label; no real scores list yet.
    private let placeholderLabel = SKLabelNode(text: "HIGH SCORES \u2014 COMING SOON")

    /// - Parameter onBackToMenu: run when the back-to-menu entry is tapped.
    ///   `GameViewController` passes `stateMachine.transition(to: .menu)`.
    init(onBackToMenu: @escaping () -> Void) {
        background = SKSpriteNode(color: PixelGritPalette.background, size: CGSize(width: 1, height: 1))

        backToMenuButton = ButtonNode(
            title: "BACK TO MENU",
            size: CGSize(width: 220, height: 48),
            accessibilityIdentifier: "highScores.backToMenuButton",
            action: onBackToMenu
        )

        placeholderLabel.fontName = "Menlo-Bold"
        placeholderLabel.fontSize = 18
        placeholderLabel.fontColor = PixelGritPalette.neonSecondary
        placeholderLabel.verticalAlignmentMode = .center
        placeholderLabel.horizontalAlignmentMode = .center

        node.name = "highScoresScreen"
        node.addChild(background)
        node.addChild(placeholderLabel)
        node.addChild(backToMenuButton)
    }

    func willEnter() {}

    func willExit() {}

    func layout(for size: CGSize, safeAreaInsets: UIEdgeInsets) {
        background.size = size
        background.position = .zero

        let verticalShift = (safeAreaInsets.bottom - safeAreaInsets.top) / 2
        let labelOffset = min(size.width, size.height) * 0.15

        placeholderLabel.position = CGPoint(x: 0, y: verticalShift + labelOffset)
        backToMenuButton.position = CGPoint(x: 0, y: verticalShift)
    }
}
