import CoreGraphics
import SpriteKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// CYBERPUN-17-4-t2: `GroundTileRenderer` turns a `TileKind` at a
/// `TileCoordinate` into a pixel-crisp, correctly depth-sorted ground node.
final class GroundTileRendererTests: XCTestCase {

    // MARK: - Kind -> rect mapping (AC7)

    /// The non-`.asphalt` kinds map to exactly one `GroundTileKind`
    /// regardless of tile coordinate.
    func test_nonAsphaltKinds_mapToTheirDocumentedGroundTileKind_atAnyCoordinate() {
        let cases: [(TileKind, GroundTileKind)] = [
            (.junctionStopLine, .junctionStopLine),
            (.kerbSidewalk, .kerbSidewalk),
            (.lot, .lot),
            (.buildingFootprint, .buildingFootprint),
        ]
        let coordinates = [
            TileCoordinate(tileX: 0, tileY: 0),
            TileCoordinate(tileX: 3, tileY: 3),
            TileCoordinate(tileX: -7, tileY: 11),
        ]

        for (tileKind, expectedGroundKind) in cases {
            for coordinate in coordinates {
                let groundKind = GroundTileRenderer.groundTileKind(for: tileKind, at: coordinate)
                XCTAssertEqual(groundKind, expectedGroundKind, "\(tileKind) at \(coordinate) mapped incorrectly.")
                XCTAssertEqual(
                    GroundTileCatalog.pixelRect(for: groundKind),
                    GroundTileCatalog.pixelRect(for: expectedGroundKind)
                )
            }
        }
    }

    /// `.asphalt` on a corridor whose *X* axis is the street band (a fixed
    /// `xMod`, `y` unconstrained) runs north-south.
    func test_asphalt_onXAxisStreetBand_mapsToNorthSouthLane() {
        // xMod = 4 (>= blockSize 3) => streetX; yMod = 0 (< 3) => not streetY.
        let coordinate = TileCoordinate(tileX: 4, tileY: 0)
        XCTAssertEqual(GroundTileRenderer.groundTileKind(for: .asphalt, at: coordinate), .asphaltNorthSouth)
    }

    /// `.asphalt` on a corridor whose *Y* axis is the street band runs
    /// east-west.
    func test_asphalt_onYAxisStreetBand_mapsToEastWestLane() {
        // xMod = 0 (< 3) => not streetX; yMod = 4 (>= 3) => streetY.
        let coordinate = TileCoordinate(tileX: 0, tileY: 4)
        XCTAssertEqual(GroundTileRenderer.groundTileKind(for: .asphalt, at: coordinate), .asphaltEastWest)
    }

    /// A lattice crossing's own ambiguous centre tile (both axes in the
    /// street band) has a documented, deterministic default.
    func test_asphalt_atCrossingCentre_defaultsToEastWest() {
        // xMod = 4, yMod = 4: both >= blockSize 3, so both axes are street.
        let coordinate = TileCoordinate(tileX: 4, tileY: 4)
        XCTAssertEqual(GroundTileRenderer.groundTileKind(for: .asphalt, at: coordinate), .asphaltEastWest)
    }

    /// AC: the 3-tile street reads as asphalt between sidewalks/kerbs —
    /// three distinct ground kinds/rects, not a single merged "street"
    /// sprite. Uses `CityLatticeGenerator.classify` to source real
    /// `TileKind`s for a genuine street cross-section rather than
    /// hand-picked kinds that might not reflect what the generator emits.
    func test_threeTileStreetCrossSection_reads_asphaltFlankedBySidewalks() {
        let seed = WorldSeed(rawValue: 42)
        // x = 3, 4, 5 at y = 0: xMod 3/4/5 are the street band's edge,
        // centre lane, edge; yMod 0 keeps this axis a block interior, so
        // this is a straight north-south corridor's width cross-section.
        let west = CityLatticeGenerator.classify(tileX: 3, tileY: 0, seed: seed)
        let centre = CityLatticeGenerator.classify(tileX: 4, tileY: 0, seed: seed)
        let east = CityLatticeGenerator.classify(tileX: 5, tileY: 0, seed: seed)

        XCTAssertEqual(west.kind, .kerbSidewalk)
        XCTAssertEqual(centre.kind, .asphalt)
        XCTAssertEqual(east.kind, .kerbSidewalk)

        let westGroundKind = GroundTileRenderer.groundTileKind(for: west.kind, at: TileCoordinate(tileX: 3, tileY: 0))
        let centreGroundKind = GroundTileRenderer.groundTileKind(for: centre.kind, at: TileCoordinate(tileX: 4, tileY: 0))
        let eastGroundKind = GroundTileRenderer.groundTileKind(for: east.kind, at: TileCoordinate(tileX: 5, tileY: 0))

        XCTAssertEqual(westGroundKind, .kerbSidewalk)
        XCTAssertEqual(eastGroundKind, .kerbSidewalk)
        XCTAssertEqual(centreGroundKind, .asphaltNorthSouth)

        let westRect = GroundTileCatalog.pixelRect(for: westGroundKind)
        let centreRect = GroundTileCatalog.pixelRect(for: centreGroundKind)
        let eastRect = GroundTileCatalog.pixelRect(for: eastGroundKind)

        XCTAssertEqual(westRect, eastRect, "Both kerb edges of one corridor must share the same texture.")
        XCTAssertNotEqual(westRect, centreRect, "The lane must render as a texture distinct from its flanking kerbs.")
    }

    // MARK: - Pixel crispness sweep (AC5)

    private static let allTileKinds: [TileKind] = [.asphalt, .junctionStopLine, .kerbSidewalk, .lot, .buildingFootprint]
    private static let sampleCoordinates: [TileCoordinate] = [
        TileCoordinate(tileX: 0, tileY: 0),
        TileCoordinate(tileX: 4, tileY: 0),
        TileCoordinate(tileX: 0, tileY: 4),
        TileCoordinate(tileX: -12, tileY: 9),
        TileCoordinate(tileX: 30, tileY: -17),
    ]

    private func allProducedNodes() -> [SKSpriteNode] {
        Self.allTileKinds.flatMap { kind in
            Self.sampleCoordinates.map { coordinate in GroundTileRenderer.node(for: kind, at: coordinate) }
        }
    }

    func test_everyProducedNode_isPixelCrisp() {
        let nodes = allProducedNodes()
        XCTAssertFalse(nodes.isEmpty)

        for node in nodes {
            XCTAssertEqual(node.texture?.filteringMode, .nearest)
            XCTAssertEqual(node.texture?.usesMipmaps, false)
            assertIsWholeNumber(node.xScale, label: "xScale")
            assertIsWholeNumber(node.yScale, label: "yScale")
            assertIsWholeNumber(node.position.x, label: "position.x")
            assertIsWholeNumber(node.position.y, label: "position.y")
        }
    }

    private func assertIsWholeNumber(
        _ value: CGFloat,
        label: String,
        accuracy: CGFloat = 1e-6,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(value, value.rounded(), accuracy: accuracy, "\(label) (\(value)) is not a whole number.", file: file, line: line)
    }

    // MARK: - Depth (ground offset from DepthModel)

    func test_everyProducedNode_zPosition_matchesDepthModelsGroundOffset_convertedRelativeToWorldLayer() {
        for kind in Self.allTileKinds {
            for coordinate in Self.sampleCoordinates {
                let node = GroundTileRenderer.node(for: kind, at: coordinate)
                let expectedAbsolute = DepthModel.groundZPosition(forTile: coordinate)
                let expectedRelative = DepthModel.worldLayerRelativeZ(forAbsoluteZ: expectedAbsolute)

                XCTAssertEqual(
                    node.zPosition,
                    expectedRelative,
                    accuracy: 1e-9,
                    "\(kind) at \(coordinate) did not get DepthModel's ground zPosition."
                )
            }
        }
    }
}
