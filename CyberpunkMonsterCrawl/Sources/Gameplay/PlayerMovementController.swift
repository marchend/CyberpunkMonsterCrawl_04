import CoreGraphics
import Foundation

/// Pure, SpriteKit-independent computation of the player's per-frame
/// movement outputs (`frameDisplacement`, `facingVector`, `isMoving`) from
/// the floating thumbstick's `StickState` plus elapsed time.
///
/// **Naming note.** The movement output is called `frameDisplacement`, not
/// `velocity`, because `deltaTime` is already folded into it: it is the
/// distance to move *this frame*, not a per-second rate. A property named
/// `velocity` invites the next caller to write `position += velocity * dt`
/// and apply the timestep twice, and a doc comment is a weak defence
/// against that. Naming it for what it actually is makes the trap
/// structural rather than documented-against -- the same discipline
/// `TilePoint` applies to keeping tile space and screen space apart.
///
/// **This is the real replacement for the demo cycle.** Where the story's
/// now-deleted `PlayerScaffoldingDriver` synthesised a scripted vector with
/// no stick at all, this type derives the same *shape* of output (a
/// SpriteKit-space facing vector, plus a tile-space displacement) from a
/// real `StickState` -- which is what let `GameScene`'s call site swap
/// source without a rewrite. Building this as a small,
/// pure type with no `SKNode`/`SKScene` reference is what makes it
/// exhaustively unit-testable without a live scene.
///
/// **Where this fits (`CYBERPUN-17-7`).** This is the input *consumer* half
/// of the story: given a `StickState` and the render clock, it computes what
/// the player's displacement/facing/moving state *should be*. It stays pure
/// by design -- it never touches `PlayerNode.position` and never resolves
/// building collision; the scene owns both. It is wired into a real build:
/// `GameScene.advanceMovementAndCamera(currentTime:)` calls
/// `update(stickState:currentTime:)` with `GameScene.thumbstick`'s live
/// reading every frame, feeds `frameDisplacement` through
/// `CollisionResolver.resolve(...)`, commits the resolved position and depth
/// to the mounted `PlayerNode`, and drives `CameraController` from that same
/// position. See `FloatingThumbstickNode`'s doc comment for the producer
/// side.
///
/// **What is still outstanding on the story, and where it is tracked.** The
/// movement/collision/camera wiring above is done; two items are not, and
/// neither is given an invented ticket ID here. (1) The run's spawn junction
/// is identical on every run, because nothing in the app writes
/// `GameScene.worldSeed` -- see `GameScene.spawnTilePosition()` for the full
/// note. (2) `GameplayScreenNode`'s `SCAFFOLDING(CYBERPUN-17-7)`
/// `gameplay.container` marker is still mounted, because no durable in-run
/// content exists for its two assertions to re-point at yet -- see that
/// type's doc comment. Both are tracked on the `CYBERPUN-17-7` story itself,
/// requested as follow-ups on its tasks. The authoritative list of what is
/// implemented versus still outstanding for this story is the
/// `CYBERPUN-17-7` entry in AGENT.md/CLAUDE.md; read that rather than
/// inferring the remaining scope from these doc comments.
///
/// Both halves now share one production call site, and
/// `ThumbstickMovementSeamTests` still drives a real
/// `FloatingThumbstickNode` drag straight into this controller: the producer
/// and consumer cannot silently disagree about y-sign, unit-vs-raw direction
/// or dead-zone semantics without turning a test red, whatever the scene
/// does.
final class PlayerMovementController {

    /// On-screen distance (points) covered by a one-tile step along a single
    /// tile axis on the 96x48 projection -- `hypot(48, 24)`. Only used to
    /// derive `maxPointsPerSecond`, so the screen-space speed constant is
    /// visibly anchored to the projection's own geometry rather than being
    /// an unexplained magic number.
    private static let pointsPerTileAxisStep = hypot(
        IsometricProjection.tileHalfWidth,
        IsometricProjection.tileHalfHeight
    )

    /// **On-screen** points per second the player covers at full stick
    /// deflection (`StickState.magnitude == 1`) -- and, unlike a tile-space
    /// speed constant, the same in *every* heading.
    ///
    /// Normalizing in tile space (what this controller used to do) makes the
    /// player's speed constant in tile units, which on a 2:1 projection
    /// means the on-screen speed varies by exactly 2x with heading: a full
    /// deflection sideways covers `hypot(96, 0)`-worth of screen per tile
    /// unit while a full deflection up the screen covers only `hypot(0,
    /// 48)`-worth. That is a feel bug no *value* of a tiles-per-second
    /// constant can fix, because it is a ratio. Pinning the speed in screen
    /// space instead makes a full stick push travel the same number of
    /// points per second whichever way it points, which is what a player
    /// actually perceives.
    ///
    /// Tuning remains a later PR's concern (once collision/camera exist to
    /// feel it against); the value is chosen to preserve the previous
    /// 3-tiles-per-second feel *along a tile axis* so this change is a pure
    /// heading-consistency fix and not a stealth speed change.
    static let maxPointsPerSecond: Double = 3 * pointsPerTileAxisStep

    /// Upper bound (seconds) on any single frame's `deltaTime`, equivalent
    /// to one 20fps frame.
    ///
    /// `max(0, ...)` alone only guards the *lower* end. A backgrounded app,
    /// a debugger pause, or the known `.gameplay`-entry generation stall
    /// (`ChunkStreamingManager.updateCamera` still generates all 49 chunks
    /// synchronously -- see the `GroundPlaneStreamer` note in AGENT.md) can
    /// hand `update` a multi-second gap, which without a cap becomes a
    /// single-frame displacement of many tiles. That is harmless while
    /// nothing applies the displacement, but it turns into a tunnelling bug
    /// the moment collision lands: a footprint-based resolver that tests (or
    /// even sweeps) the destination tile will happily step the player
    /// straight through a building if one frame moves 15 tiles. Capping
    /// here, where the delta is derived, means the guarantee exists *before*
    /// the resolver is written against it rather than being retrofitted
    /// after the first tunnelling report.
    ///
    /// The cost of the cap is that the player moves slightly slower than
    /// wall-clock through a stall, which is the standard and far cheaper
    /// trade -- a dropped fraction of a second of travel versus a player
    /// teleported inside geometry.
    static let maxFrameDelta: TimeInterval = 1.0 / 20.0

    /// The `currentTime` most recently passed to `update`, used to derive
    /// this call's `deltaTime`. `nil` until the first call, so the very
    /// first frame always sees `deltaTime == 0` rather than a huge,
    /// meaningless delta measured against an arbitrary process-start clock
    /// -- the same convention `GameScene.advancePlayer(currentTime:)`
    /// already uses for `lastFrameTime`.
    private(set) var lastFrameTimestamp: TimeInterval?

    /// This frame's tile-space displacement: the stick's screen-space
    /// (SpriteKit, y-up) direction scaled to `maxPointsPerSecond *
    /// magnitude * deltaTime` points **while still in screen space**, then
    /// converted through `IsometricProjection.screenToTile(_:)` -- the
    /// project's existing inverse isometric transform, not a duplicate of
    /// it -- so "up the screen" maps to the tile-space diagonal that
    /// actually renders as "up" once projected, rather than to a naive
    /// tile-space unit step.
    ///
    /// Because `screenToTile` is linear, projecting an already-scaled screen
    /// step preserves that screen distance exactly, so the player's
    /// *rendered* speed is identical in every heading. The earlier version
    /// re-normalized in tile space instead, which pinned the speed in tile
    /// units and therefore made a sideways push travel exactly 2x as far
    /// per second on screen as an upward one -- see `maxPointsPerSecond`.
    ///
    /// Callers apply this directly to a tile-space position; there is no
    /// further per-caller deltaTime multiplication needed. It is exactly
    /// `.zero` whenever `StickState.isBeyondDeadZone` is `false`, and also
    /// on any frame with `deltaTime == 0` -- in particular the controller's
    /// very first `update` call -- regardless of how far the stick is
    /// deflected, since zero elapsed time means zero displacement actually
    /// happened.
    private(set) var frameDisplacement: CGVector = .zero

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
    /// independent of this frame's raw stick deflection or displacement.
    private(set) var isMoving = false

    init() {}

    /// Advances the controller by one frame: `stickState` is this frame's
    /// floating-thumbstick reading, and `currentTime` is the same
    /// monotonically-increasing render clock `GameScene.update(_:)` already
    /// threads through `advancePlayer(currentTime:)`.
    func update(stickState: StickState, currentTime: TimeInterval) {
        let deltaTime = lastFrameTimestamp.map { min(Self.maxFrameDelta, max(0, currentTime - $0)) } ?? 0
        lastFrameTimestamp = currentTime

        isMoving = stickState.isBeyondDeadZone

        if stickState.isBeyondDeadZone {
            facingVector = stickState.direction
        }

        frameDisplacement = Self.tileDisplacement(
            forStickDirection: stickState.direction,
            magnitude: stickState.magnitude,
            isBeyondDeadZone: stickState.isBeyondDeadZone,
            deltaTime: deltaTime
        )
    }

    /// The pure conversion `update(stickState:currentTime:)` delegates to:
    /// a SpriteKit-space stick direction -> a tile-space displacement for
    /// `deltaTime` seconds at `maxPointsPerSecond * magnitude`.
    ///
    /// The scaling happens in **screen** space, *before* the projection, and
    /// the result is not re-normalized afterwards: `screenToTile` is linear,
    /// so projecting an already-correctly-scaled screen step yields the tile
    /// step whose rendered length is exactly that screen distance. This is
    /// the whole reason the player no longer moves twice as fast sideways as
    /// upward -- see `maxPointsPerSecond`.
    private static func tileDisplacement(
        forStickDirection direction: CGVector,
        magnitude: CGFloat,
        isBeyondDeadZone: Bool,
        deltaTime: TimeInterval
    ) -> CGVector {
        guard isBeyondDeadZone, deltaTime > 0, direction != .zero else { return .zero }

        // `StickState.direction` is documented unit-length, but normalizing
        // here keeps the screen-space distance exact for any caller that
        // hands over a merely-nonzero vector.
        let directionLength = hypot(Double(direction.dx), Double(direction.dy))
        guard directionLength > 0 else { return .zero }

        let screenDistance = maxPointsPerSecond * Double(magnitude) * deltaTime
        let screenStep = CGPoint(
            x: CGFloat(Double(direction.dx) / directionLength * screenDistance),
            y: CGFloat(Double(direction.dy) / directionLength * screenDistance)
        )

        let tileStep = IsometricProjection.screenToTile(screenStep)
        return CGVector(dx: CGFloat(tileStep.x), dy: CGFloat(tileStep.y))
    }
}
