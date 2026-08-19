import CoreGraphics
import SpriteKit

/// Muzzle-flash and hit-puff visual helpers built from `sprite_hit_puff.png`
/// (96x24px, 4 x 24x24 cells) -- frame 0 doubles as the muzzle flash single
/// frame, per `AtlasSheet.hitPuff`'s own measured-geometry comment
/// (`CYBERPUN-17-9` PR 2).
///
/// **Scope of this PR.** Node construction only. Who calls
/// `spawnMuzzleFlash`/`spawnHitPuff`, where the returned node gets mounted,
/// and the barrel-tip/impact-point geometry that produces the `position`
/// each takes is the later scene-wiring PR's job -- the same
/// "logic/rendering first, mount later" split this codebase already
/// follows for `ChunkStreamingManager`/`GroundPlaneStreamer` and
/// `RaccoonSpawnDirector`/`RaccoonNode`.
///
/// **No barrel-tip offset table lives here.** `WeaponTier`'s own doc
/// comment explains why: an earlier revision carried a per-direction
/// `barrelTipOffset` table derived from the weapon cell's *centre*, which
/// is wrong against this codebase's bottom-centre actor anchor, and was
/// removed rather than shipped wrong. `spawnMuzzleFlash(at:)` therefore
/// takes the already-resolved muzzle **position** directly rather than
/// re-deriving one from a still-nonexistent offset table, so this file does
/// not itself invent the missing numbers.
///
/// **Where that deferral now stands.** It used to point at "the PR that
/// mounts `sprite_player_weapons` for real"; that PR
/// (`CYBERPUN-17-9` PR 3, `Player`) has landed and composites the overlay
/// onto `PlayerNode.body`, but it did **not** measure the muzzle pixel off
/// the shipped art, so the one production caller
/// (`Player.handleFire(target:origin:tier:)`) passes the player's
/// bottom-centre actor anchor -- his feet -- as the flash position. That
/// open AC6 gap is recorded at that call site and in `Player`'s own
/// "Known gap" doc section rather than left as a forward reference here to
/// a PR that already merged.
enum HitEffects {

    /// One full play-through of the animation, in seconds -- 4 frames at a
    /// brisk clip so the puff/flash reads as an instant. An initial tuning
    /// constant, like every other per-effect timing value in this
    /// codebase, expected to move in a later playtesting pass.
    static let hitPuffFrameDuration: TimeInterval = 0.05

    /// The action key `spawnHitPuff` runs its animation under, so a caller
    /// (or test) can look it up by name instead of guessing whether one was
    /// applied.
    static let hitPuffAnimationActionKey = "hitPuffAnimation"

    /// `sprite_hit_puff`'s measured sheet contract, resolved once -- the
    /// same hoisted-off-the-hot-path reasoning `PlayerNode.cachedSheet` /
    /// `RaccoonNode.cachedWalkSheet` document.
    private static let cachedSheet: SpriteSheet = AtlasSheet.hitPuff.sheet
    private static var textureCache: [Int: SKTexture] = [:]

    private static var cellSize: CGSize {
        guard let cellSize = cachedSheet.cellSize else {
            preconditionFailure(
                "AtlasSheet.hitPuff declares no cellSize; HitEffects has no cell geometry to read."
            )
        }
        return cellSize
    }

    /// Cuts (and caches) one `sprite_hit_puff` column as a nearest-filtered,
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

    /// A single-frame muzzle flash: `sprite_hit_puff` frame 0 only, per the
    /// story's "muzzle flash = the first `sprite_hit_puff` frame" note --
    /// positioned at the caller-resolved barrel-tip `position` and left
    /// with no animation or removal action of its own, since a muzzle
    /// flash's on-screen lifetime (how long it's shown before the caller
    /// removes it) is a scene-wiring decision this PR does not make.
    static func spawnMuzzleFlash(at position: CGPoint) -> SKSpriteNode {
        let node = SKSpriteNode(texture: texture(forColumn: 0))
        node.size = cellSize
        node.position = position
        PixelCrispness.apply(to: node)
        return node
    }

    /// The full `sprite_hit_puff` animation (all `AtlasCellIndex.hitPuff`
    /// columns, in sheet order), positioned at the resolved impact point.
    /// Runs once and calls `removeFromParent()` on completion -- a caller
    /// must still `addChild` this node somewhere (and keep it there across
    /// frames) for the action to ever run or be visible.
    static func spawnHitPuff(at position: CGPoint) -> SKSpriteNode {
        let node = SKSpriteNode(texture: texture(forColumn: 0))
        node.size = cellSize
        node.position = position
        PixelCrispness.apply(to: node)

        let frames = (0..<AtlasCellIndex.hitPuff.count).map { texture(forColumn: $0) }
        let animate = SKAction.animate(with: frames, timePerFrame: hitPuffFrameDuration, resize: false, restore: false)
        node.run(SKAction.sequence([animate, SKAction.removeFromParent()]), withKey: hitPuffAnimationActionKey)
        return node
    }
}
