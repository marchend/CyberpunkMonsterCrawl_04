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
/// **Scale-to-radius: an ellipse on the 2:1 plane, not a square.**
/// `PulseAbility` measures its radius as a plain Euclidean distance in
/// *tile* space (`hypot(dx, dy)` on `TilePoint`), and
/// `IsometricProjection.tileToScreen` maps a tile delta to
/// `((dx - dy) * 48, (dx + dy) * 24)`. A tile-space circle of radius `R`
/// therefore projects to a screen-space **ellipse** with semi-axes
/// `sqrt(2) * tileHalfWidth * R` (~67.9R) horizontally and
/// `sqrt(2) * tileHalfHeight * R` (~33.9R) vertically -- not a circle of
/// radius `48R`. Scaling this node uniformly (as the first cut of this
/// type did) draws a `96R x 96R` square: ~29% too narrow on screen-x and
/// ~41% too tall on screen-y relative to the region the pulse actually
/// pushes, so a raccoon shoved along the screen-x diagonal comes to rest
/// *outside* the drawn ring while one directly above the player sits
/// inside a ring that never touched it (PR #48 review). `xScale(
/// forRadiusTiles:)` and `yScale(forRadiusTiles:)` are therefore derived
/// separately, from `tileHalfWidth` and `tileHalfHeight` respectively, so
/// the ring sits on the same 2:1 plane everything else in `worldLayer` is
/// drawn on.
///
/// Each axis divides by the ring's own **measured** extent inside its cell
/// (`AtlasPulseRingContent.widestFrameContentSize`, alpha-scanned off the
/// shipped `sprite_pulse.png` and re-measured by
/// `PulseRingArtMeasurementTests`) rather than by the 32px cell width:
/// scaling an `SKSpriteNode` scales the whole cell, so sizing against the
/// cell would draw the ring `cellSize / ringSize` times off, and nothing
/// in `AtlasSheet.pulse` pins where the opaque pixels sit inside a cell.
/// Both results are rounded to the nearest whole integer (floored at `1`)
/// -- the same magnitude-preserving rounding rule
/// `PixelCrispness.apply(to:)` enforces on every other actor/effect sprite
/// in this repo (`docs/bootstrap.md` section 1's "1x art only, integer
/// scaling") -- and both are restated as pure, directly-testable `static`
/// functions so `PulseRingNodeTests` can pin the scale-to-radius transform
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

    /// The screen-space **full width**, in points, of the ellipse a
    /// tile-space circle of radius `radiusTiles` projects to: twice the
    /// horizontal semi-axis `sqrt(2) * IsometricProjection.tileHalfWidth *
    /// radiusTiles` -- see the type's own doc comment for the derivation.
    static func projectedWidthPoints(forRadiusTiles radiusTiles: Double) -> CGFloat {
        CGFloat(2 * 2.0.squareRoot() * IsometricProjection.tileHalfWidth * max(0, radiusTiles))
    }

    /// The screen-space **full height**, in points, of that same ellipse:
    /// twice the vertical semi-axis `sqrt(2) *
    /// IsometricProjection.tileHalfHeight * radiusTiles`, i.e. exactly half
    /// `projectedWidthPoints(forRadiusTiles:)` -- the 2:1 plane.
    static func projectedHeightPoints(forRadiusTiles radiusTiles: Double) -> CGFloat {
        CGFloat(2 * 2.0.squareRoot() * IsometricProjection.tileHalfHeight * max(0, radiusTiles))
    }

    /// The whole-integer-friendly `xScale` this node must carry for its
    /// drawn ring to span the projected ellipse's full width:
    /// `projectedWidthPoints(forRadiusTiles:)` divided by the ring's own
    /// measured pixel width inside its cell
    /// (`AtlasPulseRingContent.widestFrameContentSize.width`), rounded to
    /// the nearest whole integer and floored at `1` -- see the type's own
    /// doc comment for why the measured ring, not the 32px cell, is the
    /// divisor, and for why this mirrors `PixelCrispness.apply(to:)`'s
    /// rounding rule rather than leaving a fractional scale that would
    /// resample the nearest-filtered art.
    ///
    /// A non-positive `radiusTiles` (never produced by
    /// `PulseAbility.trigger(...)`, but this is a pure function total over
    /// its input) floors to the same `1` a real but tiny radius would.
    static func xScale(forRadiusTiles radiusTiles: Double) -> CGFloat {
        let ringWidth = AtlasPulseRingContent.widestFrameContentSize.width
        guard ringWidth > 0 else { return 1 }
        return max(1, (projectedWidthPoints(forRadiusTiles: radiusTiles) / ringWidth).rounded())
    }

    /// The `yScale` sibling of `xScale(forRadiusTiles:)`, derived from
    /// `IsometricProjection.tileHalfHeight` and the ring's measured pixel
    /// *height* -- half the horizontal extent before rounding, so the ring
    /// lands on the same 2:1 isometric plane as everything else in
    /// `worldLayer`.
    static func yScale(forRadiusTiles radiusTiles: Double) -> CGFloat {
        let ringHeight = AtlasPulseRingContent.widestFrameContentSize.height
        guard ringHeight > 0 else { return 1 }
        return max(1, (projectedHeightPoints(forRadiusTiles: radiusTiles) / ringHeight).rounded())
    }

    // MARK: - Play

    /// Repositions this node at `position` (already in the parent's own
    /// coordinate space -- `GameScene` converts the player's world-space
    /// point into `effectsLayer`'s space before calling this, the same
    /// "Coordinate space" convention `Player` documents for its own
    /// bullets/flashes/puffs), scales it to `radiusTiles` per axis
    /// (`xScale(forRadiusTiles:)` / `yScale(forRadiusTiles:)` -- never one
    /// uniform scale, see the type's own "Scale-to-radius" doc note), and
    /// (re)plays the 8-frame shockwave animation from frame 0.
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
        // Per-axis, never a single uniform scale: the pushed region is a
        // tile-space circle, which projects to a 2:1 ellipse on screen
        // (see the type's own "Scale-to-radius" doc note).
        xScale = Self.xScale(forRadiusTiles: radiusTiles)
        yScale = Self.yScale(forRadiusTiles: radiusTiles)
        PixelCrispness.apply(to: self)
        isHidden = false

        let frames = (0..<AtlasCellIndex.pulse.count).map { Self.texture(forColumn: $0) }
        let animate = SKAction.animate(with: frames, timePerFrame: Self.frameDuration, resize: false, restore: false)
        let hide = SKAction.run { [weak self] in self?.isHidden = true }
        run(SKAction.sequence([animate, hide]), withKey: Self.animationActionKey)
    }
}
