import SpriteKit

/// Bootstrap-only scene: proves the SpriteKit render path works by showing
/// the project name on screen. `GameScene` (CYBERPUN-17-2-t2, PR 2) now
/// implements the layered scene graph (worldLayer < effectsLayer < uiLayer,
/// uiLayer pinned to the camera with UI-first touch routing) and the
/// `GameStateMachine`-driven screen registry described in docs/bootstrap.md,
/// but with no concrete screens yet. The next PR in this feature registers
/// the real menu/gameplay/death/highScores screens and switches
/// `GameViewController` to present `GameScene` instead of this bootstrap
/// shell — until then this scene has no state machine, no menu and no PLAY
/// button.
final class BootScene: SKScene {
    override func didMove(to view: SKView) {
        backgroundColor = .black

        // Central texture-loader convention starts here: any texture this
        // scene samples uses nearest-neighbour filtering and no mipmaps, so
        // future pixel-art consumers inherit crisp, non-blurred scaling.
        // (No textures are loaded yet in the bootstrap shell.)

        let label = SKLabelNode(text: "CyberpunkMonsterCrawl")
        label.fontName = "Menlo-Bold"
        label.fontSize = 28
        label.fontColor = .white
        label.position = CGPoint(x: frame.midX, y: frame.midY)
        addChild(label)
    }
}
