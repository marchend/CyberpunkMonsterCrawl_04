import CoreGraphics
import Foundation

/// Per-frame steering that moves a raccoon toward the player's current
/// tile, resolves the proposed movement against building footprints via
/// `BuildingAvoidance`, and drives the raccoon's facing/walk animation from
/// the result (`CYBERPUN-17-8` PR 2).
///
/// **Scope of this PR.** Seek-and-avoid steering only -- no bite/damage,
/// no rabies, no death. This type only ever calls
/// `RaccoonNode.setDirection(_:)` / `.playWalk()` / `.update(deltaTime:)`,
/// the exact public surface `RaccoonNode`/`RaccoonAnimationController`
/// expose "for a later PR's seek behaviour to drive" (see those types' own
/// doc comments). No invented ticket ID is given here for the rest:
/// following the convention `PlayerMovementController`'s own
/// outstanding-scope note sets, the authoritative list of what is
/// implemented versus still outstanding for this story is the
/// `CYBERPUN-17-8` entry in AGENT.md/CLAUDE.md -- read that rather than
/// inferring the remaining scope from these doc comments.
///
/// **Facing tracks the intended direction, not the collision-resolved
/// one** -- the same split `PlayerMovementController.facingVector` /
/// `.frameDisplacement` already draw for the player (a human pushing a
/// stick faces where they're pushing, even mid-frame against a wall that
/// stops them). A raccoon's "intended direction" is simply "toward the
/// player right now", so facing is derived straight from `currentPosition`
/// and `playerPosition`, independent of whatever detour
/// `BuildingAvoidance` takes this frame.
enum RaccoonSeekBehavior {

    /// On-screen points/second a raccoon closes on the player at, pinned in
    /// **screen** space for the same reason
    /// `PlayerMovementController.maxPointsPerSecond` is: normalizing in
    /// tile space would make a raccoon's on-screen speed vary with heading
    /// on this 2:1 projection. Set as a fraction of the player's own speed
    /// -- an initial tuning constant; the story explicitly defers exact
    /// difficulty numbers to playtesting.
    static let pointsPerSecond: Double = PlayerMovementController.maxPointsPerSecond * 0.75

    /// On-screen distance (points) from the player a raccoon of `tier`
    /// stops closing at: half the player's measured ground footprint plus
    /// half the raccoon's own (`RaccoonNode.shadowWidth(forTier:)`, which is
    /// `RaccoonAnimationController.groundFootprintWidth` scaled by the
    /// tier), i.e. the distance at which the two ground footprints are
    /// touching rather than overlapping. Both halves are measured off the
    /// shipped art, so this is not an invented number.
    ///
    /// **Why a standoff exists before the bite lands.** Bite/damage and
    /// death/despawn are still outstanding on this story (the
    /// `CYBERPUN-17-8` entry in AGENT.md/CLAUDE.md is the authoritative
    /// list), so nothing yet gives contact a consequence or removes a
    /// raccoon. Without a standoff, `tileDisplacement`'s overshoot clamp
    /// lands every one of `RaccoonSpawnDirector.maxConcurrentSwarmSize`
    /// raccoons on the player's *exact* tile and holds them there, where
    /// they render as a single sprite -- which is what a real build's first
    /// impression of the swarm would be until the bite PR lands. Stopping
    /// at contact instead leaves them ringed around the player, each still
    /// facing and animating toward him. It is a stop radius, not a
    /// separation model: inter-raccoon spacing belongs with the PR that
    /// gives contact meaning.
    static func contactStandoffPoints(forTier tier: RaccoonTier) -> Double {
        Double((PlayerSpriteSheet.hitboxSize.width + RaccoonNode.shadowWidth(forTier: tier)) / 2)
    }

    /// Advances one raccoon by one frame: computes the tile-space step
    /// toward `playerPosition`, resolves it against `obstructions` via
    /// `BuildingAvoidance`, sets `raccoon`'s facing from the *unresolved*
    /// seek direction and switches it to the walk animation, advances its
    /// animation clock, and returns the raccoon's new tile-space position.
    ///
    /// A no-op (returns `currentPosition` unchanged, without touching
    /// `raccoon` at all) when `deltaTime <= 0`.
    @discardableResult
    static func update(
        raccoon: RaccoonNode,
        currentPosition: TilePoint,
        playerPosition: TilePoint,
        obstructions: [CollisionResolver.FootprintBounds],
        deltaTime: TimeInterval
    ) -> TilePoint {
        guard deltaTime > 0 else { return currentPosition }

        if let direction = facing(fromCurrentPosition: currentPosition, toPlayerPosition: playerPosition) {
            raccoon.setDirection(direction)
        }
        // Unconditional, but no longer destructive: `playWalk()` holds off
        // while an attack cycle started by `BiteComponent` is still playing
        // (`RaccoonAnimationController.isAttackCycleInProgress`). Before
        // that hold existed this line ran one frame after every bite and
        // cleared `.attack` before `raccoon.update(deltaTime:)` below --
        // the only place `body.texture` is assigned -- had ever drawn a
        // single attack cell, so `sprite_raccoon_attack` never reached the
        // screen in a real build (PR #35 review).
        raccoon.playWalk()
        raccoon.update(deltaTime: deltaTime)

        let proposedDelta = tileDisplacement(
            currentPosition: currentPosition,
            playerPosition: playerPosition,
            standoffPoints: contactStandoffPoints(forTier: raccoon.tier),
            deltaTime: deltaTime
        )
        guard proposedDelta != .zero else { return currentPosition }

        return BuildingAvoidance.resolve(
            currentPosition: currentPosition,
            proposedDelta: proposedDelta,
            obstructions: obstructions
        )
    }

    /// The tile-space vector from `current` toward `player` -- exposed as a
    /// pure function so tests can assert "points toward the player"
    /// directly, without a live `RaccoonNode`. `.zero` when `current ==
    /// player`.
    static func seekVector(currentPosition current: TilePoint, playerPosition player: TilePoint) -> CGVector {
        CGVector(dx: CGFloat(player.x - current.x), dy: CGFloat(player.y - current.y))
    }

    /// The facing a raccoon at `current` should show while seeking
    /// `player` -- the tile-space seek vector, converted to **screen**
    /// space (the space `Direction8` bins facing art in, matching every
    /// other `Direction8` consumer in this codebase) via the same linear
    /// forward transform `IsometricProjection.tileToScreen` applies to a
    /// point. `nil` when `current == player` (no facing information,
    /// mirroring `Direction8`'s own zero-vector contract -- the raccoon
    /// keeps whatever facing it already had).
    static func facing(fromCurrentPosition current: TilePoint, toPlayerPosition player: TilePoint) -> Direction8? {
        let tileDelta = seekVector(currentPosition: current, playerPosition: player)
        guard tileDelta != .zero else { return nil }
        return Direction8.from(spriteKitVector: screenVector(forTileDelta: tileDelta))
    }

    /// This frame's tile-space displacement toward `playerPosition`: the
    /// seek vector's **screen-space** direction (see `facing`'s doc
    /// comment for why screen space) scaled to `pointsPerSecond *
    /// deltaTime` screen points and projected back to tile space --
    /// mirroring `PlayerMovementController.tileDisplacement(forStickDirection:...)`'s
    /// "scale in screen space, then invert" shape, so a raccoon's on-screen
    /// speed is heading-independent exactly like the player's.
    ///
    /// Capped so a single frame can never overshoot: `screenDistance` is
    /// clamped to the screen-space distance still *available* to close --
    /// the actual distance to the player less `standoffPoints` -- which is
    /// what stops a raccoon oscillating around the player once it gets
    /// close, instead of settling onto the standoff ring. A raccoon already
    /// at (or inside) the standoff proposes no movement at all.
    private static func tileDisplacement(
        currentPosition: TilePoint,
        playerPosition: TilePoint,
        standoffPoints: Double,
        deltaTime: TimeInterval
    ) -> CGVector {
        let tileDelta = seekVector(currentPosition: currentPosition, playerPosition: playerPosition)
        guard tileDelta != .zero else { return .zero }

        let screenDelta = screenVector(forTileDelta: tileDelta)
        let screenDistanceToPlayer = hypot(Double(screenDelta.dx), Double(screenDelta.dy))
        guard screenDistanceToPlayer > 0 else { return .zero }

        let closableDistance = screenDistanceToPlayer - standoffPoints
        guard closableDistance > 0 else { return .zero }

        let screenDistance = min(pointsPerSecond * deltaTime, closableDistance)
        let screenStep = CGPoint(
            x: CGFloat(Double(screenDelta.dx) / screenDistanceToPlayer * screenDistance),
            y: CGFloat(Double(screenDelta.dy) / screenDistanceToPlayer * screenDistance)
        )

        let tileStep = IsometricProjection.screenToTile(screenStep)
        return CGVector(dx: CGFloat(tileStep.x), dy: CGFloat(tileStep.y))
    }

    /// Converts a **tile-space** delta vector to its **SpriteKit-space**
    /// screen delta, via `IsometricProjection.tileToScreen` -- valid for a
    /// delta (not just a point) because the forward transform is linear,
    /// with no translation term.
    private static func screenVector(forTileDelta delta: CGVector) -> CGVector {
        let screenPoint = IsometricProjection.tileToScreen(tileX: Double(delta.dx), tileY: Double(delta.dy))
        return CGVector(dx: screenPoint.x, dy: screenPoint.y)
    }
}

// MARK: - Wounded-raccoon garbage-can diversion (`CYBERPUN-17-11` PR 2)
//
// The consumer-side half of the garbage-can pickup: a wounded raccoon
// (`RaccoonNode.isWounded`, exposed by `CYBERPUN-17-8` precisely for this
// story to read) within range of one abandons the player, walks to it
// instead, consumes it for `PickupKind.garbageCan`'s 1d6 (PR 1) once
// arrived, and resumes seeking the player afterward.
//
// **Scope of this PR.** Proven here entirely in isolation from GameScene:
// `updateWithDiversion(...)` takes a raw `garbageCanPosition: TilePoint?`
// rather than a live `Pickup`/`PickupManager`. A caller that owns a real
// `Pickup` should still expire it once `DiversionResult.consumedGarbageCan`
// comes back `true` -- but the consume effect no longer *depends* on the
// caller doing so: the raccoon itself records the can it consumed
// (`RaccoonNode.consumedGarbageCanPosition`), so keeping the same position
// coming cannot re-roll the heal (PR #37 review).
//
// **One roll per can, and the raccoon's steering owns it.** The wiring PR
// should locate the can with the non-rolling
// `PickupManager.nearestGarbageCan(within:of:)` query and expire it on the
// consumed frame -- *not* with `attemptCollectGarbageCan(at:radius:)`,
// which rolls a second 1d6 that nothing applies. (The med-kit path is the
// mirror image: there the manager owns the roll and
// `PlayerNode.heal(_:)` applies it.)
//
// Deliberately no shared code with the player's own med-kit consume effect
// (`PlayerNode+Pickups.swift`) beyond the `PickupKind` tuning table and
// `DiceSpec.roll(using:)` both read -- per this story's PR2 scope note,
// which is about the two *effects*, not about copying one dice roller.
extension RaccoonSeekBehavior {

    /// Tile-space radius within which a wounded raccoon abandons the
    /// player and diverts toward a garbage-can pickup instead. An initial
    /// tuning constant -- like `pointsPerSecond` and
    /// `contactStandoffPoints(forTier:)`, the story defers exact
    /// difficulty/feel numbers to playtesting.
    static let garbageCanDiversionRangeTiles: Double = 6.0

    /// Tile-space radius at which a diverted raccoon is considered to have
    /// arrived at the garbage can and consumes it. Small and fixed rather
    /// than tier-scaled (unlike `contactStandoffPoints(forTier:)`'s
    /// player-contact ring) -- a garbage can is a stationary point, not
    /// another actor's footprint to stand off from.
    static let garbageCanArrivalRangeTiles: Double = 0.5

    /// The result of one frame's diversion-aware step.
    struct DiversionResult: Equatable {
        /// This raccoon's new tile-space position, exactly as plain
        /// `update(...)` would report for whichever target
        /// (`seekTarget(...)`) this frame resolved to.
        let position: TilePoint
        /// Whether this call rolled and applied the garbage can's 1d6
        /// consume effect -- `true` on (and only on) the one frame the
        /// raccoon's resolved `position` first lands within
        /// `garbageCanArrivalRangeTiles` of `garbageCanPosition`.
        ///
        /// The "only on" half is enforced here, not delegated to the
        /// caller: the arrival frame records the can on
        /// `RaccoonNode.consumedGarbageCanPosition`, and every later call
        /// still passing that same position resolves back to the player
        /// and reports `false` (PR #37 review -- this used to re-fire every
        /// frame the raccoon sat in the arrival radius, so a caller that
        /// discarded this `@discardableResult` healed 1d6 *per frame*).
        ///
        /// A caller that owns the real `Pickup` should still treat `true`
        /// as the signal to remove/expire it.
        let consumedGarbageCan: Bool
    }

    /// One frame of diversion-aware seek/steer, wrapping plain
    /// `update(raccoon:currentPosition:playerPosition:obstructions:
    /// deltaTime:)` with a target resolved by `seekTarget(...)`, then rolls
    /// the garbage can's consume effect the instant the raccoon arrives.
    ///
    /// - Parameters:
    ///   - garbageCanPosition: the nearest active garbage-can pickup's
    ///     tile-space position, or `nil` if none exists (or the caller has
    ///     already treated a prior one as consumed) -- an unwounded
    ///     raccoon ignores this parameter entirely (see `seekTarget`).
    ///   - rng: the consume roll's random source, generic and `inout` --
    ///     the same shape `RabiesStatusEffect.rollInfects(tier:rng:)` uses,
    ///     so a test can pin the exact roll with a scripted generator.
    ///
    /// A dead raccoon (`RaccoonNode.isDead`, i.e. `hp <= 0`) is a complete
    /// no-op: it neither steers nor consumes, and `currentPosition` comes
    /// straight back. `isWounded` is `true` at `hp == 0`, so without this
    /// guard a raccoon whose `die()` had already fired -- kill counted,
    /// node already `removeFromParent()`-ed -- could still be walked to a
    /// garbage can and healed back above zero, un-setting `isDead` on a
    /// node that has left the scene graph (PR #37 review). It is
    /// `takeDamage(_:)`'s own `guard !isDead` seen from the healing side.
    @discardableResult
    static func updateWithDiversion<R: RandomNumberGenerator>(
        raccoon: RaccoonNode,
        currentPosition: TilePoint,
        playerPosition: TilePoint,
        garbageCanPosition: TilePoint?,
        obstructions: [CollisionResolver.FootprintBounds],
        deltaTime: TimeInterval,
        rng: inout R
    ) -> DiversionResult {
        guard !raccoon.isDead else {
            return DiversionResult(position: currentPosition, consumedGarbageCan: false)
        }

        // Latch upkeep: the "already consumed" record only ever refers to
        // the can this raccoon last consumed. The first frame a different
        // position (or `nil`) arrives, it is stale -- clear it, so a can
        // that later spawns on the very same tile is still consumable.
        if raccoon.consumedGarbageCanPosition != garbageCanPosition {
            raccoon.consumedGarbageCanPosition = nil
        }

        // The diversion decision itself, rather than `target !=
        // playerPosition` as a proxy for it: a can sitting on the player's
        // exact tile used to silently disable consumption (PR #37 review).
        let divertTo = divertTarget(
            raccoon: raccoon,
            currentPosition: currentPosition,
            garbageCanPosition: garbageCanPosition
        )

        let resolved = update(
            raccoon: raccoon,
            currentPosition: currentPosition,
            playerPosition: divertTo ?? playerPosition,
            obstructions: obstructions,
            deltaTime: deltaTime
        )

        var consumed = false
        if let divertTo, tileDistance(resolved, divertTo) <= garbageCanArrivalRangeTiles {
            consumeGarbageCan(raccoon: raccoon, rng: &rng)
            raccoon.consumedGarbageCanPosition = divertTo
            consumed = true
        }

        return DiversionResult(position: resolved, consumedGarbageCan: consumed)
    }

    /// This frame's steering target: `garbageCanPosition` when
    /// `divertTarget(...)` says this raccoon is diverting;
    /// `playerPosition` in every other case -- including, unconditionally,
    /// for an unwounded raccoon (step 4 of this PR's plan: "an unwounded
    /// raccoon's targeting logic is untouched by the new branch").
    static func seekTarget(
        raccoon: RaccoonNode,
        currentPosition: TilePoint,
        playerPosition: TilePoint,
        garbageCanPosition: TilePoint?
    ) -> TilePoint {
        divertTarget(
            raccoon: raccoon,
            currentPosition: currentPosition,
            garbageCanPosition: garbageCanPosition
        ) ?? playerPosition
    }

    /// The garbage can this raccoon is diverting to this frame, or `nil`
    /// when it is not diverting at all -- the direct, testable form of the
    /// decision `seekTarget(...)` folds into a target position, and the one
    /// `updateWithDiversion(...)` consumes. Takes no `playerPosition` on
    /// purpose: "am I diverting?" must not depend on where the player
    /// happens to be standing (a can on the player's exact tile once made
    /// the two indistinguishable).
    ///
    /// `nil` unless the raccoon `.isWounded`, is within
    /// `garbageCanDiversionRangeTiles` of a non-`nil` `garbageCanPosition`,
    /// and has not already consumed the can at that position
    /// (`RaccoonNode.consumedGarbageCanPosition`).
    static func divertTarget(
        raccoon: RaccoonNode,
        currentPosition: TilePoint,
        garbageCanPosition: TilePoint?
    ) -> TilePoint? {
        guard !raccoon.isDead, raccoon.isWounded, let garbageCanPosition else { return nil }
        guard raccoon.consumedGarbageCanPosition != garbageCanPosition else { return nil }
        guard tileDistance(currentPosition, garbageCanPosition) <= garbageCanDiversionRangeTiles else {
            return nil
        }
        return garbageCanPosition
    }

    /// Plain tile-space Euclidean distance -- not the screen-space
    /// distance `contactStandoffPoints`/`isInContact` use, since a garbage
    /// can's diversion/arrival ranges are defined directly in tile units
    /// (mirroring `PickupManager.attemptCollect(kind:at:radius:)`'s own
    /// tile-space radius, the shape a later wiring PR needs to match).
    private static func tileDistance(_ a: TilePoint, _ b: TilePoint) -> Double {
        hypot(a.x - b.x, a.y - b.y)
    }

    /// Rolls `PickupKind.garbageCan.tuning.dice` (1d6, from PR 1) via the
    /// shared `DiceSpec.roll(using:)` and applies the result directly to
    /// `raccoon.hp`, capped at `raccoon.maxHP` -- the raccoon-side mirror
    /// of `PlayerNode.heal(_:)`'s apply-then-cap shape, deliberately not
    /// shared code with it (see this file's own scope note).
    ///
    /// Guarded on `!raccoon.isDead` as well as at the
    /// `updateWithDiversion(...)` entry point: `isWounded` is `true` at
    /// `hp == 0`, and a heal that resurrects an already-counted,
    /// already-despawned raccoon is exactly the double-bookkeeping
    /// `RaccoonNode+Combat.takeDamage(_:)`'s own guard exists to prevent
    /// (PR #37 review). Returns the amount actually applied -- `0` for a
    /// dead or already-full raccoon.
    @discardableResult
    private static func consumeGarbageCan<R: RandomNumberGenerator>(raccoon: RaccoonNode, rng: inout R) -> Int {
        guard !raccoon.isDead else { return 0 }
        let roll = PickupKind.garbageCan.tuning.dice.roll(using: &rng)
        let before = raccoon.hp
        raccoon.hp = min(raccoon.maxHP, raccoon.hp + roll)
        return raccoon.hp - before
    }
}
