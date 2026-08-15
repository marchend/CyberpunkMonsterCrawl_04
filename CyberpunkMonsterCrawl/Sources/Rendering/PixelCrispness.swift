import SpriteKit

/// Shared finalization pass enforcing `docs/bootstrap.md` section 1's "1x
/// art only, integer scaling" rule on any `SKSpriteNode`, not just on the
/// texture-load path `TextureLoading` already covers.
///
/// A correctly nearest-filtered texture can still blur on screen if the node
/// carrying it is scaled by a non-integer factor, or sits at a fractional
/// point — the device's own compositor resamples across neighbouring pixels
/// in both of those cases exactly as bilinear texture filtering would.
/// `PixelCrispness.apply(to:)` is the single call site that finalizes a node
/// for pixel-crisp display, so every consumer (ground tiles today; buildings,
/// actors, bullets, pickups etc. in later PRs) enforces the same three
/// checks instead of reproducing them ad hoc:
///  1. the node's texture filters `.nearest` with mipmaps disabled;
///  2. `xScale`/`yScale` are whole integers whose *magnitude* is floored at
///     `1` so a degenerate scale never collapses a sprite to nothing, while
///     a negative scale keeps its sign: `xScale = -1` is SpriteKit's
///     standard horizontal-mirror idiom (and a plausible one here, since the
///     8-direction walk sheets can be halved into mirrored pairs), so
///     clamping it to `+1` would silently render the sprite facing the wrong
///     way with no error;
///  3. `position` is snapped to the nearest whole point — this game's world
///     runs at integer isometric tile coordinates, so any drift off a whole
///     point is exactly the sub-pixel seam/blur nearest filtering exists to
///     avoid.
enum PixelCrispness {
    /// Finalizes `node` in place. Safe to call more than once (idempotent):
    /// re-rounding an already-integer scale or position is a no-op.
    static func apply(to node: SKSpriteNode) {
        if let texture = node.texture {
            texture.filteringMode = .nearest
            texture.usesMipmaps = false
        }
        node.xScale = wholeScale(node.xScale)
        node.yScale = wholeScale(node.yScale)
        node.position = CGPoint(
            x: node.position.x.rounded(),
            y: node.position.y.rounded()
        )
    }

    /// Rounds `scale`'s **magnitude** to the nearest whole integer, floored
    /// at `1`, and re-applies the original sign.
    ///
    /// Clamping the signed value (`max(1, scale.rounded())`) would discard
    /// the sign, not just the fractional part: a mirrored sprite
    /// (`xScale = -1`) would come back as `+1` and render un-mirrored. The
    /// integer-scaling rule this helper enforces is about *magnitude*
    /// (mirroring is exact and resamples nothing), so sign is preserved and
    /// only the magnitude is rounded and floored.
    ///
    /// A scale of exactly `0` has no sign to preserve and would collapse the
    /// sprite, so it takes the floor's `+1`.
    private static func wholeScale(_ scale: CGFloat) -> CGFloat {
        let magnitude = max(1, abs(scale).rounded())
        return scale < 0 ? -magnitude : magnitude
    }

    // MARK: - Camera-driven snapping (CYBERPUN-17-6-t3)

    /// Snaps `position` to the nearest whole **device pixel** at `scale`
    /// (a `UIView`/`SKView`'s `contentScaleFactor` -- `2` at `@2x`, `3` at
    /// `@3x`), rather than merely the nearest whole *point* the way
    /// `apply(to:)` above does.
    ///
    /// At today's integer device scales a whole-point snap already lands on
    /// a device pixel boundary (every whole point is exactly 2 or 3 whole
    /// device pixels), so for a node whose position is only ever assigned
    /// from a fresh, un-drifted computation the two are equivalent. This
    /// entry point exists for the case `apply(to:)` does not cover: a
    /// position **derived through a moving camera** (`GameScene
    /// .startPlayer()`'s screen position, re-derived from tile space on
    /// every camera update), where repeated floating-point arithmetic can
    /// drift the result a fraction of a device pixel off a whole point even
    /// though it is still, numerically, "close enough" to look whole. Taking
    /// `scale` explicitly (rather than assuming it) also means this stays
    /// correct if a future consumer ever runs at a non-integer scale.
    ///
    /// A non-positive `scale` has no meaningful pixel grid to snap to, so
    /// `position` is returned unchanged rather than dividing by zero.
    static func snappedPosition(for position: CGPoint, scale: CGFloat) -> CGPoint {
        guard scale > 0 else { return position }
        return CGPoint(
            x: (position.x * scale).rounded() / scale,
            y: (position.y * scale).rounded() / scale
        )
    }

    /// Whether `scale` is a whole integer -- the same "whole-integer scale"
    /// rule `apply(to:)` enforces on a node's `xScale`/`yScale`, exposed as a
    /// standalone predicate so a caller (or a test simulating a `@2x`/`@3x`
    /// device scale) can assert it directly without constructing a live
    /// `SKSpriteNode`.
    static func isIntegerScale(_ scale: CGFloat) -> Bool {
        scale.truncatingRemainder(dividingBy: 1) == 0
    }
}
