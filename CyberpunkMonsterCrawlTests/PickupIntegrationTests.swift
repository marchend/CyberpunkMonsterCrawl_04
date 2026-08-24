import CoreGraphics
import SpriteKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-11` PR 3: the scene-wiring integration this story exists to
/// deliver -- `PickupManager` (PR 1) and the player/raccoon consume effects
/// (PR 2) each had their own suite proving the isolated units worked, and
/// what was missing was precisely that *nothing mounted a pickup or fed a
/// real collision into either effect*. These tests drive `GameScene.update(_:)`
/// -- the production per-frame entry point, exactly like
/// `RaccoonSwarmSceneWiringTests`/`ThumbstickSceneWiringTests` -- and assert
/// on the scene's own mounted nodes and its live `pickupManager`, rather
/// than on any isolated component.
///
/// Headless throughout (no `SKView`), which `GameScene` supports by design.
final class PickupIntegrationTests: XCTestCase {

    private let sceneSize = CGSize(width: 400, height: 800)

    /// A scene already in `.gameplay`: ground plane started, player mounted
    /// at the run's spawn tile, pickups engine wired and ticking.
    private func makeGameplayScene() -> GameScene {
        let scene = GameScene(size: sceneSize)
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))
        return scene
    }

    /// Every `PickupNode` currently mounted in the scene's world layer.
    private func mountedPickupNodes(_ scene: GameScene) -> [PickupNode] {
        scene.worldLayer.children.compactMap { $0 as? PickupNode }
    }

    /// Drives `seconds` of production frames from `start`, in `step`-second
    /// slices -- the same shape `RaccoonSwarmSceneWiringTests.advance(_:)`
    /// uses for the identical reason (spawn cadences are seconds-scale, so a
    /// 60fps sweep would be thousands of frames).
    ///
    /// Keeps the player at full HP before each `.gameplay` frame for the
    /// same reason that helper does (see its own doc comment): since
    /// `CYBERPUN-17-13-t5` a live run whose swarm happens to chew the
    /// player to 0 HP transitions itself to `.death`, which silently stops
    /// `GameScene.updatePickups` -- so without this, every multi-second
    /// window here would depend on `RaccoonSpawnDirector`'s random default
    /// seed. Pickups, not survival, are this suite's subject.
    ///
    /// A test that needs a *wounded* player (the med-kit heal case below)
    /// must therefore not drive its frames through this helper.
    @discardableResult
    private func advance(
        _ scene: GameScene,
        seconds: TimeInterval,
        step: TimeInterval = 0.5,
        startingAt start: TimeInterval = 1
    ) -> TimeInterval {
        var now = start
        let end = start + seconds
        while now <= end {
            if scene.stateMachine.currentState == .gameplay {
                scene.player?.hp = PlayerNode.baseMaxHP
            }
            scene.update(now)
            now += step
        }
        return now
    }

    /// A tile-space rect covering the whole 3x3 street crossing around
    /// `tile` -- `PickupManagerTests.crossingVisibleRect`'s own trick,
    /// reused here: every one of those 9 tiles is guaranteed street under
    /// every seed (`CityLatticeGenerator`'s own contract, the same one
    /// `RunSpawnSelector` relies on for the run's own spawn tile), so a
    /// forced spawn here cannot fail placement regardless of which seed a
    /// test scene happens to use.
    private func crossingVisibleRect(around tile: TilePoint, halfExtent: Double = 1.4) -> CGRect {
        CGRect(
            x: CGFloat(tile.x - halfExtent),
            y: CGFloat(tile.y - halfExtent),
            width: CGFloat(halfExtent * 2),
            height: CGFloat(halfExtent * 2)
        )
    }

    /// Pushes the stick to full deflection towards screen-right (or, when
    /// `rightward` is `false`, screen-left), starting from its own rest
    /// position -- `ThumbstickSceneWiringTests.pushStickRight`'s own shape.
    @discardableResult
    private func pushStick(_ scene: GameScene, rightward: Bool) -> Bool {
        let rest = scene.thumbstick.restPosition
        let began = scene.thumbstick.beginTouch(at: rest)
        let dx = rightward ? FloatingThumbstickNode.maxRadius : -FloatingThumbstickNode.maxRadius
        scene.thumbstick.updateTouch(at: CGPoint(x: rest.x + dx, y: rest.y))
        return began
    }

    // MARK: - Pickups appear as real mounted nodes, within the expected window

    func test_pickupsAppearAsMountedPickupNodes_withinTheExpectedTimeWindow() {
        let scene = makeGameplayScene()
        XCTAssertEqual(mountedPickupNodes(scene).count, 0, "no pickup may exist before any frame has run")

        advance(scene, seconds: 12)

        XCTAssertGreaterThan(
            mountedPickupNodes(scene).count, 0,
            "12s of gameplay frames must mount at least one real PickupNode -- the single production call site "
                + "(GameScene.updatePickups) is what makes this story's own spawn-window gate visible at all"
        )
        for node in mountedPickupNodes(scene) {
            XCTAssertTrue(node.parent === scene.worldLayer, "a mounted pickup must be a direct child of worldLayer")
        }
    }

    // MARK: - A not-yet-expired pickup survives the camera moving far away and back

    func test_notYetExpiredPickup_survives_theCameraMovingFarAwayAndBack() throws {
        let scene = makeGameplayScene()
        let spawnTile = try XCTUnwrap(scene.playerWorldPosition)

        // Forced (not a natural random spawn) so this test does not depend
        // on where a real spawn happens to land, per this file's own
        // `crossingVisibleRect` doc comment. A garbage can specifically:
        // unlike a med kit, nothing in this scenario auto-collects one (only
        // a *wounded* raccoon diverts to and consumes it, and no raccoon
        // here is ever damaged), so it cannot be accidentally picked up by
        // the player walking near it during the moves below.
        scene.pickupManager.update(
            deltaTime: PickupKind.garbageCan.tuning.firstSpawnDelay,
            visibleRect: crossingVisibleRect(around: spawnTile)
        )
        let garbageCan = try XCTUnwrap(
            scene.pickupManager.activePickups.first { $0.kind == .garbageCan },
            "sanity: the 3x3 street crossing around the run's own spawn tile must always be a legal placement"
        )

        // Move the camera/player far from where it spawned...
        pushStick(scene, rightward: true)
        let afterMovingAway = advance(scene, seconds: 6)
        XCTAssertTrue(
            scene.pickupManager.activePickups.contains { $0.id == garbageCan.id && !$0.isConsumed },
            "moving the camera away must not remove a pickup whose real accumulated age is still under its lifetime"
        )

        // ...and back. Total elapsed real age stays well under
        // `PickupKind.garbageCan.tuning.lifetime` (20s), so any disappearance
        // here can only be a visibility-based removal this story never
        // implements -- age is the *only* lifetime clock
        // (`PickupManager`'s own doc comment).
        scene.thumbstick.endTouch()
        pushStick(scene, rightward: false)
        advance(scene, seconds: 6, startingAt: afterMovingAway)

        XCTAssertTrue(
            scene.pickupManager.activePickups.contains { $0.id == garbageCan.id && !$0.isConsumed },
            "a large visibleRect swing between updates must never expire a pickup before its real deltaTime-accumulated age does"
        )
    }

    // MARK: - Walking the player over a spawned med kit collects it and heals

    func test_walkingThePlayerOverASpawnedMedKit_reducesTheManagersActiveCount_andHealsThePlayer() throws {
        let scene = makeGameplayScene()
        let player = try XCTUnwrap(scene.player)
        player.hp = 50

        let spawnTile = try XCTUnwrap(scene.playerWorldPosition)
        // A rect narrow enough that only the player's own exact spawn tile
        // can be drawn -- `PickupManagerTests.narrowVisibleRect`'s own
        // trick -- so the forced spawn lands exactly under the player,
        // deterministically, rather than merely "somewhere nearby".
        let narrowRect = CGRect(
            x: CGFloat(spawnTile.x - 0.4),
            y: CGFloat(spawnTile.y - 0.4),
            width: 0.8,
            height: 0.8
        )
        scene.pickupManager.update(deltaTime: PickupKind.medKit.tuning.firstSpawnDelay, visibleRect: narrowRect)

        let activeBefore = scene.pickupManager.activePickups.filter { !$0.isConsumed }
        XCTAssertEqual(activeBefore.count, 1, "sanity: exactly one med kit must have spawned onto the player's own tile")
        XCTAssertEqual(activeBefore.first?.kind, .medKit)
        XCTAssertEqual(mountedPickupNodes(scene).count, 0, "sanity: nothing is mounted until a real GameScene frame has run")

        // The player is already standing on the spawned med kit's exact
        // tile, so the very first live frame resolves the collision.
        scene.update(1)

        XCTAssertGreaterThan(player.hp, 50, "standing on a spawned med kit must heal the player through PlayerNode.heal(_:)")
        XCTAssertTrue(
            scene.pickupManager.activePickups.filter { !$0.isConsumed }.isEmpty,
            "the manager's active (uncollected) count must drop to zero once the player walks over the med kit"
        )
        XCTAssertTrue(
            mountedPickupNodes(scene).isEmpty,
            "the collected med kit's PickupNode must be unmounted on the very frame it is collected, not one frame later"
        )
    }

    // MARK: - Depth: a pickup renders in front of a building sharing its tile

    func test_pickupNode_rendersInFrontOfABuildingSharingItsTile() {
        let worldLayer = SKNode()
        let tilePosition = TilePoint(x: 3, y: -2)

        let pickup = PickupNode(kind: .medKit)
        pickup.updateScreenPosition(atTilePosition: tilePosition, deviceScale: 1)
        worldLayer.addChild(pickup)

        // A synthetic building node sharing the same tile, at the highest
        // legal building-content offset (`DepthModel.buildingContentRange`'s
        // own ceiling) -- the closest any building of any height class can
        // get to a co-tile actor/pickup, the same convention
        // `PlayerDepthTests.test_playerZPosition_alwaysExceeds_anyBuildingContentZPosition_inTheSameBand`
        // uses instead of rendering real building art.
        let band = DepthModel.band(forActorAt: tilePosition)
        let building = SKNode()
        building.zPosition = DepthModel.worldLayerRelativeZ(
            forAbsoluteZ: band + (DepthModel.buildingContentRange.upperBound - 0.001)
        )
        worldLayer.addChild(building)

        XCTAssertGreaterThan(
            pickup.zPosition, building.zPosition,
            "a pickup sharing a building's tile must render in front of it -- both are direct children of "
                + "worldLayer, so their zPositions are directly comparable"
        )
    }

    // MARK: - A wounded raccoon diverts to and consumes a spawned garbage can

    /// Exercised against the real `RaccoonSpawnDirector` + `PickupManager`
    /// wiring this PR adds (the director is handed the manager at
    /// construction, exactly as `GameScene.commonInit()` does), rather than
    /// a full `GameScene`: a real spawned raccoon starts 40-56 tiles off
    /// camera (`RaccoonSpawnDirector.farAxisMinimumTiles`/
    /// `farAxisMaximumTiles`) by design, which would make a full-scene
    /// version of this test either extremely slow (walking that far at
    /// `RaccoonSeekBehavior.pointsPerSecond`) or dependent on teleporting a
    /// node in a way nothing in production ever does. This still proves the
    /// exact seam this PR's plan calls out: "call the raccoon-facing
    /// garbage-can query APIs from each wounded raccoon's update path ...
    /// so `RaccoonAI`'s diversion logic can act on it" -- through the real
    /// `RaccoonSpawnDirector.update(...)` call GameScene itself drives every
    /// frame, not through `RaccoonSeekBehavior.updateWithDiversion(...)`
    /// called directly (that seam is `RaccoonPickupDiversionTests`' job).
    func test_woundedRaccoon_divertsToAndConsumesASpawnedGarbageCan_throughTheRealSpawnDirectorWiring() throws {
        let worldLayer = SKNode()
        let seed = WorldSeed(rawValue: 0x600D_CA57)
        // No obstructions provider (defaults to `{ [] }`): this test is
        // about the raccoon<->pickup wiring, not city generation, so
        // building placement is deliberately kept out of the way -- the
        // raccoon's own spawn tile is still guaranteed street regardless
        // (`RaccoonSpawnDirector.selectSpawnTile`'s own doc comment).
        let pickupManager = PickupManager(worldSeed: seed, rng: SplitMix64RandomNumberGenerator(seed: 11))
        let director = RaccoonSpawnDirector(
            worldLayer: worldLayer,
            rng: SplitMix64RandomNumberGenerator(seed: 5),
            pickupManager: pickupManager
        )

        let farPlayerPosition = TilePoint(x: 0, y: 0)
        // Exactly one spawn attempt, at the very start of a run.
        director.update(
            deltaTime: RaccoonSpawnDirector.initialSpawnInterval,
            playerPosition: farPlayerPosition,
            player: nil,
            obstructions: []
        )

        let raccoon = try XCTUnwrap(
            worldLayer.children.compactMap { $0 as? RaccoonNode }.first,
            "sanity: the director's first spawn attempt must produce a raccoon"
        )
        let raccoonTile = IsometricProjection.screenToTile(raccoon.position)
        raccoon.hp = raccoon.maxHP - 5 // wounded, so it is eligible to divert

        // Force a garbage can onto the raccoon's own 3x3 street crossing
        // (the raccoon's exact spawn tile is guaranteed street -- see
        // `RaccoonSpawnDirector.selectSpawnTile`'s own doc comment on
        // `nearestStreetLaneIndex` -- so this cannot fail placement).
        pickupManager.update(
            deltaTime: PickupKind.garbageCan.tuning.firstSpawnDelay,
            visibleRect: crossingVisibleRect(around: raccoonTile)
        )
        let garbageCan = try XCTUnwrap(pickupManager.activePickups.first { $0.kind == .garbageCan })

        var consumed = false
        for _ in 0..<400 {
            director.update(deltaTime: 0.1, playerPosition: farPlayerPosition, player: nil, obstructions: [])
            if pickupManager.activePickups.first(where: { $0.id == garbageCan.id })?.isConsumed == true {
                consumed = true
                break
            }
        }

        XCTAssertTrue(consumed, "a wounded raccoon within diversion range must eventually consume the spawned garbage can")
        XCTAssertGreaterThan(
            raccoon.hp, raccoon.maxHP - 5,
            "consuming the garbage can must heal the raccoon, through the real RaccoonSpawnDirector call site"
        )
    }

    // MARK: - A pickup that ages out is unmounted, not left as visible debris

    /// The consumed half of `GameScene.syncPickupNodes()`'s unmount branch is
    /// covered by the med-kit test above; this pins the *age-expiry* half
    /// (PR #38 review) -- the path that leaves a stale icon on the ground if
    /// it regresses, uncollectable forever since collection goes through the
    /// manager. It also gives the story's "lifetime >= 15s / expires by age"
    /// AC an assertion through the live scene rather than only inside
    /// `PickupManagerTests`.
    func test_aPickupThatReachesItsLifetime_hasItsMountedNodeUnmounted() throws {
        let scene = makeGameplayScene()
        let spawnTile = try XCTUnwrap(scene.playerWorldPosition)

        // Forced onto the guaranteed-street crossing around the run's own
        // spawn tile (this file's `crossingVisibleRect` doc comment), and a
        // garbage can specifically: nothing in this scenario consumes one
        // (no raccoon here is ever wounded, and the player never collects
        // one), so age is the only thing that can retire it.
        scene.pickupManager.update(
            deltaTime: PickupKind.garbageCan.tuning.firstSpawnDelay,
            visibleRect: crossingVisibleRect(around: spawnTile)
        )
        let garbageCan = try XCTUnwrap(
            scene.pickupManager.activePickups.first { $0.kind == .garbageCan },
            "sanity: the 3x3 street crossing around the run's own spawn tile must always be a legal placement"
        )

        // One live frame mounts it -- `syncPickupNodes()` runs even on the
        // zero-delta first frame.
        scene.update(1)
        let mountedNode = try XCTUnwrap(
            mountedPickupNodes(scene).first { $0.kind == .garbageCan },
            "sanity: the forced garbage can must be mounted by the first live frame"
        )
        XCTAssertTrue(mountedNode.parent === scene.worldLayer)

        // Past `PickupKind.Tuning.lifetime` (20s).
        advance(scene, seconds: 22, startingAt: 1)

        XCTAssertFalse(
            scene.pickupManager.activePickups.contains { $0.id == garbageCan.id },
            "a pickup that reaches its kind's lifetime must be pruned from activePickups"
        )
        XCTAssertNil(
            mountedNode.parent,
            "the expired pickup's PickupNode must be removed from worldLayer -- an icon that outlives its record is "
                + "debris no player can ever collect"
        )
        XCTAssertFalse(
            mountedPickupNodes(scene).contains { $0 === mountedNode },
            "the expired pickup's node must no longer be among the scene's mounted pickups"
        )
    }

    // MARK: - Spawns land where the camera can actually see them

    /// `GameScene.pickupVisibleTileRect()` is the axis-aligned bounding box
    /// of the visible diamond, so roughly 70% of the tiles it samples are
    /// off camera (PR #38 review). The `isVisibleOnScreen` predicate handed
    /// to `PickupManager` in `commonInit()` is what rejects those; this
    /// audits the end result against the same screen-space definition
    /// `RaccoonSpawnDirector`'s own off-screen spawn guarantee is tested
    /// with, rather than merely asserting a node is mounted.
    func test_everyPickupMounted_spawnsWhereTheCameraCanSeeIt() {
        let scene = makeGameplayScene()

        // No stick input, so the camera never leaves the run's spawn tile:
        // every node below was placed against the very camera position it
        // is being audited against here.
        advance(scene, seconds: 12)

        let mounted = mountedPickupNodes(scene)
        XCTAssertGreaterThan(mounted.count, 0, "sanity: 12s of gameplay frames must mount at least one pickup")

        for node in mounted {
            let tile = IsometricProjection.screenToTile(node.position)
            XCTAssertTrue(
                RaccoonSpawnDirector.isOnScreen(
                    tile: TileCoordinate(tileX: Int(tile.x.rounded()), tileY: Int(tile.y.rounded())),
                    cameraPosition: scene.cameraWorldPosition,
                    viewportSize: scene.size
                ),
                "a spawned pickup must be inside the viewport, not merely inside the bounding box of the visible "
                    + "diamond -- the story's first-spawn gate is about what the player can see"
            )
        }
    }

    // MARK: - RUN AGAIN starts with a clean pickups engine

    func test_runAgain_resetsThePickupsEngine_andDoesNotInheritTheLastRunsPickups() {
        let scene = makeGameplayScene()
        let afterRun = advance(scene, seconds: 12)
        XCTAssertGreaterThan(mountedPickupNodes(scene).count, 0, "sanity: run 1 must have mounted at least one pickup")

        XCTAssertTrue(scene.stateMachine.transition(to: .death))
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))

        XCTAssertTrue(
            scene.pickupManager.activePickups.isEmpty,
            "re-entering .gameplay must reset the pickups engine, exactly as it resets the swarm/stats/player -- run "
                + "1's pickups stop ageing on the death screen (updatePickups is gated on .gameplay), so an inherited "
                + "one would sit on run 2's ground scattered along last run's path"
        )
        XCTAssertTrue(
            mountedPickupNodes(scene).isEmpty,
            "run 1's PickupNodes must be unmounted at the transition itself, not left visible until some later frame"
        )

        // Run 2's cadence is re-armed from the top rather than inheriting
        // whatever was left of run 1's: nothing may spawn before the tuned
        // first-spawn delay.
        let beforeFirstSpawn = PickupKind.medKit.tuning.firstSpawnDelay - 2
        let afterQuietWindow = advance(scene, seconds: beforeFirstSpawn, startingAt: afterRun)
        XCTAssertTrue(
            mountedPickupNodes(scene).isEmpty,
            "run 2 must wait its own full firstSpawnDelay -- a carried-over timer would spawn early"
        )

        advance(scene, seconds: 12, startingAt: afterQuietWindow)
        XCTAssertGreaterThan(
            mountedPickupNodes(scene).count, 0,
            "spawning must resume on a new run, not latch off after the first death"
        )
    }
}
