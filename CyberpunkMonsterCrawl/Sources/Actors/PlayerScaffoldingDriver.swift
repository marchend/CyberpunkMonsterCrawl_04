import CoreGraphics
import Foundation

/// SCAFFOLDING(CYBERPUN-17-7): a temporary, deterministic movement
/// generator that cycles the mounted player through all 8 `Direction8`
/// facings (plus a trailing idle beat) so `PlayerNode`'s facing/animation
/// state machine is demonstrably exercised in a running build -- ahead of
/// the real floating thumbstick, which is that story's own deliverable.
///
/// **Why this exists at all:** `GameScene.startPlayer()` mounts a real
/// `PlayerNode` (`CYBERPUN-17-6-t2`), but until `CYBERPUN-17-7` lands there
/// is no input to move it, so a QA pass or a demo build would otherwise show
/// a player standing frozen on frame 0 facing south for the entire
/// `.gameplay` episode -- indistinguishable from a player that never got
/// wired up at all. This driver is the difference between "looks broken"
/// and "visibly walking, ahead of real input existing".
///
/// **Timer, not a `Timer`:** "timer-based" here means a `deltaTime`
/// accumulator driven from `GameScene.update(_:)`'s own render-clock delta
/// (the same clock `advancePlayer(currentTime:)` already derives), not a
/// Foundation `Timer`/`DispatchSourceTimer` on a wall clock. That keeps this
/// type synchronous and deterministic under test -- `advance(deltaTime:)`
/// is a pure step function of its input, with no run-loop or async
/// scheduling for a test to race against.
///
/// **Zero coupling beyond `PlayerNode`'s public API.** This type holds a
/// `PlayerNode` reference and calls nothing but its public
/// `update(deltaTime:movementVector:)` -- no `GameScene`, no `SKView`, no
/// world/camera state. That is deliberate: `CYBERPUN-17-7` ("wire the
/// floating thumbstick, player movement, building collision and camera")
/// should be able to delete this one file, plus its construction/drive call
/// sites in `GameScene`, without touching anything else.
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

    private let player: PlayerNode

    /// The `cycle` index currently being driven. Exposed for tests that want
    /// to assert the cycle's exact phase rather than only its visible
    /// effect on `player`.
    private(set) var stepIndex = idleIndex

    /// Seconds elapsed since `stepIndex` last advanced.
    private var elapsedInCurrentStep: TimeInterval = 0

    init(player: PlayerNode) {
        self.player = player
    }

    /// Advances the cycle by `deltaTime` and drives `player`'s public
    /// `update` API with whichever cycle entry is current *after* that
    /// advance -- so a `deltaTime` that crosses one or more step boundaries
    /// (a long frame, or a caller driving several seconds at once in a
    /// test) still lands on the correct entry rather than the one it left.
    func advance(deltaTime: TimeInterval) {
        elapsedInCurrentStep += deltaTime
        while elapsedInCurrentStep >= Self.secondsPerStep {
            elapsedInCurrentStep -= Self.secondsPerStep
            stepIndex = (stepIndex + 1) % Self.cycle.count
        }
        player.update(deltaTime: deltaTime, movementVector: Self.cycle[stepIndex])
    }
}
