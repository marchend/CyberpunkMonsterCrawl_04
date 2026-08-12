import CoreGraphics

/// The player's `sprite_player_walk` geometry contract: the sheet's grid,
/// the single owning `Direction8 \u2192 (row, mirrored)` table, the anchor
/// point, and the hitbox geometry anchored at it.
///
/// **Pixel/cell size** are not re-declared here as a second copy of the
/// numbers `AtlasSheet.playerWalk` already declares (144\u00d7320px, 36\u00d740
/// cell) \u2014 they are read straight from it, so the two can never drift apart.
/// This file adds the facts `AtlasSheet` deliberately does not own: which
/// row is which facing, which facings mirror, and where the anchor/hitbox
/// sit.
enum PlayerSpriteSheet {

    /// The measured-geometry contract for `sprite_player_walk`, delegated to
    /// the atlas contract's single owning declaration rather than a second,
    /// independently-typed-out copy.
    static var sheet: SpriteSheet { AtlasSheet.playerWalk.sheet }

    /// 144\u00d7320px \u2014 see `AtlasSheet.playerWalk`.
    static var pixelSize: CGSize { sheet.pixelSize }

    /// 36\u00d740px \u2014 see `AtlasSheet.playerWalk`.
    static var cellSize: CGSize { sheet.cellSize ?? CGSize(width: 36, height: 40) }

    /// 4 columns (walk-cycle frames) \u2014 see `AtlasSheet.playerWalk`.
    static var columns: Int { sheet.columns }

    /// 8 rows (only 5 are directly authored; the other 3 facings reuse a
    /// row mirrored \u2014 see `rowMapping(for:)`) \u2014 see `AtlasSheet.playerWalk`.
    static var rows: Int { sheet.rows }

    /// One row's placement in the sheet, plus whether that row must be
    /// drawn with a negative x-scale (horizontally flipped) to produce this
    /// facing.
    struct RowMapping: Equatable {
        let row: Int
        let mirrored: Bool
    }

    /// The single owning `Direction8 \u2192 (row, mirrored)` table.
    ///
    /// The art authors 5 facings directly, sweeping from due-south to
    /// due-north through the sheet's east side (rows 0\u20134: south,
    /// southeast, east, northeast, north). The remaining 3 facings
    /// (southwest, west, northwest) sit on the sheet's unauthored west
    /// side and are produced by horizontally mirroring the direct row that
    /// shares the same vertical component:
    ///
    /// - `.southwest` mirrors `.southeast`'s row (both "moving down", only
    ///   the horizontal component differs).
    /// - `.west` mirrors `.east`'s row (both purely horizontal).
    /// - `.northwest` mirrors `.northeast`'s row (both "moving up").
    ///
    /// This is the standard convention for an 8-direction walk sheet that
    /// only authors one lateral half of the compass and mirrors the other
    /// \u2014 mirroring across any other pairing would show the wrong vertical
    /// pose (e.g. an up-facing pose mirrored into a direction that should
    /// be moving down).
    static let rowMappingTable: [Direction8: RowMapping] = [
        .south: RowMapping(row: 0, mirrored: false),
        .southeast: RowMapping(row: 1, mirrored: false),
        .east: RowMapping(row: 2, mirrored: false),
        .northeast: RowMapping(row: 3, mirrored: false),
        .north: RowMapping(row: 4, mirrored: false),
        .southwest: RowMapping(row: 1, mirrored: true),
        .west: RowMapping(row: 2, mirrored: true),
        .northwest: RowMapping(row: 3, mirrored: true),
    ]

    /// This facing's row/mirror mapping. `rowMappingTable` is exhaustive over
    /// every `Direction8` case, so this never fails \u2014 the `preconditionFailure`
    /// only guards against the dictionary and the enum silently drifting
    /// apart in a future edit.
    static func rowMapping(for direction: Direction8) -> RowMapping {
        guard let mapping = rowMappingTable[direction] else {
            preconditionFailure(
                "Direction8.\(direction) has no PlayerSpriteSheet row mapping. "
                    + "Every Direction8 case must have an entry in PlayerSpriteSheet.rowMappingTable."
            )
        }
        return mapping
    }

    /// `-1` for a mirrored facing, `1` otherwise \u2014 the x-scale a consumer
    /// applies to the node showing this facing's texture.
    static func xScale(for direction: Direction8) -> CGFloat {
        rowMapping(for: direction).mirrored ? -1 : 1
    }

    /// The anchor pixel within one cell: `(18, 40)`, top-left-origin pixel
    /// coordinates the same way the design table and `AtlasSheet`'s pixel
    /// rects read them \u2014 horizontally centered (half of the 36px cell
    /// width) and at the very bottom of the 40px cell (the character's feet).
    static let anchorPixel = CGPoint(x: 18, y: 40)

    /// `anchorPixel` converted to SpriteKit's normalized, bottom-left-origin
    /// `anchorPoint` space: `(0.5, 0.0)` \u2014 bottom-center of the cell.
    static var anchorPointNormalized: CGPoint {
        CGPoint(
            x: anchorPixel.x / cellSize.width,
            y: 1 - anchorPixel.y / cellSize.height
        )
    }

    /// The player's ground-collision footprint: 14\u00d710, anchored at
    /// `anchorPointNormalized` (the feet) rather than the cell's visual
    /// center, so the box tracks the character's feet regardless of how
    /// tall the sprite draws above them.
    static let hitboxSize = CGSize(width: 14, height: 10)

    /// The hitbox rect centered on `position` \u2014 the caller's node position,
    /// which (because the node's own `anchorPoint` is `anchorPointNormalized`)
    /// already sits at the feet. Returned in whatever coordinate space
    /// `position` is given in.
    static func hitboxRect(anchoredAt position: CGPoint) -> CGRect {
        let halfWidth = hitboxSize.width / 2
        let halfHeight = hitboxSize.height / 2
        return CGRect(
            x: position.x - halfWidth,
            y: position.y - halfHeight,
            width: hitboxSize.width,
            height: hitboxSize.height
        )
    }
}
