import SpriteKit

/// Bootstrap-only scene: proves the SpriteKit render path works by showing
/// the project name on screen. CYBERPUN-17-2-t2 replaces this with the real
/// menu/gameplay/death/highScores scene driven by `GameStateMachine` and the
/// layered scene graph (worldLayer < effectsLayer < uiLayer, uiLayer pinned
/// to the camera with UI-first touch routing) described in
/// docs/bootstrap.md. Until then this scene has no state machine, no menu
/// and no PLAY button — the shipped shell is still the bootstrap label.
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
