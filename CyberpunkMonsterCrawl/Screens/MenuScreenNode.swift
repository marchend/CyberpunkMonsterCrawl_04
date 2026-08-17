import SpriteKit
import UIKit

/// The real menu screen: "Pixel Grit" dark background with a neon-accent
/// PLAY button, plus a placeholder HIGH SCORES entry.
///
/// `node` is mounted in `GameScene.uiLayer`, which is parented to the
/// scene's camera, so this screen lays out around `(0, 0)` = the centre of
/// the visible area and stays put in both orientations.
final class MenuScreenNode: ScreenNode {

    let node = SKNode()

    /// The PLAY button. Exposed so tests can assert the menu ships a
    /// reachable, tappable entry point into gameplay.
    let playButton: ButtonNode

    /// Placeholder route into `.highScores` (real transition; the high
    /// scores screen's own content is skeletal \u2014 see `HighScoresScreenNode`).
    let highScoresButton: ButtonNode

    /// Full-bleed dark backdrop, resized to the current scene size on every
    /// `layout(for:safeAreaInsets:)` call so rotation never leaves a lighter
    /// SpriteKit default background peeking out at the edges.
    private let background: SKSpriteNode

    private let titleLabel = SKLabelNode(text: "CYBERPUNK MONSTER CRAWL")

    /// A non-visual accessibility anchor identifying "the menu is mounted"
    /// independent of any one button.
    ///
    /// Unlike `GameplayScreenNode`'s former `gameplay.container` marker
    /// (removed in CYBERPUN-17-7-t5 along with the two assertions that
    /// depended on it, since the skeleton gameplay screen has no durable HUD
    /// content to re-point them at until CYBERPUN-17-12 lands),
    /// `menu.container` is a **durable accessibility
    /// contract**: the menu is a shipping screen, and VoiceOver plus any
    /// future UI test needs a stable way to identify it that survives the
    /// buttons being restyled, renamed or reordered. Keep this identifier
    /// stable; do not remove it when the menu's visuals change.
    ///
    /// It is positioned in `layout(for:safeAreaInsets:)` *clear of every
    /// button* rather than left at the screen's centre. A marker node has no
    /// visual content, so its accumulated frame is empty and
    /// `AccessibleSKView` has to synthesise a minimum-size rect to keep it
    /// findable - and at `(0, 0)` that synthesised rect landed **inside** the
    /// PLAY button (`playButton` sits within ~32pt of the centre in portrait).
    /// Two accessibility elements sharing a point is exactly the ambiguity
    /// that can make PLAY report `isHittable == false`, so the marker is
    /// parked in the gap between the title and PLAY where nothing tappable
    /// can overlap it.
    private let containerMarker = SKNode()

    /// - Parameters:
    ///   - onPlay: run when PLAY is tapped. `GameViewController` passes
    ///     `stateMachine.transition(to: .gameplay)`; the screen itself stays
    ///     ignorant of the state machine.
    ///   - onHighScores: run when the HIGH SCORES entry is tapped.
    ///     `GameViewController` passes `stateMachine.transition(to:
    ///     .highScores)`.
    init(onPlay: @escaping () -> Void, onHighScores: @escaping () -> Void) {
        background = SKSpriteNode(color: PixelGritPalette.background, size: CGSize(width: 1, height: 1))

        playButton = ButtonNode(
            title: "PLAY",
            size: CGSize(width: 220, height: 64),
            accentColor: PixelGritPalette.neonAccent,
            accessibilityIdentifier: "menu.playButton",
            action: onPlay
        )
        highScoresButton = ButtonNode(
            title: "HIGH SCORES",
            size: CGSize(width: 220, height: 48),
            accessibilityIdentifier: "menu.highScoresButton",
            action: onHighScores
        )

        titleLabel.fontName = "Menlo-Bold"
        titleLabel.fontSize = 20
        titleLabel.fontColor = .white
        titleLabel.verticalAlignmentMode = .center
        titleLabel.horizontalAlignmentMode = .center

        containerMarker.name = "menuScreen.container"
        containerMarker.isAccessibilityElement = true
        containerMarker.accessibilityIdentifier = "menu.container"
        containerMarker.accessibilityLabel = "Menu"

        node.name = "menuScreen"
        node.addChild(background)
        node.addChild(containerMarker)
        node.addChild(titleLabel)
        node.addChild(playButton)
        node.addChild(highScoresButton)
    }

    func willEnter() {}

    func willExit() {}

    /// Centres the title above the PLAY button and stacks HIGH SCORES below
    /// it, nudged by the safe-area insets so nothing collides with a notch
    /// or the home indicator in either orientation.
    func layout(for size: CGSize, safeAreaInsets: UIEdgeInsets) {
        background.size = size
        background.position = .zero

        let verticalShift = (safeAreaInsets.bottom - safeAreaInsets.top) / 2
        let titleOffset = min(size.width, size.height) * 0.2
        let highScoresOffset = min(size.width, size.height) * 0.18

        titleLabel.position = CGPoint(x: 0, y: verticalShift + titleOffset)
        playButton.position = CGPoint(x: 0, y: verticalShift)
        highScoresButton.position = CGPoint(x: 0, y: verticalShift - highScoresOffset)

        // Halfway between the title and PLAY: still unmistakably "the menu",
        // but outside every button's frame, so the size-less marker's
        // synthesised accessibility rect can never share a point with a
        // tappable element (see `containerMarker`).
        containerMarker.position = CGPoint(x: 0, y: verticalShift + titleOffset * 0.6)
    }
}
