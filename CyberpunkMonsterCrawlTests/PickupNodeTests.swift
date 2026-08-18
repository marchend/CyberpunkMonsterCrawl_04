import CoreGraphics
import SpriteKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-11` PR 1: `PickupNode` -- standalone SpriteKit composition
/// (untinted icon over a tinted pad), size, and depth-sort conformance, with
/// no scene mount.
final class PickupNodeTests: XCTestCase {

    // MARK: - Icon untinted, pad accent-tinted

    func test_icon_carriesNoTint() {
        for kind in PickupKind.allCases {
            let node = PickupNode(kind: kind)
            XCTAssertEqual(node.icon.colorBlendFactor, 0, "\(kind)'s icon must carry zero color blend")
            assertColorsMatch(
                node.icon.color, .clear,
                "\(kind)'s icon must carry no tint color"
            )
        }
    }

    /// Component-wise color comparison, with tolerance.
    ///
    /// `SKSpriteNode.color` round-trips through SpriteKit's own storage, so
    /// a color assigned as `.clear` (`UIExtendedGrayColorSpace 0 0`) can read
    /// back in a different, but numerically equivalent, color space
    /// (`UIExtendedSRGBColorSpace 0 0 0 0`) - both are fully transparent
    /// black, just represented in different models. `XCTAssertEqual` on the
    /// `UIColor`/`SKColor` objects themselves fails on that representation
    /// difference alone, not on any actual color discrepancy, so the
    /// comparison is done on extracted RGBA components instead.
    private func assertColorsMatch(
        _ lhs: SKColor, _ rhs: SKColor, _ message: String = "",
        file: StaticString = #filePath, line: UInt = #line
    ) {
        var lr: CGFloat = 0, lg: CGFloat = 0, lb: CGFloat = 0, la: CGFloat = 0
        var rr: CGFloat = 0, rg: CGFloat = 0, rb: CGFloat = 0, ra: CGFloat = 0
        lhs.getRed(&lr, green: &lg, blue: &lb, alpha: &la)
        rhs.getRed(&rr, green: &rg, blue: &rb, alpha: &ra)

        XCTAssertEqual(lr, rr, accuracy: 1e-6, message, file: file, line: line)
        XCTAssertEqual(lg, rg, accuracy: 1e-6, message, file: file, line: line)
        XCTAssertEqual(lb, rb, accuracy: 1e-6, message, file: file, line: line)
        XCTAssertEqual(la, ra, accuracy: 1e-6, message, file: file, line: line)
    }

    func test_pad_isAccentTinted() {
        for kind in PickupKind.allCases {
            let node = PickupNode(kind: kind)
            XCTAssertNotEqual(node.pad.color, .clear, "\(kind)'s pad must be visibly tinted, not clear")
        }
    }

    func test_medKitAndGarbageCan_useDistinctPadAccentColors() {
        let medKit = PickupNode(kind: .medKit)
        let garbageCan = PickupNode(kind: .garbageCan)
        XCTAssertNotEqual(
            medKit.pad.color, garbageCan.pad.color,
            "the two pickup kinds should read as visually distinct via their pad accent color"
        )
    }

    // MARK: - Icon size

    func test_iconSize_is32x32Points() {
        for kind in PickupKind.allCases {
            let node = PickupNode(kind: kind)
            XCTAssertEqual(node.icon.size, CGSize(width: 32, height: 32))
        }
    }

    // MARK: - Icon slice: the right atlas column per kind

    func test_icon_usesTheMeasuredSheetsColumnForItsKind() {
        for kind in PickupKind.allCases {
            let node = PickupNode(kind: kind)
            XCTAssertTrue(node.icon.texture === PickupNode.texture(forColumn: kind.atlasColumn))
        }
    }

    func test_medKitAndGarbageCan_useDifferentAtlasColumns() {
        XCTAssertNotEqual(PickupKind.medKit.atlasColumn, PickupKind.garbageCan.atlasColumn)
        XCTAssertFalse(
            PickupNode.texture(forColumn: PickupKind.medKit.atlasColumn)
                === PickupNode.texture(forColumn: PickupKind.garbageCan.atlasColumn)
        )
    }

    // MARK: - Pixel crispness

    func test_iconAndPad_areNearestFilteredAndWholeIntegerScaled() {
        let node = PickupNode(kind: .medKit)
        XCTAssertEqual(node.icon.texture?.filteringMode, .nearest)
        XCTAssertEqual(node.icon.texture?.usesMipmaps, false)
        XCTAssertTrue(PixelCrispness.isIntegerScale(node.icon.xScale))
        XCTAssertTrue(PixelCrispness.isIntegerScale(node.icon.yScale))
        XCTAssertTrue(PixelCrispness.isIntegerScale(node.pad.xScale))
        XCTAssertTrue(PixelCrispness.isIntegerScale(node.pad.yScale))
    }

    // MARK: - Depth-sort conformance

    /// The depth-sort key must place a pickup above the ground plane at the
    /// same tile -- the same "actor draws above ground" invariant every
    /// other world-space actor in this repo (`PlayerNode`, `RaccoonNode`)
    /// satisfies via `DepthBanding`.
    func test_updateDepth_placesThePickupAboveTheGroundPlane_atTheSameTile() {
        let node = PickupNode(kind: .medKit)
        let position = TilePoint(x: 14, y: -6)

        node.updateDepth(atTilePosition: position)

        let groundAbsoluteZ = DepthModel.groundZPosition(forTile: TileCoordinate(tileX: 14, tileY: -6))
        let groundRelativeZ = DepthModel.worldLayerRelativeZ(forAbsoluteZ: groundAbsoluteZ)

        XCTAssertGreaterThan(node.zPosition, groundRelativeZ)
    }

    /// The depth-sort key must resolve via `DepthBanding
    /// .nonPlayerActorOffsetRange` exactly the way `RaccoonNode` does, so a
    /// pickup and a synthetic building sharing the same tile draw in the
    /// correct relative order: the building's content offset
    /// (`IsometricDepthSorting`, inside `DepthModel.buildingContentRange`,
    /// strictly `< 3`) must always resolve *behind* the pickup's actor
    /// offset (`DepthModel.actorOffsetRange`, `6.5...9.9`).
    func test_updateDepth_placesThePickupAboveASyntheticBuildingAtTheSameTile() {
        let node = PickupNode(kind: .garbageCan)
        let tile = TileCoordinate(tileX: 3, tileY: 9)
        let position = TilePoint(x: Double(tile.tileX), y: Double(tile.tileY))

        node.updateDepth(atTilePosition: position)

        let buildingAbsoluteZ = IsometricDepthSorting.zPosition(forBuildingFarCornerTile: tile)
        let buildingRelativeZ = DepthModel.worldLayerRelativeZ(forAbsoluteZ: buildingAbsoluteZ)

        XCTAssertGreaterThan(
            node.zPosition, buildingRelativeZ,
            "a pickup must draw above a building occupying the same tile"
        )
    }

    /// Pins the exact value, the same way `PlayerDepthTests
    /// .test_playerNode_updateDepth_setsZPosition_toDepthBandingsWorldLayerRelativeValue`
    /// does for the player -- `accuracy:` because `SKNode.zPosition` is free
    /// to store the assigned `CGFloat` at `Float` (32-bit) precision
    /// internally, unlike the pure-Swift `DepthModel`/`DepthBanding` math it
    /// is compared against.
    func test_updateDepth_setsZPosition_toDepthBandingsWorldLayerRelativeValue() {
        let node = PickupNode(kind: .medKit)
        let position = TilePoint(x: -4, y: 20)

        node.updateDepth(atTilePosition: position)

        let expectedAbsolute = DepthBanding.actorZPosition(forActorAt: position, offset: PickupNode.depthOffset)
        let expectedRelative = DepthModel.worldLayerRelativeZ(forAbsoluteZ: expectedAbsolute)

        XCTAssertEqual(node.zPosition, expectedRelative, accuracy: 0.01)
    }

    func test_depthOffset_isWithinTheNonPlayerActorOffsetRange() {
        XCTAssertTrue(DepthBanding.nonPlayerActorOffsetRange.contains(PickupNode.depthOffset))
    }

    // MARK: - Bobbing animation present

    func test_icon_hasABobbingAction() {
        let node = PickupNode(kind: .medKit)
        XCTAssertNotNil(node.icon.action(forKey: PickupNode.bobActionKey))
    }
}
