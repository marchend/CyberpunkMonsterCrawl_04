import SpriteKit
import UIKit

/// Hosts the single SKView for the app and is the composition root: it
/// builds `GameScene`, registers every concrete screen, and presents it.
///
/// `GameStateMachine` (menu -> gameplay -> death -> highScores) drives
/// `GameScene`'s layered scene graph (worldLayer < effectsLayer < uiLayer,
/// uiLayer pinned to the camera) and its state-driven screen registry. The
/// app launches straight into `MenuScreenNode`, whose PLAY button
/// transitions the machine to `.gameplay` through `GameScene`'s UI-first
/// touch dispatch - so every piece of this architecture has a production
/// caller and is exercisable in a real build, not just from unit tests.
///
/// `.gameplay`, `.death` and `.highScores` are registered with skeleton
/// screens (`GameplayScreenNode` / `DeathScreenNode` / `HighScoresScreenNode`)
/// whose navigation (RUN AGAIN, back-to-menu) is real even though their
/// visual content is placeholder - final HUD/run-summary/scores content is
/// explicitly out of scope for CYBERPUN-17-2 (see docs/bootstrap.md and the
/// story's "Out of scope" section).
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

    /// Builds the scene and registers every screen. Separated from
    /// `viewDidLoad()` so the composition step itself is testable without an
    /// `SKView` (`GameViewControllerCompositionTests`).
    func makeGameScene(size: CGSize) -> GameScene {
        let scene = GameScene(size: size)
        scene.scaleMode = .resizeFill

        scene.register(
            MenuScreenNode(
                onPlay: { [weak scene] in
                    scene?.stateMachine.transition(to: .gameplay)
                },
                onHighScores: { [weak scene] in
                    scene?.stateMachine.transition(to: .highScores)
                }
            ),
            for: .menu
        )
        scene.register(GameplayScreenNode(), for: .gameplay)
        scene.register(
            DeathScreenNode(
                onRunAgain: { [weak scene] in
                    scene?.stateMachine.transition(to: .gameplay)
                },
                onBackToMenu: { [weak scene] in
                    scene?.stateMachine.transition(to: .menu)
                }
            ),
            for: .death
        )
        scene.register(
            HighScoresScreenNode(
                onBackToMenu: { [weak scene] in
                    scene?.stateMachine.transition(to: .menu)
                }
            ),
            for: .highScores
        )

        return scene
    }
}
