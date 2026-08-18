import CoreGraphics
import SpriteKit

/// Fixed-capacity pool of `BulletNode`s, pre-built and hidden under
/// `parent` at construction, so `acquire`/`release` never call
/// `addChild`/`removeFromParent` on the per-shot hot path
/// (`CYBERPUN-17-9` PR 2) -- the same "pre-mount, toggle state" discipline
/// `GroundPlaneStreamer`'s recycle pool already established in this
/// codebase for a different reason (a bounded resident-chunk node count);
/// here the reason is a bounded number of simultaneously in-flight
/// bullets.
///
/// **"physics" toggling.** The story text describes acquire/release as
/// toggling "visibility/physics". This codebase attaches no
/// `SKPhysicsBody` anywhere (`docs/bootstrap.md`: "no physics engine for
/// world collision" -- collision here is a tile-grid query, never a
/// physics body), so there is no physics *body* to enable/disable; the
/// SpriteKit-level state this pool toggles is `isHidden`.
///
/// **Scope of this PR.** Node lifecycle only: claiming/returning a
/// `BulletNode` and reconfiguring it in place. Nothing here decides when a
/// bullet is fired (`WeaponFiringController`, PR 1) or releases a bullet on
/// impact/off-screen.
///
/// **Mounting precondition: the caller MUST own a release path.** This is a
/// hard contract, not a nicety, and it is stated here because the failure is
/// silent. `acquire` returns `nil` once every node is on loan, so a caller
/// that mounts this pool without calling `release(_:)` on impact and on
/// leaving the screen gets `capacity` bullets that stay `isHidden == false`
/// forever, a permanently exhausted pool, and *every subsequent shot drawing
/// nothing* -- with no crash, no log, and a green suite, because the tests
/// in `BulletPoolTests` release by hand. That exhausted state is now pinned
/// by `BulletPoolTests`
/// `.test_aCallerWithNoReleasePath_permanentlyExhaustsThePool`, so the
/// consequence is asserted rather than merely described: whoever mounts this
/// can read what breaks if they skip the release path.
///
/// **Why this slice lands with no production caller -- and what that
/// costs.** Nothing in this PR constructs a `BulletPool`, a `BulletNode`, a
/// `HitEffects` or a `WeaponOverlayRenderer`: `GameScene` is untouched, so a
/// device build still shows no bullet. That is the same shape PR #34 review
/// rejected for `BiteComponent`, and `GroundTileRenderer`'s doc records the
/// repo rule it comes from ("a factory with no production caller is exactly
/// the shape of feature that never gets switched on"). The blocker is the
/// one `WeaponFiringController`'s own doc comment already records: a real
/// caller needs the per-frame `[TargetSelection.Candidate]` array built from
/// `RaccoonSpawnDirector`'s live swarm, whose `ActiveRaccoon` bookkeeping is
/// still `private` to that type and still owned by the raccoon-swarm story.
///
/// The wiring + release path is therefore still deferred, and deliberately
/// **not** cited here as a ticket ID: none has been filed, and this codebase
/// does not reference invented ticket IDs (`WeaponFiringController` states
/// the same rule for the same reason). Filing it is a human call, so it is
/// requested on this story's task record (`CYBERPUN-17-9-t2`) and in PR #42's
/// review thread; when that ticket exists, this paragraph and
/// `WeaponFiringController`'s should cite it in place of "the wiring PR".
final class BulletPool {

    /// This pool's fixed capacity -- the maximum number of bullets that can
    /// ever be simultaneously in flight.
    let capacity: Int

    /// Every pre-built pool node, in construction order. Never resized
    /// after `init` -- exactly `capacity` nodes exist for this pool's whole
    /// lifetime.
    private let nodes: [BulletNode]

    /// The identity of every node currently on loan to a caller --
    /// `ObjectIdentifier` rather than the node itself, since `BulletNode`
    /// has no `Equatable`/`Hashable` conformance of its own and identity
    /// (not value) is what "the same pool slot" means here.
    private(set) var activeIdentifiers: Set<ObjectIdentifier> = []

    /// The number of nodes currently on loan.
    var activeCount: Int { activeIdentifiers.count }

    /// - Parameters:
    ///   - capacity: fixed pool size; must be positive.
    ///   - tier: the tier every pre-built node is initially textured for --
    ///     an arbitrary starting value never observed by a caller, since
    ///     `acquire` always re-textures to the tier of the shot it serves.
    ///   - parent: node every pool node is added to, hidden, at
    ///     construction, and never removed from again.
    init(capacity: Int, tier: WeaponTier = .handgun, parent: SKNode) {
        precondition(capacity > 0, "BulletPool capacity must be positive.")
        self.capacity = capacity

        nodes = (0..<capacity).map { _ in
            let node = BulletNode(tier: tier)
            node.isHidden = true
            parent.addChild(node)
            return node
        }
    }

    /// Claims a free pool node for a new shot: retextures/repositions/
    /// rotates it (`BulletNode.configure(tier:position:shotVector:)`),
    /// unhides it, and marks it active. Returns `nil` -- rather than
    /// growing the pool or evicting the oldest in-flight bullet -- when
    /// every node is already on loan, so `capacity` is a hard ceiling on
    /// simultaneous bullets; a caller that gets `nil` simply drops that
    /// shot's visual bullet (the decision layer's fire-rate/range gating
    /// already keeps this a rare, bounded case rather than a normal one).
    ///
    /// `spriteKitShotVector` names the space it is in, the same way
    /// `BulletNode.angle(forSpriteKitShotVector:)` does: a tile-space caller
    /// converts via `BulletNode.angle(fromTileOrigin:toTileTarget:)`'s
    /// transform rather than handing a raw tile delta to this seam.
    ///
    /// **A caller that never calls `release(_:)` exhausts this pool
    /// permanently** -- see the type's own doc comment.
    @discardableResult
    func acquire(origin: CGPoint, spriteKitShotVector: CGVector, tier: WeaponTier) -> BulletNode? {
        guard let freeNode = nodes.first(where: { !activeIdentifiers.contains(ObjectIdentifier($0)) }) else {
            return nil
        }

        freeNode.configure(tier: tier, position: origin, spriteKitShotVector: spriteKitShotVector)
        freeNode.isHidden = false
        activeIdentifiers.insert(ObjectIdentifier(freeNode))
        return freeNode
    }

    /// Returns `node` to the pool: hides it and clears its active flag.
    ///
    /// A safe no-op for a node that is already released, or that never
    /// came from this pool -- `activeIdentifiers` is checked before any
    /// mutation, so a double-release (or a foreign node) can never hide an
    /// already-hidden node's visibility state twice or corrupt
    /// `activeCount`.
    func release(_ node: BulletNode) {
        let identifier = ObjectIdentifier(node)
        guard activeIdentifiers.contains(identifier) else { return }
        activeIdentifiers.remove(identifier)
        node.isHidden = true
    }
}
