import SpriteKit
import UIKit

/// Hosts the single SKView for the app and is the composition root: it
/// builds `GameScene`, registers the screens that exist, and presents it.
///
/// `GameStateMachine` (menu -> gameplay -> death -> highScores) drives
/// `GameScene`'s layered scene graph (worldLayer < effectsLayer < uiLayer,
/// uiLayer pinned to the camera) and its state-driven screen registry
/// (CYBERPUN-17-2-t2). The app launches straight into `MenuScreen`, whose
/// PLAY button transitions the machine to `.gameplay` through `GameScene`'s
/// UI-first touch dispatch - so every piece of this architecture has a
/// production caller and is exercisable in a real build, not just from unit
/// tests.
///
/// `.gameplay`, `.death` and `.highScores` have no registered screen yet
/// (CYBERPUN-17-2-t3 ships them and registers them here the same way); until
/// then a transition into those states unmounts the menu and leaves
/// `uiLayer` empty, which is the visible, honest state of the build.
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

        skView.presentScene(makeGameScene(size: view.bounds.size))
    }

    /// Builds the scene and registers every screen that exists today.
    /// Separated from `viewDidLoad()` so the composition step itself is
    /// testable without an `SKView`
    /// (`GameViewControllerCompositionTests`).
    func makeGameScene(size: CGSize) -> GameScene {
        let scene = GameScene(size: size)
        scene.scaleMode = .resizeFill
        scene.register(
            MenuScreen { [weak scene] in
                scene?.stateMachine.transition(to: .gameplay)
            },
            for: .menu
        )
        return scene
    }
}
