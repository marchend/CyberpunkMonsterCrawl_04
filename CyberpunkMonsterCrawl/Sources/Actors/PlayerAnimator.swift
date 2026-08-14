import Foundation

/// The player's walk-cycle frame-timing state machine.
///
/// Pure state \u2014 no SpriteKit knowledge. A caller combines the
/// `frameIndex(elapsedTime:isMoving:)` result with a `Direction8` (via
/// `PlayerSpriteSheet.rowMapping(for:)`) to pick the `(col: frameIndex,
/// row: mapping.row)` cell.
enum PlayerAnimator {

    /// 8 fps, per the story: `0.125s` per frame.
    static let framesPerSecond: Double = 8

    /// `1 / framesPerSecond` \u2014 `0.125` seconds.
    static let secondsPerFrame: Double = 1.0 / framesPerSecond

    /// `sprite_player_walk` has 4 columns per row: `contact \u00b7 pass-L \u00b7
    /// contact \u00b7 pass-R`. The "contact" pose (both feet momentarily
    /// together) appears twice \u2014 once between each passing leg \u2014 which is
    /// why a natural 2-leg walk cycle needs 4 frames rather than 2.
    static let frameCount = 4

    /// `frameIndex` 0. Both feet at contact, mid-stride.
    static let frameContactFirst = 0
    /// `frameIndex` 1. Left leg passing forward.
    static let framePassLeft = 1
    /// `frameIndex` 2. Both feet at contact again, opposite mid-stride.
    static let frameContactSecond = 2
    /// `frameIndex` 3. Right leg passing forward.
    static let framePassRight = 3

    /// The walk-cycle frame to show at `elapsedTime` (seconds since the
    /// current movement/idle state began).
    ///
    /// - When `isMoving` is `false`, always returns frame 0 (the idle
    ///   pose \u2014 doubles as the first contact pose so idle never needs a
    ///   dedicated frame of its own).
    /// - When `isMoving` is `true`, cycles `0 \u2192 1 \u2192 2 \u2192 3 \u2192 0 \u2026` at
    ///   `framesPerSecond` (8 fps \u2014 `secondsPerFrame` = 0.125s each).
    ///
    /// A negative `elapsedTime` (which should never occur in practice) is
    /// treated the same as `0`, rather than producing an out-of-range or
    /// negative frame index.
    static func frameIndex(elapsedTime: TimeInterval, isMoving: Bool) -> Int {
        guard isMoving else { return frameContactFirst }
        guard elapsedTime > 0 else { return frameContactFirst }

        let framesElapsed = Int(elapsedTime / secondsPerFrame)
        return framesElapsed % frameCount
    }
}
