import CoreGraphics
import SpriteKit
import UIKit
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

    /// Locates a straight north-south corridor whose *two* flanking block
    /// interiors both classify as `blockKind`, returning the corridor's
    /// west-edge tile X plus a tile Y inside those two blocks' interior
    /// rows.
    ///
    /// CYBERPUN-17-22: a corridor edge kerbs only the one block interior it
    /// actually borders, so what a cross-section reads depends on what
    /// those two specific blocks hold under the seed. Searching the lattice
    /// for a corridor the generator really reports as flanked by
    /// `blockKind` keeps the test fully deterministic (same seed, same
    /// scan order, same answer) while pinning the *generator's* behaviour
    /// rather than a hand-picked coordinate that happens to agree with it.
    private func corridorFlanked(
        byBlocksOfKind blockKind: TileKind,
        seed: WorldSeed
    ) -> (westEdgeX: Int, tileY: Int)? {
        let period = CityLatticeGenerator.period
        for blockY in -16..<16 {
            for blockX in -32..<32 {
                // Local (0, 0) of each block: both mods < blockSize, so
                // `classify` reports the block interior's own kind.
                let tileY = blockY * period
                let westBlock = CityLatticeGenerator.classify(tileX: blockX * period, tileY: tileY, seed: seed)
                let eastBlock = CityLatticeGenerator.classify(tileX: (blockX + 1) * period, tileY: tileY, seed: seed)
                guard westBlock.kind == blockKind, eastBlock.kind == blockKind else { continue }
                // The street band between the two: xMod 3/4/5 = west edge,
                // centre lane, east edge; yMod 0 keeps that axis a block
                // interior, so this is a straight corridor's cross-section.
                return (blockX * period + CityLatticeGenerator.blockSize, tileY)
            }
        }
        return nil
    }

    /// AC: the 3-tile street reads as asphalt between sidewalks/kerbs —
    /// three distinct ground kinds/rects, not a single merged "street"
    /// sprite. Uses `CityLatticeGenerator.classify` to source real
    /// `TileKind`s for a genuine street cross-section rather than
    /// hand-picked kinds that might not reflect what the generator emits.
    ///
    /// Taken beside blocks the generator reports as `.buildingFootprint`,
    /// because that is the case with a building edge to kerb.
    func test_threeTileStreetCrossSection_besideBuiltBlocks_readsAsphaltFlankedBySidewalks() {
        let seed = WorldSeed(rawValue: 42)
        guard let corridor = corridorFlanked(byBlocksOfKind: .buildingFootprint, seed: seed) else {
            return XCTFail("No corridor flanked by two building blocks in the scanned region under seed 42.")
        }
        let westX = corridor.westEdgeX
        let tileY = corridor.tileY

        let west = CityLatticeGenerator.classify(tileX: westX, tileY: tileY, seed: seed)
        let centre = CityLatticeGenerator.classify(tileX: westX + 1, tileY: tileY, seed: seed)
        let east = CityLatticeGenerator.classify(tileX: westX + 2, tileY: tileY, seed: seed)

        XCTAssertEqual(west.kind, .kerbSidewalk)
        XCTAssertEqual(centre.kind, .asphalt)
        XCTAssertEqual(east.kind, .kerbSidewalk)

        let westGroundKind = GroundTileRenderer.groundTileKind(
            for: west.kind, at: TileCoordinate(tileX: westX, tileY: tileY)
        )
        let centreGroundKind = GroundTileRenderer.groundTileKind(
            for: centre.kind, at: TileCoordinate(tileX: westX + 1, tileY: tileY)
        )
        let eastGroundKind = GroundTileRenderer.groundTileKind(
            for: east.kind, at: TileCoordinate(tileX: westX + 2, tileY: tileY)
        )

        XCTAssertEqual(westGroundKind, .kerbSidewalk)
        XCTAssertEqual(eastGroundKind, .kerbSidewalk)
        XCTAssertEqual(centreGroundKind, .asphaltNorthSouth)

        let westRect = GroundTileCatalog.pixelRect(for: westGroundKind)
        let centreRect = GroundTileCatalog.pixelRect(for: centreGroundKind)
        let eastRect = GroundTileCatalog.pixelRect(for: eastGroundKind)

        XCTAssertEqual(westRect, eastRect, "Both kerb edges of one corridor must share the same texture.")
        XCTAssertNotEqual(westRect, centreRect, "The lane must render as a texture distinct from its flanking kerbs.")
    }

    /// CYBERPUN-17-22, the sibling case: a corridor between two empty lots
    /// has no building edge to kerb on either side, so its cross-section
    /// reads as three tiles of unbroken lane asphalt — one texture across
    /// the full width, with no kerb crop anywhere in it.
    func test_threeTileStreetCrossSection_besideEmptyLots_readsAsUnbrokenAsphalt() {
        let seed = WorldSeed(rawValue: 42)
        guard let corridor = corridorFlanked(byBlocksOfKind: .lot, seed: seed) else {
            return XCTFail("No corridor flanked by two empty lots in the scanned region under seed 42.")
        }
        let westX = corridor.westEdgeX
        let tileY = corridor.tileY

        let crossSection = (0..<3).map { offset in
            CityLatticeGenerator.classify(tileX: westX + offset, tileY: tileY, seed: seed)
        }
        for (offset, info) in crossSection.enumerated() {
            XCTAssertEqual(
                info.kind, .asphalt,
                "(\(westX + offset), \(tileY)) borders an empty lot, so it has nothing to kerb."
            )
        }

        let groundKinds = crossSection.enumerated().map { offset, info in
            GroundTileRenderer.groundTileKind(for: info.kind, at: TileCoordinate(tileX: westX + offset, tileY: tileY))
        }
        XCTAssertEqual(
            groundKinds, [.asphaltNorthSouth, .asphaltNorthSouth, .asphaltNorthSouth],
            "A lot-flanked corridor must render as its north-south lane across its full 3-tile width."
        )

        let rects = groundKinds.map { GroundTileCatalog.pixelRect(for: $0) }
        let kerbRect = GroundTileCatalog.pixelRect(for: .kerbSidewalk)
        for rect in rects {
            XCTAssertNotEqual(rect, kerbRect, "No kerb texture may be drawn where there is no building to kerb.")
        }
        XCTAssertEqual(Set(rects.map(\.debugDescription)).count, 1, "The lot-flanked width must be one texture.")
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

    func test_everyProducedNode_isPixelCrisp() throws {
        let nodes = allProducedNodes()
        XCTAssertFalse(nodes.isEmpty)

        for node in nodes {
            // Every ground kind -- asphalt included, which is tinted black
            // rather than rendered textureless (CYBERPUN-17-27) -- carries
            // an atlas crop, so the filtering checks are unconditional.
            let texture = try XCTUnwrap(node.texture, "Every ground node must carry its atlas crop.")
            XCTAssertEqual(texture.filteringMode, .nearest)
            XCTAssertEqual(texture.usesMipmaps, false)
            assertIsWholeNumber(node.xScale, label: "xScale")
            assertIsWholeNumber(node.yScale, label: "yScale")
            assertIsWholeNumber(node.position.x, label: "position.x")
            assertIsWholeNumber(node.position.y, label: "position.y")
        }
    }

    // MARK: - Asphalt renders solid black (CYBERPUN-17-27)

    /// The street tiles' yellow lane-divider dash read as visually wrong
    /// on-device, so both asphalt orientations must render solid black --
    /// as a **full-strength black tint over the lane crop**, not as a
    /// textureless colour fill. Keeping the texture is what preserves the
    /// diamond's alpha silhouette: an untextured `SKSpriteNode` fills its
    /// whole rectangular `size`, so a 96x60 opaque black rectangle would
    /// overpaint the corners of the four neighbouring diamonds.
    ///
    /// Blackness is asserted on the **RGBA components**, never with
    /// `XCTAssertEqual(node.color, .black)`. `SKSpriteNode` normalises an
    /// assigned colour into extended sRGB, so the value read back is
    /// `UIExtendedSRGBColorSpace 0 0 0 1` while `UIColor.black` is
    /// `UIExtendedGrayColorSpace 0 1`; `UIColor` equality is colour-space
    /// sensitive, so that assertion fails for a node that is in fact
    /// perfectly black.
    func test_asphaltKinds_renderAsBlackTintOverTheirLaneCrop() throws {
        // tileX:4, tileY:0 maps to .asphaltNorthSouth; tileX:0, tileY:4 maps
        // to .asphaltEastWest (see test_asphalt_onXAxisStreetBand_mapsToNorthSouthLane
        // / test_asphalt_onYAxisStreetBand_mapsToEastWestLane above).
        let northSouthCoordinate = TileCoordinate(tileX: 4, tileY: 0)
        let eastWestCoordinate = TileCoordinate(tileX: 0, tileY: 4)

        for (coordinate, groundKind) in [
            (northSouthCoordinate, GroundTileKind.asphaltNorthSouth),
            (eastWestCoordinate, GroundTileKind.asphaltEastWest),
        ] {
            let node = GroundTileRenderer.node(for: .asphalt, at: coordinate)

            XCTAssertNotNil(
                node.texture,
                "\(groundKind) must keep its lane crop so the tint inherits the diamond's alpha mask."
            )
            XCTAssertEqual(node.colorBlendFactor, 1, "\(groundKind) must tint its crop at full strength.")
            assertIsBlack(node.color, label: "\(groundKind)'s tint")
            XCTAssertEqual(
                node.size, GroundTileCatalog.pixelRect(for: groundKind).size,
                "\(groundKind) must keep the lane diamond's measured footprint."
            )
        }
    }

    /// A pooled node that last rendered asphalt must not keep its
    /// full-strength black tint when `GroundPlaneStreamer` recycles it as
    /// another kind -- `configure(_:for:at:)` has to be total over the node
    /// it is handed, not merely additive. Without the `default:` branch
    /// resetting `colorBlendFactor`, a recycled kerb would draw as a black
    /// silhouette.
    func test_recycledAsphaltNode_reconfiguredAsAnotherKind_dropsItsBlackTint() throws {
        let asphaltCoordinate = TileCoordinate(tileX: 4, tileY: 0)
        let node = GroundTileRenderer.node(for: .asphalt, at: asphaltCoordinate)
        XCTAssertEqual(node.colorBlendFactor, 1, "Precondition: the node starts out as a fully tinted lane.")

        let kerbCoordinate = TileCoordinate(tileX: 3, tileY: 0)
        GroundTileRenderer.configure(node, for: .kerbSidewalk, at: kerbCoordinate)

        let texture = try XCTUnwrap(node.texture, "A recycled node must be re-cropped to its new kind's diamond.")
        XCTAssertEqual(
            node.colorBlendFactor, 0,
            "A pooled asphalt node recycled as a kerb must drop the lane's black tint, not paint the kerb black."
        )
        XCTAssertEqual(node.size, texture.size())
        XCTAssertEqual(
            node.size, GroundTileCatalog.pixelRect(for: .kerbSidewalk).size,
            "A recycled node must take its new kind's measured footprint."
        )
    }

    /// Asserts `color` is black by reading its RGBA **components**, which is
    /// colour-space agnostic, rather than comparing `UIColor` instances --
    /// see `test_asphaltKinds_renderAsBlackTintOverTheirLaneCrop` for why
    /// the equality form is unusable on a colour read back off a node.
    private func assertIsBlack(
        _ color: UIColor,
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var red: CGFloat = -1
        var green: CGFloat = -1
        var blue: CGFloat = -1
        var alpha: CGFloat = -1
        XCTAssertTrue(
            color.getRed(&red, green: &green, blue: &blue, alpha: &alpha),
            "\(label): \(color) could not be read as RGBA.", file: file, line: line
        )
        XCTAssertEqual(red, 0, accuracy: 1e-6, "\(label): red component is \(red), not 0.", file: file, line: line)
        XCTAssertEqual(green, 0, accuracy: 1e-6, "\(label): green component is \(green), not 0.", file: file, line: line)
        XCTAssertEqual(blue, 0, accuracy: 1e-6, "\(label): blue component is \(blue), not 0.", file: file, line: line)
        XCTAssertEqual(alpha, 1, accuracy: 1e-6, "\(label): alpha is \(alpha), not fully opaque.", file: file, line: line)
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
