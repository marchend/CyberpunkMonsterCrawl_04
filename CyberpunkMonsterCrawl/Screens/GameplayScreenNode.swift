import SpriteKit
import UIKit

/// Skeleton `.gameplay` screen.
///
/// CYBERPUN-17-2's own scope explicitly excludes "final HUD content" (see
/// the story's "Out of scope" section) \u2014 real gameplay content (world
/// rendering, the player actor, the raccoon swarm, auto-fire/XP HUD) lands
/// across CYBERPUN-17-3 through CYBERPUN-17-9. This screen exists purely so
/// `.gameplay` has a mounted, observable `ScreenNode` today: tapping PLAY on
/// the menu visibly lands somewhere real instead of an empty `uiLayer`.
///
/// // SCAFFOLDING(CYBERPUN-17-7): the placeholder background + label below
/// are temporary. CYBERPUN-17-7 ("Wire the floating thumbstick, player
/// movement, building collision and camera") adds the first real HUD content
/// this screen gains and should replace this placeholder wholesale.
final class GameplayScreenNode: ScreenNode {

    let node = SKNode()

    private let background: SKSpriteNode
    // SCAFFOLDING(CYBERPUN-17-7): placeholder label only; no real HUD yet.
    private let placeholderLabel = SKLabelNode(text: "GAMEPLAY \u2014 WORLD COMING SOON")

    /// Non-visual accessibility anchor identifying "gameplay is mounted",
    /// so a UI test can assert the PLAY -> gameplay transition landed
    /// somewhere real instead of only observing the menu disappear.
    private let containerMarker = SKNode()

    init() {
        background = SKSpriteNode(color: PixelGritPalette.background, size: CGSize(width: 1, height: 1))

        placeholderLabel.fontName = "Menlo-Bold"
        placeholderLabel.fontSize = 18
        placeholderLabel.fontColor = PixelGritPalette.neonSecondary
        placeholderLabel.verticalAlignmentMode = .center
        placeholderLabel.horizontalAlignmentMode = .center

        containerMarker.name = "gameplayScreen.container"
        containerMarker.isAccessibilityElement = true
        containerMarker.accessibilityIdentifier = "gameplay.container"
        containerMarker.accessibilityLabel = "Gameplay"

        node.name = "gameplayScreen"
        node.addChild(background)
        node.addChild(containerMarker)
        node.addChild(placeholderLabel)
    }

    func willEnter() {}

    func willExit() {}

    func layout(for size: CGSize, safeAreaInsets: UIEdgeInsets) {
        background.size = size
        background.position = .zero
        placeholderLabel.position = CGPoint(x: 0, y: (safeAreaInsets.bottom - safeAreaInsets.top) / 2)
    }
}
