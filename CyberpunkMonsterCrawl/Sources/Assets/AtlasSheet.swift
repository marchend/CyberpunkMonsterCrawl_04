import CoreGraphics

/// One declared `SpriteSheet` per atlas-sheet family the Pixel Grit pack
/// ships — the values below come from the story's table (CYBERPUN-17-1) and
/// are checked against the shipped art by `SpriteSheet.init`'s measurement
/// precondition, not assumed to be correct because they match a filename.
///
/// This is the single manifest of the 10 sheet ids: `AtlasCatalogTests`,
/// `AtlasDimensionsTests`, `AtlasCellIndexTests` and `TextureLoadingTests` all
/// read `AtlasSheet.allCases` rather than re-listing the ids, so a renamed or
/// dropped sheet cannot leave a stale copy of the manifest agreeing with
/// itself somewhere else.
enum AtlasSheet: CaseIterable {
    case playerWalk
    case playerWeapons
    case bullets
    case raccoonWalk
    case raccoonAttack
    case groundTiles
    case pickups
    case pulse
    case hitPuff
    case signs

    /// The measured-geometry contract for this case.
    var sheet: SpriteSheet {
        switch self {
        case .playerWalk:
            // 144×320px, 36×40 cell (4 col × 8 row): cols = frames
            // (contact·pass-L·contact·pass-R), rows 0–7 = 8 directions.
            return SpriteSheet(
                imageID: "sprite_player_walk",
                pixelSize: CGSize(width: 144, height: 320),
                cellSize: CGSize(width: 36, height: 40)
            )
        case .playerWeapons:
            // 288×120px, 36×40 cell (8 col × 3 row): cols = 8 directions,
            // rows 0/1/2 = handgun/SMG/AR.
            return SpriteSheet(
                imageID: "sprite_player_weapons",
                pixelSize: CGSize(width: 288, height: 120),
                cellSize: CGSize(width: 36, height: 40)
            )
        case .bullets:
            // 48×16px, 16×16 cell (3 col): 0 slug · 1 SMG tracer · 2 rifle round.
            return SpriteSheet(
                imageID: "sprite_bullets",
                pixelSize: CGSize(width: 48, height: 16),
                cellSize: CGSize(width: 16, height: 16)
            )
        case .raccoonWalk:
            // 192×224px, 48×28 cell (4 col × 8 row): cols = frames, rows 0–7
            // = 8 directions.
            return SpriteSheet(
                imageID: "sprite_raccoon_walk",
                pixelSize: CGSize(width: 192, height: 224),
                cellSize: CGSize(width: 48, height: 28)
            )
        case .raccoonAttack:
            // Same grid as sprite_raccoon_walk.
            return SpriteSheet(
                imageID: "sprite_raccoon_attack",
                pixelSize: CGSize(width: 192, height: 224),
                cellSize: CGSize(width: 48, height: 28)
            )
        case .groundTiles:
            // 592×60px. NOT a clean N×96: see `AtlasGroundDiamond` below for
            // how the six diamond sub-rects were measured. No uniform
            // `cellSize` — `texture(forPixelRect:)` is used instead of
            // `texture(col:row:)` for this sheet.
            return SpriteSheet(
                imageID: "tileset_ground",
                pixelSize: CGSize(width: 592, height: 60),
                cellSize: nil
            )
        case .pickups:
            // 48×24px, 24×24 cell (2 col): med kit · garbage can.
            return SpriteSheet(
                imageID: "sprite_pickups",
                pixelSize: CGSize(width: 48, height: 24),
                cellSize: CGSize(width: 24, height: 24)
            )
        case .pulse:
            // 256x32px, 32x32 cell (8 frames): pulse shockwave.
            //
            // CYBERPUN-17-10-t5 re-checked this declaration directly against
            // the shipped Assets.xcassets/Atlas/sprite_pulse.imageset
            // /sprite_pulse.png bytes while investigating the pulse-ability
            // crash. The leading hypothesis there was that this declared
            // size disagreed with the measured one, tripping
            // SpriteSheet.init's precondition -- it does not: the shipped
            // PNG decodes at exactly 256x32, matching this declaration
            // exactly (also independently pinned by
            // PulseRingArtMeasurementTests
            // .test_spritePulse_decodesAtItsDeclaredSheetGeometry_withRealPixelsInEveryFrame()
            // and AtlasDimensionsTests) -- so that hypothesis is ruled out,
            // not merely unconfirmed.
            return SpriteSheet(
                imageID: "sprite_pulse",
                pixelSize: CGSize(width: 256, height: 32),
                cellSize: CGSize(width: 32, height: 32)
            )
        case .hitPuff:
            // 96×24px, 24×24 cell (4 col): impact puff; frame 0 = muzzle flash.
            return SpriteSheet(
                imageID: "sprite_hit_puff",
                pixelSize: CGSize(width: 96, height: 24),
                cellSize: CGSize(width: 24, height: 24)
            )
        case .signs:
            // 192×144px, 48×48 cell (12 cells, 4 col × 3 row): rooftop neon signs.
            return SpriteSheet(
                imageID: "sprite_signs",
                pixelSize: CGSize(width: 192, height: 144),
                cellSize: CGSize(width: 48, height: 48)
            )
        }
    }

    /// Imageset name backing this case, without instantiating the full
    /// measured `SpriteSheet` (which trips the measurement precondition).
    var imageID: String {
        switch self {
        case .playerWalk: return "sprite_player_walk"
        case .playerWeapons: return "sprite_player_weapons"
        case .bullets: return "sprite_bullets"
        case .raccoonWalk: return "sprite_raccoon_walk"
        case .raccoonAttack: return "sprite_raccoon_attack"
        case .groundTiles: return "tileset_ground"
        case .pickups: return "sprite_pickups"
        case .pulse: return "sprite_pulse"
        case .hitPuff: return "sprite_hit_puff"
        case .signs: return "sprite_signs"
        }
    }
}

/// Where the neon glyphs actually sit *inside* each 48×48 `sprite_signs`
/// cell, measured off the shipped PNG's alpha channel rather than inferred
/// from the cell size.
///
/// **Why this exists.** `AtlasSheet.signs` pins the *sheet* geometry
/// (192×144px, 48×48 cells, 12 of them) and `SpriteSheet.init` measures that
/// against the shipped art — but neither says anything about where the
/// opaque pixels sit within a cell, and that is what a bottom-centre
/// roofline anchor depends on.
///
/// **How this was measured.** A pixel-alpha scan of the shipped
/// `sprite_signs.png` puts every cell's opaque content in a band that is
/// *vertically centred* in its cell, not flush with the cell's bottom edge:
/// cell 0's glyphs occupy rows 18..<30 of its 48-row cell, i.e. 18 fully
/// transparent rows above them and 18 below. The bands below are those
/// measured row ranges, in `AtlasCellIndex.signs` order (top-row-is-0, the
/// same convention `SpriteSheet.texture(col:row:)` reads).
///
/// **What consumes it.** `RooftopSignRenderer` anchors a sign bottom-centre
/// on its carrier building's roofline; mounting the raw 48×48 cell there
/// would leave every sign floating 8–19px above the roof it stands on (the
/// visible-gap failure AC7 calls out), because those transparent rows below
/// the glyphs would sit between the glyphs and the roofline. The renderer
/// therefore drops the cell by `bottomInset(forSignCellIndex:)` so the
/// *glyphs'* base — not the cell's empty bottom edge — lands on the
/// roofline, while still cropping the whole cell so a sign's art is never
/// clipped.
///
/// **How that stays honest.** These are not left as prose:
/// `RooftopSignSpriteAlignmentTests` re-runs the alpha scan at test time and
/// asserts every declared band equals the measured one, for all 12 cells. Art
/// re-authored bottom-flush (or re-cut on a different grid) turns the suite
/// red here rather than silently un-tuning the renderer's offset.
enum AtlasSignGlyphBand {
    /// Measured opaque-content row range within each cell, indexed by
    /// `RooftopSignRecord.signCellIndex` / `AtlasCellIndex.signs`.
    static let glyphRows: [Range<Int>] = [
        18..<30, 18..<30, 18..<31, 17..<31,
        12..<36, 8..<40, 19..<29, 19..<30,
        14..<34, 13..<35, 16..<33, 12..<36,
    ]

    /// Fully transparent rows between a cell's glyphs and the cell's bottom
    /// edge — the amount a bottom-centre-anchored sign has to drop for its
    /// glyph base to rest on the roofline.
    static func bottomInset(forSignCellIndex index: Int) -> CGFloat {
        precondition(
            glyphRows.indices.contains(index),
            "Sign cell index \(index) is outside the 12 measured sprite_signs glyph bands."
        )
        guard let cellHeight = AtlasSheet.signs.sheet.cellSize?.height else {
            preconditionFailure("sprite_signs is a uniform grid; its SpriteSheet must declare a cellSize.")
        }
        return cellHeight - CGFloat(glyphRows[index].upperBound)
    }
}

/// The six `tileset_ground` diamond sub-rects, measured directly off the
/// shipped `tileset_ground.png` pixels rather than assumed from the 96×48
/// world-tile constant.
///
/// **How this was measured:** `tileset_ground.png` is 592×60px. A pixel-alpha
/// scan of the shipped PNG puts its non-transparent content's bounding box at
/// x:[0,586] / y:[6,54] — the art sits in a 48px-tall content band with a 6px
/// pad above and below, which is the diamonds' overhang lip (the story's
/// "road/kerb/lot variants + overhang" note), and is why the sheet is 60px
/// tall rather than a clean 48. 592 does not divide evenly into six 96px-wide
/// cells (592 / 6 ≈ 98.67px), confirming this sheet is *not* a uniform grid,
/// exactly as `docs/bootstrap.md` §2 calls out. The first five diamonds —
/// including `kerbTransition` at x:384 — each sit in a standard 96px-wide
/// cell (the world tile width); only the sixth, `overhangLot` at x:480, is
/// 112px wide, because its lot overhang runs past the tile footprint.
/// 5×96 + 112 = 592px exactly, with no gap or overlap across the sheet's
/// width. Every sub-rect keeps the full 60px sheet height (rather than
/// cropping to the 48px content band) so the overhang lip stays part of the
/// cropped texture instead of being clipped.
///
/// **How that partition is pinned:** the numbers below are not left as prose.
/// `AtlasGroundDiamondTests` re-runs the alpha scan at test time and asserts
/// (a) the documented content bounding box above, (b) that the six sub-rects
/// tile the *measured* sheet width exactly — five 96px cells plus one 112px
/// cell, last — and (c) that each sub-rect's own content bounding box is
/// non-empty and sits centred in that sub-rect. A 6×98.67px partition, a
/// 96px-plus-padding layout, or the 112px cell placed at x:0 instead of
/// x:480 all fail (c), which a bounds-containment check alone cannot
/// discriminate between.
enum AtlasGroundDiamond: Int, CaseIterable {
    case laneEastWest = 0
    case laneNorthSouth = 1
    case plainLot = 2
    case intersection = 3
    case kerbTransition = 4
    case overhangLot = 5

    /// Top-left-origin pixel rect on `tileset_ground.png`, ready to pass to
    /// `AtlasSheet.groundTiles.sheet.texture(forPixelRect:)`.
    var pixelRect: CGRect {
        switch self {
        case .laneEastWest:
            return CGRect(x: 0, y: 0, width: 96, height: 60)
        case .laneNorthSouth:
            return CGRect(x: 96, y: 0, width: 96, height: 60)
        case .plainLot:
            return CGRect(x: 192, y: 0, width: 96, height: 60)
        case .intersection:
            return CGRect(x: 288, y: 0, width: 96, height: 60)
        case .kerbTransition:
            return CGRect(x: 384, y: 0, width: 96, height: 60)
        case .overhangLot:
            return CGRect(x: 480, y: 0, width: 112, height: 60)
        }
    }
}

/// Where the shockwave's opaque pixels actually sit *inside* each 32×32
/// `sprite_pulse` cell, measured off the shipped PNG's alpha channel rather
/// than inferred from the cell size.
///
/// **Why this exists.** `AtlasSheet.pulse` pins the *sheet* geometry
/// (256×32px, 8 × 32×32 cells) and `SpriteSheet.init` measures that against
/// the shipped art — but neither says anything about where the opaque pixels
/// sit *within* a cell, and that is exactly what
/// `PulseRingNode.xScale(forRadiusTiles:)`/`yScale(forRadiusTiles:)` depend
/// on: they convert a tile-space radius into the node scale whose **drawn
/// ring** spans the pulse's real screen-space extent, and scaling an
/// `SKSpriteNode` scales the whole cell, not just the ring inside it. Sizing
/// against the 32px cell instead of the measured ring draws the ring
/// `cellSize / ringSize` times off, silently (PR #48 review).
///
/// Measuring **per axis** also makes the transform indifferent to how the
/// art is authored: a ring drawn as a screen-space circle and a ring already
/// squashed onto the 2:1 isometric plane have different measured heights, so
/// dividing each axis by its own measured extent lands the drawn ring on the
/// projected ellipse either way, with no "the art is a circle" assumption
/// left unstated.
///
/// **What is measured.** `widestFrameColumn` is the frame at the shockwave's
/// full extent — the one the scale-to-radius transform calibrates against,
/// since that is the frame whose ring should coincide with the pulse's
/// radius — and `widestFrameContentSize` is that cell's opaque-content
/// bounding box, in cell-local pixels.
///
/// **How that stays honest.** These are not left as prose:
/// `PulseRingArtMeasurementTests` re-runs the alpha scan at test time and
/// asserts both the declared widest column and its declared content size
/// equal the measured ones, for the shipped `sprite_pulse.png`. Re-authored
/// art (a ring cut smaller inside its cell, an already-squashed re-export, a
/// reordered animation) turns the suite red here rather than silently
/// un-tuning `PulseRingNode`'s scale-to-radius math.
enum AtlasPulseRingContent {

    /// The `sprite_pulse` column whose ring is at its widest, as measured
    /// off the shipped PNG: the alpha scan reads per-frame content widths
    /// of `[7, 7, 12, 12, 20, 20, 27, 27]`, i.e. the shockwave grows in
    /// four steps, each **held for two frames**. Frames 6 and 7 therefore
    /// tie at the peak, and this declares the *first* of them — matching
    /// `PulseRingArtMeasurementTests`' own first-strict-max scan, so the
    /// pin stays deterministic instead of depending on a tie-break nobody
    /// wrote down.
    static let widestFrameColumn: Int = 6

    /// Measured opaque-content bounding box of `widestFrameColumn`'s cell,
    /// in cell-local pixels (top-left origin, the same convention
    /// `AtlasGroundDiamond.pixelRect` uses).
    ///
    /// **Measured, not assumed.** This deliberately is *not* the 32×32 cell
    /// size: the ring is inset within its cell, and an earlier cut of this
    /// PR declared the cell size here on the unstated "the art fills its
    /// cell" assumption the review called out — which would have drawn
    /// every pulse ring ~18% undersized on x and ~14% on y.
    static let widestFrameContentSize = CGSize(width: 27, height: 28)
}
