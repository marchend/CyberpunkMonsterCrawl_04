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

    /// Pixel-crispness of the icon and pad, restated so it measures what it
    /// claims.
    ///
    /// This replaces `PixelCrispness.isIntegerScale(icon.xScale)`
    /// assertions that were trivially true: all of the icon's magnification
    /// lives in `SKSpriteNode.size` (`PickupNode.iconSize`), so
    /// `xScale`/`yScale` are always exactly 1 and the assertion read as
    /// coverage of a draw scale it never saw -- the same vacuity
    /// `RaccoonNodeTests.test_body_isPixelCrisp_andCarriesNoMagnificationInItsScale`
    /// was written to replace. The invariant actually worth pinning is that
    /// no magnification ever reaches the scale properties (which is what
    /// stops `PixelCrispness.apply(to:)` rounding it), with the effective
    /// magnification pinned separately below.
    func test_iconAndPad_arePixelCrisp_andCarryNoMagnificationInTheirScale() {
        for kind in PickupKind.allCases {
            let node = PickupNode(kind: kind)

            XCTAssertEqual(node.icon.texture?.filteringMode, .nearest)
            XCTAssertEqual(node.icon.texture?.usesMipmaps, false)

            XCTAssertEqual(
                abs(node.icon.xScale), 1, accuracy: 1e-6,
                "\(kind): the icon's xScale must never carry magnification."
            )
            XCTAssertEqual(
                abs(node.icon.yScale), 1, accuracy: 1e-6,
                "\(kind): the icon's yScale must never carry magnification."
            )
            XCTAssertEqual(abs(node.pad.xScale), 1, accuracy: 1e-6, "\(kind): the pad's xScale must be unscaled.")
            XCTAssertEqual(abs(node.pad.yScale), 1, accuracy: 1e-6, "\(kind): the pad's yScale must be unscaled.")
        }
    }

    /// The story's 32pt icon stated as the *effective* magnification (the
    /// measured source cell to the drawn size) rather than as an `xScale`
    /// that never carries it.
    ///
    /// The icon is deliberately **outside** `PixelCrispness`'s
    /// integer-scale rule: 32/24 is 1.333x, so the compositor resamples the
    /// source pixels unevenly. That trade is the story's, documented on
    /// `PickupNode.iconSize`, and pinned here so nobody reads the crispness
    /// test above as a promise the magnification is integral.
    func test_icon_effectiveMagnification_isTheStorys32ptIconOverTheMeasured24pxCell() throws {
        let cellSize = try XCTUnwrap(
            AtlasSheet.pickups.sheet.cellSize,
            "sprite_pickups must declare a uniform cell size for this magnification to be meaningful"
        )
        let node = PickupNode(kind: .medKit)

        let horizontal = node.icon.size.width / cellSize.width
        let vertical = node.icon.size.height / cellSize.height

        XCTAssertEqual(
            horizontal, 32.0 / 24.0, accuracy: 1e-6,
            "The icon's drawn width (\(node.icon.size.width)) is not the story's 32pt over the measured "
                + "\(cellSize.width)px cell."
        )
        XCTAssertEqual(
            vertical, 32.0 / 24.0, accuracy: 1e-6,
            "The icon's drawn height (\(node.icon.size.height)) is not the story's 32pt over the measured "
                + "\(cellSize.height)px cell."
        )

        XCTAssertFalse(
            PixelCrispness.isIntegerScale(horizontal),
            "The icon's \(horizontal)x magnification is non-integer by design (docs on PickupNode.iconSize). "
                + "If it has become integral, the opt-out documented there is stale and should be removed "
                + "rather than this assertion."
        )
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
