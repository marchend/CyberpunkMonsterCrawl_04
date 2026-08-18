import CoreGraphics
import Foundation

/// Per-frame steering that moves a raccoon toward the player's current
/// tile, resolves the proposed movement against building footprints via
/// `BuildingAvoidance`, and drives the raccoon's facing/walk animation from
/// the result (`CYBERPUN-17-8` PR 2).
///
/// **Scope of this PR.** Seek-and-avoid steering only -- no bite/damage,
/// no rabies, no death (later parts of the `CYBERPUN-17-8` story). This
/// type only ever calls `RaccoonNode.setDirection(_:)` / `.playWalk()` /
/// `.update(deltaTime:)`, the exact public surface
/// `RaccoonNode`/`RaccoonAnimationController` expose "for a later PR's seek
/// behaviour to drive" (see those types' own doc comments).
///
/// **Facing tracks the intended direction, not the collision-resolved
/// one** -- the same split `PlayerMovementController.facingVector` /
/// `.frameDisplacement` already draw for the player (a human pushing a
/// stick faces where they're pushing, even mid-frame against a wall that
/// stops them). A raccoon's "intended direction" is simply "toward the
/// player right now", so facing is derived straight from `currentPosition`
/// and `playerPosition`, independent of whatever detour
/// `BuildingAvoidance` takes this frame.
enum RaccoonSeekBehavior {

    /// On-screen points/second a raccoon closes on the player at, pinned in
    /// **screen** space for the same reason
    /// `PlayerMovementController.maxPointsPerSecond` is: normalizing in
    /// tile space would make a raccoon's on-screen speed vary with heading
    /// on this 2:1 projection. Set as a fraction of the player's own speed
    /// -- an initial tuning constant; the story explicitly defers exact
    /// difficulty numbers to playtesting.
    static let pointsPerSecond: Double = PlayerMovementController.maxPointsPerSecond * 0.75

    /// Advances one raccoon by one frame: computes the tile-space step
    /// toward `playerPosition`, resolves it against `obstructions` via
    /// `BuildingAvoidance`, sets `raccoon`'s facing from the *unresolved*
    /// seek direction and switches it to the walk animation, advances its
    /// animation clock, and returns the raccoon's new tile-space position.
    ///
    /// A no-op (returns `currentPosition` unchanged, without touching
    /// `raccoon` at all) when `deltaTime <= 0`.
    @discardableResult
    static func update(
        raccoon: RaccoonNode,
        currentPosition: TilePoint,
        playerPosition: TilePoint,
        obstructions: [CollisionResolver.FootprintBounds],
        deltaTime: TimeInterval
    ) -> TilePoint {
        guard deltaTime > 0 else { return currentPosition }

        if let direction = facing(fromCurrentPosition: currentPosition, toPlayerPosition: playerPosition) {
            raccoon.setDirection(direction)
        }
        raccoon.playWalk()
        raccoon.update(deltaTime: deltaTime)

        let proposedDelta = tileDisplacement(
            currentPosition: currentPosition,
            playerPosition: playerPosition,
            deltaTime: deltaTime
        )
        guard proposedDelta != .zero else { return currentPosition }

        return BuildingAvoidance.resolve(
            currentPosition: currentPosition,
            proposedDelta: proposedDelta,
            obstructions: obstructions
        )
    }

    /// The tile-space vector from `current` toward `player` -- exposed as a
    /// pure function so tests can assert "points toward the player"
    /// directly, without a live `RaccoonNode`. `.zero` when `current ==
    /// player`.
    static func seekVector(currentPosition current: TilePoint, playerPosition player: TilePoint) -> CGVector {
        CGVector(dx: CGFloat(player.x - current.x), dy: CGFloat(player.y - current.y))
    }

    /// The facing a raccoon at `current` should show while seeking
    /// `player` -- the tile-space seek vector, converted to **screen**
    /// space (the space `Direction8` bins facing art in, matching every
    /// other `Direction8` consumer in this codebase) via the same linear
    /// forward transform `IsometricProjection.tileToScreen` applies to a
    /// point. `nil` when `current == player` (no facing information,
    /// mirroring `Direction8`'s own zero-vector contract -- the raccoon
    /// keeps whatever facing it already had).
    static func facing(fromCurrentPosition current: TilePoint, toPlayerPosition player: TilePoint) -> Direction8? {
        let tileDelta = seekVector(currentPosition: current, playerPosition: player)
        guard tileDelta != .zero else { return nil }
        return Direction8.from(spriteKitVector: screenVector(forTileDelta: tileDelta))
    }

    /// This frame's tile-space displacement toward `playerPosition`: the
    /// seek vector's **screen-space** direction (see `facing`'s doc
    /// comment for why screen space) scaled to `pointsPerSecond *
    /// deltaTime` screen points and projected back to tile space --
    /// mirroring `PlayerMovementController.tileDisplacement(forStickDirection:...)`'s
    /// "scale in screen space, then invert" shape, so a raccoon's on-screen
    /// speed is heading-independent exactly like the player's.
    ///
    /// Capped so a single frame can never overshoot the player's own tile:
    /// `screenDistance` is clamped to the *actual* screen-space distance to
    /// the player, which is what stops a raccoon oscillating around the
    /// player once it gets close, instead of settling onto its tile.
    private static func tileDisplacement(
        currentPosition: TilePoint,
        playerPosition: TilePoint,
        deltaTime: TimeInterval
    ) -> CGVector {
        let tileDelta = seekVector(currentPosition: currentPosition, playerPosition: playerPosition)
        guard tileDelta != .zero else { return .zero }

        let screenDelta = screenVector(forTileDelta: tileDelta)
        let screenDistanceToPlayer = hypot(Double(screenDelta.dx), Double(screenDelta.dy))
        guard screenDistanceToPlayer > 0 else { return .zero }

        let screenDistance = min(pointsPerSecond * deltaTime, screenDistanceToPlayer)
        let screenStep = CGPoint(
            x: CGFloat(Double(screenDelta.dx) / screenDistanceToPlayer * screenDistance),
            y: CGFloat(Double(screenDelta.dy) / screenDistanceToPlayer * screenDistance)
        )

        let tileStep = IsometricProjection.screenToTile(screenStep)
        return CGVector(dx: CGFloat(tileStep.x), dy: CGFloat(tileStep.y))
    }

    /// Converts a **tile-space** delta vector to its **SpriteKit-space**
    /// screen delta, via `IsometricProjection.tileToScreen` -- valid for a
    /// delta (not just a point) because the forward transform is linear,
    /// with no translation term.
    private static func screenVector(forTileDelta delta: CGVector) -> CGVector {
        let screenPoint = IsometricProjection.tileToScreen(tileX: Double(delta.dx), tileY: Double(delta.dy))
        return CGVector(dx: screenPoint.x, dy: screenPoint.y)
    }
}
