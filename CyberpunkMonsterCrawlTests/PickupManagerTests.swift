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
        obstructionsProvider: @escaping () -> [BuildingPlacementRecord] = { [] },
        isVisibleOnScreen: ((TileCoordinate) -> Bool)? = nil
    ) -> PickupManager {
        PickupManager(
            worldSeed: seed,
            obstructionsProvider: obstructionsProvider,
            isVisibleOnScreen: isVisibleOnScreen,
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

    /// A tile-space `visibleRect` covering the whole 3x3 crossing area
    /// around `tile` -- every one of those 9 tiles is street (see
    /// `knownGoodStreetTile`), so both kinds can find a legal tile on the
    /// same tick without stacking on each other.
    ///
    /// Needed wherever a test wants two pickups alive at once: since
    /// `PickupManager.isLegalPlacement` now rejects a tile an active pickup
    /// already occupies, `narrowVisibleRect`'s single candidate tile can
    /// hold exactly one pickup at a time by construction.
    private func crossingVisibleRect(around tile: TileCoordinate) -> CGRect {
        narrowVisibleRect(around: tile, halfExtent: 1.4)
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
        // The 3x3 crossing, not the single-tile rect: with the
        // one-pickup-per-tile rule a single candidate tile serializes the
        // two kinds behind each other, which would measure tile contention
        // rather than the med kit's own cadence.
        let rect = crossingVisibleRect(around: knownGoodStreetTile)
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

    /// The cap invariant, **plus an anti-vacuity guard on it.**
    ///
    /// `aliveCount <= maxAlive` alone is vacuous at the frozen tuning: with
    /// `spawnCadence` 25s longer than `lifetime` 20s, and the cadence only
    /// re-arming after a successful spawn, a pickup always expires before
    /// its kind's next spawn attempt -- the observed ceiling is 1, so the
    /// `maxAlive: 2` cap (and `PickupManager.update`'s hold-at-0 "no room"
    /// branch) is never reached. `PickupKind.Tuning.maxAlive` records that;
    /// the peak assertion below pins it, so a retune that makes the cap
    /// reachable turns this red instead of quietly shipping an unexercised
    /// branch under a green suite.
    func test_maxAlivePerKind_isNeverExceeded_andTheObservedCeilingIsPinned() {
        let manager = makeManager()
        let rect = crossingVisibleRect(around: knownGoodStreetTile)
        let step: TimeInterval = 1.0

        var elapsed: TimeInterval = 0
        var peakAlive: [PickupKind: Int] = [:]
        while elapsed < 300 {
            manager.update(deltaTime: step, visibleRect: rect)
            elapsed += step

            for kind in PickupKind.allCases {
                let aliveCount = manager.activePickups.filter { $0.kind == kind }.count
                XCTAssertLessThanOrEqual(
                    aliveCount, kind.tuning.maxAlive,
                    "\(kind) exceeded its max-alive cap of \(kind.tuning.maxAlive) at t=\(elapsed)s"
                )
                peakAlive[kind] = max(peakAlive[kind] ?? 0, aliveCount)
            }
        }

        for kind in PickupKind.allCases {
            XCTAssertEqual(
                peakAlive[kind], 1,
                "\(kind) peaked at \(peakAlive[kind] ?? 0) alive over 300s. The assertion above is only "
                    + "meaningful if this ceiling is 1: at the frozen tuning (cadence "
                    + "\(kind.tuning.spawnCadence)s > lifetime \(kind.tuning.lifetime)s) the "
                    + "maxAlive cap of \(kind.tuning.maxAlive) is unreachable, as "
                    + "PickupKind.Tuning.maxAlive documents. If the tuning changed so the cap is now "
                    + "reachable, add a test that exercises the cap branch and update that doc rather "
                    + "than relaxing this guard."
            )
        }
    }

    // MARK: - Lifetime: expires strictly by age

    func test_pickup_expiresExactlyAtTwentySecondsOfAge() {
        let manager = makeManager()
        // The 3x3 crossing, so both kinds spawn (and therefore both expire)
        // on the same schedule. On the single-tile rect the second kind's
        // spawn is deferred by the one-pickup-per-tile rule and would land
        // the instant the first expires, leaving `activePickups` non-empty
        // for a reason this test is not about.
        let rect = crossingVisibleRect(around: knownGoodStreetTile)

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
        let nearbyRect = crossingVisibleRect(around: knownGoodStreetTile)

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

    /// The story's rule is "the chosen tile **and** all 8 neighbours must be
    /// building-free", so an obstruction on the candidate tile *itself* --
    /// not merely beside it -- must also block the spawn. The injected
    /// record deliberately sits on a tile `CityLatticeGenerator.classify`
    /// still calls street, which is exactly the disagreement the street-kind
    /// check alone could not catch.
    func test_obstructionOnTheCandidateTileItself_preventsSpawning() {
        let tile = knownGoodStreetTile
        let obstruction = makeBuildingRecord(at: tile)

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
            "no pickup should ever spawn on a tile a building footprint occupies, however the lattice "
                + "happens to classify that tile"
        )
    }

    /// The same configuration as the two obstructed cases above, but with no
    /// obstruction at all -- proving their silence is really caused by the
    /// injected building, not by some unrelated reason spawning never
    /// happens at that tile.
    func test_sameTileWithoutObstruction_doesSpawn() {
        let tile = knownGoodStreetTile
        let manager = makeManager(rngSeed: 99, obstructionsProvider: { [] })
        let rect = narrowVisibleRect(around: tile)

        manager.update(deltaTime: 8, visibleRect: rect)

        XCTAssertFalse(manager.activePickups.isEmpty, "expected a spawn once the obstruction is removed")
    }

    // MARK: - One pickup per tile

    /// Both kinds share `firstSpawnDelay` and `spawnCadence`, so they draw
    /// from the same visible rect on the same tick. With only one legal
    /// tile available, the second kind must be turned away rather than
    /// stacking a second 32pt icon on the first at an identical depth
    /// offset.
    func test_twoKinds_doNotStackOnTheOnlyLegalTile() {
        let manager = makeManager()
        let rect = narrowVisibleRect(around: knownGoodStreetTile) // exactly one candidate tile

        manager.update(deltaTime: 8, visibleRect: rect)

        XCTAssertEqual(
            manager.activePickups.count, 1,
            "a single legal tile can hold one pickup; a second pickup here would draw on top of the first"
        )
    }

    /// The same rule across a long run and a rect with room to spread out:
    /// no two active pickups may ever share a tile.
    func test_noTwoActivePickups_everShareATile() {
        let manager = makeManager()
        let rect = crossingVisibleRect(around: knownGoodStreetTile)
        let step: TimeInterval = 1.0

        var elapsed: TimeInterval = 0
        while elapsed < 300 {
            manager.update(deltaTime: step, visibleRect: rect)
            elapsed += step

            let tiles = manager.activePickups.map { pickup in
                "\(Int(pickup.position.x.rounded())),\(Int(pickup.position.y.rounded()))"
            }
            XCTAssertEqual(
                Set(tiles).count, tiles.count,
                "two pickups occupy the same tile at t=\(elapsed)s: \(manager.activePickups.map(\.position))"
            )
        }
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
        // The 3x3 crossing: a garbage can needs a tile of its own now that
        // the med kit spawning on the same tick claims one.
        let rect = crossingVisibleRect(around: knownGoodStreetTile)
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

    // MARK: - Retiring a raccoon-consumed can, by identity (PR #38 review)

    func test_expireConsumedGarbageCanByID_retiresThatExactRecord_andIsANoOpTheSecondTime() throws {
        let manager = makeManager(rngSeed: 5)
        manager.update(deltaTime: 8, visibleRect: crossingVisibleRect(around: knownGoodStreetTile))

        let garbageCan = try XCTUnwrap(manager.activePickups.first { $0.kind == .garbageCan })

        XCTAssertTrue(manager.expireConsumedGarbageCan(id: garbageCan.id))
        XCTAssertTrue(
            manager.activePickups.first { $0.id == garbageCan.id }?.isConsumed == true,
            "the record must be marked consumed in place, pruned by the next update -- never re-rolled"
        )

        // Already retired: a second call finds nothing, rather than
        // silently marking some other can.
        XCTAssertFalse(manager.expireConsumedGarbageCan(id: garbageCan.id))
        // ...and a med kit's id is never matched by the garbage-can API.
        let medKit = try XCTUnwrap(manager.activePickups.first { $0.kind == .medKit })
        XCTAssertFalse(manager.expireConsumedGarbageCan(id: medKit.id))
        XCTAssertEqual(
            manager.activePickups.first { $0.id == medKit.id }?.isConsumed, false,
            "the garbage-can retire API must never consume a med kit, whatever id it is handed"
        )
    }

    // MARK: - Screen-space visibility predicate (PR #38 review)

    func test_aCandidateTileRejectedByTheVisibilityPredicate_isNeverSpawnedOn() {
        let manager = makeManager(rngSeed: 5, isVisibleOnScreen: { _ in false })
        manager.update(deltaTime: 8, visibleRect: crossingVisibleRect(around: knownGoodStreetTile))

        XCTAssertTrue(
            manager.activePickups.isEmpty,
            "visibleRect is only the bounding box of the visible region -- a tile the screen-space predicate rejects "
                + "must not be spawned on, however legal it is otherwise"
        )
    }

    func test_theVisibilityPredicate_isNotConsultedForAlreadyPlacedPickups() {
        var isVisible = true
        let manager = makeManager(rngSeed: 5, isVisibleOnScreen: { _ in isVisible })
        manager.update(deltaTime: 8, visibleRect: crossingVisibleRect(around: knownGoodStreetTile))
        XCTAssertFalse(manager.activePickups.isEmpty, "sanity: a visible crossing must place at least one pickup")
        let placed = manager.activePickups.map(\.id)

        // The camera turns away: placement is blocked from here on, but an
        // already-placed pickup is never re-validated or removed -- age is
        // the only lifetime clock (this type's own doc comment).
        isVisible = false
        manager.update(deltaTime: 1, visibleRect: crossingVisibleRect(around: knownGoodStreetTile))

        XCTAssertEqual(
            manager.activePickups.map(\.id), placed,
            "an off-camera pickup must keep ageing on the ground, not be culled by visibility"
        )
    }

    // MARK: - Per-run reset (PR #38 review)

    func test_reset_clearsActivePickups_andReArmsBothKindsFirstSpawnDelay() {
        let manager = makeManager(rngSeed: 5)
        let rect = crossingVisibleRect(around: knownGoodStreetTile)
        manager.update(deltaTime: 8, visibleRect: rect)
        XCTAssertFalse(manager.activePickups.isEmpty, "sanity: run 1 must have spawned something to inherit")

        manager.reset()

        XCTAssertTrue(manager.activePickups.isEmpty, "reset() must drop every pickup left over from the previous run")

        // The cadence is re-armed from the top, not left wherever run 1
        // stopped: one second short of `firstSpawnDelay` still spawns
        // nothing.
        manager.update(deltaTime: PickupKind.medKit.tuning.firstSpawnDelay - 1, visibleRect: rect)
        XCTAssertTrue(
            manager.activePickups.isEmpty,
            "a reset manager must wait the full firstSpawnDelay again, rather than inheriting run 1's remaining timer"
        )

        manager.update(deltaTime: 1, visibleRect: rect)
        XCTAssertFalse(manager.activePickups.isEmpty, "the re-armed timer must then elapse and spawn as usual")
    }

    func test_resetWithANewWorldSeed_validatesPlacementAgainstTheNewCity() {
        let manager = makeManager(rngSeed: 5)
        let otherSeed = WorldSeed(rawValue: 0x0C17_5EED)
        manager.reset(worldSeed: otherSeed)

        // A crossing of the *new* seed's own city: legal only if placement
        // is now classified against that seed rather than the constructed
        // one.
        let newCityTile = RunSpawnSelector.selectSpawnTile(seed: otherSeed)
        manager.update(deltaTime: 8, visibleRect: crossingVisibleRect(around: newCityTile))

        XCTAssertFalse(
            manager.activePickups.isEmpty,
            "after reset(worldSeed:) the manager must classify candidate tiles against the new city"
        )
        for pickup in manager.activePickups {
            let info = CityLatticeGenerator.classify(
                tileX: Int(pickup.position.x.rounded()),
                tileY: Int(pickup.position.y.rounded()),
                seed: otherSeed
            )
            XCTAssertNotEqual(info.kind, .buildingFootprint, "a pickup must never be placed on a building tile")
            XCTAssertNotEqual(info.kind, .lot, "a pickup must only be placed on a street sub-kind")
        }
    }
}
