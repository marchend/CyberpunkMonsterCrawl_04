import CoreGraphics
import SpriteKit

/// Builds and owns the player's weapon-overlay `SKSpriteNode`, composited
/// on the SAME 36x40 cell and anchor as the body sprite
/// (`sprite_player_weapons.png`, `AtlasSheet.playerWeapons`: 288x120px,
/// 8 columns = directions, 3 rows = tiers -- `weapon[tier][dir]`,
/// `CYBERPUN-17-9` PR 2).
///
/// **Scope of this PR.** Rendering only: slices the sheet, parents the
/// overlay to the body node it is handed at construction so it shares that
/// node's lifecycle, and exposes `update(tier:direction:)` to swap the
/// visible texture in place. Nothing here decides *when* tier or direction
/// change -- that is `WeaponFiringController`/level-driven tier
/// progression (PR 1) and the later scene-wiring PR that is expected to
/// hold one of these per mounted `PlayerNode` and drive it from the body's
/// own facing/tier each frame, the same "logic/rendering first, mount
/// later" split this codebase already follows for
/// `ChunkStreamingManager`/`GroundPlaneStreamer` and
/// `RaccoonSpawnDirector`/`RaccoonNode`.
///
/// **Column ordering.** `sprite_player_weapons` authors real art for every
/// one of its 8 columns -- unlike `sprite_player_walk`, which authors only
/// 5 rows directly and mirrors the rest (`PlayerSpriteSheet
/// .rowMappingTable`) -- so there is no measured mirror pairing to re-derive
/// here the way `PlayerSpriteSheetTests` does for the walk sheet. Columns
/// follow `Direction8.allCases`'s own declared order (south, southeast,
/// east, northeast, north, northwest, west, southwest): a naming convention
/// this file and `WeaponOverlayRendererTests` pin together, not a fact
/// re-derived from the shipped art (there is nothing to measure -- every
/// column is real, unmirrored art).
///
/// **Same cell, same anchor.** `overlay.size`/`overlay.anchorPoint` are
/// copied from `body` once, at construction, and never re-derived per
/// update -- "one extra draw call, no new body art" holds as long as the
/// body's own size/anchor stay fixed for its lifetime, which they do today
/// (`PlayerNode.body`'s size/anchorPoint never change after `init`).
///
/// **Mirrored facings.** `PlayerNode.update` mirrors `body.xScale` to `-1`
/// for the three facings `PlayerSpriteSheet` produces by flipping a
/// directly-authored row (southwest/west/northwest) rather than by
/// authoring new art. Because `overlay` is a *child* of `body`, it would
/// inherit that flip -- but `sprite_player_weapons` has real, unmirrored
/// art for those same three directions, so a double negative would render
/// backwards weapon art. `update(tier:direction:)` reads the body's
/// *current* `xScale` sign each call and sets `overlay.xScale` to match it,
/// canceling the inherited flip back out to a net, always-unmirrored `+1`.
final class WeaponOverlayRenderer {

    /// The live overlay node, parented as a child of `body` at
    /// construction and never reparented.
    let overlay: SKSpriteNode

    private static let cachedSheet: SpriteSheet = AtlasSheet.playerWeapons.sheet
    private static var textureCache: [Int: SKTexture] = [:]

    /// Small positive offset above the body's own relative zPosition so the
    /// weapon draws in front of the body it's a child of -- well inside a
    /// single actor's z slice, the same convention `PlayerNode`'s own
    /// `bodyRelativeZ`/`shadowRelativeZ` constants document.
    private static let overlayRelativeZ: CGFloat = 0.01

    /// The tier/direction currently shown -- set at construction, updated
    /// only by `update(tier:direction:)`.
    private(set) var tier: WeaponTier
    private(set) var direction: Direction8

    /// Weak so this type never keeps the body sprite alive on its own --
    /// the overlay is already a *child* of `body`, so `body`'s own strong
    /// reference (its `PlayerNode` owner) is what keeps both alive.
    private weak var body: SKSpriteNode?

    /// - Parameters:
    ///   - body: the player's body sprite. The overlay is added as its
    ///     child, sized and anchored identically, and left at `position ==
    ///     .zero` so it exactly overlays the body's current cell.
    ///   - tier: initial weapon tier shown.
    ///   - direction: initial facing shown.
    init(body: SKSpriteNode, tier: WeaponTier, direction: Direction8) {
        self.body = body
        self.tier = tier
        self.direction = direction

        overlay = SKSpriteNode(texture: Self.texture(tier: tier, direction: direction))
        overlay.size = body.size
        overlay.anchorPoint = body.anchorPoint
        overlay.zPosition = Self.overlayRelativeZ

        body.addChild(overlay)
        PixelCrispness.apply(to: overlay)
        overlay.xScale = body.xScale < 0 ? -1 : 1
    }

    /// Swaps the visible texture for `tier`/`direction`, without touching
    /// `overlay.size`/`anchorPoint` (per the "same cell, same anchor"
    /// contract) beyond the mirror-cancellation described on the type's own
    /// doc comment.
    func update(tier: WeaponTier, direction: Direction8) {
        self.tier = tier
        self.direction = direction
        overlay.texture = Self.texture(tier: tier, direction: direction)
        if let body = body {
            overlay.xScale = body.xScale < 0 ? -1 : 1
        }
    }

    /// This direction's column within `AtlasSheet.playerWeapons`'s 8-column
    /// grid -- `Direction8.allCases`'s own declared index, per this type's
    /// "column ordering" doc comment.
    static func column(for direction: Direction8) -> Int {
        guard let index = Direction8.allCases.firstIndex(of: direction) else {
            preconditionFailure("Direction8.allCases must contain every case, including \(direction).")
        }
        return index
    }

    /// Cuts (and caches) the `[tier][direction]` cell of `sprite_player_weapons`
    /// as a nearest-filtered, mipmap-free `SKTexture`.
    static func texture(tier: WeaponTier, direction: Direction8) -> SKTexture {
        let col = column(for: direction)
        let row = tier.weaponSheetRow
        let key = row * cachedSheet.columns + col
        if let cached = textureCache[key] {
            return cached
        }
        let texture = cachedSheet.texture(col: col, row: row)
        texture.filteringMode = .nearest
        texture.usesMipmaps = false
        textureCache[key] = texture
        return texture
    }
}
