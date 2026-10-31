import CoreGraphics
import SpriteKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-12` PR 2: `HUDLayer.bind(to:)`/`refresh()` forward a
/// `HUDRunModel`'s live values straight into each of the six mounted
/// elements' own `update(...)`, with no intermediate cached state living on
/// `HUDLayer` itself -- mutating the bound model and calling `refresh()`
/// again must always reflect the model's *current* reading, never a stale
/// snapshot taken at `bind(to:)` time.
final class HUDRunModelBindingTests: XCTestCase {

    /// A minimal `HUDRunModel` conformer driven entirely by the test, so
    /// these tests exercise `HUDLayer`'s own binding/forwarding logic in
    /// isolation from `GameScene`'s much larger composition -- the same
    /// "test the wiring against a hand-built double" shape
    /// `PulseSceneWiringTests`/`RaccoonSpawnDirectorTests` already use.
    private final class MockHUDRunModel: HUDRunModel {
        var currentHP: Int = 100
        var maxHP: Int = 100
        var level: Int = 1
        var currentXP: Int = 0
        var xpForNextLevel: Int = 100
        var elapsedSeconds: TimeInterval = 0
        var kills: Int = 0
        var pulseCooldownFraction: CGFloat = 1
        var isPulseReady: Bool = true
        var onSwarmEscalation: (() -> Void)?
        var radarRaccoonCandidates: [TargetSelection.Candidate] = []
        var radarMedKitTiles: [TilePoint] = []
        var deviceScale: CGFloat = 1
        var radarPlayerTile = TileCoordinate(tileX: 0, tileY: 0)
        var worldSeed = WorldSeed(rawValue: 0)
        var radarResidencyRevision = 0

        /// What `radarBuildingRecords` reports. Separate from the
        /// requirement itself so that read can be *counted*: the
        /// production conformer's own implementation is a `flatMap` across
        /// the whole resident chunk window, so "how many times per frame
        /// does `HUDLayer` read this?" is a behaviour worth pinning, not
        /// an implementation detail (PR #79 review).
        var radarBuildingRecordsStore: [BuildingPlacementRecord] = []
        private(set) var radarBuildingRecordsReadCount = 0
        var radarBuildingRecords: [BuildingPlacementRecord] {
            radarBuildingRecordsReadCount += 1
            return radarBuildingRecordsStore
        }

        private(set) var triggerPulseCount = 0

        func triggerPulse() {
            triggerPulseCount += 1
        }
    }

    // MARK: - bind(to:) forwards the model's values into every element

    func test_bind_forwardsTheModelsInitialValues_intoEveryElement() {
        let hud = HUDLayer()
        let model = MockHUDRunModel()
        model.currentHP = 40
        model.maxHP = 100
        model.level = 3
        model.currentXP = 25
        model.xpForNextLevel = 100
        model.elapsedSeconds = 65
        model.kills = 7
        model.pulseCooldownFraction = 0.5
        model.isPulseReady = false

        hud.bind(to: model)

        XCTAssertEqual(hud.hpBar.currentHP, 40)
        XCTAssertEqual(hud.hpBar.maxHP, 100)
        XCTAssertEqual(hud.levelXPBar.level, 3)
        XCTAssertEqual(hud.levelXPBar.currentXP, 25)
        XCTAssertEqual(hud.levelXPBar.xpForNextLevel, 100)
        XCTAssertEqual(hud.runTimer.formattedText, "01:05")
        XCTAssertEqual(hud.killCount.kills, 7)
        XCTAssertEqual(hud.pulseButton.cooldownFraction, 0.5, accuracy: 1e-6)
        XCTAssertFalse(hud.pulseButton.isReady)
    }

    // MARK: - refresh() reflects the model's latest reading -- no stale cache

    func test_refresh_reflectsTheModelsLatestValues_withNoStaleCachedCopy() {
        let hud = HUDLayer()
        let model = MockHUDRunModel()
        hud.bind(to: model)
        XCTAssertEqual(hud.killCount.kills, 0)

        model.currentHP = 10
        model.kills = 12
        model.elapsedSeconds = 5
        hud.refresh()

        XCTAssertEqual(hud.hpBar.currentHP, 10)
        XCTAssertEqual(hud.killCount.kills, 12)
        XCTAssertEqual(hud.runTimer.formattedText, "00:05")

        // A further, unrelated mutation must still show up on the very
        // next refresh -- proving there is no independent stored copy
        // anywhere on HUDLayer that could go stale between updates.
        model.kills = 13
        model.level = 4
        hud.refresh()

        XCTAssertEqual(hud.killCount.kills, 13)
        XCTAssertEqual(hud.levelXPBar.level, 4)
        // Untouched fields must still read the last value written, not
        // reset or drift as a side effect of the unrelated mutation.
        XCTAssertEqual(hud.hpBar.currentHP, 10)
    }

    // MARK: - The pulse button's press reaches the model's triggerPulse()

    func test_pulseButtonPress_invokesTheModelsTriggerPulse() {
        let hud = HUDLayer()
        let model = MockHUDRunModel()
        hud.bind(to: model)

        hud.pulseButton.handleTouch()

        XCTAssertEqual(model.triggerPulseCount, 1, "PulseButton.onPress must invoke the bound model's triggerPulse()")
    }

    func test_rebinding_toADifferentModel_retargetsThePulseButtonsTrigger() {
        let hud = HUDLayer()
        let firstModel = MockHUDRunModel()
        let secondModel = MockHUDRunModel()
        hud.bind(to: firstModel)

        hud.bind(to: secondModel)
        hud.pulseButton.handleTouch()

        XCTAssertEqual(secondModel.triggerPulseCount, 1)
        XCTAssertEqual(firstModel.triggerPulseCount, 0, "a press after rebinding must not reach the old model")
    }

    /// The other half of a rebind, which the press-path test above cannot
    /// see: `onSwarmEscalation` is a closure `bind(to:)` installs *on the
    /// model*, so a rebind has to clear the old model's copy or that model
    /// keeps a live hook straight into this layer's banner.
    func test_rebinding_toADifferentModel_clearsTheOldModelsSwarmEscalationHook() {
        let hud = HUDLayer()
        let firstModel = MockHUDRunModel()
        let secondModel = MockHUDRunModel()
        hud.bind(to: firstModel)
        XCTAssertNotNil(firstModel.onSwarmEscalation, "precondition: bind(to:) installs the hook")

        hud.bind(to: secondModel)

        XCTAssertNil(
            firstModel.onSwarmEscalation,
            "a rebind must leave the previous model inert, not holding a live hook into this layer"
        )
        firstModel.onSwarmEscalation?()
        XCTAssertFalse(
            hud.swarmBanner.isShowing,
            "an escalation on a model this layer is no longer bound to must not show the banner"
        )

        secondModel.onSwarmEscalation?()
        XCTAssertTrue(hud.swarmBanner.isShowing, "the currently bound model's escalation must still show it")
    }

    /// ... while rebinding to the *same* model (what `GameScene` does on
    /// every `.gameplay` entry) must leave that model's hook installed.
    func test_rebinding_toTheSameModel_keepsItsSwarmEscalationHookInstalled() {
        let hud = HUDLayer()
        let model = MockHUDRunModel()
        hud.bind(to: model)

        hud.bind(to: model)

        XCTAssertNotNil(model.onSwarmEscalation)
        model.onSwarmEscalation?()
        XCTAssertTrue(hud.swarmBanner.isShowing)
    }

    // MARK: - Rebinding never leaves a stale reading from the old model

    func test_rebinding_toADifferentModel_stopsForwardingFromTheOldOne() {
        let hud = HUDLayer()
        let firstModel = MockHUDRunModel()
        firstModel.kills = 5
        hud.bind(to: firstModel)
        XCTAssertEqual(hud.killCount.kills, 5)

        let secondModel = MockHUDRunModel()
        secondModel.kills = 99
        hud.bind(to: secondModel)
        XCTAssertEqual(hud.killCount.kills, 99)

        firstModel.kills = 1_000
        hud.refresh()

        XCTAssertEqual(
            hud.killCount.kills, 99,
            "refresh() must read the currently bound model, not a model this layer was previously bound to"
        )
    }

    // MARK: - The radar binding: model -> HUDLayer -> RadarMapNode

    /// The seam neither `RadarMapNode` (driven directly with hand-built
    /// tiles) nor `HUDLayout` (pure frames) exercises: the tile-rounding
    /// and predicate-construction `refresh()` does *between* the model and
    /// the node (PR #79 review).
    ///
    /// A conformer reporting fractional positions is the real case --
    /// `radarRaccoonCandidates` carries live `TilePoint`s mid-tile -- so
    /// this drives one deliberately fractional candidate and asserts its
    /// marker lands on the whole-tile offset `IsometricProjection
    /// .tile(containing:)`'s pinned seam rule rounds it to. A regression
    /// that dropped the rounding, or projected in screen space, would put
    /// every blip in the wrong place while both existing suites stayed
    /// green.
    func test_refresh_projectsTheModelsFractionalRaccoonPosition_ontoItsWholeTileRadarPoint() throws {
        let hud = HUDLayer()
        let model = MockHUDRunModel()
        let sceneSize = CGSize(width: 390, height: 844)
        hud.applyLayout(for: sceneSize, safeAreaInsets: .zero, orientation: .portrait)

        model.deviceScale = 2
        model.radarPlayerTile = TileCoordinate(tileX: 10, tileY: -4)
        // (13.4, -2.3) rounds to tile (13, -2) under `floor(coord + 0.5)`,
        // i.e. offset (+3, +2) from the player's own tile.
        model.radarRaccoonCandidates = [
            TargetSelection.Candidate(raccoon: RaccoonNode(tier: .base), position: TilePoint(x: 13.4, y: -2.3))
        ]
        model.radarMedKitTiles = [TilePoint(x: 7.6, y: -4.2)] // -> tile (8, -4), offset (-2, 0)

        hud.bind(to: model)

        let expectedRaccoonPoint = RadarGeometry.radarPoint(
            forTileOffset: (x: 3, y: 2), scale: hud.radarMap.radarScale
        )
        let raccoonContainer = try XCTUnwrap(hud.radarMap.childNode(withName: "//radarMap.raccoonMarkers"))
        let raccoonMarker = try XCTUnwrap(raccoonContainer.children.first as? SKSpriteNode)
        XCTAssertFalse(raccoonMarker.isHidden, "an in-window raccoon must be drawn")
        XCTAssertEqual(
            raccoonMarker.position,
            PixelCrispness.snappedPosition(for: expectedRaccoonPoint, scale: 2),
            "the raccoon blip must sit at its tile offset from the player, not at a raw/screen-space position"
        )

        let expectedMedKitPoint = RadarGeometry.radarPoint(
            forTileOffset: (x: -2, y: 0), scale: hud.radarMap.radarScale
        )
        let medKitContainer = try XCTUnwrap(hud.radarMap.childNode(withName: "//radarMap.medKitMarkers"))
        let medKitMarker = try XCTUnwrap(medKitContainer.children.first as? SKSpriteNode)
        XCTAssertFalse(medKitMarker.isHidden, "an in-window med kit must be drawn")
        XCTAssertEqual(
            medKitMarker.position,
            PixelCrispness.snappedPosition(for: expectedMedKitPoint, scale: 2)
        )
    }

    /// `radarPlayerTile` is the radar's *centre*: the same world tile must
    /// project to the dial's origin whatever absolute tile the player is
    /// standing on, and a blip's position must depend only on its offset.
    func test_refresh_centresTheRadarOnTheModelsPlayerTile() throws {
        let hud = HUDLayer()
        let model = MockHUDRunModel()
        hud.applyLayout(for: CGSize(width: 390, height: 844), safeAreaInsets: .zero, orientation: .portrait)

        model.radarPlayerTile = TileCoordinate(tileX: 0, tileY: 0)
        model.radarRaccoonCandidates = [
            TargetSelection.Candidate(raccoon: RaccoonNode(tier: .base), position: TilePoint(x: 2, y: 1))
        ]
        hud.bind(to: model)

        let container = try XCTUnwrap(hud.radarMap.childNode(withName: "//radarMap.raccoonMarkers"))
        let marker = try XCTUnwrap(container.children.first as? SKSpriteNode)
        let atOrigin = marker.position

        // Same *offset*, a completely different absolute tile: the blip
        // must not move, which is only true if the centre tracks the
        // model's `radarPlayerTile` rather than world (0, 0).
        model.radarPlayerTile = TileCoordinate(tileX: -120, tileY: 57)
        model.radarRaccoonCandidates = [
            TargetSelection.Candidate(raccoon: RaccoonNode(tier: .base), position: TilePoint(x: -118, y: 58))
        ]
        hud.refresh()

        XCTAssertEqual(marker.position, atOrigin, "the radar must re-centre on the player, not on world (0, 0)")
    }

    /// `radarBuildingRecords` is a `flatMap` across the full resident chunk
    /// window on the production conformer, so `refresh()` must read it only
    /// on the frames that actually rasterize a backdrop -- not on all of
    /// them (PR #79 review).
    func test_refresh_readsTheBuildingRecords_onlyOnFramesThatRebuildTheBackdrop() {
        let hud = HUDLayer()
        let model = MockHUDRunModel()
        // Before `bind(to:)`, so the layout's own `radarScale` write cannot
        // itself invalidate the backdrop built by that first refresh.
        hud.applyLayout(for: CGSize(width: 390, height: 844), safeAreaInsets: .zero, orientation: .portrait)

        hud.bind(to: model)

        XCTAssertEqual(
            model.radarBuildingRecordsReadCount, 1,
            "the first refresh rasterizes a backdrop, and must read the resident records exactly once to do it"
        )

        model.kills = 3
        hud.refresh()
        hud.refresh()
        hud.refresh()

        XCTAssertEqual(hud.killCount.kills, 3, "precondition: those refreshes really did run")
        XCTAssertEqual(
            model.radarBuildingRecordsReadCount, 1,
            "a frame that rebuilds nothing must not traverse the resident chunk window at all"
        )
    }

    /// The spawn case the player-tile-only cache key missed: `bind(to:)`
    /// runs before the first `cameraController.update(focus:)`, so the
    /// first backdrop is built against an empty resident window. Once the
    /// window streams in, a *stationary* player must still get the real
    /// city -- the dial is otherwise stuck showing only the seeded lattice
    /// until they happen to cross a tile boundary (PR #79 review).
    func test_refresh_rebuildsTheBackdrop_whenTheResidentWindowStreamsIn_underAStationaryPlayer() {
        let hud = HUDLayer()
        let model = MockHUDRunModel()
        hud.applyLayout(for: CGSize(width: 390, height: 844), safeAreaInsets: .zero, orientation: .portrait)

        model.radarPlayerTile = TileCoordinate(tileX: 4, tileY: 4)
        model.radarBuildingRecordsStore = []
        hud.bind(to: model)
        let readsAfterSpawnBuild = model.radarBuildingRecordsReadCount

        // The chunk window streams in around a player who has not moved.
        let tile = TileCoordinate(tileX: 6, tileY: 6)
        model.radarBuildingRecordsStore = [
            BuildingPlacementRecord(
                lotTile: tile,
                building: BuildingCatalog.entries[0],
                footprintTiles: [tile],
                farCornerTile: tile
            )
        ]
        model.radarResidencyRevision += 1
        hud.refresh()

        XCTAssertGreaterThan(
            model.radarBuildingRecordsReadCount, readsAfterSpawnBuild,
            "a resident-window change must rebuild the backdrop even though the player tile is unchanged"
        )
    }

    // MARK: - The live scene's own conformance reads its run state directly

    /// The production end of the same contract: `GameScene`'s `HUDRunModel`
    /// conformance must report *this* run's live state, so a real run's
    /// mutations (a kill recorded on `runStats`, the run clock advancing)
    /// reach the mounted elements on the next `refresh()` with no snapshot
    /// in between.
    func test_theLiveScene_bindsItsOwnRunState_intoTheMountedHUD() throws {
        let scene = GameScene(size: CGSize(width: 390, height: 844))
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))

        let hud = try XCTUnwrap(scene.hudLayer, "entering .gameplay must mount HUDLayer")
        XCTAssertTrue(hud.runModel === scene, "the mounted HUD must be bound to the scene itself")

        let player = try XCTUnwrap(scene.player, "entering .gameplay must mount the player")
        XCTAssertEqual(hud.hpBar.currentHP, player.hp, "a fresh run's HUD must already read the player's real HP")
        XCTAssertEqual(hud.hpBar.maxHP, player.maxHP)
        XCTAssertEqual(hud.killCount.kills, 0)

        scene.runStats.recordKill()
        hud.refresh()

        XCTAssertEqual(hud.killCount.kills, 1, "a kill recorded on the run's own stats must reach the HUD")
    }
}
