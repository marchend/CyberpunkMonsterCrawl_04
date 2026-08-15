import CoreGraphics
import SpriteKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// CYBERPUN-17-6-t2: `PlayerNode` has a production caller.
///
/// `GroundTileRenderer`'s type doc states the rule this file enforces --
/// *"A factory with no production caller is exactly the shape of feature
/// that never gets switched on, so the mount is wired here rather than
/// deferred"*. Entering `.gameplay` must therefore put a real player in
/// `worldLayer`, correctly depth-banded, and `GameScene.update(_:)` must
/// drive its per-frame state, so the anchor/shadow/depth integration is
/// reachable from a running build instead of from unit tests only.
///
/// Movement itself is still `CYBERPUN-17-7`'s (the vector is `.zero` until
/// the thumbstick exists), so nothing here asserts the player walks -- only
/// that it is mounted, placed, depth-banded and ticked.
final class PlayerMountTests: XCTestCase {

    private func makeScene() -> GameScene {
        GameScene(size: CGSize(width: 400, height: 800))
    }

    // MARK: - The mount happens at all

    func test_enteringGameplay_mountsThePlayer_asADirectChildOfWorldLayer() {
        let scene = makeScene()
        XCTAssertNil(scene.player, "Nothing should be mounted before the first .gameplay entry.")

        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))

        guard let player = scene.player else {
            return XCTFail("Entering .gameplay must mount the player.")
        }
        XCTAssertTrue(
            player.parent === scene.worldLayer,
            "The player must be a *direct* child of worldLayer -- PlayerNode.updateDepth converts its "
                + "depth with DepthModel.worldLayerRelativeZ, which is only correct for a direct child."
        )
        XCTAssertTrue(scene.worldLayer.children.contains { $0 === player })
    }

    func test_theMountedPlayer_carriesItsShadowAndBody_asSeparateNodes() {
        let scene = makeScene()
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))

        guard let player = scene.player else {
            return XCTFail("Entering .gameplay must mount the player.")
        }
        XCTAssertTrue(player.children.contains { $0 === player.shadow })
        XCTAssertTrue(player.children.contains { $0 === player.body })
        XCTAssertLessThan(player.shadow.zPosition, player.body.zPosition)
    }

    // MARK: - Placement and depth

    func test_theMountedPlayer_isPlacedAtTheCamerasTile_withDepthBandingsZPosition() {
        let scene = makeScene()
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))

        guard let player = scene.player else {
            return XCTFail("Entering .gameplay must mount the player.")
        }

        let tilePosition = scene.cameraWorldPosition
        let expectedPosition = IsometricProjection.tileToScreen(tileX: tilePosition.x, tileY: tilePosition.y)
        XCTAssertEqual(player.position.x, expectedPosition.x, accuracy: 1e-6)
        XCTAssertEqual(player.position.y, expectedPosition.y, accuracy: 1e-6)

        let expectedAbsolute = DepthBanding.playerZPosition(at: tilePosition)
        let expectedRelative = DepthModel.worldLayerRelativeZ(forAbsoluteZ: expectedAbsolute)
        // `0.01` for the same reason `PlayerDepthTests` uses it: SpriteKit
        // may store a live node's zPosition at `Float` precision.
        XCTAssertEqual(player.zPosition, expectedRelative, accuracy: 0.01)
    }

    func test_theMountedPlayer_keepsTheScenesLayerInvariantsIntact() {
        let scene = makeScene()
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))

        XCTAssertTrue(
            scene.nodesEscapingTheirLayerBand().isEmpty,
            "The mounted player escaped the world band: \(scene.layerBandViolationReport())"
        )
        XCTAssertTrue(
            scene.nodesBypassingSceneTouchDispatch().isEmpty,
            "The player (or its shadow) opted into UIKit touch delivery and would bypass the scene's dispatch."
        )
    }

    // MARK: - Restarting a run

    func test_restartingARun_reusesTheSamePlayerNode_ratherThanMountingASecondOne() {
        let scene = makeScene()
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))
        let firstPlayer = scene.player
        XCTAssertNotNil(firstPlayer)

        XCTAssertTrue(scene.stateMachine.transition(to: .death))
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))

        XCTAssertTrue(
            scene.player === firstPlayer,
            "RUN AGAIN must reuse the mounted player, not build a second one."
        )
        XCTAssertEqual(
            scene.worldLayer.children.filter { $0 is PlayerNode }.count, 1,
            "Two PlayerNodes in worldLayer is a duplicated actor at the same depth, not a cosmetic bug."
        )
    }

    func test_restartingARunWithADifferentSeed_leavesThePlayerMounted() {
        // A new seed replaces the ground streamer (and unmounts its nodes);
        // the player is not the streamer's, so it must survive that.
        let scene = makeScene()
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))

        XCTAssertTrue(scene.stateMachine.transition(to: .death))
        scene.worldSeed = WorldSeed(rawValue: scene.worldSeed.rawValue &+ 1)
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))

        guard let player = scene.player else {
            return XCTFail("Re-entering .gameplay with a new seed must leave a player mounted.")
        }
        XCTAssertTrue(player.parent === scene.worldLayer)
    }

    // MARK: - The per-frame drive

    func test_sceneUpdate_drivesThePlayersPerFrameState_idleAtFrameZero() {
        let scene = makeScene()
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))

        guard let player = scene.player else {
            return XCTFail("Entering .gameplay must mount the player.")
        }

        scene.update(1)
        scene.update(1 + PlayerAnimator.secondsPerFrame * 3)

        // The scene passes `.zero` until CYBERPUN-17-7's thumbstick lands, so
        // the player stands still, keeps its default facing and stays frozen
        // on the walk cycle's first frame -- however much time passes.
        XCTAssertFalse(player.isMoving)
        XCTAssertEqual(player.facing, .south)

        let southRow = PlayerSpriteSheet.rowMapping(for: .south).row
        XCTAssertTrue(
            player.body.texture === PlayerNode.texture(row: southRow, column: PlayerAnimator.frameContactFirst),
            "An idle player must stay on frame 0 rather than cycling on the render clock."
        )
    }

    func test_sceneUpdate_neverHandsThePlayerANegativeDelta_whenTheRenderClockGoesBackwards() {
        // A scene presented, backgrounded and re-presented can hand back a
        // smaller `currentTime`; a negative delta would run the walk cycle
        // backwards. Driving it must simply not trap or misbehave.
        let scene = makeScene()
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))

        scene.update(100)
        scene.update(1)

        XCTAssertEqual(scene.player?.isMoving, false)
        XCTAssertEqual(scene.player?.facing, .south)
    }
}
