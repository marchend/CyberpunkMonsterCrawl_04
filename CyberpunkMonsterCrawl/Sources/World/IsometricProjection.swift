import CoreGraphics

/// A point in **tile space** — the lattice the world is authored on, where
/// whole numbers are tile centers and the axes run along the diamond's two
/// edges (not along the screen's x/y).
///
/// This exists so tile space and screen space are not the same type. An
/// untyped `CGPoint -> CGPoint` transform lets a caller feed a touch
/// location (screen space) straight into the forward transform and get back
/// a silently-plausible position; with `TilePoint` that mistake is a compile
/// error instead. Same discipline as the atlas-crop convention gate and the
/// layer-band audits elsewhere in this repo: make the bad call structurally
/// impossible rather than documented-against.
struct TilePoint: Equatable {
    /// Tile-space x. Whole values are tile centers; fractional values are
    /// legal so callers can interpolate between tiles.
    var x: Double
    /// Tile-space y. Whole values are tile centers; fractional values are
    /// legal so callers can interpolate between tiles.
    var y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Forward/inverse coordinate transform between tile space and on-screen
/// point space for the game's 2:1 isometric diamonds.
///
/// World constants (`docs/bootstrap.md` §4): isometric 2:1 diamonds at
/// **96×48px** (supersedes the earlier 128×64px value referenced in older
/// docs). A tile diamond is 96px wide and 48px tall, so the forward
/// transform's half-width/half-height constants are 48 and 24 respectively.
///
/// All arithmetic is done in `Double` and only cast to `CGFloat` at the
/// public boundary, so repeated round-trips never accumulate `Float`-vs-
/// `Double` rounding drift across call sites that mix the two.
enum IsometricProjection {
    /// Half the diamond's pixel width (96px wide diamond ⇒ 48px half-width).
    static let tileHalfWidth: Double = 48
    /// Half the diamond's pixel height (48px tall diamond ⇒ 24px half-height).
    static let tileHalfHeight: Double = 24

    /// Maps a tile-space coordinate (tile centers are whole integers, but the
    /// input is `Double` so callers can project fractional/interpolated
    /// positions too) to its on-screen point.
    ///
    /// `screenX = (tileX - tileY) * 48`
    /// `screenY = (tileX + tileY) * 24`
    static func tileToScreen(tileX: Double, tileY: Double) -> CGPoint {
        let screenX = (tileX - tileY) * tileHalfWidth
        let screenY = (tileX + tileY) * tileHalfHeight
        return CGPoint(x: CGFloat(screenX), y: CGFloat(screenY))
    }

    /// The exact algebraic inverse of `tileToScreen`, solved from:
    /// `screenX = (tileX - tileY) * 48`
    /// `screenY = (tileX + tileY) * 24`
    ///
    /// ⇒ `tileX = screenX / 96 + screenY / 48`
    ///   `tileY = screenY / 48 - screenX / 96`
    ///
    /// The result is *fractional* tile space: an arbitrary screen point
    /// (a touch, a camera center) generally lands somewhere inside a
    /// diamond, not on its center. Use `tile(containing:)` when the question
    /// is "which tile owns this point" — that entry point pins the rounding
    /// rule instead of leaving it to each call site.
    static func screenToTile(screenX: Double, screenY: Double) -> (tileX: Double, tileY: Double) {
        let tileX = screenX / (2 * tileHalfWidth) + screenY / (2 * tileHalfHeight)
        let tileY = screenY / (2 * tileHalfHeight) - screenX / (2 * tileHalfWidth)
        return (tileX: tileX, tileY: tileY)
    }

    /// Forward transform for callers that already hold a **tile-space**
    /// point (a world position), returning its on-screen point.
    static func tileToScreen(_ tile: TilePoint) -> CGPoint {
        tileToScreen(tileX: tile.x, tileY: tile.y)
    }

    /// Inverse transform for callers that hold a **screen-space** point
    /// (e.g. a touch location), returning fractional tile space.
    ///
    /// See `tile(containing:)` for the integer "which tile is this?" answer.
    static func screenToTile(_ screen: CGPoint) -> TilePoint {
        let (tileX, tileY) = screenToTile(screenX: Double(screen.x), screenY: Double(screen.y))
        return TilePoint(x: tileX, y: tileY)
    }

    /// The integer tile whose diamond contains `screen`.
    ///
    /// This is the contract `screenToTile` deliberately does *not* make:
    /// `round()` and `floor()` disagree about who owns a point, and on a 2:1
    /// diamond the disagreement lands exactly on the diamond edges — i.e. on
    /// the street/building seam the lattice work cares about. The rule
    /// pinned here is `floor(coordinate + 0.5)`, which gives each tile the
    /// half-open ownership region `[center - 0.5, center + 0.5)` on both
    /// axes: a point exactly on a seam belongs to the **higher-index** tile,
    /// uniformly on both sides of the origin.
    ///
    /// (`rounded(.toNearestOrAwayFromZero)` would break that uniformity —
    /// it hands tile-space `-0.5` to tile `-1` while handing `+0.5` to tile
    /// `+1`, so the seam rule would flip sign across the origin.)
    static func tile(containing screen: CGPoint) -> (tileX: Int, tileY: Int) {
        let fractional = screenToTile(screenX: Double(screen.x), screenY: Double(screen.y))
        return (
            tileX: owningTileIndex(forTileSpaceCoordinate: fractional.tileX),
            tileY: owningTileIndex(forTileSpaceCoordinate: fractional.tileY)
        )
    }

    /// The integer tile that owns a **tile-space** point.
    ///
    /// The same pinned rule as `tile(containing screen:)`, exposed for
    /// callers that already hold tile space (a camera world position, an
    /// interpolated actor position) rather than a screen point. Without this
    /// entry point such a caller has to re-derive the rule, and the obvious
    /// guess — `rounded(.down)` — disagrees with the pinned rule for every
    /// position in the upper half of a tile (tile-space `7.6` is owned by
    /// tile `8`, not tile `7`). One rounding rule per codebase: that is the
    /// whole reason `tile(containing:)` exists, so it must cover the
    /// tile-space question too and not just the screen-space one.
    static func tile(containing tile: TilePoint) -> (tileX: Int, tileY: Int) {
        (
            tileX: owningTileIndex(forTileSpaceCoordinate: tile.x),
            tileY: owningTileIndex(forTileSpaceCoordinate: tile.y)
        )
    }

    /// `floor(coordinate + 0.5)` — see `tile(containing:)` for why this
    /// rounding rule and not `round()`.
    ///
    /// A tiny epsilon is folded in before flooring to absorb floating-point
    /// noise introduced by the screen-space round trip
    /// (`tileToScreen`/`screenToTile`): multiplying and dividing by 48/24
    /// is not exact for most tile-space values, so a coordinate that is
    /// mathematically exactly on a seam (e.g. tile-space `-4.5`) can come
    /// back from the round trip as `-4.500000000000002` instead. Without
    /// the epsilon that noise flips `floor` to the tile on the wrong side
    /// of the seam, so `tile(containing: TilePoint)` and
    /// `tile(containing: CGPoint)` disagree for the exact same position.
    /// `1e-6` is many orders of magnitude larger than the accumulated
    /// double-precision error here (~1e-13) but far smaller than the
    /// half-tile seam spacing this rule cares about, so it cannot change
    /// the answer for any position that is not already on (or numerically
    /// indistinguishable from) a seam.
    private static let seamEpsilon: Double = 1e-6

    private static func owningTileIndex(forTileSpaceCoordinate coordinate: Double) -> Int {
        Int((coordinate + 0.5 + seamEpsilon).rounded(.down))
    }
}
