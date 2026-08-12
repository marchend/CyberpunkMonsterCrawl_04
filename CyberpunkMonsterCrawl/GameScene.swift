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

    /// World-space content: the streamed ground plane today (see
    /// `groundPlane` / `startGroundPlane()`), buildings and actors in later
    /// PRs. Lowest zPosition band; never receives touches ahead of `uiLayer`.
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

    // MARK: - SCAFFOLDING(CYBERPUN-17-7): debug camera pan
    //
    // `GameScene` has no real camera-follow behaviour yet — that lands with
    // `CYBERPUN-17-7` ("Wire the floating thumbstick, player movement,
    // building collision and camera"), which should delete this block. Until
    // then, `GroundPlaneStreamer`/`ChunkStreamingManager` have no in-app way
    // to be exercised across *many* chunk boundaries during a manual run or
    // an on-device check, so this is a minimal, clearly-marked stand-in: a
    // straight-line pan, off by default, that moves the camera far enough to
    // cross several chunks so multi-chunk streaming is visible end-to-end.
    // It is deliberately not physically based, not player-controlled and not
    // camera-follow — just enough motion to drive the streaming system.
    //
    // The whole block is `#if DEBUG`, so a shipped Release build physically
    // cannot pan on its own and carries none of this state. Nothing in the
    // test suite asserts the pan's behaviour either (see
    // `ChunkStreamingGroundTests`, which drives `GroundPlaneStreamer`
    // directly instead), so `CYBERPUN-17-7` can delete these lines without
    // deleting a green test.

    #if DEBUG
    /// Tiles per second the scaffolding debug pan moves the camera once
    /// `debugPanEnabled` is set. `Chunk.size` (8 tiles) at this rate crosses
    /// a chunk boundary every 2 seconds — slow enough to inspect visually,
    /// fast enough to sweep several boundaries in a short manual run.
    static let debugPanTilesPerSecond: Double = 4

    /// Turns the scaffolding debug pan on or off. Off by default, so normal
    /// gameplay (and every test in the suite) is unaffected; only a manual
    /// on-device check that explicitly opts in sees the camera move on its
    /// own.
    var debugPanEnabled = false

    /// Where in tile space, and at what `currentTime`, the debug pan most
    /// recently (re)started — `nil` whenever it hasn't run yet this
    /// `.gameplay` episode. Reset in `startGroundPlane()` so a fresh run
    /// (including RUN AGAIN) starts its pan from the new camera position
    /// rather than replaying stale timing from a previous run.
    private var debugPanOrigin: (worldPosition: TilePoint, time: TimeInterval)?
    #endif

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
    /// structured before `didMove(to:)` — tests construct a `GameScene`
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

        stateMachine.onChange = { [weak self] state in
            guard let self else { return }
            self.transitionScreens(to: state)
            self.updateWorldContent(for: state)
        }
    }

    // MARK: - World content

    /// Brings world content in step with `state`: entering `.gameplay` starts
    /// (or restarts) the streamed ground plane in `worldLayer`.
    ///
    /// The other three states leave the mounted ground alone rather than
    /// tearing it down — their screens each carry an opaque full-bleed
    /// backdrop precisely because they are meant to hide the world (see
    /// `GameplayScreenNode`, the one screen that deliberately does not), so
    /// nothing shows through, and RUN AGAIN then re-enters `.gameplay` with a
    /// world already in place.
    private func updateWorldContent(for state: GameState) {
        switch state {
        case .gameplay:
            startGroundPlane()
        case .menu, .death, .highScores:
            break
        }
    }

    /// Mounts the ground plane for `worldSeed`, centred on the camera's own
    /// world position: reusing the existing `GroundPlaneStreamer` when the
    /// seed is unchanged, and replacing it outright when the seed (and so
    /// the city) has changed.
    ///
    /// Exposed (rather than private) so tests can drive the mount directly on
    /// a scene built without an `SKView`, the same way the screen registry is
    /// exercised.
    func startGroundPlane() {
        if let existing = groundPlane, existing.seed == worldSeed {
            // Same seed means the same city, tile for tile (`WorldSeed`'s
            // whole contract), so the mounted ground is already correct for
            // this run: keep the streamer — and with it its recycle pool and
            // its generated chunks — and just bring residency back in step
            // with wherever the camera now sits. Tearing it down and
            // building a fresh `GroundPlaneStreamer` would discard the pool
            // with the old instance and re-allocate a whole resident
            // window's worth of `SKSpriteNode`s on every RUN AGAIN.
            existing.updateCamera(worldPosition: cameraWorldPosition)
        } else {
            // A different seed is a different city, so the old streamer's
            // generated chunks can't be reused.
            groundPlane?.unmountAll()
            let plane = GroundPlaneStreamer(seed: worldSeed, worldLayer: worldLayer)
            plane.updateCamera(worldPosition: cameraWorldPosition)
            groundPlane = plane
        }
        #if DEBUG
        // SCAFFOLDING(CYBERPUN-17-7): a fresh run means a fresh pan — clear
        // any stale origin so RUN AGAIN starts the debug pan (if enabled)
        // from wherever the new run's camera actually sits.
        debugPanOrigin = nil

        // Ground nodes are the first world-space content in the graph, so
        // audit the moment they land rather than at the next touch.
        assertSceneInvariants()
        #endif
    }

    #if DEBUG
    // SCAFFOLDING(CYBERPUN-17-7): see the block comment above `debugPanEnabled`.
    // `CYBERPUN-17-7` should delete `advanceDebugPanIfNeeded(currentTime:)`
    // and the `update(_:)` override below along with it once real
    // player/camera movement exists to exercise streaming instead. Both are
    // DEBUG-only, so a Release build has no per-frame work here at all.
    override func update(_ currentTime: TimeInterval) {
        super.update(currentTime)
        advanceDebugPanIfNeeded(currentTime: currentTime)
    }

    /// Moves the camera in a straight line (+x in tile space) at
    /// `debugPanTilesPerSecond`, driving `groundPlane`'s streaming as it
    /// goes, while `debugPanEnabled` is set and a run is in progress.
    /// No-ops otherwise, so it is safe to call unconditionally from
    /// `update(_:)`.
    private func advanceDebugPanIfNeeded(currentTime: TimeInterval) {
        guard debugPanEnabled, stateMachine.currentState == .gameplay, let plane = groundPlane else { return }

        let origin: (worldPosition: TilePoint, time: TimeInterval)
        if let existing = debugPanOrigin {
            origin = existing
        } else {
            origin = (worldPosition: cameraWorldPosition, time: currentTime)
            debugPanOrigin = origin
        }

        let elapsed = currentTime - origin.time
        let travelled = elapsed * Self.debugPanTilesPerSecond
        let newWorldPosition = TilePoint(x: origin.worldPosition.x + travelled, y: origin.worldPosition.y)

        plane.updateCamera(worldPosition: newWorldPosition)

        // Move the actual SpriteKit camera to match, converting the new
        // tile-space position through the same projection ground nodes use,
        // from worldLayer's coordinate space (where `tileToScreen` output
        // lives) into the scene's own — the space `cameraNode.position` is
        // expressed in.
        let screenPoint = IsometricProjection.tileToScreen(tileX: newWorldPosition.x, tileY: newWorldPosition.y)
        cameraNode.position = worldLayer.convert(screenPoint, to: self)
    }
    #endif

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
    func transitionScreens(to state: GameState) {
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
        #if DEBUG
        assertSceneInvariants()
        #endif
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        centreCameraOnScene()
        activeScreen?.layout(for: size, safeAreaInsets: currentSafeAreaInsets)
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

    // MARK: - Touch routing

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard let touch = touches.first else { return }
        dispatchTouch(atScenePoint: touch.location(in: self))
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
