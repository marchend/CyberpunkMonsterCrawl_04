import CoreGraphics
import SpriteKit

/// One bullet's SpriteKit presence: an `SKSpriteNode` textured from
/// `sprite_bullets.png` (48x16px, 3 x 16x16 cells -- 0 slug, 1 SMG tracer,
/// 2 rifle round) indexed by `WeaponTier.bulletSheetColumn`, rotated to the
/// shot vector (`CYBERPUN-17-9` PR 2).
///
/// **Authored orientation.** The art points screen-right (positive x) at
/// `zRotation == 0`. `angle(forShotVector:)` computes `atan2(dy, dx)` in
/// SpriteKit's own y-up, zero-at-east, counter-clockwise-positive rotation
/// convention -- the exact angle a screen-right-authored sprite must be
/// rotated by to point along `vector`. A shot fired due screen-left
/// (`CGVector(dx: -1, dy: 0)`) therefore resolves to `.pi` (180 degrees)
/// from the authored pose, per the story's own AC5 wording.
///
/// **Scope of this PR.** Node/texture/rotation only -- `BulletPool` (this
/// same PR) owns lifecycle (acquire/release, visibility). Nothing here
/// decides when a bullet is fired or what it hits; both are a later
/// scene-wiring PR's job, the same deferral `WeaponFiringController`'s own
/// doc comment already documents for this story.
final class BulletNode: SKSpriteNode {

    /// `sprite_bullets`'s measured sheet contract, resolved once -- the
    /// same hoisted-off-the-hot-path reasoning `PlayerNode.cachedSheet` /
    /// `RaccoonNode.cachedWalkSheet` document.
    private static let cachedSheet: SpriteSheet = AtlasSheet.bullets.sheet
    private static var textureCache: [Int: SKTexture] = [:]

    /// This bullet's cell size -- read straight off the atlas contract, no
    /// fallback literal (the same "no second copy of the numbers"
    /// discipline `PlayerSpriteSheet.cellSize` documents).
    private static var cellSize: CGSize {
        guard let cellSize = cachedSheet.cellSize else {
            preconditionFailure(
                "AtlasSheet.bullets declares no cellSize; BulletNode has no cell geometry to read."
            )
        }
        return cellSize
    }

    /// Cuts (and caches) `tier`'s bullet-variant column as a
    /// nearest-filtered, mipmap-free `SKTexture`.
    static func texture(forTier tier: WeaponTier) -> SKTexture {
        let column = tier.bulletSheetColumn
        if let cached = textureCache[column] {
            return cached
        }
        let texture = cachedSheet.texture(col: column, row: 0)
        texture.filteringMode = .nearest
        texture.usesMipmaps = false
        textureCache[column] = texture
        return texture
    }

    /// `atan2(dy, dx)` in SpriteKit's own rotation convention -- see the
    /// type's own doc comment. A zero vector carries no heading, so it
    /// resolves to `0` (no rotation) rather than an undefined
    /// `atan2(0, 0)` result.
    static func angle(forShotVector vector: CGVector) -> CGFloat {
        guard vector.dx != 0 || vector.dy != 0 else { return 0 }
        return atan2(vector.dy, vector.dx)
    }

    /// This node's current bullet variant -- set at construction, updated
    /// only by `configure(tier:position:shotVector:)` (`BulletPool`'s
    /// re-use path).
    private(set) var tier: WeaponTier

    init(tier: WeaponTier) {
        self.tier = tier
        super.init(texture: Self.texture(forTier: tier), color: .clear, size: Self.cellSize)
        PixelCrispness.apply(to: self)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("BulletNode does not support NSCoder deserialization.")
    }

    /// Reconfigures this (possibly pool-reused) node in place for a fresh
    /// shot: retextures to `tier`'s bullet variant, moves to `position`
    /// (whatever coordinate space the caller's parent node uses), and sets
    /// `zRotation` from `angle(forShotVector:)`. Never touches `size` --
    /// every tier's bullet shares the same measured 16x16 cell.
    func configure(tier: WeaponTier, position: CGPoint, shotVector: CGVector) {
        self.tier = tier
        texture = Self.texture(forTier: tier)
        self.position = position
        zRotation = Self.angle(forShotVector: shotVector)
    }
}
