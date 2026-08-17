import CoreGraphics
import SpriteKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-7` PR 2: the movement-vs-building half.
///
/// A synthetic building footprint is mounted the way a real one is
/// rendered \u2014 `TileFieldRenderer.buildingNodeName`, position computed via
/// the same rounded `IsometricProjection.tileToScreen` call
/// `TileFieldRenderer.configure` uses \u2014 so this fixture cannot silently
/// diverge from what `GroundPlaneStreamer` would actually mount for the
/// identical `BuildingPlacementRecord` (the technique this story's own
/// prior PR recorded for movement/collision integration coverage). Only
/// the mounted node's *position convention* is asserted against that
/// production derivation; `CollisionResolver` itself never reads the
/// scene graph \u2014 it is pure tile-space geometry over
/// `BuildingPlacementRecord.footprintTiles`, exactly like `BuildingObstruction`.
final class CollisionResolverTests: XCTestCase {

    private let footprintOrigin = TileCoordinate(tileX: 20, tileY: 20)

    private func makeRecord(buildingIndex: Int, span: Int) -> BuildingPlacementRecord {
        var tiles: [TileCoordinate] = []
        for dx in 0..<span {
            for dy in 0..<span {
                tiles.append(TileCoordinate(tileX: footprintOrigin.tileX + dx, tileY: footprintOrigin.tileY + dy))
            }
        }
        return BuildingPlacementRecord(
            lotTile: footprintOrigin,
            building: BuildingCatalog.entry(atIndex: buildingIndex),
            footprintTiles: tiles,
            farCornerTile: TileCoordinate(
                tileX: footprintOrigin.tileX + span - 1,
                tileY: footprintOrigin.tileY + span - 1
            )
        )
    }

    /// Mounts a synthetic building node exactly the way
    /// `TileFieldRenderer.configure` mounts a real one: same node name,
    /// same rounded `tileToScreen(lotTile)` position \u2014 so a test fixture
    /// can never quietly drift from what production actually renders for
    /// this record.
    @discardableResult
    private func mountSyntheticBuildingNode(for record: BuildingPlacementRecord, in worldLayer: SKNode) -> SKSpriteNode {
        let node = SKSpriteNode()
        node.name = TileFieldRenderer.buildingNodeName
        let screenPoint = IsometricProjection.tileToScreen(
            tileX: Double(record.lotTile.tileX),
            tileY: Double(record.lotTile.tileY)
        )
        node.position = CGPoint(x: screenPoint.x.rounded(), y: screenPoint.y.rounded())
        worldLayer.addChild(node)
        return node
    }

    private let eightDirections: [CGVector] = [
        CGVector(dx: 1, dy: 0),
        CGVector(dx: -1, dy: 0),
        CGVector(dx: 0, dy: 1),
        CGVector(dx: 0, dy: -1),
        CGVector(dx: 1, dy: 1),
        CGVector(dx: 1, dy: -1),
        CGVector(dx: -1, dy: 1),
        CGVector(dx: -1, dy: -1),
    ]

    // MARK: - The mounted fixture matches production's own derivation

    func test_syntheticBuildingNode_isMountedAtTheSamePositionTileFieldRendererWould() {
        let worldLayer = SKNode()
        let record = makeRecord(buildingIndex: 8, span: 2)
        let node = mountSyntheticBuildingNode(for: record, in: worldLayer)

        let realNode = TileFieldRenderer.makeBuildingNode(for: record)

        XCTAssertEqual(node.name, TileFieldRenderer.buildingNodeName)
        XCTAssertEqual(node.position.x, realNode.position.x, accuracy: 1e-3)
        XCTAssertEqual(node.position.y, realNode.position.y, accuracy: 1e-3)
    }

    // MARK: - 8-direction sweep: approach, never cross the footprint

    /// Sweeps every cardinal/ordinal approach direction into a 2x2
    /// synthetic footprint, taking many small per-frame steps (mirroring
    /// how a live movement loop would call `resolve` once per frame), and
    /// asserts the resolved position never lands strictly inside the
    /// footprint at any step of any direction.
    func test_eightDirectionApproach_neverEntersTheFootprint() {
        let worldLayer = SKNode()
        let record = makeRecord(buildingIndex: 8, span: 2) // a 2x2 footprint (building_08)
        mountSyntheticBuildingNode(for: record, in: worldLayer)
        let bounds = CollisionResolver.footprintBounds(for: record)

        for direction in eightDirections {
            let dx = Double(direction.dx)
            let dy = Double(direction.dy)
            var position = TilePoint(
                x: Double(footprintOrigin.tileX) - dx * 5,
                y: Double(footprintOrigin.tileY) - dy * 5
            )
            let step = CGVector(dx: direction.dx * 0.2, dy: direction.dy * 0.2)

            for tick in 0..<200 {
                position = CollisionResolver.resolve(
                    currentPosition: position,
                    proposedDelta: step,
                    obstructedBy: [record]
                )
                XCTAssertFalse(
                    bounds.contains(x: position.x, y: position.y),
                    "direction \(direction), tick \(tick): resolved position \(position) entered the footprint"
                )
            }
        }
    }

    /// The diagonal-approach case specifically: a sustained push toward a
    /// footprint's corner must actually get close to that vertex (proving
    /// the slide is a genuine per-axis resolution, not an early stop many
    /// tiles short of it) while never entering the footprint \u2014 checked
    /// throughout the sweep, not only at the end, because once contact is
    /// made a continued diagonal push legitimately keeps sliding *along*
    /// whichever wall is now tangent to the motion (the standard per-axis
    /// slide behaviour), rather than parking exactly on the vertex forever.
    func test_diagonalApproach_getsCloseToTheFootprintsNearVertex() {
        let worldLayer = SKNode()
        let record = makeRecord(buildingIndex: 8, span: 2)
        mountSyntheticBuildingNode(for: record, in: worldLayer)
        let bounds = CollisionResolver.footprintBounds(for: record)

        let diagonalDirections = eightDirections.filter { $0.dx != 0 && $0.dy != 0 }
        XCTAssertEqual(diagonalDirections.count, 4, "precondition: exactly 4 of the 8 directions are diagonal")

        for direction in diagonalDirections {
            let dx = Double(direction.dx)
            let dy = Double(direction.dy)
            let vertexX = dx > 0 ? bounds.minX : bounds.maxX
            let vertexY = dy > 0 ? bounds.minY : bounds.maxY

            // Start exactly 5 tile-units from the footprint's own near
            // vertex on *each* axis \u2014 not from `footprintOrigin`, which
            // is the box's own corner *tile* and therefore offset from
            // the box's true corner by half a tile on the "positive"
            // side of a >1-tile-wide footprint. Anchoring on
            // `footprintOrigin` made the per-axis travel distance to the
            // vertex unequal (4.5 vs 3.5 tiles for a 2x2 footprint)
            // whenever `dx` and `dy` had opposite signs, so the diagonal
            // step direction (exactly 45\u00b0) missed the vertex by
            // construction and the resolver could never have gotten
            // closer than that built-in miss no matter how it slid.
            // Anchoring on the vertex itself guarantees the straight
            // line aims exactly at it for all 4 diagonal directions.
            var position = TilePoint(
                x: vertexX - dx * 5,
                y: vertexY - dy * 5
            )
            let step = CGVector(dx: direction.dx * 0.2, dy: direction.dy * 0.2)

            var closestDistanceToVertex = Double.greatestFiniteMagnitude
            for tick in 0..<60 {
                position = CollisionResolver.resolve(currentPosition: position, proposedDelta: step, obstructedBy: [record])
                XCTAssertFalse(
                    bounds.contains(x: position.x, y: position.y),
                    "direction \(direction), tick \(tick): resolved position \(position) entered the footprint"
                )
                closestDistanceToVertex = min(
                    closestDistanceToVertex,
                    hypot(position.x - vertexX, position.y - vertexY)
                )
            }

            XCTAssertLessThan(
                closestDistanceToVertex, 0.25,
                "direction \(direction): the approach never got close to the footprint's near vertex "
                    + "(\(vertexX), \(vertexY))"
            )
        }
    }

    // MARK: - Equal footprint, different drawn height: identical resolution

    /// AC6's movement-resolver counterpart: a tall (`building_05`) and a
    /// short (`building_10`) building sharing an identical footprint must
    /// resolve every one of the 8 approach directions identically, even
    /// though their rendered sprite heights differ enormously
    /// (`BuildingCollisionTests` pins the same parity for the discrete
    /// `BuildingObstruction` query).
    func test_tallAndShortBuildings_sharingTheSameFootprint_resolveIdentically() {
        let tallRecord = makeRecord(buildingIndex: 5, span: 1) // building_05, tall
        let shortRecord = makeRecord(buildingIndex: 10, span: 1) // building_10, lowest

        XCTAssertEqual(BuildingSprite(rawValue: tallRecord.building.index)?.heightClass, .tall)
        XCTAssertEqual(BuildingSprite(rawValue: shortRecord.building.index)?.heightClass, .lowest)

        let worldLayer = SKNode()
        mountSyntheticBuildingNode(for: tallRecord, in: worldLayer)

        for direction in eightDirections {
            let dx = Double(direction.dx)
            let dy = Double(direction.dy)
            var tallPosition = TilePoint(
                x: Double(footprintOrigin.tileX) - dx * 4,
                y: Double(footprintOrigin.tileY) - dy * 4
            )
            var shortPosition = tallPosition
            let step = CGVector(dx: direction.dx * 0.25, dy: direction.dy * 0.25)

            for _ in 0..<60 {
                tallPosition = CollisionResolver.resolve(
                    currentPosition: tallPosition,
                    proposedDelta: step,
                    obstructedBy: [tallRecord]
                )
                shortPosition = CollisionResolver.resolve(
                    currentPosition: shortPosition,
                    proposedDelta: step,
                    obstructedBy: [shortRecord]
                )
            }

            XCTAssertEqual(tallPosition.x, shortPosition.x, accuracy: 1e-9, "direction \(direction)")
            XCTAssertEqual(tallPosition.y, shortPosition.y, accuracy: 1e-9, "direction \(direction)")
        }
    }

    // MARK: - No obstruction: the full delta always applies

    func test_noObstruction_appliesTheFullProposedDelta() {
        let start = TilePoint(x: 3, y: -2)
        let delta = CGVector(dx: 0.4, dy: -0.3)

        let resolved = CollisionResolver.resolve(currentPosition: start, proposedDelta: delta, obstructedBy: [])

        XCTAssertEqual(resolved.x, 3.4, accuracy: 1e-9)
        XCTAssertEqual(resolved.y, -2.3, accuracy: 1e-9)
    }

    // MARK: - A path clear of the footprint is never touched

    func test_movementFarFromTheFootprint_isUnaffected() {
        let record = makeRecord(buildingIndex: 3, span: 1)
        let start = TilePoint(x: 0, y: 0)
        let delta = CGVector(dx: 0.5, dy: 0.5)

        let resolved = CollisionResolver.resolve(currentPosition: start, proposedDelta: delta, obstructedBy: [record])

        XCTAssertEqual(resolved.x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(resolved.y, 0.5, accuracy: 1e-9)
    }
}
