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
/// **Column ordering.** Columns follow `Direction8.allCases`'s own declared
/// order (south, southeast, east, northeast, north, northwest, west,
/// southwest).
///
/// **Every column carries its own art -- measured, and not what PR 2 first
/// claimed.** `AtlasSheet.playerWeapons` pins only the grid (288x120 /
/// 36x40 -- *that* there are 8 columns, never what is in them), so what the
/// columns hold is a claim about the shipped PNG and is re-decoded from the
/// pixels at test time, the way `PlayerSpriteSheetTests`,
/// `AtlasGroundDiamondTests` and `RooftopSignSpriteAlignmentTests` already
/// do for their sheets. Two measurements, in `WeaponOverlayRendererTests`:
///
/// - `.test_everyWeaponCell_carriesAuthoredArt_andNoWestColumnIsAnUnflippedCopyOfItsEast`
///   -- every one of the 24 cells holds at least one opaque pixel (an empty
///   column would draw an invisible gun for that facing/tier), and no west
///   column is an unflipped copy of its east counterpart (which would draw
///   an east-pointing gun on a west-facing body).
/// - `.test_theWestColumns_areHorizontalFlipsOfTheirEastCounterparts` --
///   for every tier row, columns 5/6/7 (northwest/west/southwest) measure as
///   the **horizontal flips** of columns 3/2/1 (northeast/east/southeast).
///
/// That second result is the correction: this file originally stated, by
/// convention rather than measurement, that all 8 columns were "real,
/// unmirrored art" and that there was "nothing to measure". The sheet is in
/// fact mirror-authored, the same way `sprite_player_walk` is
/// (`PlayerSpriteSheet.rowMappingTable`). It renders correctly anyway --
/// each west column already holds a west-posed gun, so the overlay must
/// draw it *unflipped*, which is exactly what the flip-cancellation below
/// produces -- but the reason stated here is now the measured one.
/// `test_everyTierDirectionPair_resolvesADistinctTexture` could never have
/// seen any of this: it compares `ObjectIdentifier`s of distinct `SKTexture`
/// crops, which differ whether or not the pixels underneath are empty or
/// duplicated.
///
/// What the scan deliberately does *not* claim: which column is which
/// compass facing. No pixel measurement can settle "column 3 is
/// northeast" -- that stays a naming convention this file and
/// `WeaponOverlayRendererTests` pin together, and the scan's job is to rule
/// out the two failure modes that convention cannot detect.
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
/// inherit that flip -- and `sprite_player_weapons` ships each of those three
/// columns already posed for its own facing (measured: they are the
/// horizontal flips of their east counterparts, see above), so inheriting
/// the body's `-1` would flip a west-posed gun back to pointing east on a
/// west-facing body. `overlay.xScale` therefore cancels the inherited flip
/// back out to a net, always-unmirrored `+1`, drawing every column exactly
/// as authored.
///
/// **Where that cancellation's sign comes from.** From
/// `PlayerSpriteSheet.xScale(for:)` -- the accessor on `rowMappingTable`,
/// the documented *single owning* `Direction8 -> (row, mirrored)` table --
/// applied to the `direction` this type is handed, **not** read back off
/// `body.xScale`'s sign. Same value either way, but sourcing it from the
/// table removes a frame-ordering dependency:
/// `PlayerNode.update(deltaTime:movementVector:)` is what writes
/// `body.xScale`, so a scene-wiring caller that drives this renderer before
/// the body -- or that changes facing without a movement vector, since
/// `PlayerNode` keeps `facing` across `.zero` vectors -- would otherwise get
/// one frame of overlay flipped against the texture it is showing. Since
/// both `init` and `update(tier:direction:)` already take `direction`
/// explicitly, the table's answer is self-consistent regardless of call
/// order within the frame.
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

    /// - Parameters:
    ///   - body: the player's body sprite. The overlay is added as its
    ///     child, sized and anchored identically, and left at `position ==
    ///     .zero` so it exactly overlays the body's current cell.
    ///   - tier: initial weapon tier shown.
    ///   - direction: initial facing shown.
    init(body: SKSpriteNode, tier: WeaponTier, direction: Direction8) {
        self.tier = tier
        self.direction = direction

        overlay = SKSpriteNode(texture: Self.texture(tier: tier, direction: direction))
        overlay.size = body.size
        overlay.anchorPoint = body.anchorPoint
        overlay.zPosition = Self.overlayRelativeZ

        body.addChild(overlay)
        PixelCrispness.apply(to: overlay)
        overlay.xScale = PlayerSpriteSheet.xScale(for: direction)
    }

    /// Swaps the visible texture for `tier`/`direction`, without touching
    /// `overlay.size`/`anchorPoint` (per the "same cell, same anchor"
    /// contract) beyond the mirror-cancellation described on the type's own
    /// doc comment.
    func update(tier: WeaponTier, direction: Direction8) {
        self.tier = tier
        self.direction = direction
        overlay.texture = Self.texture(tier: tier, direction: direction)
        overlay.xScale = PlayerSpriteSheet.xScale(for: direction)
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
