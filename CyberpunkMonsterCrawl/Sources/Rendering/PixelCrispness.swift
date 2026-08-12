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
///  2. `xScale`/`yScale` are whole integers, floored at `1` so a degenerate
///     scale never collapses a sprite to nothing;
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

    /// Rounds to the nearest whole integer, floored at `1`.
    private static func wholeScale(_ scale: CGFloat) -> CGFloat {
        max(1, scale.rounded())
    }
}
