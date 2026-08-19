import CoreGraphics
import SpriteKit

/// The player-triggered pulse ability's ring visual (`CYBERPUN-17-10-t3`):
/// an `SKSpriteNode` wrapping the 8-frame `sprite_pulse` shockwave
/// animation (measured 256x32px, 8 x 32x32 cells, single row --
/// `AtlasSheet.pulse`), scaled to `PulseAbility`'s current radius and
/// centered on the player.
///
/// **Scope of this PR.** Node construction/animation/scale-to-radius/
/// zPosition only. `GameScene` (this same PR) is the production caller: it
/// mounts a single instance directly under `effectsLayer` in
/// `commonInit()` and calls `play(radiusTiles:at:)` from
/// `applyPulseTrigger(raccoons:)` on every accepted `PulseAbility.trigger(...)`,
/// feeding it `PulseAbility.Result.radius` and the player's screen
/// position (already converted into `effectsLayer`'s own space -- see
/// that method's own coordinate-space note).
///
/// **One reused instance, not a pool.** Unlike `BulletPool` (many bullets
/// can be simultaneously in flight), there is exactly one pulse ability
/// per player, gated by its own multi-second cooldown
/// (`PulseAbility.cooldownSeconds`), so at most one ring animation is ever
/// playing at a time. `GameScene` therefore mounts a single
/// `PulseRingNode` once and calls `play(radiusTiles:at:)` again on every
/// subsequent trigger -- repositioning/rescaling it and restarting the
/// animation from frame 0 -- rather than allocating a fresh node (or a
/// pool of them) per press.
///
/// **Scale-to-radius, whole-integer-friendly.** `scale(forRadiusTiles:)`
/// converts a tile-space radius into a screen-space *diameter*, in points,
/// using `IsometricProjection.tileHalfWidth` (48pt per tile-radius on the
/// screen-x axis -- the same constant every other world-to-screen
/// conversion in this codebase is built on), divides by the ring's fixed
/// 32px cell width, and rounds the result to the nearest whole integer
/// (floored at `1`). That is the same magnitude-preserving rounding rule
/// `PixelCrispness.apply(to:)` enforces on every other actor/effect sprite
/// in this repo (`docs/bootstrap.md` section 1's "1x art only, integer
/// scaling"), restated here as a pure, directly-testable `static` function
/// so `PulseRingNodeTests` can pin the scale-to-radius transform
/// independent of constructing (and animating) a live node.
/// `play(radiusTiles:at:)` still finishes with `PixelCrispness.apply(to:)`
/// for the texture-filtering and whole-point-position half of that same
/// contract.
///
/// **zPosition: a reserved sub-range, not a per-frame comparison.** This
/// node is parented directly under `GameScene.effectsLayer` -- the same
/// convention `HitEffects`' muzzle-flash/hit-puff nodes use for transient
/// combat visuals -- and carries a fixed **relative** `zPosition` (added
/// on top of `effectsLayer`'s own `LayerConstants.effectsLayerZ` once
/// SpriteKit accumulates zPosition down the tree) drawn from
/// `PulseRingNode.zPositionRange`, a small sub-range reserved for this
/// node's own use. `effectsLayer`'s zPosition already sits at
/// `LayerConstants.effectsMinZ` -- the bottom of `effectsBand` -- so this
/// node's *cumulative* zPosition (`effectsLayerZ + relativeZPosition`)
/// stays inside `effectsBand` for the whole of `zPositionRange`, exactly
/// the way `HitEffects`' own nodes (relative zPosition `0`) already do.
/// Structurally, *any* value inside `effectsBand` already sits strictly
/// above `LayerConstants.worldMaxZ` (the world/ground layer's own ceiling)
/// and strictly below `LayerConstants.uiMinZ` (the UI layer's floor) --
/// `LayerOrderingTests` pins that containment for the three layers
/// themselves. So a ring mounted under `effectsLayer` with a relative
/// zPosition drawn from this reserved sub-range can never paint over the
/// UI or fall beneath the ground plane by construction, with no per-frame
/// band check of its own -- exactly the "structurally guaranteed" property
/// this story's acceptance criteria call for.
final class PulseRingNode: SKSpriteNode {

    // MARK: - Texture slicing (cached)

    /// `sprite_pulse`'s measured sheet contract, resolved once -- the same
    /// hoisted-off-the-hot-path reasoning `PlayerNode.cachedSheet` /
    /// `RaccoonNode.cachedWalkSheet` document.
    private static let cachedSheet: SpriteSheet = AtlasSheet.pulse.sheet
    private static var textureCache: [Int: SKTexture] = [:]

    private static var cellSize: CGSize {
        guard let cellSize = cachedSheet.cellSize else {
            preconditionFailure(
                "AtlasSheet.pulse declares no cellSize; PulseRingNode has no cell geometry to read."
            )
        }
        return cellSize
    }

    /// Cuts (and caches) one `sprite_pulse` column as a nearest-filtered,
    /// mipmap-free `SKTexture`.
    static func texture(forColumn column: Int) -> SKTexture {
        if let cached = textureCache[column] {
            return cached
        }
        let texture = cachedSheet.texture(col: column, row: 0)
        texture.filteringMode = .nearest
        texture.usesMipmaps = false
        textureCache[column] = texture
        return texture
    }

    // MARK: - Animation

    /// One full 8-frame play-through takes `8 * frameDuration` seconds --
    /// a brisk outward shockwave rather than a lingering one. An initial
    /// tuning constant, like every other per-effect timing value in this
    /// codebase (`HitEffects.hitPuffFrameDuration`, `PickupNode.bobDuration`),
    /// expected to move in a later playtesting pass.
    static let frameDuration: TimeInterval = 0.03

    /// The action key `play(radiusTiles:at:)` runs its animation under, so
    /// a caller (or test) can look it up by name instead of guessing
    /// whether one was applied -- the same convention
    /// `HitEffects.hitPuffAnimationActionKey` follows.
    static let animationActionKey = "pulseRingAnimation"

    // MARK: - zPosition

    /// A reserved **relative** zPosition sub-range for `PulseRingNode`,
    /// added on top of `effectsLayer`'s own `LayerConstants.effectsLayerZ`
    /// once mounted -- see the type's own doc comment for why the
    /// resulting *cumulative* zPosition is structurally guaranteed to sit
    /// above the world/ground layer's band and below the UI layer's band.
    /// Comfortably inside `effectsLayer`'s own band width (`effectsMinZ
    /// ... effectsMaxZ` spans nearly 2,000 units), so this reservation
    /// leaves ample room for other `effectsLayer` consumers (bullets, hit
    /// puffs) to use their own relative offsets without collision.
    static let zPositionRange: ClosedRange<CGFloat> = 0...9

    /// The single fixed relative `zPosition` every instance uses: a
    /// specific point drawn from `zPositionRange` rather than the whole
    /// range, since only one ring is ever mounted/active at a time (see
    /// the type's own "One reused instance" doc note).
    static let relativeZPosition: CGFloat = zPositionRange.lowerBound

    // MARK: - Init

    init() {
        super.init(texture: Self.texture(forColumn: 0), color: .clear, size: Self.cellSize)
        zPosition = Self.relativeZPosition
        // Hidden until the first `play(radiusTiles:at:)` call -- this is a
        // single reused instance mounted once at scene-construction time
        // (see the type's own "One reused instance" doc note), not
        // something that should be visible before the ability has ever
        // fired.
        isHidden = true
        PixelCrispness.apply(to: self)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("PulseRingNode does not support NSCoder deserialization.")
    }

    // MARK: - Scale-to-radius

    /// The whole-integer-friendly `xScale`/`yScale` magnitude this node
    /// must carry for its fixed 32pt-wide texture to visually span
    /// `radiusTiles` tile-units from its center in every direction: the
    /// screen-space diameter (`2 * radiusTiles *
    /// IsometricProjection.tileHalfWidth`) divided by the cell's own
    /// width, rounded to the nearest whole integer and floored at `1` --
    /// see the type's own doc comment for why this mirrors
    /// `PixelCrispness.apply(to:)`'s rounding rule rather than leaving a
    /// fractional scale that would resample the nearest-filtered art.
    ///
    /// A non-positive `radiusTiles` (never produced by
    /// `PulseAbility.trigger(...)`, but this is a pure function total over
    /// its input) floors to the same `1` a real but tiny radius would.
    static func scale(forRadiusTiles radiusTiles: Double) -> CGFloat {
        let diameterPoints = CGFloat(max(0, radiusTiles) * 2 * IsometricProjection.tileHalfWidth)
        let rawScale = diameterPoints / cellSize.width
        return max(1, rawScale.rounded())
    }

    // MARK: - Play

    /// Repositions this node at `position` (already in the parent's own
    /// coordinate space -- `GameScene` converts the player's world-space
    /// point into `effectsLayer`'s space before calling this, the same
    /// "Coordinate space" convention `Player` documents for its own
    /// bullets/flashes/puffs), scales it to `radiusTiles`
    /// (`scale(forRadiusTiles:)`), and (re)plays the 8-frame shockwave
    /// animation from frame 0.
    ///
    /// Unhides the node for the animation's duration and hides it again on
    /// completion, rather than removing it from the scene graph -- this is
    /// a single reused instance (see the type's own "One reused instance"
    /// doc note), not a pooled/disposable node the way `HitEffects`' hit
    /// puff is.
    func play(radiusTiles: Double, at position: CGPoint) {
        removeAction(forKey: Self.animationActionKey)

        self.position = position
        texture = Self.texture(forColumn: 0)
        let scale = Self.scale(forRadiusTiles: radiusTiles)
        xScale = scale
        yScale = scale
        PixelCrispness.apply(to: self)
        isHidden = false

        let frames = (0..<AtlasCellIndex.pulse.count).map { Self.texture(forColumn: $0) }
        let animate = SKAction.animate(with: frames, timePerFrame: Self.frameDuration, resize: false, restore: false)
        let hide = SKAction.run { [weak self] in self?.isHidden = true }
        run(SKAction.sequence([animate, hide]), withKey: Self.animationActionKey)
    }
}
