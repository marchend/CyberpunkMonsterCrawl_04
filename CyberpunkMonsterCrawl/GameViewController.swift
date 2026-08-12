import SpriteKit
import UIKit

/// Hosts the single SKView for the app. Bootstrap scope: presents the
/// trivial BootScene.
///
/// `GameStateMachine` (menu -> gameplay -> death -> highScores) is
/// implemented and unit-tested but deliberately has no caller here yet:
/// CYBERPUN-17-2-t2 replaces the BootScene presentation below with the
/// layered menu scene graph (worldLayer < effectsLayer < uiLayer, uiLayer
/// pinned to the camera) and the PLAY button that drives the machine. This
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
