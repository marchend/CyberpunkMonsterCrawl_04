import SpriteKit

/// Bootstrap-only scene: proves the SpriteKit render path works by showing
/// the project name on screen. Future PRs replace this with the real
/// menu/gameplay/death/highScores state machine and the layered scene
/// graph (worldLayer < effectsLayer < uiLayer) described in docs/bootstrap.md.
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
