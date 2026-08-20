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
    ///
    /// **Nothing in the app writes this today** (only tests do), which is why
    /// the run's spawn junction is currently the same on every run rather
    /// than a new one each time — see `spawnTilePosition()` for the full
    /// note and where that gap is tracked.
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
    /// is the real replacement for the earlier PR's now-deleted demo driver,
    /// which this story stood in with while movement, collision and
    /// camera-follow did not exist yet.
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

    /// Off-screen spawn selection and per-frame seek/avoidance for the
    /// raccoon swarm (`CYBERPUN-17-8` PR 2). Built in `commonInit()`, once
    /// `worldLayer` exists, so it is implicitly-unwrapped like
    /// `cameraController`. `updateWorldContent(for:)` resets it on every
    /// fresh entry to `.gameplay`, and `advanceMovementAndCamera(currentTime:)`
    /// drives its single `update(deltaTime:playerPosition:player:obstructions:)`
    /// call site on every frame **of a run** -- that call is gated on
    /// `stateMachine.currentState == .gameplay`, so the swarm neither
    /// spawns nor steers while the death/high-scores/menu screens are up
    /// (see the gate's own comment for why the `player`/`playerWorldPosition`
    /// guard above it is not enough on its own).
    private var raccoonSpawnDirector: RaccoonSpawnDirector!

    /// Spawn/placement/lifetime engine for ground pickups (med kits,
    /// garbage cans) -- `CYBERPUN-17-11` PR 3, the wiring PR for the
    /// pure-logic `PickupManager` (PR 1) and the player/raccoon consume
    /// effects (PR 2). Built in `commonInit()`, once `worldLayer` exists,
    /// implicitly-unwrapped like `cameraController`/`raccoonSpawnDirector`.
    /// `raccoonSpawnDirector` is handed a reference to this same instance so
    /// `RaccoonSeekBehavior`'s garbage-can diversion (PR 2) can query and
    /// consume a real, currently-active pickup rather than only the
    /// isolated `TilePoint?` its own tests pass by hand.
    ///
    /// `private(set)` (not `private`) so `PickupIntegrationTests` can assert
    /// on `activePickups.count` directly, the same way `groundPlane` and
    /// `runStats` are exposed for their own scene-integration tests.
    private(set) var pickupManager: PickupManager!

    /// One mounted `PickupNode` per `Pickup` `pickupManager` currently
    /// reports active (and not yet consumed), keyed by `Pickup.id` so
    /// `syncPickupNodes()` mounts/unmounts exactly the nodes that changed
    /// each frame rather than tearing down and rebuilding the whole set --
    /// the same "diff, don't rebuild" discipline `GroundPlaneStreamer`'s
    /// pool follows for its own much larger node population.
    private var pickupNodes: [UUID: PickupNode] = [:]

    /// Tile-space radius within which the player collects a med kit on
    /// contact. Small and fixed, the same order of magnitude as
    /// `RaccoonSeekBehavior.garbageCanArrivalRangeTiles` (`0.5`) -- a
    /// stationary ground pickup consumed by proximity, not a hitbox-overlap
    /// test against `PlayerSpriteSheet.hitboxSize`. An initial tuning
    /// constant, like every other pickup-feel number this story ships
    /// (`RaccoonSeekBehavior.pointsPerSecond` etc.) -- expected to move in a
    /// later playtesting pass.
    static let medKitCollectionRadiusTiles: Double = 0.5

    /// The current run's counters (`CYBERPUN-17-8` PR 3): kills recorded by
    /// every raccoon `raccoonSpawnDirector` spawns, infections recorded by
    /// every bite that rolls a success. One instance for the scene's whole
    /// lifetime -- `updateWorldContent(for:)` calls `reset()` on it at each
    /// `.gameplay` entry rather than swapping the object, so the
    /// death-screen summary (`CYBERPUN-17-13`) can hold this reference.
    let runStats = RunSummaryStats()

    /// Seconds elapsed in the current (or most recently completed)
    /// `.gameplay` run (`CYBERPUN-17-13`) -- the source for the death
    /// screen's SURVIVED/SURVIVAL rows. Reset to `0` on every fresh
    /// `.gameplay` entry (`updateWorldContent(for:)`, beside `runStats
    /// .reset()`) and incremented only while `stateMachine.currentState
    /// == .gameplay`, the same gate `raccoonSpawnDirector`/`pickupManager`/
    /// `playerCombat` share below -- so time parked on the death/
    /// high-scores/menu screen after a run ends is never counted toward
    /// the *next* run's clock.
    private(set) var runElapsedSeconds: TimeInterval = 0

    /// Persisted high-score table (`CYBERPUN-17-13`), constructed once for
    /// the scene's whole lifetime over the app's real `UserDefaults` suite.
    /// `DeathScreenNode` records into this exactly once per death
    /// (`willEnter()`); `HighScoresScreenNode` reads it every time it is
    /// shown.
    ///
    /// Force-unwrapped rather than optional: `HighScoreStore
    /// .productionSuiteName` is a hardcoded constant that is neither the
    /// app's own bundle identifier nor `NSGlobalDomain` (the only two
    /// values `UserDefaults(suiteName:)` rejects), so `nil` here would mean
    /// that constant itself is wrong -- a programmer error worth crashing
    /// on, not a reason to silently fall back to `.standard` (see
    /// `HighScoreStore`'s own doc comment on why it never does).
    /// `HighScoreStoreTests
    /// .test_productionSuiteName_isConstructible_andNotAReservedDomain`
    /// pins that this construction succeeds.
    let highScoreStore = HighScoreStore(suiteName: HighScoreStore.productionSuiteName)!

    /// The player's targeting/firing/bullets/effects/progression
    /// composition (`CYBERPUN-17-9` PR 3): constructed once, lazily, in
    /// `startPlayer(at:)` the first time a run mounts `PlayerNode` (its
    /// `body` sprite must already exist), and reused thereafter --
    /// `reset()`, never rebuilt, across a RUN AGAIN, the same convention
    /// `startPlayer(at:)` already follows for `PlayerNode` itself. Driven
    /// once per frame of an active run from
    /// `advanceMovementAndCamera(currentTime:)`, fed
    /// `raccoonSpawnDirector.targetCandidates` for this frame's live
    /// targets. `private(set)` (not `private`) so scene-wiring tests can
    /// assert on it directly, the same way `groundPlane`/`runStats` are
    /// exposed for theirs.
    private(set) var playerCombat: Player?

    // MARK: - Pulse ability (`CYBERPUN-17-10-t3`)

    /// The player-triggered pulse ability's pure decision layer
    /// (`CYBERPUN-17-10-t1`; `Sources/Abilities/PulseAbility.swift`).
    /// Ticked every `.gameplay` frame from
    /// `advanceMovementAndCamera(currentTime:)` (so its cooldown counts
    /// down whether or not a press ever lands, the same "no ticking behind
    /// an opaque death/high-scores/menu backdrop" reasoning
    /// `raccoonSpawnDirector`/`pickupManager`/`playerCombat` are all
    /// gated on) and consumed by `applyPulseTrigger(raccoons:)` on every
    /// accepted `pulseButton` press.
    let pulseAbility = PulseAbility()

    /// The random source `pulseAbility.trigger(...)`'s damage rolls draw
    /// from. A plain `SystemRandomNumberGenerator` -- unlike
    /// `raccoonSpawnDirector`'s own `SplitMix64RandomNumberGenerator`,
    /// nothing about the pulse's damage rolls needs to be
    /// deterministic/seedable in a real run, and keeping this independent
    /// of the swarm's own RNG stream means the two can never accidentally
    /// interact.
    private var pulseRNG = SystemRandomNumberGenerator()

    /// The pulse's ring visual (`Sources/Rendering/PulseRingNode.swift`):
    /// a single reused node -- see that type's own "One reused instance"
    /// doc note -- mounted directly under `effectsLayer` in
    /// `commonInit()`, hidden until the first trigger.
    let pulseRing = PulseRingNode()

    /// The HUD pulse-ability button (`CYBERPUN-17-10-t2`;
    /// `Sources/UI/PulseButton.swift`). Built in `commonInit()` (its
    /// `onPress` closure captures `self`, so unlike `thumbstick` it cannot
    /// be a plain stored-property initializer) and mounted at
    /// `FloatingThumbstickNode.reservedPulseButtonSlot(forSize:
    /// safeAreaInsets:)`, positioned from the slot's *centre*
    /// (`layoutPulseButton()`) per that method's own mount instructions.
    /// Hidden outside `.gameplay` by `updateWorldContent(for:)`, the same
    /// way `thumbstick.isRunActive` gates the movement stick -- this node
    /// has no `isRunActive`-style gate of its own (see its own doc
    /// comment), so the scene owns hiding it. `private(set)` so
    /// scene-wiring tests can drive a real press via
    /// `pulseButton.handleTouch()`, the same way `groundPlane`/`playerCombat`
    /// are exposed for theirs.
    private(set) var pulseButton: PulseButton!

    /// The touch currently engaging `thumbstick`, if any -- tracked so
    /// `touchesMoved`/`touchesEnded`/`touchesCancelled` can tell the stick's
    /// own drag apart from any other concurrent touch (a button tap)
    /// without `FloatingThumbstickNode` itself needing to know about
    /// `UITouch` at all (see that type's own "touch-input agnostic" doc
    /// note). Held weakly: UIKit, not this scene, owns a touch's lifetime.
    ///
    /// A *concurrent* touch really can arrive: `GameViewController` sets
    /// `isMultipleTouchEnabled` on the hosting view, and
    /// `touchesBegan(_:with:)` routes every touch of an event set rather than
    /// only `touches.first`. Until both of those were true this property was
    /// bookkeeping for a case UIKit could never deliver.
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

        // `PulseButton`'s `onPress` closure captures `self`, so it is
        // built here (once `self` is fully initialized) rather than as a
        // stored-property initializer the way `thumbstick` is. Hidden
        // until the first `.gameplay` entry, mirroring `thumbstick`'s own
        // headless-safe layout call above.
        pulseButton = PulseButton(onPress: { [weak self] in
            self?.handlePulsePress()
        })
        pulseButton.isHidden = true
        uiLayer.addChild(pulseButton)
        layoutPulseButton()

        // The pulse's ring visual: one reused node, hidden until the
        // ability first fires (see `PulseRingNode`'s own "One reused
        // instance" doc note). Mounted directly under `effectsLayer`, the
        // same convention `HitEffects`' transient combat visuals follow.
        effectsLayer.addChild(pulseRing)

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

        // Built before `raccoonSpawnDirector` so that instance can be handed
        // a reference to this one. The obstructions closure mirrors
        // `raccoonSpawnDirector`'s own per-frame `groundPlane
        // ?.residentObstructions` argument, but reads the raw
        // `[BuildingPlacementRecord]` list `PickupManager`'s init wants
        // (`CollisionResolver.FootprintBounds` -- what `residentObstructions`
        // returns -- is already a lossy projection of that data) directly
        // off `GroundPlaneStreamer.streaming.residentChunks`, the same
        // source `BuildingSceneIntegrationTests` reads.
        pickupManager = PickupManager(
            worldSeed: worldSeed,
            obstructionsProvider: { [weak self] in
                self?.groundPlane?.streaming.residentChunks.values.flatMap(\.buildingPlacements) ?? []
            },
            // The real screen-space visibility question, asked with the
            // helper that already answers it for the raccoon swarm.
            // `pickupVisibleTileRect()` alone only bounds the *sampling*
            // window (the bounding box of the visible diamond, ~3.3x the
            // area the camera actually shows -- see that method's own doc
            // comment), so without this predicate roughly two spawns in
            // three would land off camera and the story's "first spawn is
            // visible in normal play" gate would be a coin flip.
            isVisibleOnScreen: { [weak self] tile in
                guard let self else { return false }
                return RaccoonSpawnDirector.isOnScreen(
                    tile: tile,
                    cameraPosition: self.cameraWorldPosition,
                    viewportSize: self.size
                )
            }
        )

        raccoonSpawnDirector = RaccoonSpawnDirector(
            worldLayer: worldLayer,
            deviceScale: { [weak self] in self?.deviceScale ?? 1 },
            stats: runStats,
            pickupManager: pickupManager
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
            // A fresh swarm for a fresh run -- without this, a RUN AGAIN
            // would inherit the previous run's raccoons instead of
            // starting clean, the same reason `startGroundPlane()` /
            // `startPlayer(at:)` exist rather than assuming nothing needs
            // resetting.
            raccoonSpawnDirector.reset()
            // ... a fresh set of pickups, for the same reason: without
            // this, RUN AGAIN would inherit run 1's still-alive pickups
            // (frozen mid-lifetime, since `updatePickups` is gated on
            // `.gameplay`), their already-mounted nodes, and whatever was
            // left of run 1's spawn cadence.
            startPickups()
            // ... and fresh counters for a fresh run, for the same reason:
            // RUN AGAIN must not report the previous run's kills and
            // infections. (`startPlayer(at:)` above resets the player's own
            // HP/infection state.)
            runStats.reset()
            // A fresh run's elapsed-time clock: RUN AGAIN must not carry
            // the previous run's SURVIVED/SURVIVAL rows into a run that
            // has not even started yet -- the same "no bleed-through" rule
            // `runStats.reset()` above and `raccoonSpawnDirector.reset()`/
            // `startPickups()`/`pulseAbility.reset()` below all follow.
            runElapsedSeconds = 0
            thumbstick.isRunActive = true
            // `PulseButton` has no `isRunActive`-style gate of its own
            // (see that type's own "Mount instructions" doc note), so the
            // scene owns hiding it outside `.gameplay` -- otherwise a
            // live `AccessibleSKView` mirror would sit over the menu's
            // bottom-left quadrant and forward touches into
            // `dispatchTouch`. Its cooldown-derived visual is refreshed
            // every `.gameplay` frame from `advanceMovementAndCamera(
            // currentTime:)` -- but not before the *first* such frame runs,
            // so the button is snapped to "ready" here too rather than
            // opening RUN AGAIN still wearing last run's dimmed wedge.
            pulseButton.isHidden = false
            // ... and a fresh ability for a fresh run, the same reason
            // `raccoonSpawnDirector.reset()` / `startPickups()` /
            // `runStats.reset()` above exist: without this, a run that
            // ended mid-cooldown burns up to `PulseAbility.cooldownSeconds`
            // of the next one, and the player's first press does nothing --
            // a dropped input, which is exactly what this ability's "must
            // respond to every press" product gate forbids.
            pulseAbility.reset()
            pulseButton.setCooldownProgress(pulseCooldownProgress())
            cameraController.update(focus: spawn, viewportSize: size)
            #if DEBUG
            assertSceneInvariants()
            #endif
        case .menu, .death, .highScores:
            thumbstick.isRunActive = false
            pulseButton.isHidden = true
        }
    }

    /// The run's start tile for `worldSeed`, chosen once per `.gameplay`
    /// entry via `RunSpawnSelector` -- a street-intersection tile,
    /// guaranteed street under every seed (see that type's own doc
    /// comment).
    ///
    /// **As composed today this is the same junction on every run.**
    /// `RunSpawnSelector.selectSpawnTile(seed:)` is a pure function of
    /// `worldSeed`, and nothing in the app ever *writes* `worldSeed` -- it is
    /// a fixed default (see that property's own doc comment), so every RUN
    /// AGAIN and every app launch selects the identical tile. That is the
    /// selector working exactly as specified (same seed => same city, same
    /// spawn); it is not "a new starting junction per run", and this story
    /// should not be recorded as having delivered that half. What is missing
    /// is a per-run `worldSeed`, which belongs to whichever story owns run
    /// setup. No separate ticket for it exists yet, and rather than invent
    /// an ID here (the convention `PlayerMovementController`'s
    /// outstanding-scope note follows) it is tracked on the `CYBERPUN-17-7`
    /// story itself: requested as a follow-up on `CYBERPUN-17-7-t3` and
    /// re-stated on `CYBERPUN-17-7-t4`, so the request outlives whichever
    /// task closes first. Until that follow-up is filed **and** delivered,
    /// this half of the story's spawn goal is recorded as not delivered
    /// rather than quietly deferred. The moment `worldSeed` varies per run,
    /// this method varies the junction with it and needs no change.
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

        // Because the node is *reused* across a restart, its combat state
        // has to be reset explicitly -- otherwise run 2 starts on the HP
        // run 1 ended with and, since `infect(stats:)` is one-way,
        // permanently infected and ticking 1 HP/s from its first frame.
        // Same reason `updateWorldContent(for:)` calls
        // `raccoonSpawnDirector.reset()`.
        mounted.resetCombatState()

        // `CYBERPUN-17-9` PR 3: the auto-fire combat composition needs
        // `mounted.body` to exist, so it is built here (lazily, on first
        // mount) rather than in `commonInit()`. A restart reuses it and
        // resets its own state instead, the same "reuse the node, reset
        // its state" shape as `mounted.resetCombatState()` immediately
        // above.
        if let playerCombat {
            playerCombat.reset()
        } else {
            // `worldSpaceReference: worldLayer` is load-bearing, not
            // decoration: bullets/flashes/puffs are positioned from
            // `IsometricProjection.tileToScreen` points, which live in
            // `worldLayer`'s space, but are parented under `effectsLayer`,
            // which nothing camera-offsets. Without the world container to
            // convert out of, every combat effect would draw
            // `worldLayer.position` away from the world and drift as the
            // player walks (see `Player`'s "Coordinate space" note).
            playerCombat = Player(
                body: mounted.body,
                effectsParent: effectsLayer,
                worldSpaceReference: worldLayer
            )
        }

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
    /// This is the real replacement for the earlier PR's now-deleted demo
    /// driver, used while the thumbstick, `PlayerMovementController` and
    /// `CollisionResolver` existed but were not yet wired into a live scene.
    /// A no-op before the first `.gameplay` entry (`player`/
    /// `playerWorldPosition` are both `nil`).
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

        // `GroundPlaneStreamer.residentObstructions` is derived once per
        // residency change rather than rebuilt here every frame: the obvious
        // spelling (`residentChunks.values.flatMap(\.buildingPlacements)`
        // handed to `resolve(obstructedBy:)`) allocates two arrays across the
        // full 49-chunk resident window per frame, in a subsystem that pools
        // aggressively to avoid exactly that.
        let resolvedPosition = CollisionResolver.resolve(
            currentPosition: currentPosition,
            proposedDelta: movementController.frameDisplacement,
            obstructions: groundPlane?.residentObstructions ?? []
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

        // The single integration call driving the raccoon swarm
        // (`CYBERPUN-17-8` PR 2): off-screen spawn selection, cadence/ramp
        // and per-raccoon seek-and-avoid steering all live inside
        // `RaccoonSpawnDirector` itself.
        //
        // Gated on the run actually being in progress. `update(_:)` runs on
        // every screen, and neither `player` nor `playerWorldPosition` is
        // ever cleared when a run ends (the `.menu/.death/.highScores`
        // branch of `updateWorldContent(for:)` only hides the thumbstick),
        // so without this gate every frame spent on the death or
        // high-scores screen would keep ramping the director's
        // `elapsedRunTime`, spawning raccoons up to
        // `RaccoonSpawnDirector.maxConcurrentSwarmSize`, allocating their
        // nodes into `worldLayer` and steering the whole swarm behind an
        // opaque backdrop. The player pipeline above is self-limiting out
        // there (the stick reads zero once `isRunActive` is false); the
        // director is not, and its "elapsed run time" would otherwise mean
        // "time since the last `.gameplay` entry, including time parked on
        // the death screen".
        if stateMachine.currentState == .gameplay {
            // CYBERPUN-17-13: the run's own wall-clock timer, gated
            // identically to the swarm/pickups/combat updates below so
            // time spent on the death/high-scores/menu screen after this
            // run ends never counts toward the *next* run's SURVIVED row.
            runElapsedSeconds += deltaTime

            // Independent of the camera-lock/chunk-streaming code paths
            // above -- and of `raccoonSpawnDirector` below -- other than
            // sharing this same `.gameplay` gate for the reason
            // `raccoonSpawnDirector`'s own call documents (nothing may keep
            // spawning or ageing pickups behind an opaque death/high-scores/
            // menu backdrop). Runs *before* the swarm update so a raccoon's
            // garbage-can diversion query (`raccoonSpawnDirector` was handed
            // `pickupManager` at construction) sees this frame's freshly
            // spawned/expired pickups rather than last frame's.
            updatePickups(deltaTime: deltaTime, playerPosition: resolvedPosition)

            raccoonSpawnDirector.update(
                deltaTime: deltaTime,
                playerPosition: resolvedPosition,
                // The mounted player, so a raccoon that has closed to the
                // standoff ring actually bites him (attack animation +
                // damage + rabies roll, `BiteComponent`) instead of
                // ringing him harmlessly. Passing the node here is what
                // gives this story its primary action on a device.
                player: player,
                obstructions: groundPlane?.residentObstructions ?? []
            )

            // `CYBERPUN-17-9` PR 3: the auto-fire combat loop -- targeting,
            // firing, bullets, effects and XP/level progression -- driven
            // from the same per-frame pipeline as the swarm above, using
            // this frame's just-steered raccoon positions
            // (`raccoonSpawnDirector.targetCandidates`) as targets. Gated on
            // the same `.gameplay` check for the same reason the swarm/
            // pickups updates are: nothing may keep firing or tracking
            // targets behind an opaque death/high-scores/menu backdrop.
            playerCombat?.update(
                deltaTime: deltaTime,
                isMoving: movementController.isMoving,
                origin: resolvedPosition,
                direction: player.facing,
                raccoons: raccoonSpawnDirector.targetCandidates
            )

            // `CYBERPUN-17-10-t3`: tick the pulse's cooldown down every
            // frame of an active run (independent of whether a press ever
            // lands -- `PulseAbility.update(deltaTime:)` is a no-op once
            // ready) and drive `pulseButton`'s cooldown visual from it, the
            // same "decision layer owns the number, presentation layer
            // reads it" split `WeaponFiringController`/`WeaponOverlayRenderer`
            // already establish for the auto-fire weapon.
            pulseAbility.update(deltaTime: deltaTime)
            pulseButton.setCooldownProgress(pulseCooldownProgress())
        }
    }

    /// `1.0` == fully ready, `0.0` == a cooldown was just started -- the
    /// exact scale `PulseButton.setCooldownProgress(_:)` expects, derived
    /// from `PulseAbility`'s own `cooldownRemaining`/`cooldownSeconds`
    /// rather than a duplicated countdown kept on this scene.
    private func pulseCooldownProgress() -> CGFloat {
        guard PulseAbility.cooldownSeconds > 0 else { return 1 }
        let progress = 1 - (pulseAbility.cooldownRemaining / PulseAbility.cooldownSeconds)
        return CGFloat(max(0, min(1, progress)))
    }

    // MARK: - Pulse ability (`CYBERPUN-17-10-t3`)

    /// `pulseButton.onPress`'s production target: fires the ability
    /// against `raccoonSpawnDirector`'s live swarm. Thin on purpose -- the
    /// whole decide-apply-render sequence lives in
    /// `applyPulseTrigger(raccoons:)`, which is exposed (not `private`)
    /// precisely so `PulseSceneWiringTests` can drive it directly against
    /// a hand-built swarm, the same "test the wiring without needing the
    /// spawn director's own randomness/timing" shape
    /// `PlayerCombatSceneWiringTests` already established for
    /// `Player.update(...)`.
    private func handlePulsePress() {
        applyPulseTrigger(raccoons: raccoonSpawnDirector.targetCandidates)
    }

    /// Fires `pulseAbility.trigger(...)` from the player's current
    /// position/level against `raccoons`, applying every hit's damage and
    /// pushed position (`applyPulseHit(_:)`) and spawning/replaying
    /// `pulseRing` -- all within this one call, so a press's whole effect
    /// (push, damage, ring) lands in a single update tick.
    ///
    /// Returns `nil` -- doing nothing observable -- exactly when
    /// `pulseAbility.trigger(...)` itself does (the ability is on
    /// cooldown), per that method's own "no waiting out a cooldown"
    /// contract; `PulseButton` itself never gates a press (see that
    /// type's own "product gate 1" doc note), so this is the one place
    /// cooldown rejection actually takes effect. A `nil`
    /// `playerWorldPosition`/`playerCombat` (no run mounted yet -- not
    /// reachable in a real build once `pulseButton` is hidden outside
    /// `.gameplay`, but this stays total for a direct test call) is also a
    /// no-op.
    @discardableResult
    func applyPulseTrigger(raccoons: [TargetSelection.Candidate]) -> PulseAbility.Result? {
        guard let playerWorldPosition, let playerCombat else { return nil }

        guard let result = pulseAbility.trigger(
            playerPosition: playerWorldPosition,
            level: playerCombat.xpLevelSystem.level,
            raccoons: raccoons,
            obstructions: groundPlane?.residentObstructions ?? [],
            rng: &pulseRNG
        ) else {
            return nil
        }

        for hit in result.hits {
            applyPulseHit(hit)
        }

        let ringPosition = effectsSpacePoint(fromWorldSpace: IsometricProjection.tileToScreen(playerWorldPosition))
        pulseRing.play(radiusTiles: result.radius, at: ringPosition)

        return result
    }

    /// Applies one `PulseAbility.Hit`'s damage and pushed position to the
    /// live `RaccoonNode`: `takeDamage(_:)` (already public via
    /// `Damageable`), then the same tile-to-screen-position/depth
    /// projection every other world-space actor in this repo follows
    /// (`PlayerNode.updateDepth`/`RaccoonSpawnDirector.applyScreenPosition`),
    /// plus `raccoonSpawnDirector.syncPushedPosition(_:for:)` so the
    /// swarm director's own tracked position agrees -- without that call,
    /// the very next per-frame `raccoonSpawnDirector.update(...)` would
    /// re-derive this same raccoon's screen position from its own stale,
    /// pre-push tile position and silently undo the shove the same frame
    /// it landed (see that method's own doc comment).
    private func applyPulseHit(_ hit: PulseAbility.Hit) {
        hit.raccoon.takeDamage(hit.damage)

        let rawPosition = IsometricProjection.tileToScreen(hit.newPosition)
        hit.raccoon.position = PixelCrispness.snappedPosition(for: rawPosition, scale: deviceScale)
        hit.raccoon.updateDepth(atTilePosition: hit.newPosition)

        raccoonSpawnDirector.syncPushedPosition(hit.newPosition, for: hit.raccoon)
    }

    /// Converts a `worldLayer`-space point (e.g. raw
    /// `IsometricProjection.tileToScreen` output) into `effectsLayer`'s
    /// own space, so a node parented under `effectsLayer` -- which
    /// nothing camera-offsets -- draws where the world actually is rather
    /// than `worldLayer.position` away from it. The same conversion
    /// `Player`'s own private `effectsSpacePoint(fromWorldSpace:)`
    /// performs for bullets/flashes/puffs; restated here (rather than
    /// reached into, since `Player` holds no reference back to this
    /// scene) for `pulseRing`, the only other `effectsLayer` consumer of a
    /// raw world-space point.
    private func effectsSpacePoint(fromWorldSpace point: CGPoint) -> CGPoint {
        effectsLayer.convert(point, from: worldLayer)
    }

    // MARK: - Pickups (`CYBERPUN-17-11` PR 3)

    /// Brings the pickups engine in step with a fresh run, the same way
    /// `startGroundPlane()` / `startPlayer(at:)` do for the ground and the
    /// player: `pickupManager.reset(worldSeed:)` drops every pickup left
    /// over from the previous run and re-arms both kinds' cadence timers at
    /// their tuned `firstSpawnDelay`, and the immediate `syncPickupNodes()`
    /// unmounts the now-orphaned `PickupNode`s right here rather than
    /// leaving last run's icons on screen until the next frame runs.
    ///
    /// The manager instance is reset in place, not rebuilt:
    /// `raccoonSpawnDirector` was handed a reference to it at construction
    /// (`commonInit()`), so swapping the object would leave the swarm
    /// querying a detached manager -- the same reason `startPlayer(at:)`
    /// reuses the mounted `PlayerNode` and calls `resetCombatState()`
    /// instead of building a second one.
    ///
    /// The seed is passed through on every entry (rather than only when it
    /// changes, as `startGroundPlane()` must, since it owns expensive
    /// node state) because `worldSeed` is a `var` a per-run seed will one
    /// day vary: placement validation must classify tiles against the city
    /// `startGroundPlane()` just streamed, never the previous run's.
    private func startPickups() {
        pickupManager.reset(worldSeed: worldSeed)
        syncPickupNodes()
    }

    /// Advances `pickupManager` by one frame, mounts/unmounts `PickupNode`s
    /// for whatever spawned or expired/was-consumed, and resolves the
    /// player's own med-kit collection on contact.
    ///
    /// The raccoon side of collection (garbage-can diversion/consumption)
    /// is *not* driven from here: `raccoonSpawnDirector` already holds a
    /// reference to `pickupManager` (handed to it at construction in
    /// `commonInit()`) and queries/consumes a garbage can itself, once per
    /// wounded raccoon, from its own per-frame loop -- there is no single
    /// "the player's position" equivalent for a whole swarm, so that query
    /// has to happen per-raccoon, where the raccoon's own position is
    /// already in scope.
    private func updatePickups(deltaTime: TimeInterval, playerPosition: TilePoint) {
        pickupManager.update(deltaTime: deltaTime, visibleRect: pickupVisibleTileRect())
        syncPickupNodes()

        if let healedAmount = pickupManager.attemptCollectMedKit(
            at: playerPosition,
            radius: Self.medKitCollectionRadiusTiles
        ) {
            player?.heal(healedAmount)
            // The manager marks the med kit consumed immediately but only
            // prunes it from `activePickups` on its *next* `update` call
            // (see that type's own doc comment) -- sync again right away so
            // the collected icon disappears on the very frame it was
            // collected rather than lingering one extra frame.
            syncPickupNodes()
        }
    }

    /// The tile-space rectangle `pickupManager.update(deltaTime:visibleRect:)`
    /// **samples** candidate spawn tiles from this frame: an axis-aligned
    /// square in tile space, centred on `cameraWorldPosition`, sized so its
    /// screen-space image (a diamond, under `IsometricProjection`'s linear
    /// transform) fully covers the current `size`-sized viewport.
    ///
    /// **This is the bounding box of the visible region, not the visible
    /// region** (PR #38 review). The inverse image of a rectangular
    /// viewport is a 45-degree-rotated square, so the box strictly
    /// over-covers it: with `|det J| = 2 * tileHalfWidth * tileHalfHeight
    /// = 2304`, a 390x844pt viewport shows about `390 * 844 / 2304 = 143`
    /// tiles-squared while this box spans `(2 * 10.82)^2 = 469` -- roughly
    /// 70% of the tiles drawn from it are off camera. Sampling from the box
    /// is deliberate (it is a cheap closed form, and a rejected draw simply
    /// costs one more of `PickupManager.maxPlacementAttemptsPerSpawn`), but
    /// it is *not* on its own the "spawns within the visible rect" the
    /// story asks for: the `isVisibleOnScreen` predicate handed to
    /// `PickupManager` in `commonInit()` --
    /// `RaccoonSpawnDirector.isOnScreen(tile:cameraPosition:viewportSize:)`,
    /// whose own doc comment warns that a tile-space rect does not
    /// correspond to a screen-space one on this uneven 2:1 projection -- is
    /// what rejects the off-camera remainder, and
    /// `PickupIntegrationTests.test_everyPickupMounted_spawnsWhereTheCameraCanSeeIt`
    /// pins that end to end.
    ///
    /// Derived algebraically, not assumed: `IsometricProjection`'s forward
    /// transform has no translation term, so the *inverse* image of an
    /// axis-aligned screen rectangle's four corners is itself an
    /// axis-aligned rectangle in tile space -- and working through the
    /// corners (`screenToTile(screenX:screenY:)`) shows both tile axes come
    /// out to the identical half-extent `width/(4 * tileHalfWidth) +
    /// height/(4 * tileHalfHeight)`, i.e. a square. This is the same
    /// arithmetic `ChunkStreamingManager.coversViewport(widthPoints:
    /// heightPoints:radius:)` runs in the opposite direction (solved for the
    /// covering tile *radius* instead of the covered screen *rectangle*).
    ///
    /// Keyed off `cameraWorldPosition` (derived from the live
    /// `worldLayer`/`cameraNode` offset) rather than `playerWorldPosition`
    /// directly, per this PR's own wiring note: the two agree once
    /// `cameraController` has caught up, but this stays correct regardless
    /// of any camera-lock offset or lag between the two.
    private func pickupVisibleTileRect() -> CGRect {
        let halfExtent = Double(size.width) / (4 * IsometricProjection.tileHalfWidth)
            + Double(size.height) / (4 * IsometricProjection.tileHalfHeight)
        let camera = cameraWorldPosition
        return CGRect(
            x: CGFloat(camera.x - halfExtent),
            y: CGFloat(camera.y - halfExtent),
            width: CGFloat(halfExtent * 2),
            height: CGFloat(halfExtent * 2)
        )
    }

    /// Mounts a `PickupNode` for every active, not-yet-consumed pickup
    /// `pickupManager` reports that has no mounted node yet, and unmounts
    /// every mounted node whose pickup is no longer active (expired by age,
    /// or just consumed) -- a diff against `pickupNodes`, not a rebuild.
    private func syncPickupNodes() {
        let active = pickupManager.activePickups.filter { !$0.isConsumed }
        let activeIDs = Set(active.map(\.id))

        for pickup in active where pickupNodes[pickup.id] == nil {
            let node = PickupNode(kind: pickup.kind)
            // A pickup never moves once spawned (`Pickup.position`'s own
            // doc comment), so position/depth are resolved once here at
            // mount time rather than re-derived every frame.
            node.updateScreenPosition(atTilePosition: pickup.position, deviceScale: deviceScale)
            // Mounted directly under `worldLayer`, the same convention
            // `PlayerNode`/`RaccoonNode` follow and the one
            // `PickupNode.updateDepth(atTilePosition:)` itself documents --
            // this is what makes a pickup participate in the same
            // depth-sort pass as buildings/actors.
            worldLayer.addChild(node)
            pickupNodes[pickup.id] = node
        }

        for id in Array(pickupNodes.keys) where !activeIDs.contains(id) {
            pickupNodes[id]?.removeFromParent()
            pickupNodes[id] = nil
        }
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
        layoutPulseButton()
        #if DEBUG
        assertSceneInvariants()
        #endif
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        centreCameraOnScene()
        activeScreen?.layout(for: size, safeAreaInsets: currentSafeAreaInsets)
        thumbstick.layout(for: size, safeAreaInsets: currentSafeAreaInsets)
        layoutPulseButton()
    }

    /// Positions `pulseButton` at `FloatingThumbstickNode
    /// .reservedPulseButtonSlot(forSize:safeAreaInsets:)`'s *centre*
    /// (`slot.midX`/`slot.midY`, never `slot.origin`) -- `PulseButton`
    /// draws its plate centred on its own origin, so anchoring from the
    /// slot's origin would land the button half a width off the reserved
    /// slot, per that button's own "Mount instructions" doc note.
    private func layoutPulseButton() {
        // `SKScene.init(size:)` calls `-[SKScene setSize:]` synchronously
        // inside `super.init(size:)`, which fires `didChangeSize(_:)` -- and
        // therefore this method -- *before* `commonInit()` has run and
        // assigned `pulseButton`. Guard rather than force-unwrap so that
        // first, pre-`commonInit` call is a harmless no-op; every layout
        // point that matters (`commonInit()` itself, `didMove(to:)`, and
        // every later `didChangeSize(_:)`) runs after `pulseButton` exists
        // and lays it out for real.
        guard let pulseButton else { return }
        let slot = FloatingThumbstickNode.reservedPulseButtonSlot(
            forSize: size,
            safeAreaInsets: currentSafeAreaInsets
        )
        pulseButton.position = CGPoint(x: slot.midX, y: slot.midY)
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
    /// order - each of them a **leaf**: a node that opts in collapses its own
    /// subtree, exactly as UIKit's `isAccessibilityElement` does, so a
    /// button's plate and label are never published alongside the button they
    /// belong to (see `collectAccessibleNodes(under:into:)`).
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
                // An accessibility element is a **leaf**, so its subtree is
                // not walked. That is UIKit's own rule
                // (`isAccessibilityElement == true` collapses everything
                // underneath into the one element), and here it is
                // load-bearing rather than a nicety: `ButtonNode` opts in on
                // *itself* while owning a plate sprite and a centred
                // `SKLabelNode` child, and SpriteKit gives some node classes
                // an implicit `isAccessibilityElement` of its own. Descending
                // therefore appended a child of the button *after* the
                // button, so `refreshAccessibilityMirrors()` laid that child's
                // mirror **above** the button's - and UIKit's
                // topmost-sibling point lookup answered the child at the
                // button's own frame centre. The button stayed findable and
                // stopped owning its centre, which is `isHittable == false`
                // for PLAY, and it was invisible to every identifier-based
                // assertion because such a child carries no
                // `accessibilityIdentifier` at all.
                //
                // The button also *is* the `TouchResponder` the scene routes
                // to, so the element and the tappable node are the same node
                // by construction - exactly the agreement this whole feature
                // exists to keep.
                accessible.append(child)
                continue
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
    ///
    /// **Every touch in the set is routed, not just `touches.first`.** This
    /// game is two-thumbed by design (`FloatingThumbstickNode` reserves
    /// `reservedPulseButtonSlot` directly above the stick for
    /// `CYBERPUN-17-10`), so a button press and a stick drag can legitimately
    /// arrive in the same event set once
    /// `GameViewController` has switched the hosting view's
    /// `isMultipleTouchEnabled` on -- and dropping every touch but the first
    /// would silently lose one of them. Iterating here is also what makes the
    /// `activeStickTouch` bookkeeping load-bearing rather than theoretical.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)

        for touch in touches {
            let scenePoint = touch.location(in: self)

            if dispatchTouch(atScenePoint: scenePoint) != nil {
                continue
            }

            // Only one touch may drive the stick at a time: a second finger
            // landing in the left region mid-drag must not steal the stick
            // out from under the first, which `FloatingThumbstickNode` would
            // otherwise happily re-centre on the newcomer.
            guard activeStickTouch == nil else { continue }

            if thumbstick.beginTouch(at: uiLayer.convert(scenePoint, from: self)) {
                activeStickTouch = touch
            }
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
