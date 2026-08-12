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

    func test_uiLayerChildren_neverFallBelowUIMinZ() {
        let scene = makeScene()
        let placeholder = PlaceholderScreenNode(label: "menu")
        // .menu is the state machine's initial state, so registering here
        // mounts `placeholder` under `uiLayer` immediately.
        scene.register(placeholder, for: .menu)

        let cumulativeChildZ =
            scene.cameraNode.zPosition + scene.uiLayer.zPosition + placeholder.node.zPosition
        XCTAssertGreaterThanOrEqual(cumulativeChildZ, LayerConstants.uiMinZ)
    }

    func test_worldLayer_zPosition_neverExceedsWorldMaxZ() {
        let scene = makeScene()
        XCTAssertLessThanOrEqual(scene.worldLayer.zPosition, LayerConstants.worldMaxZ)
    }
}
