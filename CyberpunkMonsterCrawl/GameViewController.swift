import SpriteKit
import UIKit

/// Hosts the single SKView for the app. Bootstrap scope: presents the
/// trivial BootScene.
///
/// `GameStateMachine` (menu -> gameplay -> death -> highScores) now drives
/// `GameScene`'s layered scene graph (worldLayer < effectsLayer < uiLayer,
/// uiLayer pinned to the camera) and its state-driven screen registry
/// (CYBERPUN-17-2-t2, PR 2) — but `GameScene` has no concrete screens or
/// PLAY button registered yet, so this controller still presents
/// `BootScene` rather than `GameScene`. The next PR in this feature
/// registers the real screens and switches the presentation below. This
/// controller (and its SKView hosting responsibility) stays the same shape.
final class GameViewController: UIViewController {
    private var skView: SKView!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let skView = SKView(frame: view.bounds)
        skView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        skView.ignoresSiblingOrder = true
        view.addSubview(skView)
        self.skView = skView

        let scene = BootScene(size: view.bounds.size)
        scene.scaleMode = .resizeFill
        skView.presentScene(scene)
    }
}
