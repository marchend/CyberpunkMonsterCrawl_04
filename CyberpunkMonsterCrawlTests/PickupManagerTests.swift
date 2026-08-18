import CoreGraphics
import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-11` PR 1: `PickupManager` -- spawn cadence/max-alive/
/// lifetime-by-age and placement validation, all independently testable
/// without any scene wiring.
final class PickupManagerTests: XCTestCase {

    private let seed = WorldSeed(rawValue: 0x9BAD_F00D)

    private func makeManager(
        rngSeed: UInt64 = 1,
        obstructionsProvider: @escaping () -> [BuildingPlacementRecord] = { [] }
    ) -> PickupManager {
        PickupManager(
            worldSeed: seed,
            obstructionsProvider: obstructionsProvider,
            rng: SplitMix64RandomNumberGenerator(seed: rngSeed)
        )
    }

    /// `RunSpawnSelector.selectSpawnTile(seed:)` always lands on a lattice
    /// crossing's exact driving-lane centre -- every one of its 8
    /// neighbours is therefore *also* street (the full 3x3 crossing area is
    /// all street sub-kinds; see `CityLatticeGenerator.streetTileKind`), so
    /// this is a known-good, deterministic placement candidate with no
    /// dependency on how any particular seed happens to lay out block
    /// interiors around it.
    private var knownGoodStreetTile: TileCoordinate {
        RunSpawnSelector.selectSpawnTile(seed: seed)
    }

    /// A tile-space `visibleRect` so narrow around `knownGoodStreetTile`
    /// that every random draw `PickupManager.selectSpawnPosition` makes
    /// rounds back to that exact tile -- making placement outcomes fully
    /// deterministic rather than probabilistic.
    private func narrowVisibleRect(around tile: TileCoordinate, halfExtent: Double = 0.4) -> CGRect {
        CGRect(
            x: CGFloat(Double(tile.tileX) - halfExtent),
            y: CGFloat(Double(tile.tileY) - halfExtent),
            width: CGFloat(halfExtent * 2),
            height: CGFloat(halfExtent * 2)
        )
    }

    private func makeBuildingRecord(at tile: TileCoordinate) -> BuildingPlacementRecord {
        BuildingPlacementRecord(
            lotTile: tile,
            building: BuildingCatalog.entry(atIndex: 0),
            footprintTiles: [tile],
            farCornerTile: tile
        )
    }

    // MARK: - First spawn timing

    func test_firstSpawn_occursAtOrBeforeEightSeconds() {
        let manager = makeManager()
        let rect = narrowVisibleRect(around: knownGoodStreetTile)

        manager.update(deltaTime: 8, visibleRect: rect)

        XCTAssertFalse(manager.activePickups.isEmpty, "expected at least one pickup spawned by 8s into the run")
        XCTAssertTrue(
            manager.activePickups.allSatisfy { $0.age == 0 },
            "a pickup spawned on this very tick must start at age 0"
        )
    }

    func test_noSpawnOccurs_beforeTheFirstSpawnDelayElapses() {
        let manager = makeManager()
        let rect = narrowVisibleRect(around: knownGoodStreetTile)

        manager.update(deltaTime: 7.9, visibleRect: rect)

        XCTAssertTrue(manager.activePickups.isEmpty, "no pickup should spawn before the 8s first-spawn delay elapses")
    }

    // MARK: - Cadence: ~25s between spawns of the same kind

    func test_cadence_isTwentyFiveSecondsBetweenSuccessiveSpawnsOfTheSameKind() {
        let manager = makeManager()
        let rect = narrowVisibleRect(around: knownGoodStreetTile)
        let step: TimeInterval = 0.25

        var elapsed: TimeInterval = 0
        var firstSpawnTime: TimeInterval?
        var secondSpawnTime: TimeInterval?
        var previousMedKitCount = 0

        while elapsed < 40, secondSpawnTime == nil {
            manager.update(deltaTime: step, visibleRect: rect)
            elapsed += step

            let medKitCount = manager.activePickups.filter { $0.kind == .medKit }.count
            if medKitCount > previousMedKitCount {
                if firstSpawnTime == nil {
                    firstSpawnTime = elapsed
                } else {
                    secondSpawnTime = elapsed
                }
            }
            previousMedKitCount = medKitCount
        }

        guard let first = firstSpawnTime, let second = secondSpawnTime else {
            XCTFail("expected two med kit spawns within 40 simulated seconds")
            return
        }
        XCTAssertEqual(
            second - first, PickupKind.medKit.tuning.spawnCadence, accuracy: step,
            "cadence between successive med kit spawns should be ~25s"
        )
    }

    // MARK: - Max alive per kind

    func test_maxAlivePerKind_isNeverExceeded() {
        let manager = makeManager()
        let rect = narrowVisibleRect(around: knownGoodStreetTile)
        let step: TimeInterval = 1.0

        var elapsed: TimeInterval = 0
        while elapsed < 300 {
            manager.update(deltaTime: step, visibleRect: rect)
            elapsed += step

            for kind in PickupKind.allCases {
                let aliveCount = manager.activePickups.filter { $0.kind == kind }.count
                XCTAssertLessThanOrEqual(
                    aliveCount, kind.tuning.maxAlive,
                    "\(kind) exceeded its max-alive cap of \(kind.tuning.maxAlive) at t=\(elapsed)s"
                )
            }
        }
    }

    // MARK: - Lifetime: expires strictly by age

    func test_pickup_expiresExactlyAtTwentySecondsOfAge() {
        let manager = makeManager()
        let rect = narrowVisibleRect(around: knownGoodStreetTile)

        manager.update(deltaTime: 8, visibleRect: rect) // spawns at age 0
        XCTAssertFalse(manager.activePickups.isEmpty)

        manager.update(deltaTime: 19.5, visibleRect: rect) // age == 19.5
        XCTAssertFalse(manager.activePickups.isEmpty, "a pickup must not expire before its lifetime elapses")

        manager.update(deltaTime: 0.5, visibleRect: rect) // age == 20.0 exactly
        XCTAssertTrue(manager.activePickups.isEmpty, "a pickup must expire the instant its age reaches its lifetime")
    }

    /// Aging must be driven **only** by the real `deltaTime` argument, never
    /// by anything derived from `visibleRect` moving between calls -- a
    /// camera teleporting far away must not shorten (or lengthen) a
    /// pickup's remaining lifetime.
    func test_largeVisibleRectJumpBetweenUpdates_doesNotAffectPickupAging() {
        let manager = makeManager()
        let nearbyRect = narrowVisibleRect(around: knownGoodStreetTile)

        manager.update(deltaTime: 8, visibleRect: nearbyRect) // spawns at age 0
        XCTAssertFalse(manager.activePickups.isEmpty)

        // A huge, discontinuous jump in the visible rect (a camera teleport)
        // between two update calls.
        let farRect = CGRect(x: 1_000_000, y: -1_000_000, width: 4, height: 4)

        manager.update(deltaTime: 19.5, visibleRect: farRect) // age == 19.5
        XCTAssertFalse(
            manager.activePickups.isEmpty,
            "a visible-rect jump between calls must not expire a pickup before its real elapsed deltaTime does"
        )

        manager.update(deltaTime: 0.5, visibleRect: farRect) // age == 20.0 exactly
        XCTAssertTrue(
            manager.activePickups.isEmpty,
            "the pickup should still expire at exactly its real accumulated deltaTime lifetime"
        )
    }

    // MARK: - Placement validation: street tile, within the visible rect

    func test_everySpawnedPickup_landsOnAStreetTile_withinTheVisibleRect() {
        let manager = makeManager(rngSeed: 99)
        let tile = knownGoodStreetTile
        let rect = narrowVisibleRect(around: tile)

        manager.update(deltaTime: 8, visibleRect: rect)

        XCTAssertFalse(manager.activePickups.isEmpty)
        for pickup in manager.activePickups {
            let info = CityLatticeGenerator.classify(
                tileX: Int(pickup.position.x), tileY: Int(pickup.position.y), seed: seed
            )
            XCTAssertTrue(
                [.asphalt, .junctionStopLine, .kerbSidewalk].contains(info.kind),
                "spawned pickup at \(pickup.position) sits on non-street tile kind \(info.kind)"
            )
            XCTAssertTrue(
                rect.contains(CGPoint(x: CGFloat(pickup.position.x), y: CGFloat(pickup.position.y))),
                "spawned pickup at \(pickup.position) is outside the visible rect it was spawned within"
            )
        }
    }

    /// Injects a synthetic building obstruction adjacent to the only
    /// candidate tile the narrow visible rect allows, rather than assuming
    /// any particular generator layout (per this project's established
    /// pattern -- see `BuildingCollisionTests`). With that neighbour
    /// obstructed, the sole candidate tile is illegal and no pickup of
    /// either kind should ever spawn, however long the run continues.
    func test_obstructedNeighbourTile_preventsSpawningAtAnOtherwiseLegalStreetTile() {
        let tile = knownGoodStreetTile
        let obstructedNeighbour = TileCoordinate(tileX: tile.tileX - 1, tileY: tile.tileY)
        let obstruction = makeBuildingRecord(at: obstructedNeighbour)

        let manager = makeManager(rngSeed: 99, obstructionsProvider: { [obstruction] })
        let rect = narrowVisibleRect(around: tile)

        let step: TimeInterval = 1.0
        var elapsed: TimeInterval = 0
        while elapsed < 60 {
            manager.update(deltaTime: step, visibleRect: rect)
            elapsed += step
        }

        XCTAssertTrue(
            manager.activePickups.isEmpty,
            "no pickup should ever spawn at a tile whose neighbour is obstructed by a building"
        )
    }

    /// The same configuration as the obstructed case above, but without the
    /// obstruction -- proving the previous test's silence is really caused
    /// by the injected building, not by some unrelated reason spawning
    /// never happens at that tile.
    func test_sameTileWithoutObstruction_doesSpawn() {
        let tile = knownGoodStreetTile
        let manager = makeManager(rngSeed: 99, obstructionsProvider: { [] })
        let rect = narrowVisibleRect(around: tile)

        manager.update(deltaTime: 8, visibleRect: rect)

        XCTAssertFalse(manager.activePickups.isEmpty, "expected a spawn once the obstruction is removed")
    }

    // MARK: - Collection queries

    func test_attemptCollectMedKit_consumesTheNearestMedKitWithinRadius_andReturnsARollInDiceRange() {
        let manager = makeManager(rngSeed: 5)
        let rect = narrowVisibleRect(around: knownGoodStreetTile)
        manager.update(deltaTime: 8, visibleRect: rect)

        let medKit = manager.activePickups.first { $0.kind == .medKit }
        XCTAssertNotNil(medKit)
        guard let position = medKit?.position else { return }

        let roll = manager.attemptCollectMedKit(at: position, radius: 0.5)
        XCTAssertNotNil(roll)
        if let roll {
            XCTAssertTrue(PickupKind.medKit.tuning.dice.range.contains(roll))
        }

        // Consumed -- a second attempt at the same spot must find nothing.
        XCTAssertNil(manager.attemptCollectMedKit(at: position, radius: 0.5))
    }

    func test_attemptCollectMedKit_returnsNil_whenNothingIsWithinRadius() {
        let manager = makeManager(rngSeed: 5)
        let farAway = TilePoint(x: 999_999, y: 999_999)
        XCTAssertNil(manager.attemptCollectMedKit(at: farAway, radius: 1))
    }

    func test_nearestGarbageCan_findsAnActiveGarbageCanWithoutConsumingIt() {
        let manager = makeManager(rngSeed: 5)
        let rect = narrowVisibleRect(around: knownGoodStreetTile)
        manager.update(deltaTime: 8, visibleRect: rect)

        let garbageCan = manager.activePickups.first { $0.kind == .garbageCan }
        XCTAssertNotNil(garbageCan)
        guard let position = garbageCan?.position else { return }

        let found = manager.nearestGarbageCan(within: 0.5, of: position)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.id, garbageCan?.id)

        // A read-only query -- the pickup must still be collectable afterward.
        XCTAssertNotNil(manager.attemptCollectGarbageCan(at: position, radius: 0.5))
    }
}
