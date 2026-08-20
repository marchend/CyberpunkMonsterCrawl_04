import CoreGraphics
import SpriteKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-8` PR 2: `RaccoonSpawnDirector` -- off-screen street-tile
/// spawn selection, spawn cadence/ramp, swarm-size cap, elite fraction.
final class RaccoonSpawnDirectorTests: XCTestCase {

    // MARK: - Spawn tile selection: always street, never building (or lot)

    func test_selectSpawnTile_alwaysLandsOnAStreetTile_neverABuildingFootprintOrLot() {
        var rng = SplitMix64RandomNumberGenerator(seed: 42)
        let cameraPositions = [
            TilePoint(x: 0, y: 0),
            TilePoint(x: 500, y: -300),
            TilePoint(x: -1_200, y: 900),
        ]

        for cameraPosition in cameraPositions {
            for _ in 0..<200 {
                let tile = RaccoonSpawnDirector.selectSpawnTile(near: cameraPosition, rng: &rng)
                // Street classification never consults the seed
                // (`CityLatticeGenerator`'s own doc comment), so any seed
                // proves the point.
                let info = CityLatticeGenerator.classify(tileX: tile.tileX, tileY: tile.tileY, seed: WorldSeed(rawValue: 1))
                XCTAssertNotEqual(info.kind, .buildingFootprint, "spawn tile \(tile) landed on a building footprint")
                XCTAssertNotEqual(info.kind, .lot, "spawn tile \(tile) landed on an empty lot, not a street tile")
                XCTAssertTrue(info.isWalkable, "spawn tile \(tile) is not walkable")
            }
        }
    }

    // MARK: - Spawn tile selection: always off-screen

    func test_selectSpawnTile_isNeverOnScreen_fortheLargestSupportedViewport() {
        var rng = SplitMix64RandomNumberGenerator(seed: 7)
        let cameraPosition = TilePoint(x: 12, y: -8)
        let viewportSize = CGSize(
            width: ChunkStreamingManager.referenceViewportPoints.width,
            height: ChunkStreamingManager.referenceViewportPoints.height
        )

        for _ in 0..<500 {
            let tile = RaccoonSpawnDirector.selectSpawnTile(near: cameraPosition, rng: &rng)
            XCTAssertFalse(
                RaccoonSpawnDirector.isOnScreen(tile: tile, cameraPosition: cameraPosition, viewportSize: viewportSize),
                "spawn tile \(tile) is visible on the largest supported viewport"
            )
        }
    }

    // MARK: - isOnScreen itself

    func test_isOnScreen_isTrueForTheCamerasOwnTile() {
        let cameraPosition = TilePoint(x: 5, y: 5)
        XCTAssertTrue(
            RaccoonSpawnDirector.isOnScreen(
                tile: TileCoordinate(tileX: 5, tileY: 5),
                cameraPosition: cameraPosition,
                viewportSize: CGSize(width: 800, height: 600)
            )
        )
    }

    func test_isOnScreen_isFalseForATileFarBeyondTheViewport() {
        let cameraPosition = TilePoint(x: 0, y: 0)
        XCTAssertFalse(
            RaccoonSpawnDirector.isOnScreen(
                tile: TileCoordinate(tileX: 1_000, tileY: 1_000),
                cameraPosition: cameraPosition,
                viewportSize: CGSize(width: 800, height: 600)
            )
        )
    }

    // MARK: - Spawn cadence: the ramp curve

    func test_spawnInterval_atElapsedZero_equalsTheInitialInterval() {
        XCTAssertEqual(
            RaccoonSpawnDirector.spawnInterval(atElapsedTime: 0),
            RaccoonSpawnDirector.initialSpawnInterval,
            accuracy: 1e-9
        )
    }

    func test_spawnInterval_decreasesMonotonically_withElapsedTime_andNeverFallsBelowTheFloor() {
        let samples: [TimeInterval] = [0, 10, 30, 60, 120, 300, 3_000]
        var previous = RaccoonSpawnDirector.spawnInterval(atElapsedTime: 0)
        for elapsed in samples.dropFirst() {
            let interval = RaccoonSpawnDirector.spawnInterval(atElapsedTime: elapsed)
            XCTAssertLessThanOrEqual(interval, previous, "elapsed \(elapsed): spawn interval must not increase")
            XCTAssertGreaterThanOrEqual(
                interval, RaccoonSpawnDirector.minimumSpawnInterval - 1e-9,
                "elapsed \(elapsed): spawn interval must never fall below the floor"
            )
            previous = interval
        }
    }

    func test_spawnInterval_convergesToTheMinimum_afterAVeryLongRun() {
        let interval = RaccoonSpawnDirector.spawnInterval(atElapsedTime: 1_000_000)
        XCTAssertEqual(interval, RaccoonSpawnDirector.minimumSpawnInterval, accuracy: 1e-6)
    }

    // MARK: - Elite fraction, sampled within tolerance

    func test_selectTier_samplesTheEliteFraction_withinTolerance() {
        var rng = SplitMix64RandomNumberGenerator(seed: 99)
        let sampleCount = 20_000
        var eliteCount = 0
        for _ in 0..<sampleCount {
            if RaccoonSpawnDirector.selectTier(rng: &rng) == .elite {
                eliteCount += 1
            }
        }
        let observedFraction = Double(eliteCount) / Double(sampleCount)
        XCTAssertEqual(observedFraction, RaccoonSpawnDirector.eliteSpawnFraction, accuracy: 0.02)
    }

    // MARK: - Swarm size cap

    func test_update_neverExceedsMaxConcurrentSwarmSize_overALongRun() {
        let worldLayer = SKNode()
        let director = RaccoonSpawnDirector(worldLayer: worldLayer, rng: SplitMix64RandomNumberGenerator(seed: 3))
        let playerPosition = TilePoint(x: 0, y: 0)

        // 600 simulated seconds in small, deterministic steps -- comfortably
        // more than the worst case (40 raccoons at the *uncompressed*
        // initial 3s cadence is only 120s), so the cap is genuinely reached
        // and then held, not merely approached.
        for _ in 0..<6_000 {
            director.update(deltaTime: 0.1, playerPosition: playerPosition, player: nil, obstructions: [])
            XCTAssertLessThanOrEqual(director.swarmCount, RaccoonSpawnDirector.maxConcurrentSwarmSize)
        }

        XCTAssertEqual(
            director.swarmCount, RaccoonSpawnDirector.maxConcurrentSwarmSize,
            "a long enough run must fill the swarm to its cap"
        )
    }

    // MARK: - Cadence respected: nothing spawns before the initial interval elapses

    func test_update_spawnsNothing_beforeTheInitialIntervalElapses() {
        let worldLayer = SKNode()
        let director = RaccoonSpawnDirector(worldLayer: worldLayer, rng: SplitMix64RandomNumberGenerator(seed: 5))
        let playerPosition = TilePoint(x: 0, y: 0)

        var elapsed: TimeInterval = 0
        let step: TimeInterval = 0.1
        while elapsed + step < RaccoonSpawnDirector.initialSpawnInterval {
            director.update(deltaTime: step, playerPosition: playerPosition, player: nil, obstructions: [])
            elapsed += step
        }

        XCTAssertEqual(director.swarmCount, 0, "no raccoon should spawn before the initial spawn interval elapses")
    }

    func test_update_spawnsExactlyOne_perCall_evenOnAVeryLargeDeltaTime() {
        let worldLayer = SKNode()
        let director = RaccoonSpawnDirector(worldLayer: worldLayer, rng: SplitMix64RandomNumberGenerator(seed: 5))

        director.update(
            deltaTime: RaccoonSpawnDirector.initialSpawnInterval + 0.01,
            playerPosition: TilePoint(x: 0, y: 0),
            player: nil,
            obstructions: []
        )

        XCTAssertEqual(director.swarmCount, 1, "at most one raccoon may spawn per update(), regardless of deltaTime")
    }

    // MARK: - Spawned raccoons are actually mounted into the given world layer

    func test_spawnedRaccoons_areMountedIntoTheGivenWorldLayer() {
        let worldLayer = SKNode()
        let director = RaccoonSpawnDirector(worldLayer: worldLayer, rng: SplitMix64RandomNumberGenerator(seed: 5))

        director.update(
            deltaTime: RaccoonSpawnDirector.initialSpawnInterval + 0.01,
            playerPosition: TilePoint(x: 0, y: 0),
            player: nil,
            obstructions: []
        )

        XCTAssertEqual(worldLayer.children.count, 1)
        XCTAssertTrue(worldLayer.children.first is RaccoonNode)
    }

    // MARK: - The bite's attack animation actually reaches the sprite

    /// The production-path pin PR #35's review asked for: on the real
    /// per-frame loop, a raccoon that has closed to the standoff ring and
    /// bitten must end up **drawing** a `sprite_raccoon_attack` cell.
    ///
    /// Asserted on `RaccoonNode.body.texture`, deliberately *not* on
    /// `animationController.state`. This director runs
    /// `RaccoonSeekBehavior.update` (which plays walk, then refreshes the
    /// texture from the state) *before* `BiteComponent.update` (which plays
    /// attack), so a test reading the state straight after this method
    /// returned saw `.attack` and passed -- while the next frame's
    /// `playWalk()` cleared it again before any attack cell had ever been
    /// assigned, and the attack sheet never reached the screen in a shipped
    /// build. Only the texture can tell those two apart.
    func test_update_whenARaccoonReachesThePlayer_theBodyDrawsAnAttackCell() {
        let worldLayer = SKNode()
        let player = PlayerNode()
        let startingHP = player.hp
        let director = RaccoonSpawnDirector(
            worldLayer: worldLayer,
            rng: SplitMix64RandomNumberGenerator(seed: 11)
        )
        let playerPosition = TilePoint(x: 0, y: 0)

        // Real 60fps frames. 90 simulated seconds is comfortably past the
        // worst case for the first spawn (3s) to walk the guaranteed
        // off-screen gap in at `RaccoonSeekBehavior.pointsPerSecond`; the
        // loop stops the moment an attack cell is observed.
        let frameDelta: TimeInterval = 1.0 / 60.0
        let frameBudget = Int(90.0 / frameDelta)
        var drewAnAttackCell = false
        var frame = 0

        while frame < frameBudget && !drewAnAttackCell {
            director.update(
                deltaTime: frameDelta,
                playerPosition: playerPosition,
                player: player,
                obstructions: []
            )

            for raccoon in worldLayer.children.compactMap({ $0 as? RaccoonNode }) {
                let row = raccoon.animationController.currentRowMapping.row
                let attackCells = (0..<RaccoonAnimationController.frameCount).map {
                    RaccoonNode.texture(state: .attack, row: row, column: $0)
                }
                if attackCells.contains(where: { $0 === raccoon.body.texture }) {
                    drewAnAttackCell = true
                    break
                }
            }
            frame += 1
        }

        XCTAssertLessThan(
            player.hp, startingHP,
            "this test is only meaningful once a raccoon has actually reached the player and bitten"
        )
        XCTAssertTrue(
            drewAnAttackCell,
            "no raccoon ever drew a sprite_raccoon_attack cell on the production loop - the bite's "
                + "attack animation would be unobservable in a shipped build"
        )
    }

    // MARK: - syncPushedPosition: a pulse's shove survives the next frame

    /// Spawns a raccoon through the real per-frame loop, shoves it the way
    /// `GameScene.applyPulseHit(_:)` does, and runs one more frame.
    ///
    /// This is the regression `syncPushedPosition(_:for:)`'s doc comment
    /// describes and the one thing PR #48 left unproven (review): every live
    /// raccoon's screen position is re-derived from this director's own
    /// tracked tile position on *every* `update(...)`, so without the sync
    /// the next frame silently reverts the shove. Deleting the
    /// `activeRaccoons[index].position = position` line must turn this red.
    func test_syncPushedPosition_makesAPushSurviveTheNextUpdate() throws {
        let worldLayer = SKNode()
        let director = RaccoonSpawnDirector(worldLayer: worldLayer, rng: SplitMix64RandomNumberGenerator(seed: 5))
        let playerPosition = TilePoint(x: 0, y: 0)

        director.update(
            deltaTime: RaccoonSpawnDirector.initialSpawnInterval + 0.01,
            playerPosition: playerPosition,
            player: nil,
            obstructions: []
        )
        XCTAssertEqual(director.swarmCount, 1, "precondition: exactly one raccoon spawned through the director.")

        let spawned = try XCTUnwrap(director.targetCandidates.first)
        let raccoon = spawned.raccoon
        let spawnTile = spawned.position

        // A pulse-sized shove, well clear of a single frame's own steering
        // step (~0.05 tiles at RaccoonSeekBehavior.pointsPerSecond).
        let pushedTile = TilePoint(x: spawnTile.x + 12, y: spawnTile.y + 12)
        director.syncPushedPosition(pushedTile, for: raccoon)

        XCTAssertEqual(
            director.targetCandidates.first?.position, pushedTile,
            "the director's own tracked position must adopt the pushed tile immediately."
        )

        director.update(deltaTime: 1.0 / 60.0, playerPosition: playerPosition, player: nil, obstructions: [])

        let afterTile = try XCTUnwrap(director.targetCandidates.first?.position)
        XCTAssertLessThan(
            hypot(afterTile.x - pushedTile.x, afterTile.y - pushedTile.y), 0.5,
            "the next frame must steer *from* the pushed tile — it moved \(afterTile) instead."
        )
        XCTAssertGreaterThan(
            hypot(afterTile.x - spawnTile.x, afterTile.y - spawnTile.y), 1,
            "the raccoon snapped back toward its pre-push tile — the shove was silently undone."
        )
        XCTAssertEqual(
            raccoon.position,
            PixelCrispness.snappedPosition(for: IsometricProjection.tileToScreen(afterTile), scale: 1),
            "the mounted node's screen position must be re-derived from the pushed tile, not the stale one."
        )
    }

    func test_syncPushedPosition_isANoOp_forARaccoonThisDirectorNeverSpawned() {
        let worldLayer = SKNode()
        let director = RaccoonSpawnDirector(worldLayer: worldLayer, rng: SplitMix64RandomNumberGenerator(seed: 5))

        director.update(
            deltaTime: RaccoonSpawnDirector.initialSpawnInterval + 0.01,
            playerPosition: TilePoint(x: 0, y: 0),
            player: nil,
            obstructions: []
        )
        let trackedBefore = director.targetCandidates.map(\.position)

        // A hand-built raccoon this director has never seen: matched by node
        // identity, so it must not overwrite the tracked swarm's positions.
        director.syncPushedPosition(TilePoint(x: 99, y: 99), for: RaccoonNode(tier: .base))

        XCTAssertEqual(director.targetCandidates.map(\.position), trackedBefore)
    }

    // MARK: - reset()

    func test_reset_removesAllRaccoons_andRestartsTheSpawnTimer() {
        let worldLayer = SKNode()
        let director = RaccoonSpawnDirector(worldLayer: worldLayer, rng: SplitMix64RandomNumberGenerator(seed: 5))

        director.update(
            deltaTime: RaccoonSpawnDirector.initialSpawnInterval + 0.01,
            playerPosition: TilePoint(x: 0, y: 0),
            player: nil,
            obstructions: []
        )
        XCTAssertEqual(director.swarmCount, 1)

        director.reset()

        XCTAssertEqual(director.swarmCount, 0)
        XCTAssertEqual(worldLayer.children.count, 0, "reset() must remove the mounted node, not just forget it")

        // The timer restarted from scratch, so nothing spawns immediately.
        director.update(deltaTime: 0.1, playerPosition: TilePoint(x: 0, y: 0), player: nil, obstructions: [])
        XCTAssertEqual(director.swarmCount, 0)
    }
}
