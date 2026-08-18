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
