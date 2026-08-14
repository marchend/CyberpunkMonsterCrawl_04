import CoreGraphics

/// A shared 8-way facing direction for any actor that needs discrete
/// direction-of-travel art.
///
/// Deliberately carries **no player-specific coupling** \u2014 no row numbers,
/// no mirror flags, no sprite-sheet knowledge. `PlayerSpriteSheet` (this PR)
/// owns the player's `Direction8 \u2192 (row, mirrored)` table; a future raccoon
/// sprite sheet (CYBERPUN-17-8) owns its own table the exact same way,
/// against this same unmodified type.
enum Direction8: CaseIterable, Equatable {
    case south
    case southeast
    case east
    case northeast
    case north
    case northwest
    case west
    case southwest

    /// Bins a movement vector into one of the 8 sectors, clockwise from
    /// screen-south.
    ///
    /// **Coordinate convention:** `vector` is in on-screen (CoreGraphics /
    /// UIKit) space, where `dy` increases **downward** \u2014 the same
    /// convention every pixel-space rect in this codebase already uses
    /// (`SpriteSheet`'s top-left-origin pixel rects, `AtlasSheet`'s cell
    /// geometry). A caller sitting on top of SpriteKit's own coordinate
    /// space (where `y` increases **upward**) must not call this directly:
    /// `from(spriteKitVector:)` below owns that flip, so no call site has to
    /// remember to negate `dy` itself.
    ///
    /// `atan2(dy, dx)` is `0` at screen-east and *increases clockwise* in
    /// that y-down space (east \u2192 south \u2192 west \u2192 north \u2192 east, since
    /// rotating from "pointing right" towards "pointing down" is a clockwise
    /// turn as seen on the device). Subtracting 90\u00b0 (`.pi / 2`) shifts the
    /// zero reference from east to south without touching the direction of
    /// rotation, giving:
    ///
    /// `south=0\u00b0, southwest=45\u00b0, west=90\u00b0, northwest=135\u00b0, north=180\u00b0,`
    /// `northeast=225\u00b0, east=270\u00b0, southeast=315\u00b0`.
    ///
    /// Each of the 8 sectors spans 45\u00b0 and is **offset by 22.5\u00b0** so a
    /// direction's exact angle sits at the sector's center rather than its
    /// edge \u2014 rounding `angle / 45\u00b0` to the nearest integer produces exactly
    /// that offset, so e.g. a vector at 40\u00b0 (14\u00b0 short of due southwest)
    /// still resolves to `.southwest`, not `.south`.
    ///
    /// A zero-magnitude vector carries no facing information, so it leaves
    /// the caller's current facing unchanged \u2014 signalled by returning `nil`
    /// rather than an arbitrary direction.
    static func from(vector: CGVector) -> Direction8? {
        guard vector.dx != 0 || vector.dy != 0 else { return nil }

        let angleFromSouth = normalizedAngle(atan2(vector.dy, vector.dx) - .pi / 2)
        let sectorWidth = CGFloat.pi / 4

        // Round to the nearest sector, ties going to the *next* sector
        // clockwise (i.e. round-half-up, since `angleFromSouth` is always
        // non-negative). `atan2`-derived angles land a hair off an exact
        // half-sector boundary due to floating-point rounding in the trig
        // pipeline (e.g. 2.499999999999997 instead of 2.5), which would
        // make plain `.rounded()` round *down* at a boundary depending on
        // which side of the true value the error happens to fall. Nudging
        // by a tiny epsilon before flooring makes the tie-break direction
        // deterministic regardless of that noise.
        let ratio = angleFromSouth / sectorWidth
        let epsilon: CGFloat = 1e-9
        let sectorIndex = Int(floor(ratio + 0.5 + epsilon)) % clockwiseFromSouth.count

        return clockwiseFromSouth[sectorIndex]
    }

    /// Bins a **SpriteKit** movement vector (y-up: a node velocity, a scene
    /// coordinate delta, a stick reading in scene space) into one of the 8
    /// sectors.
    ///
    /// Every gameplay consumer of this type holds a y-up vector - the player
    /// node in this story, the raccoons in CYBERPUN-17-8 - while
    /// `from(vector:)` reads the y-down pixel-space convention the asset
    /// side of this codebase uses. Leaving the two call sites to remember
    /// "negate `dy` first" is an unenforced convention of exactly the kind
    /// that produced this repo's lane-orientation saga, and forgetting it is
    /// silent: north/south flip while east/west stay right, so a
    /// facing-vs-movement bug looks like an art problem. The flip therefore
    /// lives here, once, where a call site cannot skip it.
    ///
    /// Returns `nil` for a zero-magnitude vector for the same reason
    /// `from(vector:)` does: no facing information, so the caller keeps its
    /// current facing.
    static func from(spriteKitVector vector: CGVector) -> Direction8? {
        from(vector: CGVector(dx: vector.dx, dy: -vector.dy))
    }

    /// The 8 cases in the exact clockwise-from-south order `from(vector:)`
    /// indexes into. This is purely a binning helper \u2014 it has no bearing on
    /// any asset's row layout, which is free to order its rows however the
    /// art was authored (see `PlayerSpriteSheet`'s S/SE/E/NE/N ordering).
    private static let clockwiseFromSouth: [Direction8] = [
        .south, .southwest, .west, .northwest, .north, .northeast, .east, .southeast,
    ]

    /// Wraps `angle` (radians) into `[0, 2\u03c0)`.
    private static func normalizedAngle(_ angle: CGFloat) -> CGFloat {
        let twoPi = CGFloat.pi * 2
        var result = angle.truncatingRemainder(dividingBy: twoPi)
        if result < 0 { result += twoPi }
        return result
    }
}
