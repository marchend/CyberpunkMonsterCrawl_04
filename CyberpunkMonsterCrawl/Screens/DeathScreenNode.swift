import SpriteKit
import UIKit

/// Skeleton `.death` screen.
///
/// The RUN AGAIN / back-to-menu navigation is real \u2014 wired straight to the
/// shared `GameStateMachine` \u2014 but the run-summary content (score,
/// survival time, kills) is explicitly out of scope for CYBERPUN-17-2 (see
/// the story's "Out of scope" section: "the run-summary rows \u2014 skeleton
/// screens are enough here").
///
/// // SCAFFOLDING(CYBERPUN-17-13): the placeholder background + label below
/// stand in for the run-summary rows. `CYBERPUN-17-13` is the story that
/// replaces them with the real rows (its data layer -- `RunScoreCalculator`
/// / `RunSummary` / `HighScoreStore` -- has landed; the UI PR mounts them
/// here), so the marker names the ticket that actually owns the removal.
/// (It previously named `CYBERPUN-17-16`, which is not a filed ticket --
/// see `WeaponFiringControllerIntegrationTests`' header on this codebase's
/// no-invented-ticket-IDs rule -- so the grep gate would have outlived any
/// owner who could clear it.)
final class DeathScreenNode: ScreenNode {

    let node = SKNode()

    /// Exposed for tests: proves death has a reachable path back into a run.
    let runAgainButton: ButtonNode

    /// Exposed for tests: proves death has a reachable path back to the menu.
    let backToMenuButton: ButtonNode

    private let background: SKSpriteNode
    // SCAFFOLDING(CYBERPUN-17-13): placeholder label; no real run summary yet.
    private let placeholderLabel = SKLabelNode(text: "YOU DIED")

    /// - Parameters:
    ///   - onRunAgain: run when RUN AGAIN is tapped. `GameViewController`
    ///     passes `stateMachine.transition(to: .gameplay)`.
    ///   - onBackToMenu: run when the back-to-menu entry is tapped.
    ///     `GameViewController` passes `stateMachine.transition(to: .menu)`.
    init(onRunAgain: @escaping () -> Void, onBackToMenu: @escaping () -> Void) {
        background = SKSpriteNode(color: PixelGritPalette.background, size: CGSize(width: 1, height: 1))

        runAgainButton = ButtonNode(
            title: "RUN AGAIN",
            size: CGSize(width: 220, height: 64),
            accentColor: PixelGritPalette.neonAccent,
            accessibilityIdentifier: "death.runAgainButton",
            action: onRunAgain
        )
        backToMenuButton = ButtonNode(
            title: "BACK TO MENU",
            size: CGSize(width: 220, height: 48),
            accessibilityIdentifier: "death.backToMenuButton",
            action: onBackToMenu
        )

        placeholderLabel.fontName = "Menlo-Bold"
        placeholderLabel.fontSize = 24
        placeholderLabel.fontColor = PixelGritPalette.neonSecondary
        placeholderLabel.verticalAlignmentMode = .center
        placeholderLabel.horizontalAlignmentMode = .center

        node.name = "deathScreen"
        node.addChild(background)
        node.addChild(placeholderLabel)
        node.addChild(runAgainButton)
        node.addChild(backToMenuButton)
    }

    func willEnter() {}

    func willExit() {}

    func layout(for size: CGSize, safeAreaInsets: UIEdgeInsets) {
        background.size = size
        background.position = .zero

        let verticalShift = (safeAreaInsets.bottom - safeAreaInsets.top) / 2
        let labelOffset = min(size.width, size.height) * 0.2
        let backToMenuOffset = min(size.width, size.height) * 0.18

        placeholderLabel.position = CGPoint(x: 0, y: verticalShift + labelOffset)
        runAgainButton.position = CGPoint(x: 0, y: verticalShift)
        backToMenuButton.position = CGPoint(x: 0, y: verticalShift - backToMenuOffset)
    }
}
