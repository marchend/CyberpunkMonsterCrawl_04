import SpriteKit
import UIKit

/// Hosts the single SKView for the app. Bootstrap scope: presents the
/// trivial BootScene. Future PRs replace BootScene's contents with the
/// menu -> gameplay -> death -> highScores state machine, but this
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
