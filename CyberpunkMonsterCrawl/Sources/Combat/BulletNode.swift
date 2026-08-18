import CoreGraphics
import SpriteKit

/// One bullet's SpriteKit presence: an `SKSpriteNode` textured from
/// `sprite_bullets.png` (48x16px, 3 x 16x16 cells -- 0 slug, 1 SMG tracer,
/// 2 rifle round) indexed by `WeaponTier.bulletSheetColumn`, rotated to the
/// shot vector (`CYBERPUN-17-9` PR 2).
///
/// **Authored orientation.** The art points screen-right (positive x) at
/// `zRotation == 0`. `angle(forSpriteKitShotVector:)` computes
/// `atan2(dy, dx)` in SpriteKit's own y-up, zero-at-east,
/// counter-clockwise-positive rotation convention -- the exact angle a
/// screen-right-authored sprite must be rotated by to point along the
/// vector. A shot fired due screen-left (`CGVector(dx: -1, dy: 0)`)
/// therefore resolves to `.pi` (180 degrees) from the authored pose, per
/// the story's own AC5 wording.
///
/// **Which space a shot vector is in, named in the signature.** The
/// `atan2` above is only the right rotation for a **y-up** (SpriteKit)
/// vector, while the thing that decides a shot -- `WeaponFiringController
/// .onFire` -- hands out a `TargetSelection.Candidate` plus a `TilePoint`
/// origin, i.e. *tile* space, and `Direction8` documents the asset/pixel
/// side of this codebase as y-**down**. Leaving an unlabelled `CGVector`
/// seam for the mount PR is exactly the unenforced convention
/// `Direction8.from(spriteKitVector:)` exists to remove ("the flip lives
/// here, once, where a call site cannot skip it"), and forgetting it is
/// silent in the same way: east/west stay correct while north/south flip,
/// so bullets read as an art bug rather than a math bug. So the space is in
/// the argument label (`forSpriteKitShotVector:`,
/// `configure(tier:position:spriteKitShotVector:)`), and a tile-space
/// caller gets `angle(fromTileOrigin:toTileTarget:)`, which owns the
/// tile -> screen conversion itself via `IsometricProjection.tileToScreen`
/// rather than asking the call site to remember it.
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

    /// `atan2(dy, dx)` for a **SpriteKit-space** (y-up) shot vector -- see
    /// the type's own doc comment for why the space is in the label. A zero
    /// vector carries no heading, so it resolves to `0` (no rotation) rather
    /// than an undefined `atan2(0, 0)` result.
    ///
    /// A caller holding a *tile-space* delta (every consumer of
    /// `WeaponFiringController.onFire` does) must not call this directly:
    /// `angle(fromTileOrigin:toTileTarget:)` below owns the conversion.
    static func angle(forSpriteKitShotVector vector: CGVector) -> CGFloat {
        guard vector.dx != 0 || vector.dy != 0 else { return 0 }
        return atan2(vector.dy, vector.dx)
    }

    /// The rotation for a shot fired from tile `origin` at tile `target`.
    ///
    /// Owns the tile -> screen conversion so no call site has to: the
    /// tile-space delta is pushed through the same linear forward transform
    /// `IsometricProjection.tileToScreen` applies to a point (valid for a
    /// delta because that transform has no translation term -- the identical
    /// reasoning `RaccoonSeekBehavior.screenVector(forTileDelta:)`
    /// documents), and the resulting SpriteKit-space vector is handed to
    /// `angle(forSpriteKitShotVector:)`.
    ///
    /// This is the seam the mount PR should use: on a 2:1 isometric lattice
    /// a raw tile delta is not merely y-flipped relative to screen space, it
    /// is *sheared*, so `atan2` over tile components is wrong for every
    /// direction that is not axis-aligned on screen -- not just for
    /// north/south. `origin == target` carries no heading and resolves to
    /// `0`, matching `angle(forSpriteKitShotVector:)`'s zero-vector
    /// contract.
    static func angle(fromTileOrigin origin: TilePoint, toTileTarget target: TilePoint) -> CGFloat {
        let screenDelta = IsometricProjection.tileToScreen(
            tileX: target.x - origin.x,
            tileY: target.y - origin.y
        )
        return angle(forSpriteKitShotVector: CGVector(dx: screenDelta.x, dy: screenDelta.y))
    }

    /// This node's current bullet variant -- set at construction, updated
    /// only by `configure(tier:position:spriteKitShotVector:)`
    /// (`BulletPool`'s re-use path).
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
    /// `zRotation` from `angle(forSpriteKitShotVector:)`. Never touches
    /// `size` -- every tier's bullet shares the same measured 16x16 cell.
    ///
    /// `spriteKitShotVector` names its own space, per the type's doc
    /// comment: a tile-space caller converts through
    /// `angle(fromTileOrigin:toTileTarget:)` rather than passing a raw tile
    /// delta here.
    func configure(tier: WeaponTier, position: CGPoint, spriteKitShotVector: CGVector) {
        self.tier = tier
        texture = Self.texture(forTier: tier)
        self.position = position
        zRotation = Self.angle(forSpriteKitShotVector: spriteKitShotVector)
    }
}
