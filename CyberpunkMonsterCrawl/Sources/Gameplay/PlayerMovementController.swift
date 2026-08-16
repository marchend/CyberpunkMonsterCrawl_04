import CoreGraphics
import Foundation

/// Pure, SpriteKit-independent computation of the player's per-frame
/// movement outputs (`velocity`, `facingVector`, `isMoving`) from the
/// floating thumbstick's `StickState` plus elapsed time.
///
/// **This is the real replacement for the demo cycle.** Where
/// `SCAFFOLDING(CYBERPUN-17-7)`'s `PlayerScaffoldingDriver` synthesises a
/// scripted vector with no stick at all, this type derives the same *shape*
/// of output (a SpriteKit-space facing vector, plus a tile-space
/// displacement) from a real `StickState` -- so `GameScene`'s eventual call
/// site needs only a source swap, not a rewrite. Building this as a small,
/// pure type with no `SKNode`/`SKScene` reference is what makes it
/// exhaustively unit-testable without a live scene.
///
/// **Scope of this PR (`CYBERPUN-17-7` PR 1).** This is the input
/// *consumer* half of the story: given a `StickState` and the render clock,
/// it computes what the player's velocity/facing/moving state *should be*.
/// It does not touch `PlayerNode.position`, does not resolve building
/// collision, and is not yet wired into `GameScene.update(_:)` in place of
/// `PlayerScaffoldingDriver` -- that wiring (which also deletes the
/// `SCAFFOLDING(CYBERPUN-17-7)` demo driver and debug camera pan) lands in a
/// later PR of this same story, alongside collision and camera-follow. See
/// `FloatingThumbstickNode`'s own doc comment for the same scope note on the
/// producer side.
final class PlayerMovementController {

    /// World-space (tile) units per second the player covers at full stick
    /// deflection (`StickState.magnitude == 1`). Tuning is a later PR's
    /// concern (once collision/camera exist to feel it against); this value
    /// only needs to be positive and finite for the conversion math below.
    static let maxTilesPerSecond: Double = 3.0

    /// The `currentTime` most recently passed to `update`, used to derive
    /// this call's `deltaTime`. `nil` until the first call, so the very
    /// first frame always sees `deltaTime == 0` rather than a huge,
    /// meaningless delta measured against an arbitrary process-start clock
    /// -- the same convention `GameScene.advancePlayer(currentTime:)`
    /// already uses for `lastFrameTime`.
    private(set) var lastFrameTimestamp: TimeInterval?

    /// This frame's tile-space displacement: the stick's screen-space
    /// (SpriteKit, y-up) direction converted through
    /// `IsometricProjection.screenToTile(_:)` -- the project's existing
    /// inverse isometric transform, not a duplicate of it -- so "up the
    /// screen" maps to the tile-space diagonal that actually renders as
    /// "up" once projected, rather than to a naive tile-space unit step.
    /// The converted direction is re-normalized before being scaled by
    /// `maxTilesPerSecond * magnitude * deltaTime`, so the projection only
    /// ever decides *which way* the player moves in tile space, never how
    /// far -- that stays under this controller's own speed constant.
    ///
    /// Callers apply this directly to a tile-space position; there is no
    /// further per-caller deltaTime multiplication needed. It is exactly
    /// `.zero` whenever `StickState.isBeyondDeadZone` is `false`, and also
    /// on any frame with `deltaTime == 0` -- in particular the controller's
    /// very first `update` call -- regardless of how far the stick is
    /// deflected, since zero elapsed time means zero displacement actually
    /// happened.
    private(set) var velocity: CGVector = .zero

    /// The player's current facing, expressed the same way `PlayerNode`
    /// consumes movement (`Direction8.from(spriteKitVector:)`'s SpriteKit
    /// y-up input space) -- the stick's own raw screen-space direction,
    /// deliberately *not* run through the isometric projection: character
    /// facing art is authored against on-screen octants, exactly like every
    /// other `Direction8` consumer in this codebase, independent of which
    /// tile-space diagonal the isometric projection resolves the same input
    /// to for movement.
    ///
    /// Persists across a frame where the stick is inside its dead zone --
    /// exactly like `PlayerNode`'s own idle-freezes-last-facing behaviour --
    /// because facing tracks the **movement** stick alone; there is no aim
    /// stick in this story to override it. Defaults to south (`(0, -1)`),
    /// matching `PlayerNode`'s own default facing before any input arrives.
    private(set) var facingVector = CGVector(dx: 0, dy: -1)

    /// `true` only while `StickState.isBeyondDeadZone` is `true`. Exposed as
    /// stable, public API: the upcoming auto-fire/weapons story
    /// (`CYBERPUN-17-9`) reads this to gate movement-dependent behaviour,
    /// independent of this frame's raw stick deflection or velocity.
    private(set) var isMoving = false

    init() {}

    /// Advances the controller by one frame: `stickState` is this frame's
    /// floating-thumbstick reading, and `currentTime` is the same
    /// monotonically-increasing render clock `GameScene.update(_:)` already
    /// threads through `advancePlayer(currentTime:)`.
    func update(stickState: StickState, currentTime: TimeInterval) {
        let deltaTime = lastFrameTimestamp.map { max(0, currentTime - $0) } ?? 0
        lastFrameTimestamp = currentTime

        isMoving = stickState.isBeyondDeadZone

        if stickState.isBeyondDeadZone {
            facingVector = stickState.direction
        }

        velocity = Self.tileVelocity(
            forStickDirection: stickState.direction,
            magnitude: stickState.magnitude,
            isBeyondDeadZone: stickState.isBeyondDeadZone,
            deltaTime: deltaTime
        )
    }

    /// The pure conversion `update(stickState:currentTime:)` delegates to:
    /// a SpriteKit-space stick direction -> a tile-space displacement for
    /// `deltaTime` seconds at `maxTilesPerSecond * magnitude`.
    private static func tileVelocity(
        forStickDirection direction: CGVector,
        magnitude: CGFloat,
        isBeyondDeadZone: Bool,
        deltaTime: TimeInterval
    ) -> CGVector {
        guard isBeyondDeadZone, deltaTime > 0, direction != .zero else { return .zero }

        let tileDirection = IsometricProjection.screenToTile(CGPoint(x: direction.dx, y: direction.dy))
        let tileDirectionLength = hypot(tileDirection.x, tileDirection.y)
        guard tileDirectionLength > 0 else { return .zero }

        let displacement = maxTilesPerSecond * Double(magnitude) * deltaTime
        let scale = displacement / tileDirectionLength
        return CGVector(dx: CGFloat(tileDirection.x * scale), dy: CGFloat(tileDirection.y * scale))
    }
}
