import CoreGraphics

/// Forward/inverse coordinate transform between integer tile space and
/// on-screen point space for the game's 2:1 isometric diamonds.
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
    static func screenToTile(screenX: Double, screenY: Double) -> (tileX: Double, tileY: Double) {
        let tileX = screenX / (2 * tileHalfWidth) + screenY / (2 * tileHalfHeight)
        let tileY = screenY / (2 * tileHalfHeight) - screenX / (2 * tileHalfWidth)
        return (tileX: tileX, tileY: tileY)
    }

    /// Convenience overload taking/returning `CGPoint` at the boundary, for
    /// callers that already have screen-space points (e.g. touch locations).
    static func tileToScreen(tile: CGPoint) -> CGPoint {
        tileToScreen(tileX: Double(tile.x), tileY: Double(tile.y))
    }

    /// Convenience overload taking/returning `CGPoint` at the boundary.
    static func screenToTile(screen: CGPoint) -> CGPoint {
        let (tileX, tileY) = screenToTile(screenX: Double(screen.x), screenY: Double(screen.y))
        return CGPoint(x: CGFloat(tileX), y: CGFloat(tileY))
    }
}
