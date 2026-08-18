import CoreGraphics
import SpriteKit

/// A single raccoon actor: position/facing/hp state, tier-scaled rendering
/// and depth sorting.
///
/// **Scope of this PR (`CYBERPUN-17-8-t1`).** Rendering/actor-state layer
/// only \u2014 node assembly, tier-scaled visuals, hp/`isWounded`, and depth
/// sorting. There is no seek behaviour, no building-footprint collision, no
/// bite/rabies logic and no spawning here; those are later parts of the
/// `CYBERPUN-17-8` story. Nothing in this PR mounts a `RaccoonNode` into
/// `GameScene` either \u2014 that lands with the swarm-spawning PR, the same way
/// `PlayerNode` (`CYBERPUN-17-6-t2`) was assembled one PR before
/// `GameScene.startPlayer()` actually mounted it.
final class RaccoonNode: SKNode {

    /// The baseline (tier `.base`) raccoon max HP. Elites scale this via
    /// `RaccoonTier.maxHPMultiplier`. An initial tuning constant \u2014 the story
    /// explicitly defers exact difficulty numbers to playtesting, so this is
    /// expected to move in a later PR.
    static let baseMaxHP: Int = 20

    /// Small, strictly-ordered relative zPosition offsets for the two
    /// children below, both well inside `DepthModel.bandSpacing` (10) \u2014 the
    /// same convention `PlayerNode` uses for its own body/shadow pair.
    private static let shadowRelativeZ: CGFloat = 0
    private static let bodyRelativeZ: CGFloat = 0.01

    /// The depth offset every raccoon occupies within
    /// `DepthBanding.nonPlayerActorOffsetRange` \u2014 that range's exact lower
    /// bound, the same value as `DepthModel.actorOffsetRange.lowerBound`
    /// (`6.5`), so a raccoon always draws behind the player when they share
    /// a tile (`DepthBanding`'s player-max tie-break) while still occupying
    /// the legal actor-offset band.
    static let depthOffset: CGFloat = DepthBanding.nonPlayerActorOffsetRange.lowerBound

    /// This raccoon's tier (base/elite) \u2014 fixed for the raccoon's lifetime;
    /// a raccoon does not change tier after spawning.
    let tier: RaccoonTier

    /// This raccoon's maximum HP: `baseMaxHP` scaled by `tier.maxHPMultiplier`.
    let maxHP: Int

    /// This raccoon's current HP. Mutable so a later PR's damage/rabies
    /// systems can adjust it directly; clamped to `0...maxHP` is this type's
    /// job only insofar as `isWounded` reads it \u2014 the actual damage/death
    /// pipeline is a later PR's.
    var hp: Int

    /// The walk/attack animation + facing state machine driving `body`.
    let animationController: RaccoonAnimationController

    /// The atlas-sliced body sprite, sized at `tier.scale` x the base cell
    /// size and snapped to whole device pixels (see `scaledSize(forTier:
    /// deviceScale:)`).
    let body: SKSpriteNode

    /// The ground shadow, a distinct node z-ordered beneath `body` \u2014 the
    /// same `ActorShadowNode` `PlayerNode` uses, scaled with this raccoon's
    /// tier so an elite's shadow grows with its body.
    let shadow: ActorShadowNode

    /// This raccoon's current facing, read straight off `animationController`
    /// so `RaccoonNode` never keeps a second, possibly-drifting copy.
    var facing: Direction8 { animationController.direction }

    /// Whether this raccoon is below full HP \u2014 the pickups story
    /// (`CYBERPUN-17-11`) reads this to divert garbage-can pickups toward a
    /// wounded raccoon.
    var isWounded: Bool { hp < maxHP }

    /// - Parameters:
    ///   - tier: base or elite; fixes `maxHP` and the rendered scale.
    ///   - facing: initial facing; defaults to `.south`, matching
    ///     `PlayerNode`'s own default.
    ///   - hp: initial HP; defaults to `maxHP` (an undamaged spawn). Exposed
    ///     as a parameter (rather than always starting full) so tests can
    ///     construct an already-wounded raccoon directly.
    ///   - deviceScale: the device pixel grid `body`'s tier-scaled size is
    ///     snapped to at construction \u2014 `view?.contentScaleFactor`, the same
    ///     convention `GameScene.deviceScale` / `CameraController` use.
    ///     Defaults to `1`, the whole-point fallback for a headless,
    ///     view-less scene (unit tests).
    init(
        tier: RaccoonTier,
        facing: Direction8 = .south,
        hp: Int? = nil,
        deviceScale: CGFloat = 1
    ) {
        self.tier = tier
        let resolvedMaxHP = Int((CGFloat(Self.baseMaxHP) * tier.maxHPMultiplier).rounded())
        self.maxHP = resolvedMaxHP
        self.hp = hp ?? resolvedMaxHP

        animationController = RaccoonAnimationController(initialDirection: facing)

        let mapping = animationController.currentRowMapping
        body = SKSpriteNode(
            texture: RaccoonNode.texture(state: animationController.state, row: mapping.row, column: 0)
        )
        body.size = RaccoonNode.scaledSize(forTier: tier, deviceScale: deviceScale)
        body.anchorPoint = RaccoonAnimationController.anchorPointNormalized
        body.zPosition = Self.bodyRelativeZ
        body.xScale = mapping.mirrored ? -1 : 1

        shadow = ActorShadowNode(width: RaccoonNode.shadowWidth(forTier: tier))
        shadow.zPosition = Self.shadowRelativeZ

        super.init()

        addChild(shadow)
        addChild(body)

        PixelCrispness.apply(to: body)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("RaccoonNode does not support NSCoder deserialization.")
    }

    /// The rendered size of a raccoon's body at `tier`'s scale factor,
    /// snapped to whole device pixels at `deviceScale`.
    ///
    /// The 1.6x elite scale is applied to `SKSpriteNode.size` directly
    /// (never to `xScale`/`yScale`), because `PixelCrispness.apply(to:)`
    /// floors scale *magnitude* to whole integers \u2014 1.6 would round away to
    /// 2 there, silently drawing an elite twice as large as the story calls
    /// for. Snapping goes through the existing
    /// `PixelCrispness.snappedPosition(for:scale:)` helper (treating
    /// `(width, height)` as an `(x, y)` pair) rather than a second, parallel
    /// rounding formula, so this and every other pixel-crisp consumer in the
    /// codebase agree on one snap rule.
    static func scaledSize(forTier tier: RaccoonTier, deviceScale: CGFloat) -> CGSize {
        let baseCellSize = RaccoonAnimationController.cellSize
        let rawSize = CGPoint(x: baseCellSize.width * tier.scale, y: baseCellSize.height * tier.scale)
        let snapped = PixelCrispness.snappedPosition(for: rawSize, scale: deviceScale)
        return CGSize(width: snapped.x, height: snapped.y)
    }

    /// The ground shadow's width for `tier`: the tier-scaled body's width,
    /// so an elite's shadow grows with its larger body rather than staying
    /// pinned to the base raccoon's footprint.
    static func shadowWidth(forTier tier: RaccoonTier) -> CGFloat {
        RaccoonAnimationController.cellSize.width * tier.scale
    }

    /// Sets the facing this raccoon shows. Thin forwarding to
    /// `animationController` so a later PR's seek behaviour can drive the
    /// node directly rather than reaching into its internals.
    func setDirection(_ direction: Direction8) {
        animationController.setDirection(direction)
    }

    /// Switches to the walk animation. See `RaccoonAnimationController.playWalk()`.
    func playWalk() {
        animationController.playWalk()
    }

    /// Switches to the attack animation. See `RaccoonAnimationController.playAttack()`.
    func playAttack() {
        animationController.playAttack()
    }

    /// Advances this raccoon's animation state by `deltaTime` and refreshes
    /// `body`'s texture/mirroring from the result. A later PR's per-frame
    /// update loop (the raccoon-swarm scene wiring) calls this once per
    /// frame, the same way `GameScene.update(_:)` drives
    /// `PlayerNode.update(deltaTime:movementVector:)`.
    func update(deltaTime: TimeInterval) {
        animationController.advance(deltaTime: deltaTime)

        let mapping = animationController.currentRowMapping
        let frameColumn = animationController.currentFrameColumn
        body.texture = RaccoonNode.texture(state: animationController.state, row: mapping.row, column: frameColumn)

        let magnitude = abs(body.xScale)
        body.xScale = mapping.mirrored ? -magnitude : magnitude
    }

    /// Updates this node's absolute `zPosition` for a raccoon standing at
    /// fractional tile-space `tilePosition`, via `DepthBanding
    /// .actorZPosition(forActorAt:offset:)` at `depthOffset` \u2014 inside
    /// `DepthBanding.nonPlayerActorOffsetRange`, so this raccoon can never
    /// tie with (let alone exceed) the player's own offset within the same
    /// band. Converted via `DepthModel.worldLayerRelativeZ(forAbsoluteZ:)`
    /// for a node parented directly under `GameScene.worldLayer`, the same
    /// convention `PlayerNode.updateDepth(atTilePosition:)` uses.
    func updateDepth(atTilePosition tilePosition: TilePoint) {
        let absoluteZ = DepthBanding.actorZPosition(forActorAt: tilePosition, offset: Self.depthOffset)
        zPosition = DepthModel.worldLayerRelativeZ(forAbsoluteZ: absoluteZ)
    }

    // MARK: - Texture slicing (cached, one cache per sheet)

    /// `sprite_raccoon_walk`'s measured sheet contract, resolved once \u2014 the
    /// same hoisted-off-the-hot-path reasoning `PlayerNode.cachedSheet`
    /// documents.
    private static let cachedWalkSheet: SpriteSheet = AtlasSheet.raccoonWalk.sheet

    /// `sprite_raccoon_attack`'s measured sheet contract, resolved once.
    private static let cachedAttackSheet: SpriteSheet = AtlasSheet.raccoonAttack.sheet

    /// Both sheets share the same grid (see `RaccoonAnimationController`'s
    /// doc comment), so one column count serves both caches' keys.
    private static let cachedColumns: Int = RaccoonNode.cachedWalkSheet.columns

    /// One `SKTexture` per `(row, column)` cell of `sprite_raccoon_walk`,
    /// sliced on first use and reused thereafter.
    private static var walkTextureCache: [Int: SKTexture] = [:]

    /// One `SKTexture` per `(row, column)` cell of `sprite_raccoon_attack`,
    /// sliced on first use and reused thereafter. Kept as a distinct cache
    /// from `walkTextureCache` \u2014 the two sheets are different images, so a
    /// shared cache keyed only on `(row, column)` would collide between
    /// them.
    private static var attackTextureCache: [Int: SKTexture] = [:]

    /// **Isolation:** as with `PlayerNode.textureCache`, these caches are
    /// mutable static state with no synchronization, and are safe only
    /// because every access happens on SpriteKit's main-thread update loop.
    ///
    /// Cuts (and caches) the `(row, column)` cell of whichever sheet `state`
    /// selects, as a nearest-filtered, mipmap-free `SKTexture`. Exposed (not
    /// private) so tests can compare a produced texture's identity against
    /// the exact cache this node's production path uses.
    static func texture(state: RaccoonAnimationState, row: Int, column: Int) -> SKTexture {
        let key = row * cachedColumns + column
        switch state {
        case .walk:
            if let cached = walkTextureCache[key] {
                return cached
            }
            let texture = cachedWalkSheet.texture(col: column, row: row)
            texture.filteringMode = .nearest
            texture.usesMipmaps = false
            walkTextureCache[key] = texture
            return texture
        case .attack:
            if let cached = attackTextureCache[key] {
                return cached
            }
            let texture = cachedAttackSheet.texture(col: column, row: row)
            texture.filteringMode = .nearest
            texture.usesMipmaps = false
            attackTextureCache[key] = texture
            return texture
        }
    }
}
