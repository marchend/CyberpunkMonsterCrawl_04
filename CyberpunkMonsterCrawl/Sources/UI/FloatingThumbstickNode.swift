import CoreGraphics
import SpriteKit
import UIKit

/// Plain, SpriteKit-independent snapshot of `FloatingThumbstickNode`'s
/// current deflection -- the one thing `PlayerMovementController` needs from
/// it, so the controller can be exhaustively unit-tested (and, in a later PR
/// of this story, driven from a live scene) without importing SpriteKit at
/// all.
struct StickState: Equatable {
    /// Resting/neutral state: no direction, zero magnitude, inside the dead
    /// zone. What the stick reports before any touch and immediately after
    /// `endTouch()`/a cancelled run.
    static let resting = StickState(direction: .zero, magnitude: 0, isBeyondDeadZone: false)

    /// Unit-length deflection direction in SpriteKit (scene, y-up) space --
    /// the same convention `PlayerNode.update(deltaTime:movementVector:)`
    /// and `Direction8.from(spriteKitVector:)` already read. `.zero` at rest
    /// (magnitude `0`), never an arbitrary direction with no real intent
    /// behind it.
    let direction: CGVector

    /// `0...1` fraction of `FloatingThumbstickNode.maxRadius` the active
    /// touch is currently deflected. Clamped at `1` once the touch is
    /// dragged past the max radius.
    let magnitude: CGFloat

    /// Whether `magnitude` has crossed `FloatingThumbstickNode
    /// .deadZoneFraction`. `PlayerMovementController.isMoving` is defined as
    /// exactly this value.
    let isBeyondDeadZone: Bool
}

/// The on-screen floating movement thumbstick: appears wherever the player
/// first touches down inside the left half of the safe content area, tracks
/// the drag, clamps at `maxRadius`, and springs back to a dimmed "ready"
/// position on release -- staying dimmed-but-visible (never fully hidden)
/// for the whole of an active run, so the player always has a visual anchor
/// for where their next touch should land.
///
/// **Scope of this PR (`CYBERPUN-17-7` PR 1).** This is the input
/// *producer* half of the story: a self-contained, exhaustively unit-tested
/// node that turns raw touch points into a `StickState`. It is not yet
/// mounted anywhere in `GameScene`/`GameplayScreenNode`, and `GameScene`'s
/// touch handling is not yet extended to route `touchesMoved`/`touchesEnded`
/// to it (today it only reacts to `touchesBegan` -- see
/// `GameScene.touchesBegan(_:with:)`). That wiring, together with replacing
/// `PlayerScaffoldingDriver`'s scripted `SCAFFOLDING(CYBERPUN-17-7)` demo
/// vector with this node's real `StickState` fed through
/// `PlayerMovementController`, building collision and camera-follow, lands
/// in a later PR of this same story -- this PR's own scope is explicitly
/// "one producer (stick state), one consumer (displacement/facing/isMoving);
/// no collision, camera, or world logic". That deferred half is tracked on
/// the `CYBERPUN-17-7` story itself, with a follow-up task under it
/// requested on this PR's task, `CYBERPUN-17-7-t1`; see
/// `PlayerMovementController`'s doc comment and the `CYBERPUN-17-7` entry in
/// AGENT.md/CLAUDE.md for the implemented-versus-deferred list.
///
/// Until that wiring lands, `ThumbstickMovementSeamTests` pipes this node's
/// own `stickState` from a real drag straight into
/// `PlayerMovementController`, so the two halves' conventions are pinned
/// against each other rather than only against their own isolated suites.
///
/// **Touch-input agnostic.** This node holds no `UITouch` and does not
/// override `touchesBegan`/`touchesMoved`/`touchesEnded` -- doing so would
/// require `isUserInteractionEnabled`, which `GameScene`'s
/// `nodesBypassingSceneTouchDispatch()` audit forbids graph-wide (see
/// `TouchResponder`'s doc comment): a node that opts into direct UIKit
/// delivery receives a touch *before* the scene's own
/// `touchesBegan(_:with:)` runs, bypassing UI-first routing entirely.
/// `beginTouch(at:)` / `updateTouch(at:)` / `endTouch()` are the seam a
/// future scene-level touch tracker drives instead, which is what lets this
/// node support a full press-drag-release gesture that the single-callback
/// `TouchResponder` protocol cannot express.
///
/// **Coordinate space.** Every point this type accepts or reports is in the
/// same coordinate space `layout(for:safeAreaInsets:)` lays out in: `(0, 0)`
/// at the centre of the visible area, `x` increasing right, `y` increasing
/// up -- exactly `GameScene.uiLayer`'s own space (see `MenuScreenNode`'s doc
/// comment for the same convention). `self.position` is never touched;
/// `base`/`knob` are positioned directly in that space so a future caller
/// mounting this node in `uiLayer` needs no extra offset math.
final class FloatingThumbstickNode: SKNode {

    // MARK: - Tunables

    /// Radius (points) at which the stick clamps a drag -- `StickState
    /// .magnitude` reaches `1` exactly at this distance from the base.
    static let maxRadius: CGFloat = 60

    /// Fraction of `maxRadius` a drag must exceed before `StickState
    /// .isBeyondDeadZone` flips to `true`. Below this, a touch is treated as
    /// "settling", not a deliberate move -- the usual floating-stick
    /// convention that absorbs an imprecise touch-down without triggering
    /// movement. Strictly-greater-than, so a drag landing exactly on the
    /// boundary distance is not yet "beyond" it.
    static let deadZoneFraction: CGFloat = 0.15

    /// Visual radius of the outer ring.
    static let baseRadius: CGFloat = 52

    /// Visual radius of the draggable knob.
    static let knobRadius: CGFloat = 24

    /// Alpha while a run is active but no touch is currently engaging the
    /// stick -- dimmed, but per this story's acceptance criteria never `0`:
    /// fully invisible would give the player no idea where to put their
    /// thumb next.
    static let restAlpha: CGFloat = 0.35

    /// Alpha while an active touch is engaging the stick.
    static let activeAlpha: CGFloat = 0.85

    /// Margin (points) between the safe content area's bottom-left corner
    /// and the stick's own rest position, on both axes -- what keeps the
    /// stick's full `maxRadius` extent clear of the safe-area insets rather
    /// than just its centre point.
    static let cornerMargin: CGFloat = 24

    /// Gap (points) between the stick's own top extent (`restPosition.y +
    /// maxRadius`) and the reserved pulse-button slot directly above it.
    static let pulseButtonSlotGap: CGFloat = 16

    /// Size of the reserved HUD slot for the future pulse-ability button
    /// (`CYBERPUN-17-10`). Stacked directly above the stick's own rest
    /// position, in the same bottom-left "thumb quadrant" -- both controls
    /// share that quadrant, so a touch that starts in the slot must resolve
    /// to "tap the future pulse button", never "engage the stick", even
    /// though the point still falls inside the stick's own left-region
    /// touch-acceptance box. `CYBERPUN-17-10` should mount its real button
    /// at exactly `reservedPulseButtonSlot(forSize:safeAreaInsets:)` rather
    /// than re-deriving its own placement, so the two can never drift apart.
    static let pulseButtonSlotSize = CGSize(width: 72, height: 72)

    // MARK: - Nodes

    private let base = SKShapeNode(circleOfRadius: FloatingThumbstickNode.baseRadius)
    private let knob = SKShapeNode(circleOfRadius: FloatingThumbstickNode.knobRadius)

    // MARK: - State

    /// Where the stick currently springs back to on release, and where it
    /// (re)appears the moment `layout(for:safeAreaInsets:)` runs while no
    /// touch is active. Recomputed on every layout pass so rotation (a
    /// safe-area change) keeps it clear of the new insets.
    private(set) var restPosition: CGPoint = .zero

    private var currentSize: CGSize = .zero
    private var currentSafeAreaInsets: UIEdgeInsets = .zero

    private var isTracking = false

    /// The stick's current reading. `PlayerMovementController` (a separate,
    /// SpriteKit-independent type) is the consumer.
    private(set) var stickState: StickState = .resting

    /// Whether a run is currently in progress. A later PR wires this to
    /// `GameplayScreenNode`'s `willEnter()`/`willExit()`. While `false` the
    /// stick is fully hidden -- there is nothing to move in
    /// `.menu`/`.death`/`.highScores` -- any touch currently tracking is
    /// cancelled back to rest, so a run ending mid-drag can never strand the
    /// stick off-centre or mid-fade for the next run, and no *new* touch may
    /// begin one (`canBeginTouch(at:)` refuses while this is `false`). Those
    /// two halves together are what make "no run => no stick interaction" an
    /// invariant rather than a convention each call site has to uphold.
    var isRunActive: Bool = false {
        didSet {
            guard isRunActive != oldValue else { return }
            if !isRunActive {
                cancelTracking()
            }
            updateVisibility()
        }
    }

    // MARK: - Init

    override init() {
        super.init()

        base.fillColor = PixelGritPalette.plate
        base.strokeColor = PixelGritPalette.neonSecondary
        base.lineWidth = 2
        base.name = "thumbstick.base"

        knob.fillColor = PixelGritPalette.neonAccent
        knob.strokeColor = .clear
        knob.name = "thumbstick.knob"

        name = "thumbstick"
        addChild(base)
        addChild(knob)

        // Identifier lives on the interactive root itself, not on a wrapper
        // applied after these children are added -- the same convention
        // `ButtonNode` uses, and the one this project's accessibility-frame
        // pipeline (`AccessibleSKView.swift`) depends on for a camera-fixed
        // UI node.
        isAccessibilityElement = true
        accessibilityIdentifier = "gameplay.thumbstick"
        accessibilityLabel = "Movement thumbstick"

        updateVisibility()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout

    /// Recomputes `restPosition` for the current scene `size`/
    /// `safeAreaInsets`, and -- while no touch is tracking -- snaps the
    /// stick back there. A touch in progress is left alone; the *next*
    /// release re-centres on the up-to-date `restPosition` instead of
    /// stranding the stick at a pre-rotation layout.
    func layout(for size: CGSize, safeAreaInsets: UIEdgeInsets) {
        currentSize = size
        currentSafeAreaInsets = safeAreaInsets
        restPosition = Self.restingPosition(forSize: size, safeAreaInsets: safeAreaInsets)

        if !isTracking {
            base.position = restPosition
            knob.position = restPosition
        }
    }

    // MARK: - Regions (shared with a future real pulse button)

    /// The left half of the safe content area -- the only region a touch
    /// may start the stick in. `x` runs from the safe-area-inset left edge
    /// to the screen's horizontal centre; `y` spans the full safe-area
    /// height.
    static func leftRegion(forSize size: CGSize, safeAreaInsets: UIEdgeInsets) -> CGRect {
        let minX = -size.width / 2 + safeAreaInsets.left
        let minY = -size.height / 2 + safeAreaInsets.bottom
        let maxY = size.height / 2 - safeAreaInsets.top
        return CGRect(x: minX, y: minY, width: -minX, height: maxY - minY)
    }

    /// Where the stick rests -- clear of `safeAreaInsets` on both the left
    /// and bottom edges by `cornerMargin`, with `maxRadius` folded in so the
    /// stick's full visual/drag extent (not just its centre point) stays
    /// clear of the insets.
    static func restingPosition(forSize size: CGSize, safeAreaInsets: UIEdgeInsets) -> CGPoint {
        CGPoint(
            x: -size.width / 2 + safeAreaInsets.left + cornerMargin + maxRadius,
            y: -size.height / 2 + safeAreaInsets.bottom + cornerMargin + maxRadius
        )
    }

    /// The reserved HUD slot for the future pulse-ability button -- stacked
    /// directly above the stick's own rest position, separated from it by
    /// `pulseButtonSlotGap`. See `pulseButtonSlotSize`'s doc comment for why
    /// this sits inside `leftRegion` rather than off to one side of it.
    static func reservedPulseButtonSlot(forSize size: CGSize, safeAreaInsets: UIEdgeInsets) -> CGRect {
        let rest = restingPosition(forSize: size, safeAreaInsets: safeAreaInsets)
        let slotMinY = rest.y + maxRadius + pulseButtonSlotGap
        return CGRect(
            x: rest.x - pulseButtonSlotSize.width / 2,
            y: slotMinY,
            width: pulseButtonSlotSize.width,
            height: pulseButtonSlotSize.height
        )
    }

    // MARK: - Touch tracking

    /// Whether a touch at `point` (already in this node's coordinate space)
    /// is allowed to engage the stick: a run is active, the point is inside
    /// the left region, and it is outside the reserved pulse-button slot.
    ///
    /// The `isRunActive` half makes the run invariant hold from *both*
    /// directions. `isRunActive`'s `didSet` already owns "run ended =>
    /// cancel the in-flight drag"; without the check here a touch could
    /// still *start* one after the run was over -- `beginTouch` would return
    /// `true`, `isTracking` would flip, `alpha` would go to `activeAlpha` on
    /// a hidden node, and `stickState` would start reporting deflection with
    /// nothing left to move. Owning it here rather than leaving it to every
    /// future call site is what stops the next caller from forgetting.
    func canBeginTouch(at point: CGPoint) -> Bool {
        assert(
            currentSize != .zero,
            """
            FloatingThumbstickNode was asked about a touch before \
            layout(for:safeAreaInsets:) ran. `currentSize`/\
            `currentSafeAreaInsets` are still `.zero`, which makes \
            `leftRegion` a degenerate rect at the origin, so every touch is \
            silently refused and the stick simply never responds. Call \
            `layout(for:safeAreaInsets:)` when mounting the node (and on \
            every size/safe-area change) before routing touches to it.
            """
        )

        guard isRunActive else { return false }

        let region = Self.leftRegion(forSize: currentSize, safeAreaInsets: currentSafeAreaInsets)
        guard region.contains(point) else { return false }
        let reserved = Self.reservedPulseButtonSlot(forSize: currentSize, safeAreaInsets: currentSafeAreaInsets)
        return !reserved.contains(point)
    }

    /// Begins tracking a new touch at `point`, if `canBeginTouch(at:)`
    /// allows it: the stick appears centred exactly on `point` (the
    /// documented "touch-down appears at first-touch location" behaviour),
    /// not at `restPosition`. Returns whether the touch was accepted.
    @discardableResult
    func beginTouch(at point: CGPoint) -> Bool {
        guard canBeginTouch(at: point) else { return false }
        isTracking = true
        base.position = point
        knob.position = point
        stickState = .resting
        updateVisibility()
        return true
    }

    /// Updates the drag toward `point` (same coordinate space), clamping the
    /// knob at `maxRadius` from the base and recomputing `stickState`. A
    /// no-op while no touch is tracking.
    func updateTouch(at point: CGPoint) {
        guard isTracking else { return }

        let rawOffset = CGVector(dx: point.x - base.position.x, dy: point.y - base.position.y)
        let clamped = Self.clamp(rawOffset, toRadius: Self.maxRadius)
        knob.position = CGPoint(x: base.position.x + clamped.dx, y: base.position.y + clamped.dy)
        stickState = Self.computeStickState(forOffset: clamped)
    }

    /// Ends the current touch: the stick springs back to `restPosition` and
    /// `stickState` resets to `.resting`. A no-op while no touch is
    /// tracking.
    func endTouch() {
        guard isTracking else { return }
        cancelTracking()
    }

    private func cancelTracking() {
        isTracking = false
        base.position = restPosition
        knob.position = restPosition
        stickState = .resting
        updateVisibility()
    }

    // MARK: - Visuals

    private func updateVisibility() {
        isHidden = !isRunActive
        alpha = isTracking ? Self.activeAlpha : Self.restAlpha
    }

    // MARK: - Pure helpers

    private static func clamp(_ vector: CGVector, toRadius radius: CGFloat) -> CGVector {
        let distance = hypot(vector.dx, vector.dy)
        guard distance > radius, distance > 0 else { return vector }
        let scale = radius / distance
        return CGVector(dx: vector.dx * scale, dy: vector.dy * scale)
    }

    private static func computeStickState(forOffset offset: CGVector) -> StickState {
        let distance = hypot(offset.dx, offset.dy)
        let magnitude = min(1, distance / maxRadius)
        let direction: CGVector = distance > 0
            ? CGVector(dx: offset.dx / distance, dy: offset.dy / distance)
            : .zero
        let isBeyondDeadZone = magnitude > deadZoneFraction
        return StickState(direction: direction, magnitude: magnitude, isBeyondDeadZone: isBeyondDeadZone)
    }
}
