import CoreGraphics
import SpriteKit

/// Assembles the player's on-screen presence: the atlas-sliced walk-cycle
/// body sprite, a separate ground `ActorShadowNode`, and the frame/facing
/// state machine (`PlayerAnimator` + `Direction8` + `PlayerSpriteSheet`,
/// `CYBERPUN-17-6-t1`) that drives the body's texture and mirroring.
///
/// **Who mounts this in a real build:** `GameScene.startPlayer(at:)` parents
/// one of these directly under `GameScene.worldLayer` on entry to
/// `.gameplay`, at the run's spawn tile and with its depth resolved through
/// `DepthBanding`, and `GameScene.advanceMovementAndCamera(currentTime:)`
/// (called from `update(_:)`) drives `update(deltaTime:movementVector:)`
/// once per frame. This follows the rule
/// `GroundTileRenderer`'s type doc writes down for this repo -- *"a factory
/// with no production caller is exactly the shape of feature that never gets
/// switched on"* -- so the anchor, shadow and depth integration is
/// observable on a device from this PR rather than from the next one.
///
/// **Scope of this PR (`CYBERPUN-17-6-t2`):** node assembly and per-frame
/// visual state only. There is no physics body and no movement of this
/// node's own `position` -- `update(deltaTime:movementVector:)` only reads
/// the vector to resolve facing/animation, it never applies it. The scene
/// passed `.zero` while nothing produced real input, and the mounted player
/// stood idle on frame 0. Movement, the floating thumbstick and
/// camera-follow have since landed with `CYBERPUN-17-7`:
/// `GameScene.advanceMovementAndCamera(currentTime:)` resolves the stick
/// against building collision, commits `position` and this node's depth
/// itself, and passes the resulting movement vector here purely for facing
/// and frame state. The scripted demo driver that previously stood in for
/// real input, and the `GameScene.debugPlayerDemoEnabled` flag that gated
/// it, are gone.
final class PlayerNode: SKNode {

    /// The player's ground-collision hitbox size -- delegated to
    /// `PlayerSpriteSheet` rather than a second copy of the numbers.
    static let hitboxSize = PlayerSpriteSheet.hitboxSize

    /// The width of the player's ground shadow: the player's **measured**
    /// ground footprint (`PlayerSpriteSheet.hitboxSize.width`), not a
    /// hand-picked shadow size. `ActorShadowNode` is deliberately
    /// actor-agnostic, so the actor is the only place that knows which
    /// measurement its shadow should match -- and matching the footprint is
    /// what keeps the ellipse under the character's feet instead of
    /// overhanging them by an unexplained margin.
    static let shadowWidth = PlayerSpriteSheet.hitboxSize.width

    /// Small, strictly-ordered relative zPosition offsets for the two
    /// children below, both well inside `DepthModel.bandSpacing` (10) so
    /// neither can bleed into a neighbouring band once a caller sets this
    /// node's own absolute `zPosition` (via `DepthBanding.playerZPosition`)
    /// and SpriteKit accumulates these on top of it.
    private static let shadowRelativeZ: CGFloat = 0
    private static let bodyRelativeZ: CGFloat = 0.01

    /// The walk-cycle body sprite. A direct child so its own `zPosition`
    /// (`bodyRelativeZ`) sits strictly above the shadow's.
    let body: SKSpriteNode

    /// The ground shadow, drawn as a distinct node -- never baked into
    /// `body`'s texture -- and z-ordered beneath `body`.
    let shadow: ActorShadowNode

    /// The facing currently shown. Persists across `.zero`-vector
    /// (not-moving) calls, so idle keeps the last direction the player was
    /// walking rather than snapping back to a default.
    private(set) var facing: Direction8 = .south

    /// Whether the most recent `update` call was given a non-zero movement
    /// vector.
    private(set) var isMoving = false

    /// Seconds elapsed since the current moving/idle state began. Reset to
    /// `0` whenever `isMoving` flips, so a freshly-started walk cycle always
    /// begins at `PlayerAnimator`'s first frame rather than resuming
    /// mid-cycle from an unrelated previous walk.
    private var elapsedInCurrentMotionState: TimeInterval = 0

    // MARK: - Combat state (`CYBERPUN-17-8` PR 3)
    //
    // Ordinary stored properties, declared here on the class that owns
    // them, so the player's HP invariant is visible to anyone reading this
    // file and the per-frame `tickRabies` path is a direct field access.
    // The behaviour over this state -- `takeDamage(_:)`, `infect(stats:)`,
    // `tickRabies(deltaTime:)` and `resetCombatState()` -- lives in
    // `PlayerNode+Rabies.swift`.

    /// The player's baseline max HP. `PlayerNode` carried no HP concept
    /// before this PR (movement/rendering only); introduced here because
    /// the rabies DoT tick and the bite's direct damage are the first
    /// things that need one. An initial tuning constant, expected to move
    /// in a later playtesting pass, like `RaccoonNode.baseMaxHP`.
    static let baseMaxHP: Int = 100

    /// The player's maximum HP -- a full `baseMaxHP` at spawn, the same
    /// "spawns at full HP" convention `RaccoonNode.init(hp:)` documents.
    var maxHP: Int = PlayerNode.baseMaxHP

    /// The player's current HP, clamped to `0...maxHP` by this property's
    /// own `didSet`. Re-assigning inside `didSet` does not re-enter it, so
    /// the clamp runs exactly once per write.
    var hp: Int = PlayerNode.baseMaxHP {
        didSet {
            let clamped = min(max(0, hp), maxHP)
            if hp != clamped {
                hp = clamped
            }
        }
    }

    /// Whether the player currently carries the rabies infection.
    var isInfected = false

    /// Seconds' worth of rabies damage accumulated but not yet applied as a
    /// whole HP -- see `tickRabies(deltaTime:)`. Internal rather than
    /// `private` only because that method lives in the extension file
    /// beside the rest of the rabies behaviour.
    var rabiesDamageAccumulator: TimeInterval = 0

    override init() {
        let initialMapping = PlayerSpriteSheet.rowMapping(for: .south)
        body = SKSpriteNode(texture: Self.texture(row: initialMapping.row, column: PlayerAnimator.frameContactFirst))
        body.size = PlayerSpriteSheet.cellSize
        body.anchorPoint = PlayerSpriteSheet.anchorPointNormalized
        body.zPosition = Self.bodyRelativeZ

        shadow = ActorShadowNode(width: Self.shadowWidth)
        shadow.zPosition = Self.shadowRelativeZ

        super.init()

        // Shadow first: no ordering requirement for `addChild` itself (that
        // is what `zPosition` is for), but adding the ground-plane-adjacent
        // node first mirrors the visual stacking for readability.
        addChild(shadow)
        addChild(body)

        PixelCrispness.apply(to: body)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("PlayerNode does not support NSCoder deserialization.")
    }

    /// The player's ground-collision hitbox, anchored at this node's own
    /// `position` -- which already sits at the character's feet, since
    /// `body`'s `anchorPoint` puts the visual anchor at this node's local
    /// origin. No physics body is attached; this is exposed purely as
    /// geometry for a future collision consumer.
    var hitbox: CGRect {
        PlayerSpriteSheet.hitboxRect(anchoredAt: position)
    }

    /// Updates this node's absolute `zPosition` for a player standing at
    /// fractional tile-space `tilePosition`, via `DepthBanding
    /// .playerZPosition(at:)` -- the depth-banding/z-order integration this
    /// PR wires up. `DepthBanding` always assigns the player the top of
    /// `DepthModel.actorOffsetRange`, so this node's zPosition is guaranteed
    /// the maximum within its band among any other (non-player) actor.
    ///
    /// The result is converted via `DepthModel.worldLayerRelativeZ(
    /// forAbsoluteZ:)` because a node parented **directly** under
    /// `GameScene.worldLayer` (the same convention `GroundTileRenderer`
    /// follows) must carry a *relative* zPosition -- SpriteKit accumulates
    /// zPosition down the tree, and `worldLayer` already carries its own
    /// offset. A future caller that parents `PlayerNode` anywhere else would
    /// need its own conversion; this node does not assume where it is
    /// mounted beyond this one documented convention.
    func updateDepth(atTilePosition tilePosition: TilePoint) {
        let absoluteZ = DepthBanding.playerZPosition(at: tilePosition)
        zPosition = DepthModel.worldLayerRelativeZ(forAbsoluteZ: absoluteZ)
    }

    /// Advances the player's visual state by `deltaTime`, given the
    /// player's current movement vector in **SpriteKit (y-up) scene
    /// space** -- a stick reading, a resolved velocity, or `.zero` while
    /// idle.
    ///
    /// This never touches `position`; callers that also move the node do so
    /// separately (out of scope here -- see the type-level doc comment).
    ///
    /// 1. Resolves facing via `Direction8.from(spriteKitVector:)`. A
    ///    zero-magnitude vector resolves to `nil` and leaves `facing`
    ///    unchanged, exactly as `Direction8` documents.
    /// 2. Looks up `(row, mirrored)` for that facing via
    ///    `PlayerSpriteSheet.rowMapping(for:)`.
    /// 3. Gets the walk-cycle frame column via
    ///    `PlayerAnimator.frameIndex(elapsedTime:isMoving:)`, which freezes
    ///    to frame 0 whenever `isMoving` is `false`.
    /// 4. Assigns the resulting texture and sets `body.xScale`'s *sign*
    ///    from the mirror flag, preserving its magnitude.
    func update(deltaTime: TimeInterval, movementVector: CGVector) {
        // CYBERPUN-17-8 PR 3: the rabies DoT tick (`PlayerNode+Rabies.swift`).
        // A no-op while not infected.
        tickRabies(deltaTime: deltaTime)

        let newlyMoving = movementVector.dx != 0 || movementVector.dy != 0

        if newlyMoving, let resolvedDirection = Direction8.from(spriteKitVector: movementVector) {
            facing = resolvedDirection
        }

        if newlyMoving != isMoving {
            // Motion state just flipped (started or stopped moving): reset
            // the walk cycle rather than resuming mid-stride from whatever
            // state the previous motion segment left behind.
            elapsedInCurrentMotionState = 0
        } else if newlyMoving {
            elapsedInCurrentMotionState += deltaTime
        }
        isMoving = newlyMoving

        let mapping = PlayerSpriteSheet.rowMapping(for: facing)
        let frameColumn = PlayerAnimator.frameIndex(elapsedTime: elapsedInCurrentMotionState, isMoving: isMoving)
        body.texture = Self.texture(row: mapping.row, column: frameColumn)

        let magnitude = abs(body.xScale)
        body.xScale = mapping.mirrored ? -magnitude : magnitude
    }

    // MARK: - Texture slicing (cached)

    /// The player's measured sheet contract, resolved **once**.
    ///
    /// `PlayerSpriteSheet.sheet` is a computed `var` over
    /// `AtlasSheet.playerWalk.sheet`, so *every* read constructs a fresh
    /// `SpriteSheet`, which re-runs `SpriteSheet.init`'s measurement
    /// `precondition` -- an asset-catalog lookup plus a `UIImage`/`.cgImage`
    /// decode. That is the right amount of paranoia for a one-off contract
    /// check and the wrong amount for a path `update(deltaTime:
    /// movementVector:)` runs ~60x/second, so the invariant is hoisted off
    /// the hot path here: the sheet is measured once, on first use, and the
    /// per-frame path below is a pure dictionary lookup.
    private static let cachedSheet: SpriteSheet = PlayerSpriteSheet.sheet

    /// `cachedSheet`'s column count -- the cache key's stride. Read off the
    /// already-measured sheet rather than through `PlayerSpriteSheet.columns`
    /// (which re-enters the atlas contract, and so would re-measure the image
    /// on every cache *hit*, which is precisely the work the cache exists to
    /// avoid).
    private static let cachedColumns: Int = PlayerNode.cachedSheet.columns

    /// One `SKTexture` per `(row, column)` cell of `sprite_player_walk`,
    /// sliced on first use and reused thereafter -- slicing on every
    /// `update` call would allocate a fresh `SKTexture` many times a
    /// second for no visual benefit, since the sheet's cells never change.
    ///
    /// **Isolation:** this is mutable static state with no synchronisation,
    /// and it is safe only because every access happens on SpriteKit's
    /// main-thread update loop (`SKScene.update(_:)` and node construction);
    /// nothing here may be touched from a background queue. Moving this
    /// target to Swift 6 strict concurrency will require `@MainActor` (or an
    /// equivalent isolation) on this property and on `texture(row:column:)`
    /// rather than a lock, since the single-threaded access pattern is the
    /// actual invariant.
    private static var textureCache: [Int: SKTexture] = [:]

    /// Cuts (and caches) the `(row, column)` cell of `PlayerSpriteSheet` as
    /// a nearest-filtered, mipmap-free `SKTexture`. Exposed (not private) so
    /// tests can compare a produced texture's identity against the exact
    /// same cache this node's production path uses, rather than
    /// constructing a second, possibly-drifting crop of their own.
    static func texture(row: Int, column: Int) -> SKTexture {
        let key = row * cachedColumns + column
        if let cached = textureCache[key] {
            return cached
        }
        let texture = cachedSheet.texture(col: column, row: row)
        texture.filteringMode = .nearest
        texture.usesMipmaps = false
        textureCache[key] = texture
        return texture
    }
}
