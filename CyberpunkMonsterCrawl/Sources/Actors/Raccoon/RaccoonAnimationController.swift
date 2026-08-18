import CoreGraphics
import Foundation

/// Which of the raccoon's two sheets is currently playing.
enum RaccoonAnimationState: Equatable {
    case walk
    case attack
}

/// The raccoon's walk/attack frame-timing + facing state machine, over
/// `sprite_raccoon_walk` / `sprite_raccoon_attack`
/// (`AtlasSheet.raccoonWalk` / `.raccoonAttack`: both 192x224px, 48x28 cell,
/// 4 columns x 8 rows \u2014 `CYBERPUN-17-8`).
///
/// Mirrors `PlayerSpriteSheet` (measured row/anchor table) and
/// `PlayerAnimator` (pure frame-timing math)'s split responsibilities, but
/// bundled into one type and given a small amount of instance state: unlike
/// the player, a raccoon has to switch between two *separate* sheets (walk
/// vs. attack) at two different frame rates, which is a genuine state
/// machine rather than a single always-looping cycle.
///
/// **Scope of this PR (`CYBERPUN-17-8-t1`).** This is the rendering/
/// animation-state surface only: `setDirection(_:)` / `playWalk()` /
/// `playAttack()` / `advance(deltaTime:)` are the public seam a later PR's
/// seek/attack behaviour drives every frame. No caller of its own outside
/// `RaccoonNode` and its tests lands with this PR.
final class RaccoonAnimationController {

    // MARK: - Measured sheet contract

    /// Both `sprite_raccoon_walk` and `sprite_raccoon_attack` share the
    /// exact same grid (see the type doc comment) \u2014 read once, off the walk
    /// sheet, rather than kept as a second copy of the numbers that could
    /// drift from `AtlasSheet`.
    static var cellSize: CGSize {
        guard let cellSize = AtlasSheet.raccoonWalk.sheet.cellSize else {
            preconditionFailure(
                "AtlasSheet.raccoonWalk declares no cellSize, so RaccoonAnimationController has "
                    + "no cell geometry to read."
            )
        }
        return cellSize
    }

    /// 4 columns (frames per row), shared by both the walk and attack
    /// sheets.
    static var frameCount: Int { AtlasSheet.raccoonWalk.sheet.columns }

    /// One row's placement in the sheet, plus whether that row must be
    /// drawn mirrored \u2014 the same shape `PlayerSpriteSheet.RowMapping` uses.
    struct RowMapping: Equatable {
        let row: Int
        let mirrored: Bool
    }

    /// The raccoon's `Direction8 -> (row, mirrored)` table: 5 rows directly
    /// authored (south sweeping through north on the sheet's east side), the
    /// remaining 3 (southwest/west/northwest) mirrored from the row sharing
    /// their vertical component \u2014 the exact convention
    /// `PlayerSpriteSheet.rowMappingTable` uses, per the story's own framing
    /// ("same `Direction8` mapping the player uses").
    static let rowMappingTable: [Direction8: RowMapping] = [
        .south: RowMapping(row: 0, mirrored: false),
        .southeast: RowMapping(row: 1, mirrored: false),
        .east: RowMapping(row: 2, mirrored: false),
        .northeast: RowMapping(row: 3, mirrored: false),
        .north: RowMapping(row: 4, mirrored: false),
        .southwest: RowMapping(row: 1, mirrored: true),
        .west: RowMapping(row: 2, mirrored: true),
        .northwest: RowMapping(row: 3, mirrored: true),
    ]

    /// This facing's row/mirror mapping. `rowMappingTable` is exhaustive
    /// over every `Direction8` case, so this never fails in practice \u2014 the
    /// `preconditionFailure` only guards against the dictionary and the enum
    /// silently drifting apart in a future edit.
    static func rowMapping(for direction: Direction8) -> RowMapping {
        guard let mapping = rowMappingTable[direction] else {
            preconditionFailure(
                "Direction8.\(direction) has no RaccoonAnimationController row mapping. Every "
                    + "Direction8 case must have an entry in RaccoonAnimationController.rowMappingTable."
            )
        }
        return mapping
    }

    /// The anchor pixel within one cell: `(23, 20)`, top-left-origin pixel
    /// coordinates \u2014 per the story's measured table ("Anchor 23,20").
    static let anchorPixel = CGPoint(x: 23, y: 20)

    /// `anchorPixel` converted to SpriteKit's normalized, bottom-left-origin
    /// `anchorPoint` space.
    static var anchorPointNormalized: CGPoint {
        CGPoint(
            x: anchorPixel.x / cellSize.width,
            y: 1 - anchorPixel.y / cellSize.height
        )
    }

    // MARK: - Frame timing

    /// 10 fps walk cadence, per the story ("Walk 10 fps").
    static let walkFramesPerSecond: Double = 10

    /// 12 fps attack cadence, per the story ("attack 12 fps").
    static let attackFramesPerSecond: Double = 12

    /// The frame rate `state` plays at.
    static func framesPerSecond(for state: RaccoonAnimationState) -> Double {
        switch state {
        case .walk: return walkFramesPerSecond
        case .attack: return attackFramesPerSecond
        }
    }

    /// The animation frame (column) to show at `elapsedTime` seconds into
    /// the current state, cycling `0 -> 1 -> 2 -> 3 -> 0 ...` at
    /// `framesPerSecond`.
    ///
    /// A pure function \u2014 exposed statically, like
    /// `PlayerAnimator.frameIndex(elapsedTime:isMoving:)`, so tests can pin
    /// the walk/attack cadence directly against a fixed `elapsedTime`
    /// without needing a live controller instance.
    ///
    /// A negative or zero `elapsedTime` is treated as frame `0`, the same
    /// convention `PlayerAnimator` uses.
    static func frameIndex(elapsedTime: TimeInterval, framesPerSecond: Double) -> Int {
        guard elapsedTime > 0 else { return 0 }
        let secondsPerFrame = 1.0 / framesPerSecond
        let framesElapsed = Int(elapsedTime / secondsPerFrame)
        return framesElapsed % frameCount
    }

    // MARK: - Instance state (the state machine)

    /// The facing this controller currently shows.
    private(set) var direction: Direction8

    /// The animation currently playing.
    private(set) var state: RaccoonAnimationState

    /// Seconds elapsed since `state` last changed \u2014 reset to `0` whenever
    /// the state flips, so switching from walk to attack (or back) always
    /// starts its new cycle at frame 0 rather than resuming mid-cycle from
    /// an unrelated previous state.
    private(set) var elapsedInCurrentState: TimeInterval = 0

    init(initialDirection: Direction8 = .south, initialState: RaccoonAnimationState = .walk) {
        direction = initialDirection
        state = initialState
    }

    /// Sets the facing this controller shows. Exposed as the public surface
    /// a later PR's seek behaviour drives every frame from the raccoon's
    /// movement vector.
    func setDirection(_ newDirection: Direction8) {
        direction = newDirection
    }

    /// Switches to the walk animation, resetting the cycle if not already
    /// walking. A no-op if already walking, so a caller driving this every
    /// frame while walking does not keep restarting the cycle.
    func playWalk() {
        guard state != .walk else { return }
        state = .walk
        elapsedInCurrentState = 0
    }

    /// Switches to the attack animation, resetting the cycle if not already
    /// attacking. A no-op if already attacking, for the same reason
    /// `playWalk()` is.
    func playAttack() {
        guard state != .attack else { return }
        state = .attack
        elapsedInCurrentState = 0
    }

    /// Advances the frame-timing clock by `deltaTime`. A later PR's
    /// per-frame update (the raccoon's own `RaccoonNode.update(deltaTime:)`)
    /// calls this once per frame.
    func advance(deltaTime: TimeInterval) {
        guard deltaTime > 0 else { return }
        elapsedInCurrentState += deltaTime
    }

    /// This controller's current row/mirror mapping, derived from
    /// `direction`.
    var currentRowMapping: RowMapping {
        Self.rowMapping(for: direction)
    }

    /// The animation frame (column) to show right now, derived from `state`
    /// and `elapsedInCurrentState`.
    var currentFrameColumn: Int {
        Self.frameIndex(elapsedTime: elapsedInCurrentState, framesPerSecond: Self.framesPerSecond(for: state))
    }
}
