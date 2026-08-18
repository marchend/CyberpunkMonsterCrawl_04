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
    ///
    /// **Measured against the shipped art, not inferred from the ticket.**
    /// Both sheets ship 8 rows and `AtlasCellIndex.raccoonWalk` /
    /// `.raccoonAttack` declare all 32 cells of each valid, so "only 5
    /// facings are authored" is a claim about the art that has to be checked
    /// against the art: if rows 5-7 held real west-side drawings (asymmetric
    /// detail, a different tail sweep), this table would render mirrored
    /// east art for half the compass and leave 12 shipped cells dead per
    /// sheet, with a fully green suite. That is the failure mode
    /// `PlayerSpriteSheet.rowMappingTable`'s doc was written to prevent, and
    /// asserting this table against itself (southwest.row == southeast.row)
    /// cannot see it.
    ///
    /// `RaccoonSpriteSheetPixelTests`
    /// `.test_theRowsTheTableNeverReads_carryNoArtBeyondTheMirrorOfTheirSourceRow_onBothSheets`
    /// therefore re-decodes **both** `sprite_raccoon_walk` and
    /// `sprite_raccoon_attack` and requires each row this table never reads
    /// (5/6/7, the compass sweep's northwest / west / southwest
    /// continuation) to be either empty or the exact horizontal flip of the
    /// row mirrored in its place (3/2/1). The attack sheet is scanned
    /// separately rather than assumed to share the walk sheet's row order:
    /// it is a different image and could have been cut on a different one.
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

    /// The anchor pixel within one cell: `(23, 24)`, top-left-origin pixel
    /// coordinates -- the raccoon's feet, measured off the shipped art.
    ///
    /// **Measured, and the measurement moved it.** The player's `(18, 40)`
    /// reduces to "half the cell width, cell bottom" and is checkable with a
    /// calculator; a raccoon's feet sit somewhere inside its cell, so only
    /// the pixels can settle where. This constant read `(23, 20)` -- the
    /// story's table -- until `RaccoonSpriteSheetPixelTests`
    /// `.test_anchorPixel_sitsAtTheMeasuredGroundContactCentreOfBothSheets`
    /// re-decoded both sheets: the south facing's silhouette occupies rows
    /// 8..<24 of `sprite_raccoon_walk` (8..<25 on `sprite_raccoon_attack`,
    /// one row lower for the lunge), so row 20 is *inside the raccoon's
    /// legs* and the ticket's anchor floated every raccoon's shadow and
    /// depth sample 4px above its feet. `24` is the walk sheet's measured
    /// ground line, and it is within the scan's 2px tolerance of the attack
    /// sheet's, so the raccoon does not hop when the two sheets swap.
    ///
    /// `x` is unchanged: 23 is the measured centre of the south silhouette
    /// (within the same tolerance), so the ticket had that half right. The
    /// scan is the same test-time alpha measurement `AtlasSignGlyphBand`
    /// uses to pin its bands, for the same reason -- prose about where art
    /// sits inside a cell goes stale silently on the next re-export.
    static let anchorPixel = CGPoint(x: 23, y: 24)

    /// `anchorPixel` converted to SpriteKit's normalized, bottom-left-origin
    /// `anchorPoint` space.
    static var anchorPointNormalized: CGPoint {
        CGPoint(
            x: anchorPixel.x / cellSize.width,
            y: 1 - anchorPixel.y / cellSize.height
        )
    }

    /// The raccoon's ground footprint width, in points: the widest
    /// paw-to-paw span the shipped walk art draws in the bottom rows of its
    /// silhouette (its ground-contact band), across every directly-authored
    /// facing, on an unscaled 48x28 cell.
    ///
    /// **How it was measured.** An alpha scan of `sprite_raccoon_walk` puts
    /// the south facing's silhouette in rows 8..<24 of its 28-row cell,
    /// widest at x 14..28 (the body) and tapering through the leg rows. Its
    /// ground-contact band measures 9px there, and per authored facing:
    /// south 9, southeast 10, east 14, northeast 7, north 7 -- widest
    /// side-on, narrowest facing away, as a quadruped's stance should be.
    /// `14` is that widest stance, because a shadow is one ellipse fixed at
    /// construction and has to cover whichever way the raccoon turns.
    /// Nothing about it follows from the 48pt cell the art is cropped from,
    /// which is why the full-cell-width shadow this replaced drew a puddle
    /// more than three times the width of the animal's actual footprint.
    ///
    /// **Measured, not chosen.** This is the number
    /// `RaccoonNode.shadowWidth(forTier:)` passes to `ActorShadowNode`,
    /// which deliberately takes no default because "a shadow's size is a
    /// property of *the actor casting it*" -- `PlayerNode` passes its own
    /// measured `PlayerSpriteSheet.hitboxSize.width`, and this is the
    /// raccoon's. The value below is read off the shipped
    /// `sprite_raccoon_walk` alpha channel and re-measured at test time by
    /// `RaccoonSpriteSheetPixelTests`
    /// `.test_groundFootprintWidth_equalsTheMeasuredGroundContactSpan`, the
    /// same way `AtlasSignGlyphBand.glyphRows` pins its bands: art
    /// re-authored with a wider or narrower stance turns the suite red here
    /// rather than silently un-tuning every raccoon's shadow.
    ///
    /// **Width only, deliberately.** A shadow needs a width; the footprint's
    /// depth component is a collision fact this slice has no way to measure
    /// (the building-footprint collision work lands later in
    /// `CYBERPUN-17-8`). It gets added there, beside the code that first
    /// needs it, rather than invented here.
    static let groundFootprintWidth: CGFloat = 14

    // MARK: - Frame timing

    /// 10 fps walk cadence, per the story ("Walk 10 fps").
    static let walkFramesPerSecond: Double = 10

    /// 12 fps attack cadence, per the story ("attack 12 fps").
    static let attackFramesPerSecond: Double = 12

    /// Seconds one complete attack cycle lasts: all `frameCount` frames of
    /// `sprite_raccoon_attack` at `attackFramesPerSecond` (4 / 12 = 0.333s).
    ///
    /// This is the window `playWalk()` refuses to interrupt -- see its doc
    /// comment for why the attack sheet otherwise never reaches the screen
    /// at all.
    static var attackCycleDuration: TimeInterval {
        Double(frameCount) / attackFramesPerSecond
    }

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

    /// Whether an attack cycle started by `playAttack()` has yet to play
    /// all `frameCount` of its frames. `playWalk()` is held off while this
    /// is `true`, so a started attack always gets drawn.
    var isAttackCycleInProgress: Bool {
        state == .attack && elapsedInCurrentState < Self.attackCycleDuration
    }

    /// Switches to the walk animation, resetting the cycle if not already
    /// walking. A no-op if already walking, so a caller driving this every
    /// frame while walking does not keep restarting the cycle.
    ///
    /// **Also a no-op while an attack cycle is still playing**
    /// (`isAttackCycleInProgress`) -- which is what makes
    /// `sprite_raccoon_attack` reach the screen at all. Review of PR #35
    /// traced one production frame: `RaccoonSpawnDirector.update` runs
    /// `RaccoonSeekBehavior.update` first, which calls `playWalk()`
    /// unconditionally *before* `RaccoonNode.update(deltaTime:)` refreshes
    /// `body.texture` -- the only place the texture is assigned -- and
    /// `BiteComponent.update` calls `playAttack()` *after* that refresh.
    /// So `.attack` was set on the frame a bite landed, drew nothing that
    /// frame, and was flipped back to `.walk` on the next frame before the
    /// texture refresh could ever see it: the attack sheet never drew in a
    /// real build, and the 12 fps attack cadence was unobservable. A unit
    /// test reading `state` immediately after the bite saw `.attack` and
    /// passed, which is why the suite stayed green over it.
    ///
    /// Holding here rather than in the seek behaviour keeps the guarantee
    /// caller-order-independent: whoever drives walk, and whenever, an
    /// attack that started still gets its four frames on screen before
    /// walk can reclaim the sprite.
    func playWalk() {
        guard state != .walk else { return }
        guard !isAttackCycleInProgress else { return }
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
