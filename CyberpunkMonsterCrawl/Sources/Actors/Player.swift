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
/// working whole, and those upstream deferrals are closed by the production
/// mount described below rather than by a later ticket.
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
/// The *visual* bullet is moved every frame while that timer runs:
/// `advanceInFlightBullets(deltaTime:)` interpolates the node from the
/// muzzle to the target's **current** world position by
/// `elapsed / travelDuration`, so a bullet is drawn crossing the gap rather
/// than parked at the muzzle for its whole flight. Its `zRotation` is set
/// once, at fire time, from the shot vector (`BulletNode.configure`) and is
/// deliberately not re-derived per frame: AC5's "drawn rotated to the shot
/// vector" is about the shot that was taken, and a target that strafes
/// mid-flight must not make the sprite spin.
///
/// **Coordinate space (why every point goes through
/// `effectsSpacePoint(fromWorldSpace:)`).** `IsometricProjection
/// .tileToScreen` points are in **world space** -- the space
/// `GameScene.worldLayer`'s children live in, and the only space
/// `CameraController` ever offsets (`container.position = viewportCentre -
/// projected(focus)`). Bullets and transient effects are parented under
/// `GameScene.effectsLayer`, which nothing repositions, so writing a raw
/// world point into an `effectsLayer` child draws it `worldLayer.position`
/// away from where the world actually is -- a large offset from the very
/// first frame (the spawn junction is far from tile 0,0) that drifts
/// further as the player walks. Every point this type hands to
/// `bulletPool`/`HitEffects` is therefore converted out of world space
/// first, through the same `convert(_:from:)` seam
/// `GameScene.accessibilityFrameInScene(for:)` uses to keep two spaces in
/// agreement by construction, and in-flight bullets are re-converted every
/// frame so a scrolling camera cannot leave them behind.
/// `PlayerCombatSceneWiringTests` pins a fired bullet's *scene-space*
/// position onto the shooter, which is the assertion that keeps this
/// honest -- a child count or an `activeCount` cannot see this class of
/// bug.
///
/// **Known gap: the muzzle flash is at the actor anchor, not the barrel
/// tip (AC6).** `handleFire(target:origin:tier:)` spawns the flash at the
/// player's projected tile position, which is this codebase's
/// bottom-centre actor anchor -- his feet -- and not the barrel tip AC6
/// asks for. Closing it needs a *measured* per-direction muzzle pixel read
/// off the shipped `sprite_player_weapons.png` (24 cells: 8 directions x 3
/// tiers); an earlier revision inferred that table from the weapon cell's
/// centre, which was wrong against the bottom-centre anchor, and
/// `WeaponTier`/`HitEffects` record why it was removed rather than shipped
/// wrong. No pixel measurement of the shipped art was made in this PR, so
/// no offset table is invented here either: the gap is recorded at the
/// spawn site and on this story's task record (`CYBERPUN-17-9-t3`) instead,
/// and `HitEffects`' own note now points here rather than at "the PR that
/// mounts `sprite_player_weapons`", which is this one.
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
/// that node's own `body` sprite, `effectsLayer` as the parent for pooled
/// bullets and transient effects, and `worldLayer` as the world-space
/// reference every projected point is converted out of (see "Coordinate
/// space" above) -- and reuses (never rebuilds) it
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

    /// The node raw `IsometricProjection.tileToScreen` points resolve in --
    /// `GameScene.worldLayer` in the live game, the one container
    /// `CameraController` offsets. Every world point is converted out of
    /// this node's space and into `effectsParent`'s before it is written to
    /// a node (see the type's "Coordinate space" note).
    ///
    /// Weak for the reason `CameraController.container` documents: the
    /// scene (or a test) owns this node's lifetime, and this type must
    /// never keep a torn-down subtree alive.
    ///
    /// `nil` -- or a reference not yet in the same scene as `effectsParent`
    /// -- means there is no camera-offset container to convert out of, as
    /// in the headless unit tests that drive `update(...)` against loose
    /// nodes; world points are then used unconverted, which is exactly
    /// right when both spaces are the identity.
    private weak var worldSpaceReference: SKNode?

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

        /// The muzzle, in **world** space -- the fixed end of the flight
        /// the node is interpolated from every frame.
        let originWorldPosition: CGPoint

        /// Where the target was, in **world** space, when the shot was
        /// fired. Only the fallback destination: a target still mounted in
        /// `worldSpaceReference` is chased at its *current* position
        /// instead (`currentTargetWorldPosition(of:)`), since raccoons are
        /// re-steered every frame by `RaccoonSpawnDirector` and a
        /// 0.05-0.5s flight would otherwise land the bullet and its hit
        /// puff where the target no longer is.
        let targetWorldPositionAtFireTime: CGPoint

        var elapsed: TimeInterval
        let travelDuration: TimeInterval
    }

    private var inFlightBullets: [InFlightBullet] = []

    /// - Parameters:
    ///   - body: the player's body sprite `weaponOverlayRenderer` composites
    ///     onto -- the same node `PlayerNode.body` exposes.
    ///   - effectsParent: node muzzle flashes/hit puffs and `bulletPool`'s
    ///     pre-mounted bullets are added to.
    ///   - worldSpaceReference: the camera-offset world container raw
    ///     `IsometricProjection.tileToScreen` points resolve in
    ///     (`GameScene.worldLayer`); see the property of the same name.
    ///     Defaults to `nil` for headless callers whose effects parent is
    ///     itself the world space.
    ///   - initialTier: the weapon tier shown/fired at construction.
    ///   - initialDirection: the facing shown at construction.
    ///   - bulletPoolCapacity: see `defaultBulletPoolCapacity`.
    init(
        body: SKSpriteNode,
        effectsParent: SKNode,
        worldSpaceReference: SKNode? = nil,
        initialTier: WeaponTier = .handgun,
        initialDirection: Direction8 = .south,
        bulletPoolCapacity: Int = Player.defaultBulletPoolCapacity
    ) {
        self.effectsParent = effectsParent
        self.worldSpaceReference = worldSpaceReference
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
        let originWorld = IsometricProjection.tileToScreen(origin)
        let targetWorld = IsometricProjection.tileToScreen(target.position)

        // The shot vector is a *delta*, so it needs no space conversion:
        // the world -> effects transform this type applies is a pure
        // translation (the camera offset), which leaves deltas -- and so
        // the rotation `BulletNode` derives from them -- unchanged.
        let shotVector = CGVector(dx: targetWorld.x - originWorld.x, dy: targetWorld.y - originWorld.y)

        let muzzleInEffectsSpace = effectsSpacePoint(fromWorldSpace: originWorld)

        guard let bullet = bulletPool.acquire(
            origin: muzzleInEffectsSpace,
            spriteKitShotVector: shotVector,
            tier: tier
        ) else {
            // Pool exhausted: drop this shot's visual bullet, the same
            // accepted rare case `BulletPool.acquire`'s own doc comment
            // describes.
            return
        }

        // Placed at the player's actor anchor (his feet), *not* the barrel
        // tip AC6 asks for -- see the type doc's "Known gap". Closing it
        // needs a measured per-direction muzzle pixel off the shipped
        // `sprite_player_weapons.png`; none was measured in this PR, and
        // this codebase already rejected one inferred offset table
        // (`WeaponTier`/`HitEffects`), so the flash stays at the anchor
        // rather than at an invented offset.
        let flash = HitEffects.spawnMuzzleFlash(at: muzzleInEffectsSpace)
        effectsParent.addChild(flash)
        flash.run(SKAction.sequence([SKAction.wait(forDuration: HitEffects.hitPuffFrameDuration), SKAction.removeFromParent()]))

        let distance = hypot(targetWorld.x - originWorld.x, targetWorld.y - originWorld.y)
        let travelDuration = TimeInterval(distance) / Self.bulletSpeedPointsPerSecond

        inFlightBullets.append(
            InFlightBullet(
                bulletNode: bullet,
                target: target.raccoon,
                tier: tier,
                originWorldPosition: originWorld,
                targetWorldPositionAtFireTime: targetWorld,
                elapsed: 0,
                travelDuration: travelDuration
            )
        )
    }

    // MARK: - Coordinate spaces

    /// Converts a world-space point (any `IsometricProjection.tileToScreen`
    /// result, or the position of a node parented in `worldSpaceReference`)
    /// into `effectsParent`'s own space, so a node written with it draws
    /// where the world actually is rather than `worldLayer.position` away
    /// from it. See the type's "Coordinate space" note for the failure this
    /// prevents.
    ///
    /// Falls back to the point unchanged when there is no world container
    /// to convert out of, or when the two nodes are not yet in the same
    /// scene -- `SKNode.convert(_:from:)` is only defined for nodes sharing
    /// a scene, and the two spaces are the identity in that case anyway.
    private func effectsSpacePoint(fromWorldSpace point: CGPoint) -> CGPoint {
        guard let worldSpaceReference,
              let worldScene = worldSpaceReference.scene,
              effectsParent.scene === worldScene
        else {
            return point
        }
        return effectsParent.convert(point, from: worldSpaceReference)
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
                // The visual half of "bullets travel": the node is moved
                // along its flight every frame, and re-converted out of
                // world space every frame so a scrolling camera cannot
                // leave it behind.
                bullet.bulletNode.position = effectsSpacePoint(
                    fromWorldSpace: inFlightWorldPosition(of: bullet)
                )
                stillFlying.append(bullet)
                continue
            }

            resolveHit(bullet: bullet)
            bulletPool.release(bullet.bulletNode)
        }

        inFlightBullets = stillFlying
    }

    /// Where `bullet` has got to along its flight, in world space:
    /// a straight interpolation from the muzzle to the target's current
    /// position by `elapsed / travelDuration`, clamped to that segment. A
    /// zero-length flight (a target on the player's own tile) resolves
    /// straight to the destination rather than dividing by zero.
    private func inFlightWorldPosition(of bullet: InFlightBullet) -> CGPoint {
        let destination = currentTargetWorldPosition(of: bullet)
        guard bullet.travelDuration > 0 else { return destination }

        let progress = CGFloat(min(1, max(0, bullet.elapsed / bullet.travelDuration)))
        return CGPoint(
            x: bullet.originWorldPosition.x + (destination.x - bullet.originWorldPosition.x) * progress,
            y: bullet.originWorldPosition.y + (destination.y - bullet.originWorldPosition.y) * progress
        )
    }

    /// The target's **current** world-space position -- its node position,
    /// which `RaccoonSpawnDirector` rewrites every frame as it re-steers
    /// the swarm, so a bullet and its hit puff resolve against where the
    /// raccoon is now rather than where it stood at fire time.
    ///
    /// Only trusted while the node is a direct child of the same world
    /// container this type converts out of: that is exactly how
    /// `RaccoonSpawnDirector` mounts a raccoon (`worldLayer.addChild`).
    /// Any other arrangement (a headless test's loose parent node, a
    /// re-parented raccoon) falls back to the fire-time position rather
    /// than mixing two spaces.
    private func currentTargetWorldPosition(of bullet: InFlightBullet) -> CGPoint {
        guard let worldSpaceReference, bullet.target.parent === worldSpaceReference else {
            return bullet.targetWorldPositionAtFireTime
        }
        return bullet.target.position
    }

    private func resolveHit(bullet: InFlightBullet) {
        // An already-dead target (killed by something else between firing
        // and arrival) takes no further damage and awards nothing.
        guard !bullet.target.isDead else { return }

        // Resolved *before* `takeDamage(_:)` below: a killing blow runs
        // `RaccoonNode.die()`, which removes the node from the scene graph,
        // and an unparented node can no longer be converted out of world
        // space -- the puff would then land at the raw world point, i.e.
        // the very bug the "Coordinate space" note describes.
        let impactPoint = effectsSpacePoint(fromWorldSpace: currentTargetWorldPosition(of: bullet))

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

        let puff = HitEffects.spawnHitPuff(at: impactPoint)
        effectsParent.addChild(puff)
    }
}
