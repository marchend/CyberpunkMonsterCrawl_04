import SpriteKit
import UIKit

/// The minimal menu screen: the game's title plus a working PLAY button.
///
/// Deliberately small - it exists so this feature's primary acceptance
/// criterion ("the app launches into a menu; PLAY starts a run") is
/// observable in a real build rather than only asserted in unit tests. The
/// styled menu (high-scores entry, art, layout polish) and the gameplay /
/// death / high-scores screens land in CYBERPUN-17-2-t3.
///
/// `node` is mounted in `GameScene.uiLayer`, which is parented to the
/// scene's camera, so this screen lays out around `(0, 0)` = the centre of
/// the visible area and stays put in both orientations.
final class MenuScreen: ScreenNode {

    let node = SKNode()

    /// The PLAY button. Exposed so tests can assert the menu ships a
    /// reachable, tappable entry point into gameplay.
    let playButton: ButtonNode

    private let titleLabel = SKLabelNode(text: "CYBERPUNK MONSTER CRAWL")

    /// - Parameter onPlay: run when PLAY is tapped. `GameViewController`
    ///   passes `stateMachine.transition(to: .gameplay)`; the screen itself
    ///   stays ignorant of the state machine.
    init(onPlay: @escaping () -> Void) {
        playButton = ButtonNode(
            title: "PLAY",
            size: CGSize(width: 220, height: 64),
            action: onPlay
        )

        titleLabel.fontName = "Menlo-Bold"
        titleLabel.fontSize = 20
        titleLabel.fontColor = .white
        titleLabel.verticalAlignmentMode = .center
        titleLabel.horizontalAlignmentMode = .center

        node.name = "menuScreen"
        node.addChild(titleLabel)
        node.addChild(playButton)
    }

    func willEnter() {}

    func willExit() {}

    /// Centres the title above the PLAY button, nudged by the safe-area
    /// insets so neither collides with a notch or the home indicator.
    func layout(for size: CGSize, safeAreaInsets: UIEdgeInsets) {
        let verticalShift = (safeAreaInsets.bottom - safeAreaInsets.top) / 2
        let titleOffset = min(size.width, size.height) * 0.2

        playButton.position = CGPoint(x: 0, y: verticalShift)
        titleLabel.position = CGPoint(x: 0, y: verticalShift + titleOffset)
    }
}
