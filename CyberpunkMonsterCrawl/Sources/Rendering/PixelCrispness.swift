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
}
