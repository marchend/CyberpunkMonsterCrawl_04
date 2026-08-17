import CoreGraphics
import SpriteKit

/// Keeps a moving focus point (the player's tile-space position) near the
/// centre of the viewport by repositioning a container node, and drives
/// chunk streaming with that same focus point every call.
///
/// **Scope of this PR (`CYBERPUN-17-7` PR 2).** This is the pure
/// camera-lock geometry only \u2014 it does not decide *which* scene node plays
/// the role of `container` in a real build (`GameScene.worldLayer` versus
/// the existing `cameraNode`) or drive it from `GameScene.update(_:)`; that
/// is scene wiring, and scene wiring (along with deleting
/// `PlayerScaffoldingDriver` and the `SCAFFOLDING(CYBERPUN-17-7)` debug
/// camera pan) is explicitly out of scope here \u2014 "does not touch input or
/// scene wiring" \u2014 and lands in a later PR of this same story.
///
/// **AGENT.md's camera-lock rationale, and why this never touches
/// `SKCameraNode`.** `GameScene.uiLayer` is already parented to a single
/// `SKCameraNode` (`cameraNode`) precisely so UI content stays camera-locked
/// once world-camera scrolling lands \u2014 that camera already exists, and
/// this type must not introduce a second one. `container` here is
/// deliberately a plain `SKNode`: the geometry below (see "The formula")
/// works identically whether a future wiring PR hands it `worldLayer`
/// (offsetting world content so the focus lands at screen centre while
/// `cameraNode` stays fixed \u2014 `GameScene.centreCameraOnScene()`'s existing
/// behaviour) or some other camera-following container; deciding which is,
/// again, scene wiring.
///
/// **The formula.** `container.position = viewportCentre -
/// projected(focus)` \u2014 the container is offset by the *negative* of the
/// focus's projected screen point, biased so the focus lands at the
/// viewport's centre rather than at the coordinate origin. World content in
/// this codebase is always parented at its own raw
/// `IsometricProjection.tileToScreen` position, unshifted (every renderer in
/// `Sources/World` follows this convention already), so a child positioned
/// at exactly `projected(focus)` resolves through `container` to
/// `projected(focus) + container.position == viewportCentre` by
/// construction \u2014 `CameraControllerTests` pins that identity directly
/// (`container.convert(_:to:)`) rather than trusting the arithmetic in
/// prose, for a focus point that moves and for both portrait and landscape
/// viewport sizes, so nothing about the centring depends on orientation.
///
/// **No world-edge clipping is needed because there is no world edge** \u2014
/// the city is procedurally endless (`docs/bootstrap.md`) \u2014 so "clips world
/// edges cleanly in portrait and landscape" reduces to "never leaves an
/// unrendered gap at the viewport edge in either orientation", which is
/// already `ChunkStreamingManager.residentRadius`'s own guarantee
/// (`coversViewport(widthPoints:heightPoints:)`, checked for both
/// orientations in `ChunkStreamingManagerTests`). This type's only remaining
/// responsibility toward that guarantee is calling the streaming trigger
/// with the *live* focus point on every frame, which `update(focus:
/// viewportSize:)` always does \u2014 never a stale or debug-scripted one.
final class CameraController {
    /// The node this controller repositions every `update` call. Weak: the
    /// scene (or a test) owns this node's lifetime, and a controller must
    /// never keep a torn-down node's subtree alive.
    private weak var container: SKNode?

    /// Called with the live focus point on every `update`, so chunk
    /// residency tracks the camera exactly the way
    /// `GroundPlaneStreamer.updateCamera(worldPosition:)` /
    /// `ChunkStreamingManager.updateCamera(worldPosition:)` already expect
    /// \u2014 both are already parameterized on a live `TilePoint`, so this type
    /// wires an existing entry point rather than adding a parallel one.
    private let streamingUpdate: (TilePoint) -> Void

    /// - Parameters:
    ///   - container: the node to reposition. Never an `SKCameraNode`
    ///     constructed by this type \u2014 see this type's own doc comment.
    ///   - streamingUpdate: forwards the live focus point to whichever
    ///     existing chunk-streaming trigger a caller wires up
    ///     (`GroundPlaneStreamer.updateCamera` /
    ///     `ChunkStreamingManager.updateCamera`, or a test double).
    init(container: SKNode, streamingUpdate: @escaping (TilePoint) -> Void) {
        self.container = container
        self.streamingUpdate = streamingUpdate
    }

    /// Advances the camera lock for one frame: repositions `container` so
    /// `focus` projects to the centre of a `viewportSize`-sized viewport,
    /// then forwards `focus` to the streaming trigger.
    ///
    /// `viewportSize` is taken fresh on every call (rather than cached at
    /// init) so a rotation \u2014 portrait to landscape or back \u2014 is reflected
    /// on the very next frame instead of requiring a separate resize hook.
    func update(focus: TilePoint, viewportSize: CGSize) {
        streamingUpdate(focus)

        guard let container else { return }

        let focusScreenPoint = IsometricProjection.tileToScreen(focus)
        let viewportCentre = CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)

        container.position = CGPoint(
            x: viewportCentre.x - focusScreenPoint.x,
            y: viewportCentre.y - focusScreenPoint.y
        )
    }
}
