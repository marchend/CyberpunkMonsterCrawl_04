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
            // 256×32px, 32×32 cell (8 frames): pulse shockwave.
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
/// **Which crop holds which diamond was measured too, not read off the
/// sheet's left-to-right order.** The three left-hand crops (x:0 / x:96 /
/// x:192) all share the dark asphalt base (luminance median 20.7, minimum
/// 4.6); the three right-hand ones (x:288 / x:384 / x:480) are the light
/// concrete family (median 54-68). Inside the asphalt family only *two* crops
/// carry high-contrast paint, and they carry the same amount of it: x:96 and
/// x:192 share a 98th-percentile luminance of 58.4 and peak at 133.2 / 132.2,
/// while x:0's brightest pixel reaches only 29.7 against the same 20.7 median.
/// So x:96 and x:192 are the pack's directional lane pair (identical marking
/// colour and paint budget, dashes on the two *opposite* screen diagonals) and
/// x:0 is the featureless bare-ground diamond. `GroundTileSemanticsTests`
/// re-measures both facts at test time.
enum AtlasGroundDiamond: Int, CaseIterable {
    /// The sheet's first diamond (x:0): the asphalt-toned crop that carries
    /// **no paint at all** (brightest pixel 29.7 against a 20.7 median, a
    /// 1.4x contrast, where both lane crops reach 6.4x), so it is the
    /// featureless bare-ground diamond rather than either lane.
    case plainLot = 0
    /// The sheet's second diamond (x:96): its painted dash runs along the
    /// **tile-Y** diagonal, which is the axis a north-south corridor runs
    /// along.
    ///
    /// `GroundTileSemanticsTests
    /// .test_eachLaneCrop_carriesPaintElongatedAlongTheAxisItsCaseNameClaims`
    /// re-measures the shipped pixels and fails if the two lane names are ever
    /// bound the other way round, or bound onto the paintless `plainLot` crop
    /// next door.
    case laneNorthSouth = 1
    /// The sheet's third diamond (x:192): paint elongated along the **tile-X**
    /// diagonal, i.e. the east-west corridor. See `laneNorthSouth` above for
    /// how the pair was measured.
    case laneEastWest = 2
    case intersection = 3
    case kerbTransition = 4
    case overhangLot = 5

    /// Top-left-origin pixel rect on `tileset_ground.png`, ready to pass to
    /// `AtlasSheet.groundTiles.sheet.texture(forPixelRect:)`.
    var pixelRect: CGRect {
        switch self {
        case .plainLot:
            return CGRect(x: 0, y: 0, width: 96, height: 60)
        case .laneNorthSouth:
            return CGRect(x: 96, y: 0, width: 96, height: 60)
        case .laneEastWest:
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
