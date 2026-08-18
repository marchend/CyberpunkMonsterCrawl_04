import CoreGraphics
import SpriteKit

/// Composes the player's targeting/firing/bullets/effects/progression
/// subsystems into one working auto-fire combat loop (`CYBERPUN-17-9` PR
/// 3): `WeaponFiringController` (PR 1) decides *when* and *at whom* to
/// fire; `BulletPool`/`BulletNode`/`HitEffects`/`WeaponOverlayRenderer` (PR
/// 2) render the shot, the muzzle flash, the impact and the held weapon;
/// `XPLevelSystem`/`RunStats` (this PR) track progression and combat
/// counters. Nothing upstream of this PR wired any of these five types to
/// one another -- each says so in its own doc comment ("nothing in this PR
/// constructs a caller") -- so this is where the loop first becomes one
/// working whole.
///
/// **Not a replacement for `PlayerNode`.** `PlayerNode` (an `SKNode`) owns
/// the player's body/shadow sprite, HP/rabies and walk-cycle state; `Player`
/// (a plain reference type, not a node) owns the combat/progression
/// composition described above and is handed `PlayerNode.body` at
/// construction purely so `weaponOverlayRenderer` can composite onto it.
///
/// **What "bullet travel" means here.** There is no physics engine in this
/// codebase (`docs/bootstrap.md`; `BulletPool`'s own doc comment), so a
/// fired bullet's "flight" is a fixed-duration timer derived from the
/// screen-space distance to the target at `bulletSpeedPointsPerSecond`, not
/// a per-frame collision query against a moving target. Damage, the kill
/// check and the hit puff apply once that timer elapses, and the bullet is
/// released back to `bulletPool` at that same instant -- or immediately,
/// un-damaging, the moment the target is found to have left the scene graph
/// first (see "Bullet-leak safety" below).
///
/// **Progression wiring (AC7).** `XPLevelSystem.onLevelChange` is
/// subscribed once, at construction: the instant a kill's `awardXP(_:)`
/// call crosses a level boundary, this type calls both
/// `weaponFiringController.setTier(_:)` and
/// `weaponOverlayRenderer.update(tier:direction:)` synchronously, inside
/// that same call stack -- so both the decision layer's tier and the drawn
/// overlay row change on the exact frame the level-up happened, never one
/// frame later. `update(...)` also re-applies the overlay's tier/direction
/// unconditionally at the end of every call, so a frame with no level-up
/// still keeps the overlay's facing in sync with the player's current
/// heading.
///
/// **Bullet-leak safety (regression case).** A bullet's target can leave
/// the scene graph mid-flight for reasons this type does not control --
/// killed by something else, or (in the live game) its chunk streamed out
/// from under it. `advanceInFlightBullets(deltaTime:)` checks
/// `target.raccoon.parent == nil` *before* checking whether the flight
/// timer has elapsed, and releases the bullet without applying damage the
/// first frame that holds -- so a despawned target can never leave a
/// bullet permanently on loan from `bulletPool` (see that type's own
/// "mounting precondition" doc comment for what an unreleased bullet costs
/// in a real run).
///
/// **Production mount.** `GameScene.startPlayer(at:)` constructs one of
/// these, lazily, the first time a run mounts `PlayerNode` -- handing it
/// that node's own `body` sprite and `effectsLayer` as the parent for
/// pooled bullets and transient effects -- and reuses (never rebuilds) it
/// across a RUN AGAIN, calling `reset()` instead (the same "reuse the
/// node, reset its state" convention `startPlayer(at:)` already follows
/// for `PlayerNode` itself). `GameScene.advanceMovementAndCamera(
/// currentTime:)` drives `update(...)` once per frame of an active run,
/// fed `RaccoonSpawnDirector.targetCandidates` for this frame's live
/// targets -- so this is the type that finally makes the auto-fire loop
/// (`WeaponFiringController`, PR 1) fire at a real, on-screen raccoon
/// rather than only at a `WeaponFiringControllerIntegrationTests` double.
final class Player {

    /// XP awarded per raccoon killed by gunfire -- an initial tuning
    /// constant, like every other combat number in this codebase, expected
    /// to move in a later playtesting pass.
    static let xpPerKill: Int = 20

    /// Screen points/second a fired bullet is treated as covering, used
    /// only to derive how long its fixed-duration "flight" timer runs
    /// before damage/hit-puff apply (see the type's own "What bullet
    /// travel means" doc). An initial tuning constant.
    static let bulletSpeedPointsPerSecond: Double = 900

    /// Default fixed pool size handed to `BulletPool` -- comfortably above
    /// the assault rifle's fire rate (`WeaponTier.assaultRifle
    /// .fireIntervalSeconds`, 0.15s) times any plausible on-screen flight
    /// duration, so ordinary play never drops a shot to pool exhaustion.
    static let defaultBulletPoolCapacity: Int = 24

    let weaponFiringController: WeaponFiringController
    let bulletPool: BulletPool
    let weaponOverlayRenderer: WeaponOverlayRenderer
    let xpLevelSystem = XPLevelSystem()
    let runStats = RunStats()

    /// The node transient effects (muzzle flash, hit puff) are mounted
    /// into, and the node `bulletPool`'s pre-mounted bullets live under.
    private let effectsParent: SKNode

    /// The tier/overlay `reset()` restores on a fresh run -- the tier this
    /// instance was originally constructed with, so RUN AGAIN does not
    /// inherit whatever tier the previous run's progression had reached.
    private let initialTier: WeaponTier

    /// The facing most recently handed to `update(...)`, kept so
    /// `xpLevelSystem.onLevelChange`'s handler -- which can fire from
    /// *inside* `update(...)`, off a kill resolved that same call -- always
    /// has a current direction to hand `weaponOverlayRenderer.update(
    /// tier:direction:)`, rather than needing one threaded through the
    /// closure.
    private(set) var currentDirection: Direction8

    private struct InFlightBullet {
        let bulletNode: BulletNode
        let target: RaccoonNode
        let tier: WeaponTier
        let targetScreenPositionAtFireTime: CGPoint
        var elapsed: TimeInterval
        let travelDuration: TimeInterval
    }

    private var inFlightBullets: [InFlightBullet] = []

    /// - Parameters:
    ///   - body: the player's body sprite `weaponOverlayRenderer` composites
    ///     onto -- the same node `PlayerNode.body` exposes.
    ///   - effectsParent: node muzzle flashes/hit puffs and `bulletPool`'s
    ///     pre-mounted bullets are added to.
    ///   - initialTier: the weapon tier shown/fired at construction.
    ///   - initialDirection: the facing shown at construction.
    ///   - bulletPoolCapacity: see `defaultBulletPoolCapacity`.
    init(
        body: SKSpriteNode,
        effectsParent: SKNode,
        initialTier: WeaponTier = .handgun,
        initialDirection: Direction8 = .south,
        bulletPoolCapacity: Int = Player.defaultBulletPoolCapacity
    ) {
        self.effectsParent = effectsParent
        self.currentDirection = initialDirection
        self.initialTier = initialTier

        weaponFiringController = WeaponFiringController(tier: initialTier)
        bulletPool = BulletPool(capacity: bulletPoolCapacity, tier: initialTier, parent: effectsParent)
        weaponOverlayRenderer = WeaponOverlayRenderer(body: body, tier: initialTier, direction: initialDirection)

        weaponFiringController.onFire = { [weak self] target, origin, tier in
            self?.handleFire(target: target, origin: origin, tier: tier)
        }

        xpLevelSystem.onLevelChange = { [weak self] level in
            guard let self else { return }
            let tier = XPLevelSystem.tier(forLevel: level)
            self.weaponFiringController.setTier(tier)
            self.weaponOverlayRenderer.update(tier: tier, direction: self.currentDirection)
        }
    }

    /// Advances the whole loop by one frame: gates/decides a shot
    /// (`weaponFiringController`), advances every in-flight bullet
    /// (resolving damage/kills/XP as their timers elapse), and re-syncs
    /// `weaponOverlayRenderer` to the current tier/direction.
    ///
    /// - Parameters:
    ///   - deltaTime: seconds since the previous call.
    ///   - isMoving: the movement gate `WeaponFiringController` requires --
    ///     `PlayerMovementController.isMoving` in the live game.
    ///   - origin: the player's current tile-space position.
    ///   - direction: the player's current facing.
    ///   - raccoons: this frame's live target candidates.
    func update(
        deltaTime: TimeInterval,
        isMoving: Bool,
        origin: TilePoint,
        direction: Direction8,
        raccoons: [TargetSelection.Candidate]
    ) {
        currentDirection = direction

        weaponFiringController.update(deltaTime: deltaTime, isMoving: isMoving, origin: origin, raccoons: raccoons)
        advanceInFlightBullets(deltaTime: deltaTime)

        // Idempotent re-sync: a level-up mid-call already drove this exact
        // update (with whatever direction was current at that instant) via
        // `onLevelChange`, so this is a no-op in that case and simply keeps
        // the overlay's facing current on every other frame.
        weaponOverlayRenderer.update(tier: weaponFiringController.tier, direction: currentDirection)
    }

    /// Returns this composition to a fresh run's starting state:
    /// unconditionally releases every in-flight bullet back to
    /// `bulletPool` (a run boundary is not a mid-flight despawn -- there is
    /// no live target to check, so this releases every outstanding bullet
    /// rather than going through `advanceInFlightBullets`'s despawn-first
    /// logic), resets `xpLevelSystem`/`runStats`, and re-syncs
    /// `weaponFiringController`'s tier and `weaponOverlayRenderer`'s drawn
    /// row back to `initialTier` -- mirroring
    /// `RaccoonSpawnDirector.reset()`/`RunSummaryStats.reset()`/
    /// `PlayerNode.resetCombatState()`'s own "RUN AGAIN must not inherit
    /// the previous run's state" rule. `GameScene.startPlayer(at:)` calls
    /// this on every fresh `.gameplay` entry once this instance already
    /// exists.
    ///
    /// **Accepted gap:** `WeaponFiringController`'s in-flight fire-rate
    /// cooldown is not reset here (it exposes no such API) -- a run
    /// restarting mid-cooldown may make the player wait up to one tier's
    /// `fireIntervalSeconds` longer than usual for their first shot of the
    /// new run. A cosmetic timing detail, not a state leak: the tier and
    /// counters below are what a stale run boundary could otherwise
    /// visibly carry over.
    func reset() {
        for bullet in inFlightBullets {
            bulletPool.release(bullet.bulletNode)
        }
        inFlightBullets.removeAll()

        xpLevelSystem.reset()
        runStats.reset()

        weaponFiringController.setTier(initialTier)
        weaponOverlayRenderer.update(tier: initialTier, direction: currentDirection)
    }

    // MARK: - Firing

    private func handleFire(target: TargetSelection.Candidate, origin: TilePoint, tier: WeaponTier) {
        let originScreen = IsometricProjection.tileToScreen(origin)
        let targetScreen = IsometricProjection.tileToScreen(target.position)
        let shotVector = CGVector(dx: targetScreen.x - originScreen.x, dy: targetScreen.y - originScreen.y)

        guard let bullet = bulletPool.acquire(origin: originScreen, spriteKitShotVector: shotVector, tier: tier) else {
            // Pool exhausted: drop this shot's visual bullet, the same
            // accepted rare case `BulletPool.acquire`'s own doc comment
            // describes.
            return
        }

        let flash = HitEffects.spawnMuzzleFlash(at: originScreen)
        effectsParent.addChild(flash)
        flash.run(SKAction.sequence([SKAction.wait(forDuration: HitEffects.hitPuffFrameDuration), SKAction.removeFromParent()]))

        let distance = hypot(targetScreen.x - originScreen.x, targetScreen.y - originScreen.y)
        let travelDuration = TimeInterval(distance) / Self.bulletSpeedPointsPerSecond

        inFlightBullets.append(
            InFlightBullet(
                bulletNode: bullet,
                target: target.raccoon,
                tier: tier,
                targetScreenPositionAtFireTime: targetScreen,
                elapsed: 0,
                travelDuration: travelDuration
            )
        )
    }

    // MARK: - Bullet flight / hit resolution

    private func advanceInFlightBullets(deltaTime: TimeInterval) {
        guard deltaTime > 0, !inFlightBullets.isEmpty else { return }

        var stillFlying: [InFlightBullet] = []
        stillFlying.reserveCapacity(inFlightBullets.count)

        for var bullet in inFlightBullets {
            // The despawn check runs before the arrival check: a target
            // gone from the scene graph must release its bullet the first
            // frame that is discovered, whether or not the flight timer has
            // also elapsed this same frame.
            guard bullet.target.parent != nil else {
                bulletPool.release(bullet.bulletNode)
                continue
            }

            bullet.elapsed += deltaTime
            guard bullet.elapsed >= bullet.travelDuration else {
                stillFlying.append(bullet)
                continue
            }

            resolveHit(bullet: bullet)
            bulletPool.release(bullet.bulletNode)
        }

        inFlightBullets = stillFlying
    }

    private func resolveHit(bullet: InFlightBullet) {
        // An already-dead target (killed by something else between firing
        // and arrival) takes no further damage and awards nothing.
        guard !bullet.target.isDead else { return }

        // `onDeath` is the kill-award seam `RaccoonNode`'s own doc comment
        // names for this exact story; set once, lazily, rather than
        // overwriting it on every hit.
        if bullet.target.onDeath == nil {
            bullet.target.onDeath = { [weak self] in
                guard let self else { return }
                self.xpLevelSystem.awardXP(Self.xpPerKill)
                self.runStats.recordKill()
            }
        }

        bullet.target.takeDamage(bullet.tier.damage)
        runStats.recordDamage(bullet.tier.damage)

        let puff = HitEffects.spawnHitPuff(at: bullet.targetScreenPositionAtFireTime)
        effectsParent.addChild(puff)
    }
}
