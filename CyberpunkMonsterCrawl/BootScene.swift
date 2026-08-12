import SpriteKit

/// Bootstrap-only scene: proves the SpriteKit render path works by showing
/// the project name on screen.
///
/// **No longer presented.** `GameViewController` presents `GameScene`
/// (CYBERPUN-17-2-t2), which implements the layered scene graph
/// (worldLayer < effectsLayer < uiLayer, uiLayer pinned to the camera with
/// UI-first touch dispatch), the `GameStateMachine`-driven screen registry
/// described in docs/bootstrap.md, and a `MenuScreen` whose PLAY button
/// drives menu → gameplay. This scene is retained only as the minimal
/// render-path smoke target; CYBERPUN-17-2-t3 removes it once the
/// gameplay/death/highScores screens make it redundant.
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
