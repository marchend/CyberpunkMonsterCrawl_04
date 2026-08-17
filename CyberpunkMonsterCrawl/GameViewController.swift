import SpriteKit
import UIKit

/// Hosts the single SKView for the app (an `AccessibleSKView`, so
/// accessibility-driven taps land where the scene actually hit-tests) and is
/// the composition root: it builds `GameScene`, registers every concrete
/// screen, and presents it.
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

    /// The single hosted view.
    ///
    /// An `AccessibleSKView` rather than a plain `SKView`: without that swap
    /// every accessible UI node reports a wrong screen-space
    /// `accessibilityFrame`, so a tap driven by accessibility element
    /// (XCUITest, the scripted runtime probe, VoiceOver) misses the button
    /// entirely and PLAY appears to do nothing - see `AccessibleSKView` for
    /// the full failure. This line *is* the entry-point wiring: nothing else
    /// in the app instantiates that class.
    ///
    /// `private(set)` rather than `private` so
    /// `GameViewControllerCompositionTests` can pin the wiring and catch a
    /// silent regression back to a plain `SKView`; nothing outside this class
    /// writes it.
    private(set) var skView: AccessibleSKView!

    /// The plain `UIView` that presents the scene's UI to UIAccessibility, as
    /// a set of real invisible subviews mirroring the accessible `SKNode`s.
    ///
    /// It has to be a **sibling installed above** `skView`, not a child of
    /// it: `SceneAccessibilityContainerView` silences SpriteKit's competing
    /// (camera-unaware) accessibility tree by setting
    /// `accessibilityElementsHidden` on the `SKView`, and that flag hides a
    /// view's whole accessibility subtree - a nested container would be
    /// hidden with it. It draws nothing, and although it *is* interactive (a
    /// non-interactive view is invisible to the hit-test walk the
    /// accessibility point lookup is built on) it hands every real touch back
    /// to the scene by forwarding it, converted into scene space, into
    /// `GameScene.dispatchTouch(atScenePoint:)` - so the only thing this line
    /// changes for a real finger is nothing at all. What it changes for
    /// XCUITest / VoiceOver is that
    /// `menu.playButton` becomes *hittable* instead of merely findable - real
    /// views are natively resolvable from a point, which hand-vended
    /// `UIAccessibilityElement`s were not (see `AccessibleSKView`, parts 2
    /// and 3).
    ///
    /// `private(set)` so `AccessibleSKViewTests` can pin the wiring and catch
    /// a silent regression back to the `SKView`-as-container arrangement.
    private(set) var accessibilityContainerView: SceneAccessibilityContainerView!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let skView = AccessibleSKView(frame: view.bounds)
        skView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        skView.ignoresSiblingOrder = true
        view.addSubview(skView)
        self.skView = skView

        let accessibilityContainerView = SceneAccessibilityContainerView(sceneView: skView)
        accessibilityContainerView.frame = view.bounds
        accessibilityContainerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(accessibilityContainerView)
        self.accessibilityContainerView = accessibilityContainerView

        // Presenting last, with the container already wired up, so the first
        // set of accessibility mirrors is built from the scene the app
        // actually launches into (`presentScene` refreshes them).
        skView.presentScene(makeGameScene(size: view.bounds.size))
    }

    /// The container's mirrors are geometry, so they have to follow every
    /// layout pass - a rotation resizes the scene and moves every
    /// camera-locked button on screen. Refreshing here (as well as from the
    /// container's own `layoutSubviews()` and from each accessibility query)
    /// keeps `AppLaunchAndRotationUITests`' post-rotation frames honest.
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        accessibilityContainerView?.refreshAccessibilityMirrors()
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
