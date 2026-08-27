import SpriteKit
import UIKit
// `SCAFFOLDING(CYBERPUN-17-13)` — close-cleanup lane TEST FIXTURE (2026-08-27): a deliberate prose mention of this story's removed LaunchGotoState bridge, staged so the enabled lane's first run has a real audit finding. The lane is expected to delete exactly this line.

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
        // `UIView` defaults this to `false`, which means UIKit delivers a
        // second finger to nobody at all. This game is two-thumbed by design:
        // `FloatingThumbstickNode` drives movement from the left region and
        // reserves `reservedPulseButtonSlot` directly above it for
        // `CYBERPUN-17-10`'s pulse button - a control specifically meant to
        // be pressed *while* the other thumb is moving. Without this line
        // `GameScene.touchesBegan(_:with:)`'s per-touch loop (and the
        // `activeStickTouch` bookkeeping it feeds) could never see the
        // concurrent touch they exist to tell apart, and gate 1's "the stick
        // moves the player, every button responds" would fail the moment a
        // HUD button lands.
        skView.isMultipleTouchEnabled = true
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
        let scene = makeGameScene(size: view.bounds.size)
        skView.presentScene(scene)
    }

    /// The container's mirrors are geometry, so they have to follow every
    /// layout pass - a rotation resizes the scene and moves every
    /// camera-locked button on screen. Refreshing here (as well as from the
    /// container's own `layoutSubviews()` and from each accessibility query)
    /// keeps `AppLaunchAndRotationUITests`' post-rotation frames honest.
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        accessibilityContainerView?.refreshAccessibilityMirrors()
        // `CYBERPUN-17-10-t4`: the safe area a scene laid itself out for can
        // be stale by the time this pass finishes -- `didMove(to:)` fires
        // from `presentScene(_:)` in `viewDidLoad()`, before the first real
        // layout pass has settled the true insets, and nothing but a *size*
        // change ever re-derived them afterward. Refreshing here (as well as
        // from `viewSafeAreaInsetsDidChange()` below) is the belt-and-braces
        // half of the pair: this hook runs *after* layout, so the hosted
        // `SKView`'s own `safeAreaInsets` are settled by now, which the
        // controller-level callback alone does not guarantee.
        // `refreshLayoutForCurrentSafeArea()` no-ops unless the insets
        // actually moved, so a per-pass call costs one comparison.
        currentGameScene?.refreshLayoutForCurrentSafeArea()
    }

    /// The one place UIKit tells us the safe area moved. Forwarding it into
    /// the scene fixes late-settling insets for **every** consumer of
    /// `GameScene.currentSafeAreaInsets` -- the `.menu` screen (registered
    /// before `presentScene(_:)`, so it is first laid out with `view == nil`
    /// -> `.zero`), the active screen of any other state, the thumbstick and
    /// the pulse button -- rather than at one state transition. See
    /// `GameScene.refreshLayoutForCurrentSafeArea()`.
    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        currentGameScene?.refreshLayoutForCurrentSafeArea()
    }

    /// The presented scene, when there is one. `skView` is implicitly
    /// unwrapped and both hooks above can run before `viewDidLoad()` has
    /// built it, so this is deliberately optional all the way down.
    private var currentGameScene: GameScene? {
        skView?.scene as? GameScene
    }

    /// Builds the scene and registers every screen. Separated from
    /// `viewDidLoad()` so the composition step itself is testable without an
    /// `SKView` (`GameViewControllerCompositionTests`).
    ///
    /// - Parameter highScoreStore: the persisted table `DeathScreenNode`
    ///   records into and `HighScoresScreenNode` reads. `nil` (the
    ///   production default, and what `viewDidLoad()` passes) means the real
    ///   `HighScoreStore.productionSuiteName` suite. A test that drives a
    ///   real run into `.death` through this composition root passes a
    ///   scratch `UserDefaults` suite instead, so recording a run here never
    ///   appends a row to the player's own high-score table -- the same
    ///   persistent side effect `runSummaryProvider`'s note below guards
    ///   against from the other direction (`PlayerDeathTriggerTests`).
    func makeGameScene(size: CGSize, highScoreStore: HighScoreStore? = nil) -> GameScene {
        let scene = highScoreStore.map { GameScene(size: size, highScoreStore: $0) }
            ?? GameScene(size: size)
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

        // `deathScreen` is kept as a local so `HighScoresScreenNode` below
        // can read its `lastRecordedRunID` after the fact (`CYBERPUN-17-13`
        // PR 2's "thread the just-finished run's id from death into
        // high-scores" requirement) -- weakly, the same way every other
        // closure here captures `scene` weakly, so neither screen keeps the
        // other alive.
        let deathScreen = DeathScreenNode(
            onRunAgain: { [weak scene] in
                // `startNewRun()` (`CYBERPUN-17-13` PR 3), not a plain
                // `stateMachine.transition(to: .gameplay)`: RUN AGAIN must
                // draw a fresh `worldSeed` (new city, new starting
                // junction) before landing in `.gameplay`, which only this
                // entry point does.
                scene?.startNewRun()
            },
            onBackToMenu: { [weak scene] in
                scene?.stateMachine.transition(to: .menu)
            },
            runSummaryProvider: { [weak scene] in
                // A `nil` scene/playerCombat means `.death` was entered
                // without a run ever having mounted a player -- not
                // reachable from real gameplay (`.death` is only a legal
                // transition from `.gameplay`, which always mounts one
                // first), but reachable from a direct
                // `stateMachine.transition(to: .death)` call: a test.
                //
                // Returning `nil` rather than an all-zero `RunSummary` is
                // the difference between "no run to report" and "a run
                // scoring 0": `DeathScreenNode.willEnter()` persists
                // whatever it is handed, so a manufactured zero summary
                // permanently appended a fake `score: 0` /
                // `SURVIVED 00:00` row to the real high-score table on
                // every `-goto death` launch -- after which that device's
                // high-scores screen could never show its empty state
                // again. `nil` still renders (as an all-zero, unrecorded
                // placeholder), so the call site stays well-defined
                // without the persistent side effect.
                guard let scene, let playerCombat = scene.playerCombat else {
                    return nil
                }
                return RunScoreCalculator.summarize(
                    runSummaryStats: scene.runStats,
                    runStats: playerCombat.runStats,
                    xpLevelSystem: playerCombat.xpLevelSystem,
                    elapsedSeconds: scene.runElapsedSeconds
                )
            },
            highScoreStore: scene.highScoreStore
        )
        // NOTE (`CYBERPUN-17-13-t5`): the real production entry point into
        // `.death` is `GameScene.advanceMovementAndCamera(currentTime:)`'s
        // HP-zero check, run once per `.gameplay` frame after every
        // HP-affecting update that frame (raccoon bites/rabies, the
        // player's own `update(...)`) has already applied. An earlier PR in
        // this story had deleted the last DEBUG-only launch bridge that used
        // to reach `.death` before this real trigger existed, leaving a
        // stretch where nothing in any build transitioned here except a
        // test's direct `stateMachine.transition(to: .death)` call -- that
        // gap is what this PR closed. This screen and everything behind it
        // (`RunScoreCalculator`, `HighScoreStore.recordRun`,
        // `HighScoresScreenNode`'s just-finished-run highlight, and the
        // `startNewRun()` RUN AGAIN entry point above) is reachable by a
        // player now, not only from a test.
        scene.register(deathScreen, for: .death)

        scene.register(
            HighScoresScreenNode(
                onBackToMenu: { [weak scene] in
                    scene?.stateMachine.transition(to: .menu)
                },
                highScoreStore: scene.highScoreStore,
                highlightedRunIDProvider: { [weak deathScreen] in
                    deathScreen?.lastRecordedRunID
                }
            ),
            for: .highScores
        )

        return scene
    }
}
