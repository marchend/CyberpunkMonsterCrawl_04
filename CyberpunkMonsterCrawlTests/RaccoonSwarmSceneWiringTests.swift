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
