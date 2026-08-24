import CoreGraphics
import SpriteKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-8` PR 2: the swarm's *scene* wiring -- `GameScene.update(_:)`
/// driving `RaccoonSpawnDirector`, and (the half review caught) **not**
/// driving it once the run is over.
///
/// `advanceMovementAndCamera(currentTime:)` runs on every screen, and
/// neither `player` nor `playerWorldPosition` is cleared when a run ends, so
/// the director's own `guard` cannot tell a run from a death screen. These
/// tests assert on the scene's mounted nodes rather than on the director
/// (which is private to the scene), the same way `ThumbstickSceneWiringTests`
/// asserts on `playerWorldPosition` rather than on the controller.
///
/// Headless throughout (no `SKView`) -- see `ThumbstickSceneWiringTests` for
/// why the scene supports that by design.
final class RaccoonSwarmSceneWiringTests: XCTestCase {

    private let sceneSize = CGSize(width: 400, height: 800)

    private func makeGameplayScene() -> GameScene {
        let scene = GameScene(size: sceneSize)
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))
        return scene
    }

    /// Every raccoon currently mounted in the scene's world layer.
    private func mountedRaccoons(_ scene: GameScene) -> [RaccoonNode] {
        scene.worldLayer.children.compactMap { $0 as? RaccoonNode }
    }

    /// Drives `seconds` of production frames from `start`, in `step`-second
    /// slices. Coarser than 60fps on purpose: the spawn cadence starts at
    /// `RaccoonSpawnDirector.initialSpawnInterval` (3s), so a 60fps sweep
    /// long enough to spawn anything would be thousands of frames.
    ///
    /// **Why the HP top-up.** `CYBERPUN-17-13-t5` made `player.hp <= 0`
    /// transition the scene to `.death` by itself, once per `.gameplay`
    /// frame. These tests drive 12s of *live* gameplay against a stationary
    /// player while `RaccoonSpawnDirector` runs on its production default
    /// RNG (`SplitMix64RandomNumberGenerator(seed: UInt64.random(in:))`),
    /// so how much of the swarm converges and bites inside that window is a
    /// per-run coin flip -- and a window that ever added up to
    /// `PlayerNode.baseMaxHP` would leave the scene already in `.death`
    /// before the explicit `transition(to: .death)` below, which would then
    /// return `false` and fail these tests intermittently, keyed to nothing
    /// but a seed. Restoring full HP before each `.gameplay` frame takes
    /// the seed out of the question instead of leaving the margin to
    /// chance: at `initialSpawnInterval` 3s at most one raccoon spawns per
    /// elapsed interval, so a 12s window holds ~5, each biting at most once
    /// per `BiteComponent.biteIntervalSeconds` (1s) for `biteDamage` (5) --
    /// ~25 HP inside a 0.5s step against 100 restored.
    ///
    /// Death is not this suite's subject (spawn/steer gating is); the
    /// HP-zero trigger is pinned directly by `PlayerDeathTriggerTests`. A
    /// test that needs a *wounded* player must therefore not drive its
    /// frames through this helper.
    @discardableResult
    private func advance(
        _ scene: GameScene,
        seconds: TimeInterval,
        step: TimeInterval = 0.5,
        startingAt start: TimeInterval = 1
    ) -> TimeInterval {
        var now = start
        let end = start + seconds
        while now <= end {
            if scene.stateMachine.currentState == .gameplay {
                scene.player?.hp = PlayerNode.baseMaxHP
            }
            scene.update(now)
            now += step
        }
        return now
    }

    // MARK: - A run does drive the swarm

    func test_gameplayFrames_spawnRaccoonsIntoTheWorldLayer() {
        let scene = makeGameplayScene()
        XCTAssertEqual(mountedRaccoons(scene).count, 0, "no raccoon may exist before any frame has run")

        advance(scene, seconds: 12)

        XCTAssertGreaterThan(
            mountedRaccoons(scene).count, 0,
            "12s of gameplay frames must spawn raccoons -- the single production call site is what makes this story visible at all"
        )
    }

    // MARK: - The death screen does not

    func test_deathScreenFrames_spawnNoRaccoons_andDoNotSteerTheExistingSwarm() {
        let scene = makeGameplayScene()
        let afterRun = advance(scene, seconds: 12)

        let swarmAtDeath = mountedRaccoons(scene)
        XCTAssertGreaterThan(swarmAtDeath.count, 0, "the run must have produced a swarm to park")
        let positionsAtDeath = swarmAtDeath.map(\.position)

        XCTAssertEqual(
            scene.stateMachine.currentState, .gameplay,
            "precondition: the run must still be live -- `advance(_:)` keeps the player at full HP so the "
                + "HP-zero -> .death trigger (CYBERPUN-17-13-t5) cannot have fired inside the window above."
        )
        XCTAssertTrue(scene.stateMachine.transition(to: .death))

        // Far longer than the run itself: at the ramped cadence this would
        // be a dozen more spawns if the director were still being driven.
        advance(scene, seconds: 60, startingAt: afterRun)

        let swarmAfterDeath = mountedRaccoons(scene)
        XCTAssertEqual(
            swarmAfterDeath.count, swarmAtDeath.count,
            "the swarm must not grow while the death screen is up -- it spawns behind an opaque backdrop and ramps 'elapsed run time' outside a run"
        )
        XCTAssertEqual(
            swarmAfterDeath.map(\.position), positionsAtDeath,
            "no raccoon may be steered while the death screen is up"
        )
    }

    // MARK: - RUN AGAIN starts clean, and the swarm restarts with it

    func test_runAgain_resetsTheSwarm_andSpawningResumes() {
        let scene = makeGameplayScene()
        let afterRun = advance(scene, seconds: 12)
        XCTAssertGreaterThan(mountedRaccoons(scene).count, 0)

        XCTAssertEqual(
            scene.stateMachine.currentState, .gameplay,
            "precondition: the run must still be live -- `advance(_:)` keeps the player at full HP so the "
                + "HP-zero -> .death trigger (CYBERPUN-17-13-t5) cannot have fired inside the window above."
        )
        XCTAssertTrue(scene.stateMachine.transition(to: .death))
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))

        XCTAssertEqual(
            mountedRaccoons(scene).count, 0,
            "re-entering .gameplay must reset() the director, not inherit the previous run's raccoons"
        )

        advance(scene, seconds: 12, startingAt: afterRun)
        XCTAssertGreaterThan(
            mountedRaccoons(scene).count, 0,
            "the gate must re-open on a new run, not latch the swarm off after the first death"
        )
    }
}
