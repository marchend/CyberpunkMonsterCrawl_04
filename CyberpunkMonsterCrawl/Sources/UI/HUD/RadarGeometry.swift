import CoreGraphics

/// Pure tile\u2194radar mapping/scale/classification math for the minimap radar
/// (`CYBERPUN-17-23`). No SpriteKit dependency and no scene construction --
/// every function here is a closed-form transform of plain numbers, so
/// `RadarGeometryTests` can prove the two product-critical facts (AC9's
/// direction-matching, AC12's scale invariance) from pure unit tests alone.
///
/// **Scope of this PR (`CYBERPUN-17-23-t1`):** the geometry only. The
/// `SKShapeNode`/`SKSpriteNode` radar dial that actually draws these points
/// is a later PR's job (see `RadarBackdropRenderer`'s own scope note).
enum RadarGeometry {
    /// The radar's content square is 110x110 points, centred on its own
    /// origin -- `isWithinContentSquare(_:)` tests against half that, 55.
    static let contentSquareSize: CGFloat = 110

    /// Half of `contentSquareSize` -- the per-axis bound a radar-space point
    /// must stay within to be drawn inside the dial.
    static let halfContentSquareSize: CGFloat = contentSquareSize / 2

    /// The denominator tuning constant in `radarScale(for:)`'s formula: the
    /// radar always shows a fixed *screen-relative* field of view, 2.5x the
    /// device's longer screen dimension, regardless of portrait/landscape
    /// (AC12) -- a device rotating between the two must not change how much
    /// world the radar shows, since nothing about the world itself changed.
    private static let fieldOfViewMultiplier: CGFloat = 2.5

    /// The radar's world-to-radar scale factor for a scene of `sceneSize`:
    /// `110 / (2.5 * max(width, height))`.
    ///
    /// Keyed off `max(width, height)` (not width alone, not height alone,
    /// not some combination of both) specifically so a portrait and a
    /// landscape scene of the same device -- `portraitSize` and
    /// `landscapeSize` being the same two numbers merely transposed -- yield
    /// the *identical* scale (AC12): `max` is symmetric under that swap,
    /// while either bare dimension alone would not be.
    static func radarScale(for sceneSize: CGSize) -> CGFloat {
        let maxDimension = max(sceneSize.width, sceneSize.height)
        guard maxDimension > 0 else { return 0 }
        return contentSquareSize / (fieldOfViewMultiplier * maxDimension)
    }

    /// Maps a tile-space offset (relative to the radar's own centre --
    /// typically the player's tile) to a radar-local point, at `scale`.
    ///
    /// Derived to match `IsometricProjection.tileToScreen`'s own sign
    /// convention exactly, rather than independently: that forward
    /// transform is `screenX = (tileX - tileY) * tileHalfWidth`,
    /// `screenY = (tileX + tileY) * tileHalfHeight`, with
    /// `tileHalfWidth = 2 * tileHalfHeight` (a 2:1 isometric diamond). This
    /// function is the *identical* formula with `scale` standing in for
    /// `tileHalfWidth` and `scale / 2` standing in for `tileHalfHeight` --
    /// i.e. a uniform positive rescaling of `tileToScreen`'s own output by
    /// the constant factor `scale / IsometricProjection.tileHalfWidth`.
    /// A uniform positive rescaling can never flip a sign or change an
    /// angle, which is exactly what `RadarGeometryTests`' direction-matching
    /// case (AC9) proves holds against `IsometricProjection.tileToScreen`
    /// directly, rather than leaving the two conventions to agree by
    /// construction alone.
    static func radarPoint(forTileOffset offset: (x: Int, y: Int), scale: CGFloat) -> CGPoint {
        let dx = CGFloat(offset.x)
        let dy = CGFloat(offset.y)
        let x = (dx - dy) * scale
        let y = (dx + dy) * (scale / 2)
        return CGPoint(x: x, y: y)
    }

    /// Whether `point` (in the radar's own local space, centred on its
    /// origin) falls inside the 110x110 content square -- the window test a
    /// radar icon's drawn position must pass before it is actually mounted,
    /// so an icon whose tile offset projects far outside the dial is simply
    /// not shown rather than drawn overflowing it.
    static func isWithinContentSquare(_ point: CGPoint) -> Bool {
        abs(point.x) <= halfContentSquareSize && abs(point.y) <= halfContentSquareSize
    }
}
