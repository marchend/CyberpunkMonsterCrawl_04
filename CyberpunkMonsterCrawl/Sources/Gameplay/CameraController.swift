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
/// behaviour) or some other container the world's content is parented
/// under; which world container it is remains scene wiring.
///
/// It is deliberately **not** container-agnostic in the wider sense,
/// because this doc exists to guide the wiring PR's choice: the formula
/// below offsets a *world* container. Moving a camera to look at a focus
/// point needs `position = projected(focus)`, not its negation, so handing
/// this controller `cameraNode` would scroll the view backwards at double
/// speed. Only a node the world's content is parented under is a legal
/// `container`.
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
/// The pixel snap described next perturbs that identity by at most half a
/// device pixel, which is the tolerance those tests assert.
///
/// **The offset is snapped to the device pixel grid.** This is the one line
/// in the codebase that moves a world container every frame, so an
/// unsnapped fractional offset here re-blurs *every* world-space child
/// whatever their own positions are -- exactly the defect AGENT.md assigns
/// to this ticket ("`cameraNode.position` is not snapped anywhere, so once
/// the camera moves off a whole device pixel every world-space child
/// inherits the sub-pixel offset again -- snapping the camera belongs with
/// `CYBERPUN-17-7`") and the same "Known limit (CYBERPUN-17-7)" that
/// `GameScene.startPlayer()` records against its own mount snap. So the
/// computed offset goes through `PixelCrispness.snappedPosition(for:
/// scale:)`, with `deviceScale` read live on every call the way
/// `GameScene.deviceScale` reads `view?.contentScaleFactor`, falling back
/// to `1` (a whole-*point* snap) for a headless, view-less scene. The
/// honest centring contract is therefore "the focus lands within half a
/// device pixel of the viewport centre", not "exactly on it", and
/// `CameraControllerTests` asserts that tolerance at simulated `@1x`,
/// `@2x` and `@3x` rather than a bare `1e-3`.
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

    /// The device pixel grid the computed offset is snapped to, evaluated
    /// on every `update` rather than captured once: a scene's `view` (and
    /// so its `contentScaleFactor`) may not exist yet when a controller is
    /// constructed, and a stale scale would snap to the wrong grid for the
    /// whole run. Mirrors `GameScene.deviceScale`'s own live read.
    private let deviceScale: () -> CGFloat

    /// - Parameters:
    ///   - container: the world-content node to reposition. Never an
    ///     `SKCameraNode` -- neither one constructed by this type nor the
    ///     scene's existing `cameraNode`, whose position would need the
    ///     un-negated projection; see this type's own doc comment.
    ///   - deviceScale: the device pixel grid the offset is snapped to,
    ///     read live per call like `GameScene.deviceScale`
    ///     (`view?.contentScaleFactor ?? 1`). Defaults to `1`, the
    ///     whole-point fallback for a headless, view-less scene.
    ///   - streamingUpdate: forwards the live focus point to whichever
    ///     existing chunk-streaming trigger a caller wires up
    ///     (`GroundPlaneStreamer.updateCamera` /
    ///     `ChunkStreamingManager.updateCamera`, or a test double).
    init(
        container: SKNode,
        deviceScale: @escaping () -> CGFloat = { 1 },
        streamingUpdate: @escaping (TilePoint) -> Void
    ) {
        self.container = container
        self.deviceScale = deviceScale
        self.streamingUpdate = streamingUpdate
    }

    /// Advances the camera lock for one frame: repositions `container` so
    /// `focus` projects to within half a device pixel of the centre of a
    /// `viewportSize`-sized viewport (the offset is snapped to the device
    /// pixel grid -- see this type's doc comment), then forwards `focus` to
    /// the streaming trigger.
    ///
    /// `viewportSize` is taken fresh on every call (rather than cached at
    /// init) so a rotation \u2014 portrait to landscape or back \u2014 is reflected
    /// on the very next frame instead of requiring a separate resize hook.
    func update(focus: TilePoint, viewportSize: CGSize) {
        streamingUpdate(focus)

        guard let container else { return }

        let focusScreenPoint = IsometricProjection.tileToScreen(focus)
        let viewportCentre = CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        let rawOffset = CGPoint(
            x: viewportCentre.x - focusScreenPoint.x,
            y: viewportCentre.y - focusScreenPoint.y
        )

        // Snapped, not assigned raw: see this type's "The offset is snapped
        // to the device pixel grid" note. Half a device pixel of centring
        // error is the price of every world-space child staying on the
        // pixel grid, which is the trade `docs/bootstrap.md` section 1
        // ("hard, un-resampled pixel edges") makes for us.
        container.position = PixelCrispness.snappedPosition(for: rawOffset, scale: deviceScale())
    }
}
