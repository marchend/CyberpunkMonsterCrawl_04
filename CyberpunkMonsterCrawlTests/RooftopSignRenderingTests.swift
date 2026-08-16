import CoreGraphics
import SpriteKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// CYBERPUN-17-5-t3: renders a rooftop sign as a **distinct**
/// `sprite_signs`-textured node, added as a child of its carrier building
/// node -- never composited into the building's own texture. Covers this
/// PR's rendering half of AC7 (`RooftopSignPlacementTests` already covers
/// the pure-logic half: which block gets signed, which lot carries it, which
/// of the 12 variants).
final class RooftopSignRenderingTests: XCTestCase {

    private func makeBuildingRecord(lotTile: TileCoordinate, buildingIndex: Int = 0) -> BuildingPlacementRecord {
        BuildingPlacementRecord(
            lotTile: lotTile,
            building: BuildingCatalog.entry(atIndex: buildingIndex),
            footprintTiles: [lotTile],
            farCornerTile: lotTile
        )
    }

    // MARK: - A signed building carries a distinct sprite_signs child

    func test_makeSignNode_addsADistinctSpriteSignsTexturedChild_toTheBuildingNode() {
        let lotTile = TileCoordinate(tileX: 2, tileY: 1)
        let buildingRecord = makeBuildingRecord(lotTile: lotTile, buildingIndex: 3)
        let buildingNode = TileFieldRenderer.makeBuildingNode(for: buildingRecord)
        XCTAssertTrue(
            buildingNode.children.isEmpty,
            "Precondition: a freshly built building node must carry no children of its own."
        )

        let signRecord = RooftopSignRecord(
            block: BlockCoordinate(x: 0, y: 0), carrierLotTile: lotTile, signCellIndex: 5
        )
        let signNode = RooftopSignRenderer.makeSignNode(for: signRecord, parent: buildingNode)

        XCTAssertTrue(signNode.parent === buildingNode, "The sign must be mounted as a child of the building node.")
        XCTAssertEqual(buildingNode.children.count, 1, "The building must carry exactly one sign child.")
        XCTAssertTrue(buildingNode.children.first === signNode)
        XCTAssertEqual(signNode.name, RooftopSignRenderer.signNodeName)

        guard let signTexture = signNode.texture else {
            return XCTFail("Sign node must carry a non-nil texture.")
        }
        // Distinct from the building's own texture: a separate sprite_signs
        // node, never a pixel baked into the building art.
        XCTAssertTrue(
            signTexture !== buildingNode.texture,
            "Sign texture must not be the building's own texture instance."
        )
        XCTAssertNotEqual(
            signTexture.size(), buildingNode.size,
            "The sign's 48×48 sprite_signs cell must not coincidentally equal this building's own texture size."
        )

        let expectedCell = AtlasCellIndex.signs[signRecord.signCellIndex]
        let expectedTexture = AtlasSheet.signs.sheet.texture(col: expectedCell.col, row: expectedCell.row)
        XCTAssertEqual(signTexture.size(), expectedTexture.size())
        XCTAssertEqual(signTexture.textureRect(), expectedTexture.textureRect())
        XCTAssertEqual(signTexture.filteringMode, .nearest)
        XCTAssertFalse(signTexture.usesMipmaps)
    }

    func test_makeSignNode_anchorsBottomCentre_atTheBuildingsRoofline() {
        let lotTile = TileCoordinate(tileX: 5, tileY: 5)
        let buildingRecord = makeBuildingRecord(lotTile: lotTile, buildingIndex: 5)
        let buildingNode = TileFieldRenderer.makeBuildingNode(for: buildingRecord)

        let signRecord = RooftopSignRecord(
            block: BlockCoordinate(x: 1, y: 1), carrierLotTile: lotTile, signCellIndex: 0
        )
        let signNode = RooftopSignRenderer.makeSignNode(for: signRecord, parent: buildingNode)

        XCTAssertEqual(signNode.anchorPoint.x, 0.5, accuracy: 1e-6)
        XCTAssertEqual(signNode.anchorPoint.y, 0, accuracy: 1e-6)

        // The sign's position lives in the BUILDING node's local coordinate
        // space (it is the building's child), so it must land at the
        // building's own top-centre extent regardless of the building's
        // absolute screen position — a child's position is offset from its
        // parent's position, unaffected by the parent's own anchorPoint.
        XCTAssertEqual(signNode.position.x, 0, accuracy: 1e-6)
        XCTAssertEqual(signNode.position.y, buildingNode.size.height.rounded(), accuracy: 1e-6)
    }

    func test_differentSignCellIndices_produceDistinctAtlasCrops() {
        let lotTile = TileCoordinate(tileX: 0, tileY: 0)
        let buildingRecord = makeBuildingRecord(lotTile: lotTile)

        var rects: [CGRect] = []
        for cellIndex in 0..<RooftopSignPlacement.signCellCount {
            let buildingNode = TileFieldRenderer.makeBuildingNode(for: buildingRecord)
            let record = RooftopSignRecord(
                block: BlockCoordinate(x: cellIndex, y: 0), carrierLotTile: lotTile, signCellIndex: cellIndex
            )
            let signNode = RooftopSignRenderer.makeSignNode(for: record, parent: buildingNode)
            guard let texture = signNode.texture else {
                XCTFail("Sign cell \(cellIndex) produced no texture.")
                continue
            }
            rects.append(texture.textureRect())
        }

        XCTAssertEqual(rects.count, RooftopSignPlacement.signCellCount)
        for i in 0..<rects.count {
            for j in (i + 1)..<rects.count {
                XCTAssertNotEqual(rects[i], rects[j], "Sign cells \(i) and \(j) must crop distinct atlas cells.")
            }
        }
    }

    // MARK: - Unsigned building carries no sign child

    /// The bare building factory — with no `RooftopSignRenderer` call —
    /// must never composite a sign of its own; only an explicit
    /// `makeSignNode` call (driven by an actual `RooftopSignRecord`)
    /// attaches one.
    func test_unsignedBuilding_hasNoSpriteSignsChild() {
        let lotTile = TileCoordinate(tileX: 9, tileY: 9)
        let buildingRecord = makeBuildingRecord(lotTile: lotTile, buildingIndex: 7)

        let buildingNode = TileFieldRenderer.makeBuildingNode(for: buildingRecord)

        XCTAssertNil(
            buildingNode.children.first { $0.name == RooftopSignRenderer.signNodeName },
            "An unsigned building must carry no sprite_signs-named child node."
        )
        XCTAssertTrue(buildingNode.children.isEmpty)
    }

    // MARK: - Production wiring: GroundPlaneStreamer actually mounts signs

    /// `RooftopSignRenderer.makeSignNode` in isolation proves the factory
    /// works; it does not prove anything in a real build actually calls it.
    /// This drives the same production mount `BuildingSceneIntegrationTests`
    /// exercises for the building half, and asserts every signed block in
    /// the resident window ends up with a real, textured sign child on its
    /// carrier building — the AC7 rendering half taken end-to-end rather
    /// than only through the factory.
    func test_loadingAChunk_mountsRooftopSignsAsBuildingChildren_forEverySignedBlockInTheResidentWindow() {
        let seed = WorldSeed(rawValue: 909_090)
        let worldLayer = SKNode()
        let streamer = GroundPlaneStreamer(seed: seed, worldLayer: worldLayer)

        streamer.updateCamera(worldPosition: TilePoint(x: 0, y: 0))
        var ticks = 0
        while streamer.advanceIncrementalMount() > 0, ticks < 200 {
            ticks += 1
        }
        XCTAssertLessThan(ticks, 200, "Incremental mount did not converge.")

        let residentSigns = streamer.streaming.residentChunks.values.flatMap(\.roofSigns)
        XCTAssertGreaterThan(
            residentSigns.count, 0,
            "Precondition: this seed's resident window must contain at least one signed block, or the "
                + "rest of this test proves nothing."
        )

        let buildingSprites = worldLayer.children
            .compactMap { $0 as? SKSpriteNode }
            .filter { $0.name == TileFieldRenderer.buildingNodeName }
        let buildingsByPosition = Dictionary(
            buildingSprites.map { ($0.position, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for sign in residentSigns {
            let screenPoint = IsometricProjection.tileToScreen(
                tileX: Double(sign.carrierLotTile.tileX),
                tileY: Double(sign.carrierLotTile.tileY)
            )
            let roundedPoint = CGPoint(x: screenPoint.x.rounded(), y: screenPoint.y.rounded())
            guard let carrierNode = buildingsByPosition[roundedPoint] else {
                XCTFail("No mounted building node found at carrier lot \(sign.carrierLotTile) for sign \(sign).")
                continue
            }

            guard let signChild = carrierNode.children.first(where: { $0.name == RooftopSignRenderer.signNodeName })
            else {
                XCTFail("Carrier building at \(sign.carrierLotTile) has no mounted sign child.")
                continue
            }
            XCTAssertNotNil((signChild as? SKSpriteNode)?.texture, "Mounted sign child carries no texture.")
        }
    }
}
