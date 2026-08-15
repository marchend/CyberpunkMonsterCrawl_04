import CoreGraphics
import Foundation

#if DEBUG
/// SCAFFOLDING(CYBERPUN-17-7): a temporary, deterministic **movement-vector
/// generator** that cycles through all 8 `Direction8` facings (plus a
/// trailing idle beat) so `PlayerNode`'s facing/animation state machine can
/// be demonstrably exercised in a running DEBUG build -- ahead of the real
/// floating thumbstick, which is that story's own deliverable.
///
/// **DEBUG-only, and opt-in.** The whole type is compiled out of a Release
/// build (`#if DEBUG`), and `GameScene.debugPlayerDemoEnabled` is `false`
/// by default, exactly like the sibling `SCAFFOLDING(CYBERPUN-17-7)` debug
/// camera pan in `GameScene`. A shipped build therefore physically cannot
/// auto-walk the player: a scripted S->SE->E->NE->N->NW->W->SW lap with no
/// input is a worse "looks broken" than the frozen frame-0 it is meant to
/// diagnose, so this is a developer aid rather than shipped behaviour.
///
/// **Why this exists at all:** `GameScene.startPlayer()` mounts a real
/// `PlayerNode` (`CYBERPUN-17-6-t2`), but until `CYBERPUN-17-7` lands there
/// is no input to move it, so a manual QA pass would otherwise show a player
/// standing frozen on frame 0 facing south for the entire `.gameplay`
/// episode -- indistinguishable from a player that never got wired up at
/// all. Flipping `debugPlayerDemoEnabled` on a DEBUG build is the difference
/// between "looks broken" and "visibly walking, ahead of real input".
///
/// **Timer, not a `Timer`:** "timer-based" here means a `deltaTime`
/// accumulator driven from `GameScene.update(_:)`'s own render-clock delta
/// (the same clock `advancePlayer(currentTime:)` already derives), not a
/// Foundation `Timer`/`DispatchSourceTimer` on a wall clock. That keeps this
/// type synchronous and deterministic -- `currentVector(advancedBy:)` is a
/// pure step function of its input, with no run-loop or async scheduling.
///
/// **Zero coupling to anything.** This type holds no `PlayerNode`, no
/// `GameScene`, no `SKView` and no world/camera state: it only answers "what
/// movement vector is the demo cycle on now?". The scene stays the one
/// caller of `PlayerNode.update(deltaTime:movementVector:)`, so
/// `CYBERPUN-17-7` swaps this one expression for the resolved stick reading
/// and deletes this file -- the production call site survives the deletion
/// rather than disappearing with it.
///
/// **Cycle order**, per the story: `south -> southeast -> east -> northeast
/// -> north -> northwest -> west -> southwest -> idle`, then repeats. The
/// driver starts on the trailing **idle** entry (not `south`) so a
/// freshly-spawned player stands still -- matching `PlayerNode`'s own
/// default idle-at-spawn behaviour -- until the first full
/// `secondsPerStep` interval has actually elapsed; only then does the cycle
/// begin advancing through the 8 facings.
final class PlayerScaffoldingDriver {

    /// Seconds each entry in `cycle` is held before advancing to the next.
    /// Slow enough that a manual observer can see and name every facing,
    /// fast enough that a full lap (9 entries) finishes in under 10 seconds.
    static let secondsPerStep: TimeInterval = 1

    /// One full lap: the 8 `Direction8` facings in the story's specified
    /// order, expressed as unit-length **SpriteKit-space** (y-up) vectors --
    /// the same space `PlayerNode.update(deltaTime:movementVector:)` and
    /// `Direction8.from(spriteKitVector:)` read -- followed by a trailing
    /// idle (`.zero`) beat.
    static let cycle: [CGVector] = [
        CGVector(dx: 0, dy: -1), // south
        CGVector(dx: 1, dy: -1), // southeast
        CGVector(dx: 1, dy: 0), // east
        CGVector(dx: 1, dy: 1), // northeast
        CGVector(dx: 0, dy: 1), // north
        CGVector(dx: -1, dy: 1), // northwest
        CGVector(dx: -1, dy: 0), // west
        CGVector(dx: -1, dy: -1), // southwest
        .zero, // idle
    ]

    /// `cycle`'s index of the trailing idle entry -- both the driver's
    /// starting position and where a full lap wraps back around to.
    private static let idleIndex = cycle.count - 1

    /// The `cycle` index currently being driven.
    private(set) var stepIndex = idleIndex

    /// Seconds elapsed since `stepIndex` last advanced.
    private var elapsedInCurrentStep: TimeInterval = 0

    /// Advances the cycle by `deltaTime` and returns whichever cycle entry
    /// is current *after* that advance -- so a `deltaTime` that crosses one
    /// or more step boundaries (a long frame, or a caller driving several
    /// seconds at once) still lands on the correct entry rather than the one
    /// it left.
    ///
    /// Returning the vector (rather than driving a `PlayerNode` with it) is
    /// what keeps the scene as the caller of
    /// `PlayerNode.update(deltaTime:movementVector:)`.
    func currentVector(advancedBy deltaTime: TimeInterval) -> CGVector {
        elapsedInCurrentStep += deltaTime
        while elapsedInCurrentStep >= Self.secondsPerStep {
            elapsedInCurrentStep -= Self.secondsPerStep
            stepIndex = (stepIndex + 1) % Self.cycle.count
        }
        return Self.cycle[stepIndex]
    }
}
#endif
