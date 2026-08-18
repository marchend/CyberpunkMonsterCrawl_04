import CoreGraphics
import Foundation

/// Pure spawn/placement/lifetime engine for ground pickups (med kits,
/// garbage cans) -- no SpriteKit dependency, mirroring
/// `ChunkStreamingManager` / `RaccoonSpawnDirector`'s own "logic first,
/// rendering is a later PR" split. `PickupNode` (this same PR) is the
/// SpriteKit half; nothing mounts one yet -- `CYBERPUN-17-11` PR 1's scope
/// is explicitly "no scene wiring". No invented ticket ID is given for that
/// wiring here: the authoritative list of what is implemented versus still
/// outstanding for this story (the scene mount, applying a med kit's 1d10
/// heal, diverting a wounded raccoon to a garbage can) is the
/// `CYBERPUN-17-11` entry in AGENT.md/CLAUDE.md -- read that rather than
/// inferring the remaining scope from these doc comments, the same
/// convention `RaccoonSpawnDirector` follows.
///
/// **Per-kind spawn/cadence timers.** Each `PickupKind` counts down its own
/// `PickupKind.Tuning.firstSpawnDelay` once, then re-arms at
/// `PickupKind.Tuning.spawnCadence` after every successful spawn --
/// `RaccoonSpawnDirector.timeUntilNextSpawn`'s own pattern, generalized to
/// two independent kinds instead of one swarm. A kind already at its
/// `maxAlive` cap, or one whose placement search this tick found nowhere
/// legal, holds its timer at exactly `0` rather than accumulating a
/// backlog of missed spawns -- the same "retry next tick, don't burst" rule
/// `RaccoonSpawnDirector.update` documents for its own swarm cap.
///
/// **Age is the only lifetime clock.** `update(deltaTime:visibleRect:)`
/// advances every active pickup's `age` by `deltaTime` alone -- never by
/// anything derived from `visibleRect` (a camera jump, a viewport resize) --
/// so a pickup's on-ground lifetime cannot be shortened or lengthened by how
/// far the camera has moved between two calls. `PickupManagerTests` pins
/// this directly: a huge `visibleRect` jump between two `update` calls must
/// never expire a pickup before its real accumulated `deltaTime` reaches
/// `PickupKind.Tuning.lifetime`.
///
/// **Placement validation, at spawn-attempt time only.** A candidate tile
/// must be (a) classified a *street* kind by `CityLatticeGenerator.classify`
/// -- asphalt, junction stop-line or kerb-sidewalk, never a `.lot` or
/// `.buildingFootprint` block-interior tile -- (b) unoccupied by any
/// already-active pickup of *either* kind, and (c) have the tile itself and
/// all 8 of its neighbours free of any building footprint, checked via
/// `BuildingObstruction.isObstructed(_:byAnyOf:)` against whatever
/// `obstructionsProvider()` currently reports (the same shape
/// `GroundPlaneStreamer.residentObstructions` hands `RaccoonSpawnDirector`;
/// defaults to an empty list so a caller with no buildings at all -- most
/// unit tests -- needs no fixture). All three checks run only while
/// searching for a *new* spawn location; an already-placed pickup is never
/// re-validated or moved.
///
/// **One pickup per tile.** Both kinds share a `firstSpawnDelay` and a
/// `spawnCadence`, so they attempt their spawns on the same tick and draw
/// independently from the same `visibleRect`; without check (b) a med kit
/// and a garbage can could land on the identical tile, where the depth
/// model would resolve both to the same rounded tile and the same
/// `DepthBanding.nonPlayerActorOffsetRange.lowerBound` offset -- two icons
/// drawn over each other in undefined order, against the story's "legible
/// at a glance" gate. Rejecting an occupied tile is the same "don't place
/// on top of existing content" rule `Chunk.reserve(footprint:at:)` applies
/// to buildings.
final class PickupManager {

    /// Upper bound on how many candidate tiles a single spawn attempt tries
    /// before giving up for this tick. A failed search holds that kind's
    /// timer at `0` (see the type doc comment), so the search simply runs
    /// again next `update` call rather than looping unboundedly this one.
    static let maxPlacementAttemptsPerSpawn = 64

    private let worldSeed: WorldSeed
    private let obstructionsProvider: () -> [BuildingPlacementRecord]
    private var rng: SplitMix64RandomNumberGenerator

    /// Every pickup currently alive: not yet expired by age and not yet
    /// consumed. `update` prunes both cases immediately, so this array never
    /// holds a stale entry a caller has to filter around.
    private(set) var activePickups: [Pickup] = []

    private var timeUntilNextSpawn: [PickupKind: TimeInterval]

    /// - Parameters:
    ///   - worldSeed: the run's city seed -- the same value
    ///     `GameScene.worldSeed` / `ChunkStreamingManager` are constructed
    ///     with, so placement validation classifies tiles against the exact
    ///     city a real run would stream.
    ///   - obstructionsProvider: reports the currently-relevant building
    ///     footprints for the building-free neighbour check. Defaults to an
    ///     empty list -- the "no buildings anywhere" case most unit tests
    ///     want -- and is read live (a closure, not a snapshot) so a caller
    ///     backed by a moving `ChunkStreamingManager` can hand over
    ///     `groundPlane.residentObstructions` without this type needing to
    ///     know that type exists.
    ///   - rng: the placement/roll random source. Defaults to a freshly
    ///     seeded generator (real gameplay variety needs no determinism);
    ///     tests inject a fixed seed instead, the same convention
    ///     `RaccoonSpawnDirector.init` documents.
    init(
        worldSeed: WorldSeed,
        obstructionsProvider: @escaping () -> [BuildingPlacementRecord] = { [] },
        rng: SplitMix64RandomNumberGenerator = SplitMix64RandomNumberGenerator(
            seed: UInt64.random(in: UInt64.min...UInt64.max)
        )
    ) {
        self.worldSeed = worldSeed
        self.obstructionsProvider = obstructionsProvider
        self.rng = rng
        self.timeUntilNextSpawn = Dictionary(
            uniqueKeysWithValues: PickupKind.allCases.map { ($0, $0.tuning.firstSpawnDelay) }
        )
    }

    // MARK: - Per-frame update

    /// Advances every active pickup's age by `deltaTime`, expires anything
    /// that has now reached its kind's lifetime, and -- independently, per
    /// kind -- attempts a new spawn once that kind's timer has elapsed and
    /// it still has room under `PickupKind.Tuning.maxAlive`.
    ///
    /// - Parameters:
    ///   - deltaTime: real elapsed seconds since the previous call. Ignored
    ///     (a no-op call) when `<= 0`, the same guard
    ///     `RaccoonSpawnDirector.update` uses.
    ///   - visibleRect: the **tile-space** rectangle pickups may be placed
    ///     within -- e.g. the camera's current viewport expressed in tile
    ///     space (`origin`/`size` in tile units, not screen points). A
    ///     future scene-wiring PR derives this from the live camera the same
    ///     way `RaccoonSpawnDirector.isOnScreen` derives its own
    ///     screen-space check; nothing in this type assumes how that
    ///     derivation is done, and this value is consulted only while
    ///     searching for a spawn location -- never used to age or expire an
    ///     already-placed pickup (see this type's own doc comment).
    func update(deltaTime: TimeInterval, visibleRect: CGRect) {
        guard deltaTime > 0 else { return }

        for index in activePickups.indices {
            activePickups[index].age += deltaTime
        }
        activePickups.removeAll { $0.isConsumed || $0.age >= $0.kind.tuning.lifetime }

        for kind in PickupKind.allCases {
            let remaining = (timeUntilNextSpawn[kind] ?? kind.tuning.firstSpawnDelay) - deltaTime
            timeUntilNextSpawn[kind] = remaining
            guard remaining <= 0 else { continue }

            let aliveCount = activePickups.reduce(into: 0) { count, pickup in
                if pickup.kind == kind { count += 1 }
            }
            guard aliveCount < kind.tuning.maxAlive else {
                // No room: hold at zero so a slot freeing up (a future
                // collection call) is spawned into on the very next tick,
                // mirroring `RaccoonSpawnDirector.update`'s own "no room"
                // branch.
                //
                // Unreachable at the frozen tuning (cadence 25s > lifetime
                // 20s makes the effective ceiling 1 per kind, below
                // `maxAlive: 2`) -- see `PickupKind.Tuning.maxAlive`, which
                // records why this branch ships unexercised and what a
                // retune owes it.
                timeUntilNextSpawn[kind] = 0
                continue
            }

            if let position = selectSpawnPosition(within: visibleRect) {
                activePickups.append(Pickup(kind: kind, position: position))
                timeUntilNextSpawn[kind] = kind.tuning.spawnCadence
            } else {
                // No legal tile found this tick -- retry next tick rather
                // than accumulating a backlog of missed spawns.
                timeUntilNextSpawn[kind] = 0
            }
        }
    }

    // MARK: - Collection queries

    /// Consumes the nearest active, unconsumed med kit within `radius` tiles
    /// of `position`, if any, returning its rolled heal amount
    /// (`PickupKind.medKit`'s dice, 1d10). `nil` if none is in range.
    ///
    /// **This is the med kit's authoritative roll** (PR #37 review): this
    /// call owns the pickup record, so it owns the number, and
    /// `PlayerNode.heal(_:)` applies exactly what is returned here rather
    /// than rolling a second, independent 1d10 of its own.
    @discardableResult
    func attemptCollectMedKit(at position: TilePoint, radius: Double) -> Int? {
        attemptCollect(kind: .medKit, at: position, radius: radius)
    }

    /// Consumes the nearest active, unconsumed garbage can within `radius`
    /// tiles of `position`, if any, returning its rolled consume value
    /// (`PickupKind.garbageCan`'s dice, 1d6). `nil` if none is in range.
    @discardableResult
    func attemptCollectGarbageCan(at position: TilePoint, radius: Double) -> Int? {
        attemptCollect(kind: .garbageCan, at: position, radius: radius)
    }

    /// The nearest active, unconsumed garbage can within `radius` tiles of
    /// `position`, without consuming it -- a read-only query for a future
    /// consumer (e.g. steering a wounded raccoon toward one; see
    /// `RaccoonNode.isWounded`'s own doc comment) that needs to know where
    /// one is before deciding whether to go collect it.
    func nearestGarbageCan(within radius: Double, of position: TilePoint) -> Pickup? {
        guard let index = nearestActiveIndex(kind: .garbageCan, of: position, within: radius) else { return nil }
        return activePickups[index]
    }

    /// Retires the active garbage can at exactly `position`, **without**
    /// rolling `PickupKind.garbageCan`'s dice again (`CYBERPUN-17-11`
    /// PR 3) -- the wounded-raccoon diversion path
    /// (`RaccoonSeekBehavior.updateWithDiversion(...)`) already rolled and
    /// applied that can's 1d6 itself, on the raccoon, the instant it
    /// arrived, so this call only needs to mark the record consumed (pruned
    /// by the very next `update(deltaTime:visibleRect:)` call). Calling
    /// `attemptCollectGarbageCan(at:radius:)` here instead would roll a
    /// second 1d6 that nothing applies -- exactly the double-roll this
    /// type's own PR2 note warns a wiring caller away from.
    ///
    /// `position` must be the exact `Pickup.position` a prior
    /// `nearestGarbageCan(within:of:)` call reported for this same can --
    /// not an independently-computed point -- since the lookup here is an
    /// exact (zero-radius) match, the same tolerance
    /// `isOccupiedByActivePickup(_:)` uses for its own rounded-tile
    /// equality check. Returns whether a matching, still-active garbage can
    /// was actually found and retired; `false` is a no-op (already
    /// retired, or nothing was ever there).
    @discardableResult
    func expireConsumedGarbageCan(at position: TilePoint) -> Bool {
        guard let index = nearestActiveIndex(kind: .garbageCan, of: position, within: 0) else { return false }
        activePickups[index].isConsumed = true
        return true
    }

    private func attemptCollect(kind: PickupKind, at position: TilePoint, radius: Double) -> Int? {
        guard let index = nearestActiveIndex(kind: kind, of: position, within: radius) else { return nil }
        activePickups[index].isConsumed = true
        return kind.tuning.dice.roll(using: &rng)
    }

    private func nearestActiveIndex(kind: PickupKind, of position: TilePoint, within radius: Double) -> Int? {
        var bestIndex: Int?
        var bestDistanceSquared = Double.greatestFiniteMagnitude
        let radiusSquared = radius * radius

        for (index, pickup) in activePickups.enumerated() {
            guard pickup.kind == kind, !pickup.isConsumed else { continue }
            let dx = pickup.position.x - position.x
            let dy = pickup.position.y - position.y
            let distanceSquared = dx * dx + dy * dy
            guard distanceSquared <= radiusSquared, distanceSquared < bestDistanceSquared else { continue }
            bestDistanceSquared = distanceSquared
            bestIndex = index
        }
        return bestIndex
    }

    // MARK: - Placement validation

    /// Selects a legal spawn tile within `visibleRect`, or `nil` if none was
    /// found within `maxPlacementAttemptsPerSpawn` random draws.
    private func selectSpawnPosition(within visibleRect: CGRect) -> TilePoint? {
        guard visibleRect.width > 0, visibleRect.height > 0 else { return nil }

        let minTileX = Double(visibleRect.minX)
        let maxTileX = Double(visibleRect.maxX)
        let minTileY = Double(visibleRect.minY)
        let maxTileY = Double(visibleRect.maxY)
        guard minTileX <= maxTileX, minTileY <= maxTileY else { return nil }

        for _ in 0..<Self.maxPlacementAttemptsPerSpawn {
            let candidateX = Int(Double.random(in: minTileX...maxTileX, using: &rng).rounded())
            let candidateY = Int(Double.random(in: minTileY...maxTileY, using: &rng).rounded())
            let candidate = TileCoordinate(tileX: candidateX, tileY: candidateY)

            guard isLegalPlacement(candidate, visibleRect: visibleRect) else { continue }
            return TilePoint(x: Double(candidate.tileX), y: Double(candidate.tileY))
        }
        return nil
    }

    /// A candidate tile is legal when: it is still inside `visibleRect`
    /// (rounding a random draw to the nearest whole tile can only ever move
    /// it *toward* the sampled range's own bounds, but the check is made
    /// explicit rather than assumed), it classifies as a street kind
    /// (`isStreetKind`), no already-active pickup occupies it
    /// (`isOccupiedByActivePickup`), and the tile itself plus every one of
    /// its 8 neighbours is free of any building footprint.
    ///
    /// The candidate tile is checked for obstruction alongside its
    /// neighbours rather than skipped: the story's rule is "the chosen tile
    /// **and** all 8 neighbours must be building-free", and leaving the
    /// tile itself to `isStreetKind` alone would rest on
    /// `CityLatticeGenerator.classify` and the `BuildingPlacementRecord` set
    /// never disagreeing about which tiles a building occupies -- a
    /// cross-system invariant this type does not own. `obstructions` is
    /// already in hand, so asking directly costs nothing and also covers a
    /// future placement pass reserving a tile the lattice calls street.
    private func isLegalPlacement(_ tile: TileCoordinate, visibleRect: CGRect) -> Bool {
        guard visibleRect.contains(CGPoint(x: CGFloat(tile.tileX), y: CGFloat(tile.tileY))) else { return false }

        let info = CityLatticeGenerator.classify(tileX: tile.tileX, tileY: tile.tileY, seed: worldSeed)
        guard Self.isStreetKind(info.kind) else { return false }

        guard !isOccupiedByActivePickup(tile) else { return false }

        let obstructions = obstructionsProvider()
        for dx in -1...1 {
            for dy in -1...1 {
                // The candidate tile itself (dx == 0, dy == 0) *and* all 8
                // neighbours -- see this method's doc comment.
                let subject = TileCoordinate(tileX: tile.tileX + dx, tileY: tile.tileY + dy)
                if BuildingObstruction.isObstructed(subject, byAnyOf: obstructions) {
                    return false
                }
            }
        }
        return true
    }

    /// Whether any currently-active pickup -- of either kind -- already
    /// stands on `tile`. Every spawned pickup sits at a whole tile centre
    /// (`selectSpawnPosition` rounds its draw), so comparing the rounded
    /// tile-space position is exact rather than a distance tolerance.
    private func isOccupiedByActivePickup(_ tile: TileCoordinate) -> Bool {
        activePickups.contains { pickup in
            Int(pickup.position.x.rounded()) == tile.tileX
                && Int(pickup.position.y.rounded()) == tile.tileY
        }
    }

    /// Whether `kind` is one of the three street sub-kinds
    /// (`CityLatticeGenerator`'s own asphalt / junction-stop-line /
    /// kerb-sidewalk vocabulary) rather than a block interior (`.lot`,
    /// which is walkable open ground but not street, or
    /// `.buildingFootprint`).
    private static func isStreetKind(_ kind: TileKind) -> Bool {
        switch kind {
        case .asphalt, .junctionStopLine, .kerbSidewalk:
            return true
        case .lot, .buildingFootprint:
            return false
        }
    }
}
