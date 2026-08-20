import SpriteKit
import UIKit

/// Skeleton `.highScores` screen.
///
/// The back-to-menu navigation is real \u2014 wired straight to the shared
/// `GameStateMachine` \u2014 but the actual scores list is explicitly out of
/// scope for CYBERPUN-17-2: local high-score persistence is deferred work
/// (see CLAUDE.md "Deferred work"), so there is nothing real to render yet.
///
/// // SCAFFOLDING(CYBERPUN-17-13): the placeholder background + label below
/// stand in for the scores list. `CYBERPUN-17-13` is the story that replaces
/// them with the real list -- local persistence has landed (`HighScoreStore`),
/// and that story's UI PR renders it here -- so the marker names the ticket
/// that actually owns the removal. (It previously named `CYBERPUN-17-16`,
/// which is not a filed ticket -- see
/// `WeaponFiringControllerIntegrationTests`' header on this codebase's
/// no-invented-ticket-IDs rule -- so the grep gate would have outlived any
/// owner who could clear it.)
final class HighScoresScreenNode: ScreenNode {

    let node = SKNode()

    /// Exposed for tests: proves high scores has a reachable path back to
    /// the menu.
    let backToMenuButton: ButtonNode

    private let background: SKSpriteNode
    // SCAFFOLDING(CYBERPUN-17-13): placeholder label; no real scores list yet.
    private let placeholderLabel = SKLabelNode(text: "HIGH SCORES \u{2014} COMING SOON")

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
