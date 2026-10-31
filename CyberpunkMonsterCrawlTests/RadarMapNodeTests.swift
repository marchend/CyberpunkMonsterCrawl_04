import CoreGraphics
import SpriteKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-23-t2`: `RadarMapNode` construction, accessibility opacity,
/// marker pooling (no per-frame allocation once a pool's high-water mark is
/// reached), the `SKCropNode` clip, the out-of-window marker-hiding rule
/// and the player marker's fixed centre.
final class RadarMapNodeTests: XCTestCase {

    // MARK: - Helpers

    private func allDescendants(of node: SKNode) -> [SKNode] {
        node.children.flatMap { [$0] + allDescendants(of: $0) }
    }

    private func raccoonMarkerContainer(of node: RadarMapNode) throws -> SKNode {
        try XCTUnwrap(
            node.childNode(withName: "//radarMap.raccoonMarkers"),
            "the raccoon marker pool's container must be mounted somewhere under RadarMapNode"
        )
    }

    private func medKitMarkerContainer(of node: RadarMapNode) throws -> SKNode {
        try XCTUnwrap(
            node.childNode(withName: "//radarMap.medKitMarkers"),
            "the med-kit marker pool's container must be mounted somewhere under RadarMapNode"
        )
    }

    private func playerMarker(of node: RadarMapNode) throws -> SKNode {
        try XCTUnwrap(
            node.childNode(withName: "//radarMap.playerMarker"),
            "the player marker must be mounted somewhere under RadarMapNode"
        )
    }

    private let noBlocked: (Int, Int) -> Bool = { _, _ in false }

    // MARK: - Construction

    func test_construction_setsTheExpectedName() {
        let node = RadarMapNode()
        XCTAssertEqual(node.name, "radarMap")
    }

    func test_construction_conformsToAccessibilityOpaqueNode() {
        let node = RadarMapNode()
        XCTAssertTrue(node is AccessibilityOpaqueNode)
    }

    func test_construction_isNotAnAccessibilityElement_onSelfOrAnyChild() {
        let node = RadarMapNode()
        XCTAssertFalse(node.isAccessibilityElement, "the node itself must not be an accessibility element")

        for descendant in allDescendants(of: node) {
            XCTAssertFalse(
                descendant.isAccessibilityElement,
                "\(descendant.name ?? "<unnamed>") must not be an accessibility element"
            )
        }
    }

    func test_construction_mountsASKCropNode_forClipping() {
        let node = RadarMapNode()
        XCTAssertTrue(
            node.children.contains { $0 is SKCropNode },
            "RadarMapNode must clip its content with a SKCropNode"
        )
    }

    // MARK: - Player marker: always exactly centred

    func test_playerMarker_isAlwaysExactlyCentred_regardlessOfUpdates() throws {
        let node = RadarMapNode()
        node.radarScale = 2.5

        node.update(
            playerTile: TileCoordinate(tileX: 0, tileY: 0),
            raccoonTiles: [],
            medKitTiles: [],
            isTileBlocked: noBlocked,
            deviceScale: 2
        )
        var marker = try playerMarker(of: node)
        XCTAssertEqual(marker.position, .zero)

        // A later update, with the player having moved to a wildly
        // different tile, must still leave the marker centred -- the radar
        // itself re-centres on the player, the marker never moves.
        node.update(
            playerTile: TileCoordinate(tileX: 500, tileY: -300),
            raccoonTiles: [],
            medKitTiles: [],
            isTileBlocked: noBlocked,
            deviceScale: 2
        )
        marker = try playerMarker(of: node)
        XCTAssertEqual(marker.position, .zero)
    }

    // MARK: - Out-of-window raccoons/med kits are not drawn

    func test_outOfWindowRaccoon_isHidden_whileAnInWindowOneIsShown() throws {
        let node = RadarMapNode()
        node.radarScale = 1

        node.update(
            playerTile: TileCoordinate(tileX: 0, tileY: 0),
            raccoonTiles: [
                TileCoordinate(tileX: 5, tileY: 5), // well inside the 110x110 window
                TileCoordinate(tileX: 1_000, tileY: 0), // far outside it
            ],
            medKitTiles: [],
            isTileBlocked: noBlocked,
            deviceScale: 1
        )

        let container = try raccoonMarkerContainer(of: node)
        let markers = container.children.compactMap { $0 as? SKSpriteNode }
        XCTAssertEqual(markers.count, 2)
        XCTAssertFalse(markers[0].isHidden, "the in-window raccoon must be drawn")
        XCTAssertTrue(markers[1].isHidden, "the out-of-window raccoon must not be drawn")
    }

    func test_outOfWindowMedKit_isHidden() throws {
        let node = RadarMapNode()
        node.radarScale = 1

        node.update(
            playerTile: TileCoordinate(tileX: 0, tileY: 0),
            raccoonTiles: [],
            medKitTiles: [TileCoordinate(tileX: 0, tileY: -1_000)],
            isTileBlocked: noBlocked,
            deviceScale: 1
        )

        let container = try medKitMarkerContainer(of: node)
        let markers = container.children.compactMap { $0 as? SKSpriteNode }
        XCTAssertEqual(markers.count, 1)
        XCTAssertTrue(markers[0].isHidden, "the out-of-window med kit must not be drawn")
    }

    // MARK: - Pooling: repeated updates never grow past the high-water mark

    func test_repeatedUpdates_neverGrowTheRaccoonPool_pastItsHighWaterMark() throws {
        let node = RadarMapNode()
        node.radarScale = 1

        func raccoonTiles(_ count: Int) -> [TileCoordinate] {
            (0..<count).map { TileCoordinate(tileX: $0, tileY: 0) }
        }

        node.update(
            playerTile: .init(tileX: 0, tileY: 0), raccoonTiles: raccoonTiles(2), medKitTiles: [],
            isTileBlocked: noBlocked, deviceScale: 1
        )
        let container = try raccoonMarkerContainer(of: node)
        XCTAssertEqual(container.children.count, 2)

        node.update(
            playerTile: .init(tileX: 0, tileY: 0), raccoonTiles: raccoonTiles(7), medKitTiles: [],
            isTileBlocked: noBlocked, deviceScale: 1
        )
        XCTAssertEqual(container.children.count, 7, "the pool must grow to the new, higher count")

        node.update(
            playerTile: .init(tileX: 0, tileY: 0), raccoonTiles: raccoonTiles(1), medKitTiles: [],
            isTileBlocked: noBlocked, deviceScale: 1
        )
        XCTAssertEqual(
            container.children.count, 7,
            "a lower count must hide the surplus, not remove nodes -- no per-frame allocation on growth/shrink"
        )
        let visibleAfterShrink = container.children.compactMap { $0 as? SKSpriteNode }.filter { !$0.isHidden }
        XCTAssertEqual(visibleAfterShrink.count, 1)

        node.update(
            playerTile: .init(tileX: 0, tileY: 0), raccoonTiles: raccoonTiles(7), medKitTiles: [],
            isTileBlocked: noBlocked, deviceScale: 1
        )
        XCTAssertEqual(
            container.children.count, 7,
            "returning to the prior high-water mark must reuse the existing pooled nodes, not grow further"
        )
    }

    func test_repeatedUpdates_neverGrowTheMedKitPool_pastItsHighWaterMark() throws {
        let node = RadarMapNode()
        node.radarScale = 1

        func medKitTiles(_ count: Int) -> [TileCoordinate] {
            (0..<count).map { TileCoordinate(tileX: 0, tileY: $0) }
        }

        node.update(
            playerTile: .init(tileX: 0, tileY: 0), raccoonTiles: [], medKitTiles: medKitTiles(3),
            isTileBlocked: noBlocked, deviceScale: 1
        )
        let container = try medKitMarkerContainer(of: node)
        XCTAssertEqual(container.children.count, 3)

        node.update(
            playerTile: .init(tileX: 0, tileY: 0), raccoonTiles: [], medKitTiles: medKitTiles(0),
            isTileBlocked: noBlocked, deviceScale: 1
        )
        XCTAssertEqual(container.children.count, 3, "dropping to zero must hide, not remove, pooled nodes")
        XCTAssertTrue(container.children.allSatisfy { ($0 as? SKSpriteNode)?.isHidden ?? false })

        node.update(
            playerTile: .init(tileX: 0, tileY: 0), raccoonTiles: [], medKitTiles: medKitTiles(3),
            isTileBlocked: noBlocked, deviceScale: 1
        )
        XCTAssertEqual(container.children.count, 3, "must not exceed the already-reached high-water mark")
    }

    // MARK: - Backdrop rebuild cadence: only on a player-tile change

    func test_backdrop_isOnlyRebuilt_whenThePlayerTileChanges() {
        let node = RadarMapNode()
        node.radarScale = 1
        var callCount = 0
        let countingPredicate: (Int, Int) -> Bool = { _, _ in
            callCount += 1
            return false
        }

        node.update(
            playerTile: TileCoordinate(tileX: 0, tileY: 0), raccoonTiles: [], medKitTiles: [],
            isTileBlocked: countingPredicate, deviceScale: 1
        )
        XCTAssertGreaterThan(callCount, 0, "the first update must build the backdrop")

        let countAfterFirstBuild = callCount
        node.update(
            playerTile: TileCoordinate(tileX: 0, tileY: 0), raccoonTiles: [], medKitTiles: [],
            isTileBlocked: countingPredicate, deviceScale: 1
        )
        XCTAssertEqual(
            callCount, countAfterFirstBuild,
            "the same player tile must not trigger another backdrop rebuild"
        )

        node.update(
            playerTile: TileCoordinate(tileX: 1, tileY: 0), raccoonTiles: [], medKitTiles: [],
            isTileBlocked: countingPredicate, deviceScale: 1
        )
        XCTAssertGreaterThan(callCount, countAfterFirstBuild, "a changed player tile must rebuild the backdrop")
    }

    /// The other half of `RadarBackdropRenderer`'s stated cadence -- "a
    /// rebuild when the player's tile changes **or when the resident chunk
    /// window does**". A predicate that has changed its answers while the
    /// player stood still (the spawn case: `HUDLayer.bind(to:)` builds the
    /// first backdrop before a single chunk has streamed in) must not be
    /// served from the cache (PR #79 review).
    func test_backdrop_isRebuilt_whenTheResidencyRevisionChanges_onAStationaryPlayer() {
        let node = RadarMapNode()
        node.radarScale = 1
        var callCount = 0
        var blockedAnswer = false
        let countingPredicate: (Int, Int) -> Bool = { _, _ in
            callCount += 1
            return blockedAnswer
        }
        let tile = TileCoordinate(tileX: 0, tileY: 0)

        node.update(
            playerTile: tile, raccoonTiles: [], medKitTiles: [],
            isTileBlocked: countingPredicate, deviceScale: 1, residencyRevision: 0
        )
        let countAfterFirstBuild = callCount
        XCTAssertGreaterThan(countAfterFirstBuild, 0, "precondition: the first update builds the backdrop")

        // Same tile, same revision -- still cached.
        node.update(
            playerTile: tile, raccoonTiles: [], medKitTiles: [],
            isTileBlocked: countingPredicate, deviceScale: 1, residencyRevision: 0
        )
        XCTAssertEqual(callCount, countAfterFirstBuild, "an unchanged input set must not rebuild")

        // The resident chunk window moved under a stationary player, and
        // the predicate now answers differently.
        blockedAnswer = true
        node.update(
            playerTile: tile, raccoonTiles: [], medKitTiles: [],
            isTileBlocked: countingPredicate, deviceScale: 1, residencyRevision: 1
        )
        XCTAssertGreaterThan(
            callCount, countAfterFirstBuild,
            "a resident-window change must rebuild the backdrop even on an unchanged player tile"
        )
    }

    /// The remaining two raster inputs. `deviceScale` changes when the node
    /// is first mounted into a real view (headless `1` -> the device's own
    /// `@2x`/`@3x`) and `radarScale` on every rotation, and either leaves
    /// the cached texture the wrong *size* for what is being drawn, not
    /// merely stale.
    func test_backdrop_isRebuilt_whenTheDeviceScaleOrRadarScaleChanges() {
        let node = RadarMapNode()
        node.radarScale = 1
        var callCount = 0
        let countingPredicate: (Int, Int) -> Bool = { _, _ in
            callCount += 1
            return false
        }
        let tile = TileCoordinate(tileX: 0, tileY: 0)

        node.update(
            playerTile: tile, raccoonTiles: [], medKitTiles: [],
            isTileBlocked: countingPredicate, deviceScale: 1
        )
        let afterFirstBuild = callCount

        node.update(
            playerTile: tile, raccoonTiles: [], medKitTiles: [],
            isTileBlocked: countingPredicate, deviceScale: 3
        )
        let afterDeviceScaleChange = callCount
        XCTAssertGreaterThan(
            afterDeviceScaleChange, afterFirstBuild,
            "a changed device scale rasterizes a different-sized bitmap and must rebuild"
        )

        // `HUDLayer.applyLayout(...)` writes this on every rotation.
        node.radarScale = 2.5
        node.update(
            playerTile: tile, raccoonTiles: [], medKitTiles: [],
            isTileBlocked: countingPredicate, deviceScale: 3
        )
        XCTAssertGreaterThan(
            callCount, afterDeviceScaleChange,
            "a changed radar scale changes the dial's field of view and must rebuild"
        )
    }
}
