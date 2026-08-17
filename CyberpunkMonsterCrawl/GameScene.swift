import SpriteKit
import UIKit

/// The game's single top-level scene: three persistent layers
/// (`worldLayer < effectsLayer < uiLayer`, per `LayerConstants`), a
/// `GameStateMachine` driving a `[GameState: ScreenNode]` registry that
/// swaps the active screen in `uiLayer`, and UI-first touch routing.
///
/// This is the structural fix for the v1 failure mode described in
/// `docs/bootstrap.md`: the world node rendered over the UI while every unit
/// test passed. Here, "the UI always wins" is a checked numeric fact
/// (`LayerOrderingTests`) and a checked routing function
/// (`TouchRoutingTests`), not an unenforced convention.
///
/// `GameViewController` presents this scene and registers `MenuScreenNode`
/// for `.menu` plus the skeleton `GameplayScreenNode` / `DeathScreenNode` /
/// `HighScoresScreenNode` for the remaining states, so the layer bands,
/// camera pinning, screen registry and touch dispatch below are reachable
/// from the running app rather than from unit tests only: launching the app
/// shows the menu, and tapping PLAY drives
/// `stateMachine.transition(to: .gameplay)` through `ButtonNode`.
/// `GameSceneScreenSwitchingTests` continues to exercise the generic swap
/// logic with `PlaceholderScreenNode` doubles.
final class GameScene: SKScene {

    // MARK: - Layers

    /// World-space content: the streamed ground plane (see `groundPlane` /
    /// `startGroundPlane()`) and the player (see `player` / `startPlayer()`);
    /// buildings and the raccoon swarm in later PRs. Lowest zPosition band;
    /// never receives touches ahead of `uiLayer`.
    ///
    /// Ground nodes are parented **directly** here, with the
    /// `worldLayer`-relative `zPosition` `DepthModel.worldLayerRelativeZ`
    /// produces — an intermediate container would add its own `zPosition` to
    /// every descendant and shift the whole depth scheme.
    let worldLayer = SKNode()

    /// Particles / muzzle flashes / hit puffs (future PRs). Sandwiched
    /// strictly between `worldLayer` and `uiLayer`.
    let effectsLayer = SKNode()

    /// Camera-pinned UI (HUD, menus, buttons). Highest zPosition band, and
    /// first refusal on every touch the scene dispatches - see
    /// `routeTouch(at:)` / `dispatchTouch(atScenePoint:)`.
    ///
    /// "First refusal" holds only because the scene is the *sole* touch
    /// dispatcher: UIKit hands a touch to any node with
    /// `isUserInteractionEnabled == true` before `touchesBegan(_:with:)`
    /// runs here, so that flag is banned graph-wide and audited by
    /// `nodesBypassingSceneTouchDispatch()`. See `TouchResponder` for the
    /// full contract.
    let uiLayer = SKNode()

    /// The scene's camera. `uiLayer` is parented to this node (not to the
    /// scene directly) so UI content stays camera-locked once world-camera
    /// scrolling lands (future PR).
    let cameraNode = SKCameraNode()

    // MARK: - State machine + screen registry

    /// Scene/rendering-agnostic menu/gameplay/death/highScores state
    /// machine (PR 1). `GameScene` is its first production caller.
    let stateMachine = GameStateMachine()

    /// State -> screen registry. Empty by default; the composition root
    /// (`GameViewController`) registers `MenuScreenNode`, `GameplayScreenNode`,
    /// `DeathScreenNode` and `HighScoresScreenNode` for their respective
    /// states.
    private(set) var screens: [GameState: ScreenNode] = [:]

    /// The screen currently mounted in `uiLayer`, if any.
    private(set) var activeScreen: ScreenNode?

    // MARK: - World content

    /// The seed the run's city is generated from.
    ///
    /// A fixed default so a launch is reproducible (and so the ground plane
    /// needs no extra composition-root plumbing to exist); whichever later
    /// story owns run setup can set this per run before `.gameplay` is
    /// entered, and the whole world follows from it — `WorldSeed`'s contract
    /// is that the same seed reproduces the identical city forever.
    var worldSeed = WorldSeed(rawValue: 0x0C17_5EED)

    /// The mounted ground plane, streamed into `worldLayer` while a run is in
    /// progress (`nil` before the first `.gameplay` entry).
    ///
    /// This is what makes `GroundTileRenderer` observable in a real build
    /// rather than in unit tests only: entering `.gameplay` mounts one ground
    /// node per tile of `ChunkStreamingManager`'s resident window, so tapping
    /// PLAY shows the generated city.
    private(set) var groundPlane: GroundPlaneStreamer?

    /// The mounted player, parented **directly** under `worldLayer` while a
    /// run is in progress (`nil` before the first `.gameplay` entry).
    ///
    /// `GroundTileRenderer`'s own type doc states this repo's rule --
    /// "A factory with no production caller is exactly the shape of feature
    /// that never gets switched on, so the mount is wired here rather than
    /// deferred" -- and `PlayerNode` is held to it: entering `.gameplay`
    /// puts a real player in the graph, at the run's spawn tile (see
    /// `RunSpawnSelector`), with its depth resolved through `DepthBanding`.
    ///
    /// `advanceMovementAndCamera(currentTime:)` drives this node's position,
    /// depth and visual state every frame: `thumbstick` -> `movementController`
    /// -> `CollisionResolver` -> commit position -> `cameraController`. This
    /// is the real replacement for the `SCAFFOLDING(CYBERPUN-17-7)` demo
    /// driver an earlier PR of this story stood in with while movement,
    /// collision and camera-follow did not exist yet.
    private(set) var player: PlayerNode?

    /// The player's current position in tile space -- the single source of
    /// truth `advanceMovementAndCamera(currentTime:)` resolves every frame.
    /// `player.position` (screen space, pixel-snapped) and the camera focus
    /// fed to `cameraController` are both derived from this, never the other
    /// way around. `nil` before the first `.gameplay` entry.
    private(set) var playerWorldPosition: TilePoint?

    /// The `currentTime` of the previous `update(_:)`, used to derive the
    /// per-frame delta handed to `player`'s visual/animation state. `nil`
    /// until the first frame runs, where the delta is `0` rather than an
    /// invented value.
    private var lastFrameTime: TimeInterval?

    /// The on-screen floating movement thumbstick (`CYBERPUN-17-7` PR 1).
    /// Mounted directly in `uiLayer` in `commonInit()` -- independent of the
    /// state-driven screen registry, since it is not itself a `ScreenNode`
    /// -- and shown only while a run is active (`isRunActive`, toggled by
    /// `updateWorldContent(for:)`). `touchesBegan`/`touchesMoved`/
    /// `touchesEnded`/`touchesCancelled` route the touch that engages it via
    /// `beginTouch(at:)`/`updateTouch(at:)`/`endTouch()` -- see
    /// `activeStickTouch`.
    let thumbstick = FloatingThumbstickNode()

    /// Turns `thumbstick`'s per-frame `StickState` into a tile-space
    /// proposed displacement, facing vector and `isMoving` flag
    /// (`CYBERPUN-17-7` PR 1). Fed the live stick reading every frame by
    /// `advanceMovementAndCamera(currentTime:)`.
    let movementController = PlayerMovementController()

    /// Keeps `playerWorldPosition` centred on screen (by repositioning
    /// `worldLayer`, never `cameraNode` -- see that type's own doc comment
    /// for why) and drives `groundPlane`'s chunk streaming with the same
    /// focus point every frame (`CYBERPUN-17-7` PR 2). Built in
    /// `commonInit()`, once `worldLayer` exists, so it is
    /// implicitly-unwrapped rather than given a stored-property initializer.
    private var cameraController: CameraController!

    /// The touch currently engaging `thumbstick`, if any -- tracked so
    /// `touchesMoved`/`touchesEnded`/`touchesCancelled` can tell the stick's
    /// own drag apart from any other concurrent touch (a button tap)
    /// without `FloatingThumbstickNode` itself needing to know about
    /// `UITouch` at all (see that type's own "touch-input agnostic" doc
    /// note). Held weakly: UIKit, not this scene, owns a touch's lifetime.
    private weak var activeStickTouch: UITouch?

    // MARK: - Init

    override init(size: CGSize) {
        super.init(size: size)
        commonInit()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }

    /// Builds the persistent layer hierarchy and wires the state machine.
    /// Runs from both designated initializers so `GameScene` is fully
    /// structured before `didMove(to:)` -- tests construct a `GameScene`
    /// directly (no `SKView`) and rely on this having already happened.
    private func commonInit() {
        // The dark "Pixel Grit" base every screen sits on. The menu, death
        // and high-scores screens each add their own opaque full-bleed
        // backdrop (they are meant to hide the world), but `GameplayScreenNode`
        // deliberately does not - the world must show *through* it - so the
        // scene itself supplies the fill rather than leaving SpriteKit's
        // lighter default showing behind gameplay.
        backgroundColor = PixelGritPalette.background

        addChild(worldLayer)
        addChild(effectsLayer)
        addChild(cameraNode)
        camera = cameraNode
        cameraNode.addChild(uiLayer)

        worldLayer.zPosition = LayerConstants.worldLayerZ
        effectsLayer.zPosition = LayerConstants.effectsLayerZ
        uiLayer.zPosition = LayerConstants.uiLayerZ

        // Mounted directly, independent of the state-driven screen
        // registry -- the thumbstick is not a `ScreenNode`, it just stays
        // hidden (`isRunActive == false`) outside `.gameplay`. Laid out
        // immediately with this scene's own `size` and zero insets so a
        // headless (view-less) scene -- which never calls `didMove(to:)` --
        // still satisfies `FloatingThumbstickNode`'s "layout must have run
        // before a touch is asked about" precondition; `didMove(to:)` /
        // `didChangeSize(_:)` refresh it with the real safe-area insets once
        // a view attaches.
        uiLayer.addChild(thumbstick)
        thumbstick.layout(for: size, safeAreaInsets: .zero)

        // Repositions `worldLayer` (never `cameraNode`) to keep
        // `playerWorldPosition` centred on screen, and forwards the same
        // focus point to `groundPlane`'s chunk streaming every frame -- see
        // `CameraController`'s own doc comment for why `worldLayer`, not the
        // camera, is the node that moves.
        cameraController = CameraController(
            container: worldLayer,
            deviceScale: { [weak self] in self?.deviceScale ?? 1 },
            streamingUpdate: { [weak self] worldPosition in
                self?.groundPlane?.updateCamera(worldPosition: worldPosition)
            }
        )

        stateMachine.onChange = { [weak self] state in
            guard let self else { return }
            self.transitionScreens(to: state)
            self.updateWorldContent(for: state)
        }
    }

    // MARK: - World content

    /// Brings world content in step with `state`: entering `.gameplay` picks
    /// the run's spawn tile (`RunSpawnSelector`), starts (or restarts) the
    /// streamed ground plane centred there, mounts (or repositions) the
    /// player on it, shows the thumbstick and drives the camera/streaming
    /// to that same focus point immediately -- so the very first frame of a
    /// run already shows the player centred on-screen rather than only
    /// catching up once `update(_:)` next runs.
    ///
    /// The other three states leave the mounted ground alone rather than
    /// tearing it down -- their screens each carry an opaque full-bleed
    /// backdrop precisely because they are meant to hide the world (see
    /// `GameplayScreenNode`, the one screen that deliberately does not), so
    /// nothing shows through, and RUN AGAIN then re-enters `.gameplay` with a
    /// world already in place. They do hide the thumbstick, though -- there
    /// is nothing to move outside a run, and `FloatingThumbstickNode
    /// .isRunActive`'s own `didSet` cancels any in-flight drag when it goes
    /// false, so a run ending mid-drag can never strand the stick off-centre.
    private func updateWorldContent(for state: GameState) {
        switch state {
        case .gameplay:
            let spawn = spawnTilePosition()
            playerWorldPosition = spawn
            startGroundPlane()
            // After the ground, so the player is mounted onto a world that
            // already exists; ordering in `worldLayer` is decided by
            // `DepthModel`/`DepthBanding` zPositions, not by child order.
            startPlayer(at: spawn)
            thumbstick.isRunActive = true
            cameraController.update(focus: spawn, viewportSize: size)
            #if DEBUG
            assertSceneInvariants()
            #endif
        case .menu, .death, .highScores:
            thumbstick.isRunActive = false
        }
    }

    /// The run's start tile for `worldSeed`, chosen once per `.gameplay`
    /// entry via `RunSpawnSelector` -- a street-intersection tile,
    /// guaranteed street under every seed (see that type's own doc
    /// comment).
    private func spawnTilePosition() -> TilePoint {
        let tile = RunSpawnSelector.selectSpawnTile(seed: worldSeed)
        return TilePoint(x: Double(tile.tileX), y: Double(tile.tileY))
    }

    /// Ensures the ground plane matches `worldSeed`: keeping the existing
    /// `GroundPlaneStreamer` when the seed is unchanged, and replacing it
    /// outright when the seed (and so the city) has changed. Does not itself
    /// mount any tiles -- `updateWorldContent(for:)`'s subsequent
    /// `cameraController.update(focus:viewportSize:)` call is what drives
    /// `updateCamera(worldPosition:)` and actually streams the quickstart
    /// ring in, for both a kept and a freshly built streamer alike.
    ///
    /// Exposed (rather than private) so tests can drive the mount directly on
    /// a scene built without an `SKView`, the same way the screen registry is
    /// exercised.
    func startGroundPlane() {
        guard groundPlane == nil || groundPlane?.seed != worldSeed else {
            // Same seed means the same city, tile for tile (`WorldSeed`'s
            // whole contract), so the mounted ground is already correct for
            // this run: keep the streamer -- and with it its recycle pool
            // and its generated chunks -- rather than discarding the pool
            // and re-allocating a whole resident window's worth of
            // `SKSpriteNode`s on every RUN AGAIN.
            return
        }
        // A different seed is a different city, so the old streamer's
        // generated chunks can't be reused.
        groundPlane?.unmountAll()
        groundPlane = GroundPlaneStreamer(seed: worldSeed, worldLayer: worldLayer)
    }

    /// Mounts the player into `worldLayer` at `tilePosition` (the run's spawn
    /// tile on first mount, per `updateWorldContent(for:)`), or repositions
    /// the already-mounted one there when a run restarts.
    ///
    /// The node is parented **directly** under `worldLayer` (the same
    /// convention the ground nodes follow) because that is the one mount
    /// point `PlayerNode.updateDepth(atTilePosition:)` documents: it converts
    /// its absolute depth through `DepthModel.worldLayerRelativeZ(
    /// forAbsoluteZ:)`, which is only correct for a direct child. An
    /// intermediate container would add its own `zPosition` to the player and
    /// shift it out of the band the depth scheme placed it in.
    ///
    /// A restart reuses the existing node rather than building a second one:
    /// two `PlayerNode`s in the graph is not a cosmetic bug but a duplicated
    /// actor at the same depth, and the reuse keeps the sliced-texture cache
    /// and the node identity stable across RUN AGAIN.
    ///
    /// Exposed (rather than private) for the same reason as
    /// `startGroundPlane()`: tests drive the mount directly on a scene built
    /// without an `SKView`.
    func startPlayer(at tilePosition: TilePoint) {
        let mounted: PlayerNode
        if let existing = player {
            mounted = existing
        } else {
            mounted = PlayerNode()
            player = mounted
        }

        if mounted.parent !== worldLayer {
            mounted.removeFromParent()
            worldLayer.addChild(mounted)
        }

        // Snapped via `PixelCrispness` (not assigned raw) because
        // `IsometricProjection.tileToScreen`'s floating-point arithmetic can
        // drift a fraction of a device pixel off a whole point even when the
        // input tile position looks clean. The world's whole rendering rule
        // is hard, un-resampled pixel edges (`docs/bootstrap.md` section 1).
        // `deviceScale` falls back to `1` for a headless (view-less) scene,
        // which whole-point-snaps instead -- still correct, just coarser
        // than a real device's `@2x`/`@3x` grid.
        let rawPosition = IsometricProjection.tileToScreen(tileX: tilePosition.x, tileY: tilePosition.y)
        mounted.position = PixelCrispness.snappedPosition(for: rawPosition, scale: deviceScale)
        mounted.updateDepth(atTilePosition: tilePosition)

        #if DEBUG
        // The player is the first non-ground world content in the graph, and
        // its depth comes from a different part of the model than the ground
        // does (`DepthBanding`'s actor band rather than the ground offset),
        // so audit the moment it lands.
        assertSceneInvariants()

        // Pixel-crispness invariant (CYBERPUN-17-6-t3): the body sprite must
        // stay nearest-filtered, mipmap-free and whole-integer-scaled at the
        // moment the player is spawned -- `PixelCrispness.apply(to:)`
        // (called once, in `PlayerNode.init`) is what guarantees this, and
        // this assert exists so a future change to that finalization pass
        // trips here rather than only being caught by `PlayerNodeTests`.
        assert(
            mounted.body.texture?.filteringMode == .nearest,
            "The player's body must stay nearest-filtered at spawn time."
        )
        assert(
            mounted.body.texture?.usesMipmaps == false,
            "The player's body must never generate mipmaps."
        )
        assert(
            PixelCrispness.isIntegerScale(mounted.body.xScale)
                && PixelCrispness.isIntegerScale(mounted.body.yScale),
            "The player's body scale must stay whole-integer at spawn time, got "
                + "(\(mounted.body.xScale), \(mounted.body.yScale))."
        )
        #endif
    }

    /// The device scale (`@1x`/`@2x`/`@3x`) content is being rendered at --
    /// `view.contentScaleFactor` once the scene is presented, or `1` for a
    /// headless (view-less) scene, as unit tests construct. Read here rather
    /// than assumed at each call site, so `PixelCrispness.snappedPosition(
    /// for:scale:)` always snaps to the grid the running device actually
    /// composites at.
    private var deviceScale: CGFloat {
        view?.contentScaleFactor ?? 1
    }

    /// Advances the run's movement pipeline for one frame, in a fixed order:
    /// read `thumbstick` -> resolve `movementController`'s proposed
    /// displacement -> resolve it against building collision
    /// (`CollisionResolver`) -> commit the result to `playerWorldPosition`
    /// and the mounted player's position/depth/visual state -> drive
    /// `cameraController` (world-layer offset + chunk streaming) from that
    /// same resolved position.
    ///
    /// This is the real replacement for the `SCAFFOLDING(CYBERPUN-17-7)`
    /// demo driver an earlier PR of this story used while the thumbstick,
    /// `PlayerMovementController` and `CollisionResolver` existed but were
    /// not yet wired into a live scene. A no-op before the first
    /// `.gameplay` entry (`player`/`playerWorldPosition` are both `nil`).
    private func advanceMovementAndCamera(currentTime: TimeInterval) {
        // The player's visual/animation deltaTime is derived independently
        // of `movementController`'s own internal clock (which additionally
        // clamps to `PlayerMovementController.maxFrameDelta`), exactly as
        // before this pipeline existed: an idle player still freezes at
        // walk-cycle frame 0 whatever the movement math below computes.
        // `max(0, ...)` because `currentTime` is the render clock: a scene
        // presented, backgrounded and re-presented can hand back a smaller
        // value, and a negative delta would run the walk cycle backwards.
        let deltaTime = lastFrameTime.map { max(0, currentTime - $0) } ?? 0
        lastFrameTime = currentTime

        guard let player, let currentPosition = playerWorldPosition else { return }

        movementController.update(stickState: thumbstick.stickState, currentTime: currentTime)

        let obstructions = groundPlane?.streaming.residentChunks.values.flatMap { $0.buildingPlacements } ?? []
        let resolvedPosition = CollisionResolver.resolve(
            currentPosition: currentPosition,
            proposedDelta: movementController.frameDisplacement,
            obstructedBy: obstructions
        )
        playerWorldPosition = resolvedPosition

        let rawPosition = IsometricProjection.tileToScreen(resolvedPosition)
        player.position = PixelCrispness.snappedPosition(for: rawPosition, scale: deviceScale)
        player.updateDepth(atTilePosition: resolvedPosition)

        // `PlayerNode` reads "moving" from a non-zero vector, so the facing
        // vector (which persists at its last value below the stick's dead
        // zone) is only ever handed over while `isMoving` is actually true.
        let visualVector = movementController.isMoving ? movementController.facingVector : .zero
        player.update(deltaTime: deltaTime, movementVector: visualVector)

        cameraController.update(focus: resolvedPosition, viewportSize: size)
    }

    /// Drains `groundPlane`'s incremental-mount queue a few chunks at a time
    /// (`GroundPlaneStreamer.advanceIncrementalMount()`) and advances the
    /// run's movement/camera pipeline (`advanceMovementAndCamera(
    /// currentTime:)`).
    ///
    /// `CYBERPUN-17-4-t4`: the incremental-mount drain runs in Release too,
    /// deliberately. It exists to fix a real stall (entering `.gameplay` used
    /// to mount the entire resident chunk window synchronously, inside the
    /// PLAY tap's own call stack, which a runtime probe caught mid-stall), so
    /// it is production behaviour. It is also what keeps the deferred
    /// remainder moving now that `cameraController` drives `updateCamera`
    /// every frame: `updateCamera` only ever mounts the quickstart ring, so
    /// this drain is the only thing that brings the rest of the window in.
    override func update(_ currentTime: TimeInterval) {
        super.update(currentTime)
        groundPlane?.advanceIncrementalMount()
        advanceMovementAndCamera(currentTime: currentTime)
    }

    /// Where the camera sits in **tile space**, derived through the same
    /// projection the ground nodes are placed with, so the resident chunk
    /// window is centred on what the camera can actually see rather than on
    /// the world origin.
    var cameraWorldPosition: TilePoint {
        IsometricProjection.screenToTile(worldLayer.convert(cameraNode.position, from: self))
    }

    // MARK: - Screen registry

    /// Registers (or replaces) the screen node for `state`.
    ///
    /// If `state` is the state machine's current state, the newly registered
    /// screen becomes the active screen immediately: with nothing active
    /// this is the first mount (which lets a caller register the initial
    /// `.menu` screen right after construction without a separate "activate
    /// now" call), and with a *different* screen already mounted for that
    /// state it is a full swap through `transitionScreens(to:)` -
    /// `willExit()` + removal of the outgoing screen, then mount, layout and
    /// `willEnter()` on the replacement. Registering the screen that is
    /// already active is a no-op, so a repeat registration cannot double up
    /// `willExit()`/`willEnter()` on the same instance.
    ///
    /// Without the swap, `screens[state]` and the scene graph would disagree
    /// until some transition away and back happened - and for `.menu` at
    /// startup that may be never.
    func register(_ screen: ScreenNode, for state: GameState) {
        screens[state] = screen
        guard stateMachine.currentState == state else { return }
        guard activeScreen !== screen else { return }
        transitionScreens(to: state)
    }

    /// Swaps the active screen in `uiLayer` for `state`: `willExit()` then
    /// removal of the outgoing screen (if any), followed by mounting,
    /// layout and `willEnter()` on the incoming screen (if one is
    /// registered for `state`). A state with no registered screen at all
    /// (not possible in the composed app today, but exercised directly by
    /// unit tests) simply clears `activeScreen`.
    ///
    /// A screen swap replaces the whole accessible UI without resizing the
    /// hosting view, so it triggers no `layoutSubviews()` /
    /// `didMoveToWindow()` / `presentScene(_:)` pass - and
    /// `SceneAccessibilityContainerView` deliberately no longer rebuilds its
    /// mirrors lazily from an accessibility query (doing so mutated the
    /// hierarchy a driver was mid-way through resolving, which is what made a
    /// correctly-framed PLAY button report `isHittable == false`). This is
    /// therefore the explicit refresh point for the change: the `defer` runs
    /// on *every* exit path, including the early return for a state with no
    /// registered screen, so mirrors for an unmounted screen (`menu.*`, most
    /// obviously) are always retired.
    func transitionScreens(to state: GameState) {
        defer { (view as? AccessibleSKView)?.refreshSceneAccessibility() }

        if let current = activeScreen {
            current.willExit()
            current.node.removeFromParent()
            activeScreen = nil
        }
        guard let next = screens[state] else { return }
        uiLayer.addChild(next.node)
        next.layout(for: size, safeAreaInsets: currentSafeAreaInsets)
        next.willEnter()
        activeScreen = next
        #if DEBUG
        // A newly mounted screen is the most likely source of an out-of-band
        // zPosition or a node that steals touch delivery, so audit here
        // rather than waiting for the first touch.
        assertSceneInvariants()
        #endif
    }

    // MARK: - Layout

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        // `uiLayer` is camera-pinned, so it is centred whatever the camera
        // does; the camera is centred on the scene so world-space content
        // (future PRs) lines up with the scene's 0..width / 0..height
        // coordinate space instead of showing its bottom-left quadrant.
        centreCameraOnScene()
        activeScreen?.layout(for: size, safeAreaInsets: currentSafeAreaInsets)
        thumbstick.layout(for: size, safeAreaInsets: currentSafeAreaInsets)
        #if DEBUG
        assertSceneInvariants()
        #endif
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        centreCameraOnScene()
        activeScreen?.layout(for: size, safeAreaInsets: currentSafeAreaInsets)
        thumbstick.layout(for: size, safeAreaInsets: currentSafeAreaInsets)
    }

    /// Only applied once the scene is presented (and on every size change,
    /// i.e. rotation). Unit-test scenes are built without an `SKView`, so
    /// they keep the camera at the origin and their scene-space coordinates
    /// map straight through to `uiLayer`.
    private func centreCameraOnScene() {
        guard view != nil else { return }
        cameraNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
    }

    private var currentSafeAreaInsets: UIEdgeInsets {
        view?.safeAreaInsets ?? .zero
    }

    // MARK: - Accessibility

    /// Every *visible* node in the `uiLayer` subtree that presents itself to
    /// UIAccessibility (`isAccessibilityElement == true`), in scene-graph
    /// order.
    ///
    /// `AccessibleSKView` publishes one `UIAccessibilityElement` per entry.
    /// The walk lives here rather than inside the view so it is testable
    /// without a live `SKView`, a window or an accessibility client - see
    /// `AccessibleSKViewTests`.
    ///
    /// Only `uiLayer` is walked: `worldLayer`/`effectsLayer` hold thousands
    /// of ground tiles and (later) actors, none of which is an accessibility
    /// element, and none of which is ever the target of an element-driven
    /// tap.
    ///
    /// Invisible nodes are skipped so the walk stays *total* with respect to
    /// this feature's central invariant - "the published frame and the hit
    /// test cannot disagree". `routeTouch(at:)` resolves through
    /// `SKNode.atPoint(_:)`, which never returns a hidden node, so an
    /// invisible accessible node would publish a frame that an
    /// element-driven tap aims at and the scene then refuses to route: the
    /// original defect wearing yet another hat. Nothing hides a button
    /// today; this keeps it from becoming a bug the day something does.
    func accessibleUINodes() -> [SKNode] {
        var accessible: [SKNode] = []
        collectAccessibleNodes(under: uiLayer, into: &accessible)
        return accessible
    }

    private func collectAccessibleNodes(under node: SKNode, into accessible: inout [SKNode]) {
        for child in node.children {
            // The whole subtree is skipped, not just the node itself:
            // hiding a parent hides everything under it, so its descendants
            // are equally unreachable by `atPoint(_:)`.
            guard isVisibleToTouchRouting(child) else { continue }
            if child.isAccessibilityElement {
                accessible.append(child)
            }
            collectAccessibleNodes(under: child, into: &accessible)
        }
    }

    /// Whether `node` can be returned by the `atPoint(_:)` walk
    /// `routeTouch(at:)` performs. `isHidden` is what SpriteKit's hit test
    /// itself honours; `alpha <= 0` is filtered too because a node nobody
    /// can see is a node nobody should be told to tap - and erring towards
    /// publishing *fewer* elements keeps "published implies routable" true
    /// in the safe direction.
    private func isVisibleToTouchRouting(_ node: SKNode) -> Bool {
        !node.isHidden && node.alpha > 0
    }

    /// `node`'s accumulated frame expressed in **scene** coordinates - the
    /// single geometric fact `AccessibleSKView` turns into an
    /// `accessibilityFrame`, and the exact space
    /// `dispatchTouch(atScenePoint:)` takes its argument in.
    ///
    /// Derived through `SKNode.convert(_:from:)` off the node's own parent,
    /// which is the algebraic inverse of the `uiLayer.convert(_:from: self)`
    /// + `atPoint(_:)` walk `routeTouch(at:)` performs. That is what makes
    /// "the frame an element-driven tap aims at" and "the point the scene
    /// hit-tests" the same number *by construction* rather than by luck: the
    /// two paths cannot disagree, which is precisely the failure the runtime
    /// probe hit (see `AccessibleSKView`). `AccessibleSKViewTests` pins the
    /// agreement so it cannot silently regress.
    ///
    /// Returns `nil` for a node with no parent (nothing to convert from).
    /// A marker node with no visual content of its own (e.g.
    /// `MenuScreenNode`'s `menu.container`) legitimately yields an *empty*
    /// rect - it is still published, so it can still be found by identifier,
    /// but it is not meant to be tapped.
    func accessibilityFrameInScene(for node: SKNode) -> CGRect? {
        guard let parent = node.parent else { return nil }

        let frameInParent = node.calculateAccumulatedFrame()

        // A marker node with no visual content of its own has no accumulated
        // frame, and SpriteKit is entitled to report that as a null/infinite
        // rect - whose corners would subtract into NaN and reach UIKit as a
        // NaN `accessibilityFrame`. Publish a zero-size rect at the node's own
        // position instead: findable by identifier, honestly not tappable.
        if frameInParent.isNull || frameInParent.isInfinite {
            return CGRect(origin: convert(node.position, from: parent), size: .zero)
        }

        let corners = [
            CGPoint(x: frameInParent.minX, y: frameInParent.minY),
            CGPoint(x: frameInParent.maxX, y: frameInParent.minY),
            CGPoint(x: frameInParent.minX, y: frameInParent.maxY),
            CGPoint(x: frameInParent.maxX, y: frameInParent.maxY),
        ].map { self.convert($0, from: parent) }

        // All four corners, so a rotated node still yields a containing box.
        let xs = corners.map(\.x)
        let ys = corners.map(\.y)
        guard
            let minX = xs.min(), let maxX = xs.max(),
            let minY = ys.min(), let maxY = ys.max()
        else {
            return nil
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // MARK: - Touch routing

    /// UI responders (buttons) get first refusal, exactly like every other
    /// touch this scene dispatches: `dispatchTouch(atScenePoint:)` only
    /// returns `nil` when nothing in `uiLayer`/`worldLayer` claimed the
    /// touch, and only then is `thumbstick.beginTouch(at:)` offered it --
    /// which itself refuses outside the left region / the reserved
    /// pulse-button slot / while no run is active (`canBeginTouch(at:)`).
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard let touch = touches.first else { return }
        let scenePoint = touch.location(in: self)

        if dispatchTouch(atScenePoint: scenePoint) != nil {
            return
        }

        if thumbstick.beginTouch(at: uiLayer.convert(scenePoint, from: self)) {
            activeStickTouch = touch
        }
    }

    /// Forwards the drag to `thumbstick` when the moved touch is the one
    /// tracking it (`activeStickTouch`); a no-op for any other touch (a
    /// button press moving slightly under a finger has nothing to do with
    /// the stick).
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        guard let touch = touches.first(where: { $0 === activeStickTouch }) else { return }
        thumbstick.updateTouch(at: uiLayer.convert(touch.location(in: self), from: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        endStickTrackingIfNeeded(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        endStickTrackingIfNeeded(touches)
    }

    private func endStickTrackingIfNeeded(_ touches: Set<UITouch>) {
        guard touches.contains(where: { $0 === activeStickTouch }) else { return }
        thumbstick.endTouch()
        activeStickTouch = nil
    }

    /// Routes `scenePoint` UI-first and *delivers* the touch to the nearest
    /// `TouchResponder` at or above the hit node, returning the responder
    /// that consumed it (or `nil` if nothing responded).
    ///
    /// This is the whole of `touchesBegan(_:with:)`'s body apart from
    /// unwrapping the `UITouch`, and it is the seam the tests drive:
    /// `UITouch` cannot be constructed with a location in a unit test, so
    /// `TouchDispatchTests` exercises this method rather than reimplementing
    /// routing against the pure `routeTouch(at:)` helper.
    ///
    /// The touch is delivered to the nearest `TouchResponder` *ancestor* of
    /// the hit node rather than to the hit node itself because
    /// `SKNode.atPoint(_:)` returns the deepest descendant under the point -
    /// for a `ButtonNode` that is its label, not the button.
    @discardableResult
    func dispatchTouch(atScenePoint scenePoint: CGPoint) -> TouchResponder? {
        #if DEBUG
        assertSceneInvariants()
        #endif
        guard let hit = routeTouch(at: scenePoint) else { return nil }
        guard let responder = touchResponder(for: hit) else { return nil }
        responder.handleTouch()
        return responder
    }

    /// Walks up from `node` to the nearest `TouchResponder`, stopping at the
    /// layer containers (a responder must live *inside* a layer, so the
    /// walk never escapes into the scene itself).
    func touchResponder(for node: SKNode) -> TouchResponder? {
        var candidate: SKNode? = node
        while let current = candidate {
            if let responder = current as? TouchResponder { return responder }
            if current === uiLayer || current === effectsLayer
                || current === worldLayer || current === self {
                return nil
            }
            candidate = current.parent
        }
        return nil
    }

    /// UI-first touch routing: returns the node hit under `uiLayer` at
    /// `scenePoint`, if any; otherwise falls through to the node hit under
    /// `worldLayer`; otherwise `nil`. Pure and independently testable —
    /// `TouchRoutingTests` calls it directly with overlapping UI/world nodes
    /// to prove the UI wins.
    func routeTouch(at scenePoint: CGPoint) -> SKNode? {
        let uiPoint = uiLayer.convert(scenePoint, from: self)
        let uiHit = uiLayer.atPoint(uiPoint)
        if uiHit !== uiLayer {
            return uiHit
        }

        let worldPoint = worldLayer.convert(scenePoint, from: self)
        let worldHit = worldLayer.atPoint(worldPoint)
        return worldHit !== worldLayer ? worldHit : nil
    }
}
