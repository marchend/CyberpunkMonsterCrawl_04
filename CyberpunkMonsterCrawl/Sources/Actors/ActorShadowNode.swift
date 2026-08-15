import CoreGraphics
import SpriteKit

/// A reusable drop-shadow node: a flat, semi-transparent 2:1 ellipse drawn
/// as a distinct `SKShapeNode`, never baked into an actor's body texture.
///
/// **Reused by future actors, not just the player.** `PlayerNode` (this PR,
/// `CYBERPUN-17-6-t2`) is the first consumer; the raccoon swarm
/// (`CYBERPUN-17-8`) is expected to add one of these as a sibling of its own
/// body sprite the same way, which is why this type carries no
/// player-specific knowledge (no `PlayerSpriteSheet` coupling, no
/// `Direction8`) -- a shadow does not change shape with facing.
///
/// **2:1, matching the world's isometric diamond aspect** (`docs/bootstrap.md`
/// section 4: 96x48px tile diamonds are themselves 2:1) so a flat ellipse
/// under an actor reads as lying on the isometric ground plane rather than
/// as an arbitrary blob.
///
/// **Positioning contract:** a caller adds this as a sibling of the owning
/// actor's body sprite, at `position == .zero` in the actor's own node space
/// -- i.e. at the actor's anchor. That is what "positioned at the owning
/// actor's anchor" means in practice: the actor's body sprite already uses
/// an `anchorPoint` that puts its feet at the actor node's local origin (see
/// `PlayerSpriteSheet.anchorPointNormalized` / `PlayerNode`), so a shadow
/// left at `.zero` sits exactly under those feet without this type needing
/// to know anything about the body's own geometry.
///
/// **z-order:** this node's own `zPosition` is left at `0` by `init` -- the
/// owning actor node (`PlayerNode`) is responsible for giving it a small
/// *positive* offset relative to the ground plane and a smaller one than its
/// own body, so the shadow reads as "on the ground, under the body" without
/// this type needing to know the actor's absolute depth.
final class ActorShadowNode: SKShapeNode {

    /// Default shadow width in points, used when a caller does not need a
    /// size tied to a specific actor's own footprint.
    static let defaultWidth: CGFloat = 20

    /// Width:height ratio every shadow this type draws is drawn at -- the
    /// same 2:1 ratio as the world's isometric tile diamonds.
    static let aspectRatio: CGFloat = 2

    /// This shadow's width, in points.
    let width: CGFloat

    /// This shadow's height, in points: always `width / aspectRatio`, so the
    /// 2:1 ratio can never drift out of sync with `width` at a call site.
    var height: CGFloat { width / Self.aspectRatio }

    /// The fill colour every shadow uses: a soft, semi-transparent black.
    /// Not fully opaque, so ground detail can still be seen faintly through
    /// it -- a flat black disc would read as a hole in the ground instead of
    /// a shadow.
    static let shadowFillColor = SKColor.black.withAlphaComponent(0.35)

    /// - Parameter width: This shadow's width in points; height is derived
    ///   from `aspectRatio`. Defaults to `defaultWidth`.
    init(width: CGFloat = ActorShadowNode.defaultWidth) {
        self.width = width
        super.init()

        let size = CGSize(width: width, height: width / Self.aspectRatio)
        let rect = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
        path = CGPath(ellipseIn: rect, transform: nil)
        fillColor = Self.shadowFillColor
        strokeColor = .clear
        lineWidth = 0
        // No physics body, no user interaction -- purely decorative.
        isUserInteractionEnabled = false
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("ActorShadowNode does not support NSCoder deserialization.")
    }
}
