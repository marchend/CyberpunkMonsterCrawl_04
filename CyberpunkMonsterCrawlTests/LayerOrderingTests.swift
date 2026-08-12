import XCTest
import SpriteKit
import UIKit
@testable import CyberpunkMonsterCrawl

/// Proves the v1 failure mode (world rendered over the UI, every unit test
/// green) is structurally impossible here: `LayerConstants` enforces
/// `worldLayer < effectsLayer < uiLayer` as checked numbers, and a live
/// `GameScene` actually uses those numbers for its three layer containers.
final class LayerOrderingTests: XCTestCase {

    private func makeScene() -> GameScene {
        GameScene(size: CGSize(width: 400, height: 800))
    }

    // MARK: - Named-constant ordering invariant (AC3)

    func test_orderingInvariant_worldStrictlyBelowEffectsStrictlyBelowUI() {
        XCTAssertLessThan(LayerConstants.worldMinZ, LayerConstants.worldMaxZ)
        XCTAssertLessThan(LayerConstants.effectsMinZ, LayerConstants.effectsMaxZ)
        XCTAssertLessThan(LayerConstants.uiMinZ, LayerConstants.uiMaxZ)

        XCTAssertLessThan(
            LayerConstants.worldMaxZ, LayerConstants.effectsMinZ,
            "world's max must sit strictly below effects' min"
        )
        XCTAssertLessThan(
            LayerConstants.effectsMaxZ, LayerConstants.uiMinZ,
            "effects' max must sit strictly below UI's min"
        )
        // AC3, restated directly: the UI layer's minimum zPosition must
        // exceed the world layer's maximum zPosition.
        XCTAssertGreaterThan(LayerConstants.uiMinZ, LayerConstants.worldMaxZ)
    }

    func test_containerZPositions_fallInsideTheirOwnBand() {
        XCTAssertGreaterThanOrEqual(LayerConstants.worldLayerZ, LayerConstants.worldMinZ)
        XCTAssertLessThanOrEqual(LayerConstants.worldLayerZ, LayerConstants.worldMaxZ)
        XCTAssertGreaterThanOrEqual(LayerConstants.effectsLayerZ, LayerConstants.effectsMinZ)
        XCTAssertLessThanOrEqual(LayerConstants.effectsLayerZ, LayerConstants.effectsMaxZ)
        XCTAssertGreaterThanOrEqual(LayerConstants.uiLayerZ, LayerConstants.uiMinZ)
        XCTAssertLessThanOrEqual(LayerConstants.uiLayerZ, LayerConstants.uiMaxZ)
    }

    // MARK: - Live GameScene wiring

    func test_gameScene_usesSharedConstantsForItsLayers() {
        let scene = makeScene()

        XCTAssertEqual(scene.worldLayer.zPosition, LayerConstants.worldLayerZ)
        XCTAssertEqual(scene.effectsLayer.zPosition, LayerConstants.effectsLayerZ)
        XCTAssertEqual(scene.uiLayer.zPosition, LayerConstants.uiLayerZ)
    }

    func test_uiLayer_isParentedToTheCamera() {
        let scene = makeScene()

        XCTAssertTrue(scene.uiLayer.parent === scene.cameraNode)
        XCTAssertTrue(scene.camera === scene.cameraNode)
        XCTAssertTrue(scene.cameraNode.parent === scene)
    }

    func test_worldLayer_andEffectsLayer_areDirectSceneChildren() {
        let scene = makeScene()

        XCTAssertTrue(scene.worldLayer.parent === scene)
        XCTAssertTrue(scene.effectsLayer.parent === scene)
    }

    func test_uiLayer_cumulativeZPosition_neverFallsBelowUIMinZ() {
        let scene = makeScene()

        let cumulativeUIZ = scene.cameraNode.zPosition + scene.uiLayer.zPosition
        XCTAssertGreaterThanOrEqual(cumulativeUIZ, LayerConstants.uiMinZ)
    }

    func test_worldLayer_zPosition_neverExceedsWorldMaxZ() {
        let scene = makeScene()
        XCTAssertLessThanOrEqual(scene.worldLayer.zPosition, LayerConstants.worldMaxZ)
    }

    // MARK: - Hostile cases: descendants escaping their band (AC3)
    //
    // SpriteKit accumulates `zPosition` down the tree, so a UI child with a
    // large negative offset (or a world child with a large positive one)
    // escapes its band and reproduces the v1 "world paints over UI" bug.
    // Checking the three container nodes cannot catch that, so
    // `GameScene.nodesEscapingTheirLayerBand()` walks every descendant and
    // `assertSceneInvariants()` trips on it in DEBUG. These tests drive that
    // mechanism with the violations it exists to catch.

    func test_bandAudit_isClean_forAFreshScene_andForAMountedScreen() {
        let scene = makeScene()
        XCTAssertTrue(
            scene.nodesEscapingTheirLayerBand().isEmpty,
            "a freshly constructed scene must satisfy the band invariant"
        )

        scene.register(PlaceholderScreenNode(label: "menu"), for: .menu)

        XCTAssertTrue(
            scene.nodesEscapingTheirLayerBand().isEmpty,
            "mounting a screen must not break the band invariant"
        )
        XCTAssertTrue(scene.layerBandViolationReport().isEmpty)
    }

    func test_uiChildWithLargeNegativeZ_escapesUIBand_andIsCaught() {
        let scene = makeScene()
        let sinker = SKNode()
        sinker.name = "uiSinker"
        // Cumulative: uiLayerZ (1_000) + (-5_000) = -4_000, i.e. below the
        // world layer's maximum - exactly the v1 failure.
        sinker.zPosition = -5_000
        scene.uiLayer.addChild(sinker)

        let offenders = scene.nodesEscapingTheirLayerBand()

        XCTAssertTrue(
            offenders.contains { $0 === sinker },
            "a UI child whose cumulative z drops below uiMinZ must be reported"
        )
        XCTAssertFalse(
            scene.layerBandViolationReport().isEmpty,
            "the violation must also be reported in human-readable form for the assertion message"
        )
    }

    func test_deepUIDescendantWithOutOfBandZ_isCaught() {
        let scene = makeScene()
        let container = SKNode()
        scene.uiLayer.addChild(container)
        let sinker = SKNode()
        sinker.name = "deepUISinker"
        sinker.zPosition = -3_000 // cumulative: 1_000 + 0 + (-3_000) = -2_000
        container.addChild(sinker)

        let offenders = scene.nodesEscapingTheirLayerBand()

        XCTAssertTrue(
            offenders.contains { $0 === sinker },
            "the audit must accumulate z down the whole subtree, not just direct children"
        )
        XCTAssertFalse(
            offenders.contains { $0 === container },
            "an in-band intermediate node must not be reported"
        )
    }

    func test_worldChildWithLargePositiveZ_escapesWorldBand_andIsCaught() {
        let scene = makeScene()
        let riser = SKNode()
        riser.name = "worldRiser"
        // Cumulative: worldLayerZ (-100_000) + 200_000 = 100_000, above uiMinZ.
        riser.zPosition = 200_000
        scene.worldLayer.addChild(riser)

        let offenders = scene.nodesEscapingTheirLayerBand()

        XCTAssertTrue(
            offenders.contains { $0 === riser },
            "a world child that climbs past worldMaxZ must be reported"
        )
    }

    func test_inBandChildren_areNotFlagged() {
        let scene = makeScene()

        let worldChild = SKNode()
        worldChild.zPosition = 50_000 // cumulative -50_000, inside the world band
        scene.worldLayer.addChild(worldChild)

        let uiChild = SKNode()
        uiChild.zPosition = 500 // cumulative 1_500, inside the UI band
        scene.uiLayer.addChild(uiChild)

        XCTAssertTrue(
            scene.nodesEscapingTheirLayerBand().isEmpty,
            "legal in-band offsets must not be reported as violations"
        )
    }
}
