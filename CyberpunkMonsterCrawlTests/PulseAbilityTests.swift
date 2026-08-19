import Foundation
import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-10` PR 1: `PulseAbility`'s pure gameplay logic -- push
/// geometry, crush/footprint clamping, damage rolls, cooldown gating,
/// footprint-height irrelevance and dead-raccoon exclusion -- proven
/// entirely independent of SpriteKit scene wiring, the HUD pulse button
/// and the `sprite_pulse` ring animation (all later PRs in this story).
final class PulseAbilityTests: XCTestCase {

    /// A scripted `RandomNumberGenerator` that replays a fixed sequence of
    /// raw `UInt64` values (clamped to the last one once exhausted, so a
    /// caller that rolls one time too many does not crash the whole test
    /// process the way an out-of-bounds array subscript would) while
    /// counting exactly how many times `next()` was called -- lets a test
    /// pin both a `DiceSpec.roll(using:)`'s exact result *and* that
    /// exactly one (or exactly two) rolls were actually consumed, rather
    /// than only inferring the count from the final damage total.
    private final class CountingRandomNumberGenerator: RandomNumberGenerator {
        private let values: [UInt64]
        private(set) var callCount = 0

        init(_ values: [UInt64]) {
            self.values = values
        }

        func next() -> UInt64 {
            defer { callCount += 1 }
            return values[min(callCount, values.count - 1)]
        }
    }

    private func makeRaccoon(hp: Int? = nil) -> RaccoonNode {
        RaccoonNode(tier: .base, hp: hp)
    }

    /// A single 1x1 building footprint occupying tile `(tileX, tileY)`,
    /// via `BuildingCatalog.entry(atIndex:)` -- the same construction
    /// `BuildingAvoidanceTests.makeRecord` uses -- so `atIndex` alone
    /// varies a record's height class while its footprint stays put.
    private func makeRecord(atIndex index: Int, tileX: Int, tileY: Int) -> BuildingPlacementRecord {
        let tile = TileCoordinate(tileX: tileX, tileY: tileY)
        return BuildingPlacementRecord(
            lotTile: tile,
            building: BuildingCatalog.entry(atIndex: index),
            footprintTiles: [tile],
            farCornerTile: tile
        )
    }

    // MARK: - Push geometry: ray-preserving, radius + epsilon

    func test_pushTarget_landsJustPastTheRadiusEdge_alongTheRayFromPlayerThroughRaccoon() {
        let player = TilePoint(x: 10, y: 10)
        let raccoon = TilePoint(x: 12, y: 10) // due east, distance 2

        let target = PulseAbility.pushTarget(
            playerPosition: player,
            raccoonPosition: raccoon,
            radius: 3.0,
            epsilon: 0.05
        )

        XCTAssertEqual(target.x, 13.05, accuracy: 1e-9)
        XCTAssertEqual(target.y, 10.0, accuracy: 1e-9)
    }

    func test_pushTarget_preservesBearing_forADiagonalRaccoon() {
        let player = TilePoint(x: 0, y: 0)
        let raccoon = TilePoint(x: 3, y: 4) // distance 5, a 3-4-5 triangle

        let target = PulseAbility.pushTarget(
            playerPosition: player,
            raccoonPosition: raccoon,
            radius: 3.0,
            epsilon: 0.05
        )

        // The pushed target must sit on the exact same ray: its unit
        // vector from the player must match the original raccoon's.
        let originalUnit = (x: raccoon.x / 5.0, y: raccoon.y / 5.0)
        let targetDistance = hypot(target.x - player.x, target.y - player.y)
        let targetUnit = (x: (target.x - player.x) / targetDistance, y: (target.y - player.y) / targetDistance)

        XCTAssertEqual(targetUnit.x, originalUnit.x, accuracy: 1e-9)
        XCTAssertEqual(targetUnit.y, originalUnit.y, accuracy: 1e-9)
        XCTAssertEqual(targetDistance, 3.05, accuracy: 1e-9)
    }

    // MARK: - Exactly one damage roll per clear push

    func test_trigger_clearPush_appliesExactlyOneDamageRoll() {
        let ability = PulseAbility()
        let raccoon = makeRaccoon()
        let candidates = [TargetSelection.Candidate(raccoon: raccoon, position: TilePoint(x: 2, y: 0))]

        // rawValue 2 -> 2 % 6 + 1 == 3 for the level-1 (below 6) 1d6 die.
        var rng = CountingRandomNumberGenerator([2, 40])

        let result = ability.trigger(
            playerPosition: TilePoint(x: 0, y: 0),
            level: 1,
            raccoons: candidates,
            obstructions: [],
            rng: &rng
        )

        guard let result, let hit = result.hits.first else {
            return XCTFail("expected exactly one hit")
        }
        XCTAssertEqual(rng.callCount, 1, "a clear push must consume exactly one damage roll")
        XCTAssertEqual(hit.damage, 3)
        XCTAssertFalse(hit.wasCrushed)
        XCTAssertEqual(hit.newPosition.x, 3.05, accuracy: 1e-9)
        XCTAssertEqual(hit.newPosition.y, 0, accuracy: 1e-9)
    }

    // MARK: - Crush: clamps to the footprint edge, two rolls (2d6 total)

    func test_trigger_pushBlockedByFootprint_stopsAtTheEdgeAndAppliesTwoDamageRolls() {
        let ability = PulseAbility()
        let raccoon = makeRaccoon()
        let candidates = [TargetSelection.Candidate(raccoon: raccoon, position: TilePoint(x: 2, y: 0))]
        // A 1x1 footprint at tile (3, 0): bounds x in [2.5, 3.5], directly
        // between the player and the unobstructed push target (3.05, 0).
        let obstructions = [CollisionResolver.footprintBounds(for: makeRecord(atIndex: 3, tileX: 3, tileY: 0))]

        // rawValue 2 -> 2 % 6 + 1 == 3, applied twice.
        var rng = CountingRandomNumberGenerator([2, 2])

        let result = ability.trigger(
            playerPosition: TilePoint(x: 0, y: 0),
            level: 1,
            raccoons: candidates,
            obstructions: obstructions,
            rng: &rng
        )

        guard let result, let hit = result.hits.first else {
            return XCTFail("expected exactly one hit")
        }
        XCTAssertEqual(rng.callCount, 2, "a crushed push must consume exactly two damage rolls")
        XCTAssertEqual(hit.damage, 6, "2d6 total: 3 (push) + 3 (crush)")
        XCTAssertTrue(hit.wasCrushed)
        XCTAssertEqual(hit.newPosition.x, 2.5, accuracy: 1e-9, "must stop exactly at the footprint edge")
        XCTAssertEqual(hit.newPosition.y, 0, accuracy: 1e-9)
        XCTAssertLessThan(hit.newPosition.x, 3.5, "must never enter the footprint")
    }

    /// The narrow half of the crush criterion: `CollisionResolver` is a
    /// per-axis *slide*, so a footprint can deflect one axis while the
    /// other completes and still leave the raccoon shoved clear of the
    /// radius. That raccoon was *not* crushed -- the story's rule is
    /// "cannot be pushed clear of the radius" -- so it must take one die,
    /// not two, even though its resolved position differs from the full
    /// push target.
    func test_trigger_pushDeflectedButStillClearOfTheRadius_isNotACrush() {
        let ability = PulseAbility()
        let player = TilePoint(x: 0, y: 0)
        let raccoonPosition = TilePoint(x: 2, y: 0.4)
        let candidates = [TargetSelection.Candidate(raccoon: makeRaccoon(), position: raccoonPosition)]
        // A 1x1 footprint at tile (3, 1): bounds x [2.5, 3.5] x y [0.5, 1.5].
        // The push target (~2.991, ~0.598) lands inside it, but only the
        // Y axis is blocked -- X completes freely, because at y = 0.4 the
        // swept X path never enters the rectangle.
        let obstructions = [CollisionResolver.footprintBounds(for: makeRecord(atIndex: 3, tileX: 3, tileY: 1))]

        var rng = CountingRandomNumberGenerator([2, 2])

        guard let result = ability.trigger(
            playerPosition: player,
            level: 1,
            raccoons: candidates,
            obstructions: obstructions,
            rng: &rng
        ), let hit = result.hits.first else {
            return XCTFail("expected exactly one hit")
        }

        // Anti-vacuity: this case is only interesting if the resolver
        // really did clamp the raccoon short of its full push target.
        let fullTarget = PulseAbility.pushTarget(
            playerPosition: player,
            raccoonPosition: raccoonPosition,
            radius: result.radius,
            epsilon: PulseAbility.pushOvershootEpsilon
        )
        XCTAssertEqual(hit.newPosition.y, 0.5, accuracy: 1e-9, "Y clamps to the footprint's near edge")
        XCTAssertLessThan(hit.newPosition.y, fullTarget.y, "sanity: the push really was deflected")

        // ...and yet it ended up outside the radius, so it was pushed clear.
        let resolvedDistance = hypot(hit.newPosition.x - player.x, hit.newPosition.y - player.y)
        XCTAssertGreaterThan(
            resolvedDistance, result.radius,
            "a deflected-but-cleared raccoon (~3.03 tiles out) is outside the 3.0 radius"
        )
        XCTAssertFalse(hit.wasCrushed, "being outside the radius is exactly 'pushed clear' -- not a crush")
        XCTAssertEqual(rng.callCount, 1, "a raccoon pushed clear of the radius must consume exactly one roll")
        XCTAssertEqual(hit.damage, 3, "1d6, not 2d6")
    }

    func test_trigger_pushBlockedByFootprint_atLevel6_uses2d8() {
        let ability = PulseAbility()
        let raccoon = makeRaccoon()
        let candidates = [TargetSelection.Candidate(raccoon: raccoon, position: TilePoint(x: 2, y: 0))]
        let obstructions = [CollisionResolver.footprintBounds(for: makeRecord(atIndex: 3, tileX: 3, tileY: 0))]

        // rawValue 7 is deliberately a value that *separates* the two
        // dice: `DiceSpec.roll` computes `next() % sides + 1`, so
        // 7 % 8 + 1 == 8 under the level-6 1d8 die but 7 % 6 + 1 == 2
        // under the 1d6 one. The expected total is therefore 16 here and
        // would be 4 if `trigger` never consulted
        // `LevelScaling.pulseDamageDie(forLevel:)` -- unlike a rawValue of
        // 2, which yields 3 under both dice and leaves this test green
        // even with the level-6 branch deleted.
        var rng = CountingRandomNumberGenerator([7, 7])

        let result = ability.trigger(
            playerPosition: TilePoint(x: 0, y: 0),
            level: 6,
            raccoons: candidates,
            obstructions: obstructions,
            rng: &rng
        )

        guard let result, let hit = result.hits.first else {
            return XCTFail("expected exactly one hit")
        }
        XCTAssertEqual(hit.damage, 16, "2d8 total: 8 (push) + 8 (crush); 2d6 on the same rolls would be 4")
        XCTAssertTrue(hit.wasCrushed)
    }

    // MARK: - Level scaling reaches `trigger`: radius multiplier

    /// The radius counterpart of the d6/d8 test above: a raccoon placed
    /// between the level-1 radius (3.0) and the level-3 one (3.0 * 1.25
    /// == 3.75) is *missed* at level 1 and *hit* at level 3, so dropping
    /// `LevelScaling.pulseRadiusMultiplier(forLevel:)` from `trigger`
    /// turns this red rather than shipping "green suite, feature absent".
    func test_trigger_radiusMultiplier_missesAtLevel1_andHitsAtLevel3() {
        let player = TilePoint(x: 0, y: 0)
        let raccoonPosition = TilePoint(x: 3.5, y: 0) // between 3.0 and 3.75

        let atLevel1 = PulseAbility()
        var rng1 = CountingRandomNumberGenerator([2])
        guard let level1Result = atLevel1.trigger(
            playerPosition: player,
            level: 1,
            raccoons: [TargetSelection.Candidate(raccoon: makeRaccoon(), position: raccoonPosition)],
            obstructions: [],
            rng: &rng1
        ) else {
            return XCTFail("expected the pulse to fire even with nobody in range")
        }

        XCTAssertEqual(level1Result.radius, 3.0, accuracy: 1e-9, "level 1 must fire at the unscaled base radius")
        XCTAssertTrue(level1Result.hits.isEmpty, "a raccoon at 3.5 tiles is outside the level-1 radius of 3.0")
        XCTAssertEqual(rng1.callCount, 0)

        let atLevel3 = PulseAbility()
        var rng3 = CountingRandomNumberGenerator([2])
        guard let level3Result = atLevel3.trigger(
            playerPosition: player,
            level: 3,
            raccoons: [TargetSelection.Candidate(raccoon: makeRaccoon(), position: raccoonPosition)],
            obstructions: [],
            rng: &rng3
        ), let level3Hit = level3Result.hits.first else {
            return XCTFail("a raccoon at 3.5 tiles must be inside the level-3 radius of 3.75")
        }

        XCTAssertEqual(level3Result.radius, 3.75, accuracy: 1e-9, "level 3 applies the +25% multiplier")
        XCTAssertEqual(
            level3Hit.newPosition.x, 3.8, accuracy: 1e-9,
            "the clear push must land at the *scaled* radius plus the overshoot epsilon (3.75 + 0.05)"
        )
        XCTAssertEqual(level3Hit.newPosition.y, 0, accuracy: 1e-9)
        XCTAssertFalse(level3Hit.wasCrushed)
    }

    /// Level 6 compounds the two +25% steps rather than stacking them
    /// additively, and `trigger` must fire at that compounded radius --
    /// `3.0 * 1.25 * 1.25 == 4.6875`, not `4.5`.
    func test_trigger_radiusMultiplier_compoundsAtLevel6() {
        let ability = PulseAbility()
        var rng = CountingRandomNumberGenerator([2])

        // 4.6 tiles: inside the compounded level-6 radius (4.6875) but
        // outside the additive reading (4.5), so this case also pins
        // *which* of the two readings ships.
        guard let result = ability.trigger(
            playerPosition: TilePoint(x: 0, y: 0),
            level: 6,
            raccoons: [TargetSelection.Candidate(raccoon: makeRaccoon(), position: TilePoint(x: 4.6, y: 0))],
            obstructions: [],
            rng: &rng
        ), let hit = result.hits.first else {
            return XCTFail("a raccoon at 4.6 tiles must be inside the compounded level-6 radius of 4.6875")
        }

        XCTAssertEqual(result.radius, 4.6875, accuracy: 1e-9, "1.25 * 1.25, not 1.5")
        XCTAssertEqual(hit.newPosition.x, 4.7375, accuracy: 1e-9, "4.6875 + 0.05")
    }

    // MARK: - Footprint-height irrelevance: equal footprints pin identically

    func test_crushClamp_isIdentical_forEqualFootprints_regardlessOfBuildingHeight() {
        func runTrigger(buildingIndex: Int) -> PulseAbility.Hit? {
            let ability = PulseAbility()
            let raccoon = makeRaccoon()
            let candidates = [TargetSelection.Candidate(raccoon: raccoon, position: TilePoint(x: 2, y: 0))]
            let obstructions = [
                CollisionResolver.footprintBounds(for: makeRecord(atIndex: buildingIndex, tileX: 3, tileY: 0)),
            ]
            var rng = CountingRandomNumberGenerator([2, 2])
            return ability.trigger(
                playerPosition: TilePoint(x: 0, y: 0),
                level: 1,
                raccoons: candidates,
                obstructions: obstructions,
                rng: &rng
            )?.hits.first
        }

        // Index 3 is `.low` (~2 storey); index 5 is `.tall` (~4 storey).
        // Both are `.oneByOne` footprints, so `makeRecord` places them
        // over the exact same tile.
        guard let low = runTrigger(buildingIndex: 3), let tall = runTrigger(buildingIndex: 5) else {
            return XCTFail("expected a hit from both building heights")
        }

        XCTAssertEqual(low.newPosition.x, tall.newPosition.x, accuracy: 1e-9)
        XCTAssertEqual(low.newPosition.y, tall.newPosition.y, accuracy: 1e-9)
        XCTAssertEqual(low.damage, tall.damage)
        XCTAssertEqual(low.wasCrushed, tall.wasCrushed)
    }

    // MARK: - Cooldown gating

    func test_trigger_secondPressWithinCooldown_isANoOp() {
        let ability = PulseAbility()
        let raccoon = makeRaccoon()
        let candidates = [TargetSelection.Candidate(raccoon: raccoon, position: TilePoint(x: 2, y: 0))]
        var rng = CountingRandomNumberGenerator([2])

        let first = ability.trigger(
            playerPosition: TilePoint(x: 0, y: 0),
            level: 1,
            raccoons: candidates,
            obstructions: [],
            rng: &rng
        )
        XCTAssertNotNil(first, "the first press, with no cooldown in effect, must fire")
        XCTAssertTrue(ability.isOnCooldown)

        let callCountAfterFirst = rng.callCount
        let second = ability.trigger(
            playerPosition: TilePoint(x: 0, y: 0),
            level: 1,
            raccoons: candidates,
            obstructions: [],
            rng: &rng
        )

        XCTAssertNil(second, "a second press within the cooldown window must emit no pulse")
        XCTAssertEqual(rng.callCount, callCountAfterFirst, "no damage roll must occur on a no-op trigger")
    }

    func test_trigger_afterCooldownElapses_firesAgain() {
        let ability = PulseAbility()
        let raccoon = makeRaccoon()
        let candidates = [TargetSelection.Candidate(raccoon: raccoon, position: TilePoint(x: 2, y: 0))]
        var rng = CountingRandomNumberGenerator([2, 2])

        XCTAssertNotNil(ability.trigger(
            playerPosition: TilePoint(x: 0, y: 0),
            level: 1,
            raccoons: candidates,
            obstructions: [],
            rng: &rng
        ))

        ability.update(deltaTime: PulseAbility.cooldownSeconds)
        XCTAssertFalse(ability.isOnCooldown)

        XCTAssertNotNil(ability.trigger(
            playerPosition: TilePoint(x: 0, y: 0),
            level: 1,
            raccoons: candidates,
            obstructions: [],
            rng: &rng
        ), "once the cooldown has fully elapsed, the next press must fire")
    }

    // MARK: - Dead raccoons are excluded from all results

    func test_trigger_excludesDeadRaccoons_fromPushAndDamage() {
        let ability = PulseAbility()
        let deadRaccoon = makeRaccoon(hp: 0)
        let livingRaccoon = makeRaccoon()
        XCTAssertTrue(deadRaccoon.isDead, "sanity: hp 0 must read as dead")

        let candidates = [
            TargetSelection.Candidate(raccoon: deadRaccoon, position: TilePoint(x: 2, y: 0)),
            TargetSelection.Candidate(raccoon: livingRaccoon, position: TilePoint(x: 0, y: 2)),
        ]
        var rng = CountingRandomNumberGenerator([2])

        guard let result = ability.trigger(
            playerPosition: TilePoint(x: 0, y: 0),
            level: 1,
            raccoons: candidates,
            obstructions: [],
            rng: &rng
        ) else {
            return XCTFail("expected the pulse to fire")
        }

        XCTAssertEqual(result.hits.count, 1, "the dead raccoon must not appear in the results at all")
        XCTAssertTrue(result.hits[0].raccoon === livingRaccoon)
    }

    // MARK: - Raccoons outside the radius are unaffected

    func test_trigger_ignoresRaccoonsOutsideTheRadius() {
        let ability = PulseAbility()
        let farRaccoon = makeRaccoon()
        // Base radius is 3.0 tiles at level 1 (no scaling yet); 50 tiles
        // away is comfortably outside it.
        let candidates = [TargetSelection.Candidate(raccoon: farRaccoon, position: TilePoint(x: 50, y: 0))]
        var rng = CountingRandomNumberGenerator([2])

        guard let result = ability.trigger(
            playerPosition: TilePoint(x: 0, y: 0),
            level: 1,
            raccoons: candidates,
            obstructions: [],
            rng: &rng
        ) else {
            return XCTFail("expected the pulse to fire, even though nobody is in range")
        }

        XCTAssertTrue(result.hits.isEmpty)
        XCTAssertEqual(rng.callCount, 0, "no damage roll must occur for a raccoon outside the radius")
    }
}
