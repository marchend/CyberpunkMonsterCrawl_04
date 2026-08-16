import CoreGraphics
import XCTest
@testable import CyberpunkMonsterCrawl

/// The measured basis for `TileFieldRenderer`'s bottom-centre anchor
/// (CYBERPUN-17-5-t2 AC5).
///
/// `TileFieldRenderer.configure` places every building at
/// `anchorPoint = (0.5, 0)` on its lot tile's screen point, and its doc
/// comment used to justify that with a claim about how the shipped art *was
/// authored*. Nothing measured it \u2014 and three buildings
/// (`building_08`/`building_09` at 144px, `building_11` at 192px) are wider
/// than the 96px tile diamond they stand on, so a half-tile offset on those
/// three would have shipped green behind two 1x1-footprint position tests.
///
/// This file gives the anchor the same treatment `AtlasGroundDiamondTests`
/// gives `AtlasGroundDiamond`'s `5x96 + 112` partition: re-derive the fact
/// from the image's alpha channel at test time, for all 12 buildings, so the
/// anchor rests on a measurement rather than on a belief about the art.
///
/// Three facts, one per test below:
/// 1. the opaque content is horizontally centred inside its own PNG \u2014 what
///    makes `anchorPoint.x = 0.5` put the building's base on the tile's
///    screen x;
/// 2. the content runs to the PNG's bottom edge, with no transparent padding
///    below it \u2014 what makes `anchorPoint.y = 0` put the art's ground-contact
///    row on the node's position instead of somewhere above it;
/// 3. a `.twoByTwo` building's art measures wider than one 96px tile while a
///    `.oneByOne` building's does not \u2014 the "extends outward for a 2x2
///    footprint" claim stated as a measurement.
///
/// *Which* tile of a multi-tile footprint the sprite anchors to is a separate
/// decision and is pinned in code, not in the art:
/// `BuildingDepthAndAnchorTests.test_makeBuildingNode_twoByTwoFootprint_anchorsAtTheBaseTile_notTheFootprintCentre`.
final class BuildingSpriteBaseAlignmentTests: XCTestCase {

    /// One world tile diamond is 96px wide (`docs/bootstrap.md` \u00a74: 96x48
    /// isometric tiles), re-derived from `IsometricProjection` rather than
    /// re-typed, so a change to the tile size cannot leave this file
    /// asserting against a stale constant.
    private static let tilePixelWidth = 2 * IsometricProjection.tileHalfWidth

    /// Decoded pixels plus the opaque content's bounding box, or an explicit
    /// failure \u2014 never a quiet skip, which would let every assertion below
    /// pass vacuously on an image that failed to decode.
    private func measuredContent(
        of building: BuildingSprite,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> (pixels: ImagePixelSampling.Pixels, bounds: (x: Range<Int>, y: Range<Int>)) {
        let pixels = try XCTUnwrap(
            ImagePixelSampling.pixels(ofImageNamed: building.imageID),
            "\(building.imageID) could not be decoded from Assets.xcassets.",
            file: file,
            line: line
        )
        let bounds = try XCTUnwrap(
            pixels.contentBounds(inColumns: 0..<pixels.width),
            "\(building.imageID) decoded with no opaque pixels at all.",
            file: file,
            line: line
        )
        return (pixels, bounds)
    }

    /// Anti-vacuity guard for the three measurements below: every building
    /// decodes at exactly its declared size, and holds real opaque content
    /// inside that rectangle.
    func test_everyBuildingSprite_decodesAtItsDeclaredSize_withOpaqueContent() throws {
        for building in BuildingSprite.allCases {
            let measured = try measuredContent(of: building)

            XCTAssertEqual(
                CGSize(width: measured.pixels.width, height: measured.pixels.height),
                building.declaredPixelSize,
                "\(building.imageID) decoded \(measured.pixels.width)x\(measured.pixels.height) but the "
                    + "table declares \(building.declaredPixelSize)."
            )
            XCTAssertGreaterThan(measured.bounds.x.count, 0)
            XCTAssertGreaterThan(measured.bounds.y.count, 0)
        }
    }

    /// **Fact 1 \u2014 `anchorPoint.x = 0.5`.** The opaque content sits centred in
    /// its own PNG, so anchoring at the sprite's horizontal midpoint puts the
    /// building's base over the tile's screen x.
    ///
    /// The 8px tolerance is the same order `AtlasGroundDiamondTests` uses for
    /// the ground diamonds: loose enough to survive an asymmetric neon lip or
    /// a one-sided fire escape, far tighter than the misalignment that
    /// matters (half a tile is 48px), and it does not grow with the sprite \u2014
    /// `building_11`'s 192px art is held to the same 8px as a 96px building.
    func test_everyBuildingSprite_opaqueContentIsHorizontallyCentredInItsOwnPNG() throws {
        for building in BuildingSprite.allCases {
            let measured = try measuredContent(of: building)
            let contentCentre = CGFloat(measured.bounds.x.lowerBound + measured.bounds.x.upperBound) / 2
            let spriteCentre = CGFloat(measured.pixels.width) / 2

            XCTAssertEqual(
                contentCentre, spriteCentre, accuracy: 8,
                "\(building.imageID)'s opaque content spans columns \(measured.bounds.x) of a "
                    + "\(measured.pixels.width)px image — centred at x:\(contentCentre), not x:\(spriteCentre). "
                    + "TileFieldRenderer anchors these at (0.5, 0), so off-centre art draws off its own lot."
            )
        }
    }

    /// **Fact 2 \u2014 `anchorPoint.y = 0`.** The art's ground-contact row is the
    /// bottom row of the PNG: transparent padding below the silhouette would
    /// lift every building off its lot by exactly that many pixels, uniformly
    /// and invisibly (nothing else in the pipeline would flag it).
    ///
    /// Stated as "at most 2 rows" rather than exactly zero so a single-row
    /// authoring artifact does not fail the suite; 2px against the tile
    /// diamond's 24px half-height is under a tenth of a tile, while the
    /// failure this is aimed at \u2014 a sprite authored with its base somewhere in
    /// the middle of its own rect \u2014 is tens of pixels.
    func test_everyBuildingSprite_contentRunsToTheBottomEdge_withNoTransparentPaddingBelow() throws {
        for building in BuildingSprite.allCases {
            let measured = try measuredContent(of: building)
            // `Pixels` is top-left-origin and row-major top row first, so the
            // *bottom* edge of the image is `height` and the content's lowest
            // occupied row is `bounds.y.upperBound`.
            let transparentRowsBelowContent = measured.pixels.height - measured.bounds.y.upperBound

            XCTAssertLessThanOrEqual(
                transparentRowsBelowContent, 2,
                "\(building.imageID) has \(transparentRowsBelowContent) fully transparent rows under its "
                    + "silhouette. TileFieldRenderer anchors at (0.5, 0), i.e. the sprite rect's bottom edge, "
                    + "so that padding would hold the building that far above the tile it stands on."
            )
            XCTAssertGreaterThanOrEqual(
                transparentRowsBelowContent, 0,
                "\(building.imageID)'s content bounds fall outside its own image."
            )
        }
    }

    /// **Fact 3 \u2014 "extends outward for a 2x2 footprint", measured.** The three
    /// 2x2 buildings' art really is wider than one 96px tile, and every 1x1
    /// building's art really does fit inside one \u2014 so the footprint column
    /// `BuildingCatalog`/`BuildingSprite` declare is what the pixels say, and
    /// the outward spread of a 2x2 sprite around its bottom-centre anchor is
    /// a measured span rather than an assumption about authoring.
    func test_twoByTwoBuildingsArtIsWiderThanOneTile_andOneByOneArtIsNot() throws {
        var twoByTwoCount = 0
        var oneByOneCount = 0

        for building in BuildingSprite.allCases {
            let measured = try measuredContent(of: building)
            let contentWidth = CGFloat(measured.bounds.x.count)
            let imageWidth = CGFloat(measured.pixels.width)

            switch building.footprint {
            case .twoByTwo:
                twoByTwoCount += 1
                XCTAssertGreaterThan(
                    imageWidth, Self.tilePixelWidth,
                    "\(building.imageID) declares a 2x2 footprint but its image is only \(imageWidth)px wide — "
                        + "one lot is \(Self.tilePixelWidth)px."
                )
                XCTAssertGreaterThan(
                    contentWidth, Self.tilePixelWidth,
                    "\(building.imageID) declares a 2x2 footprint but its opaque art spans only "
                        + "\(contentWidth)px — it does not actually cover more than one \(Self.tilePixelWidth)px "
                        + "lot, so anchoring it bottom-centre on the base tile is not a 2x2 building."
                )
            case .oneByOne:
                oneByOneCount += 1
                XCTAssertLessThanOrEqual(
                    imageWidth, Self.tilePixelWidth,
                    "\(building.imageID) declares a 1x1 footprint but its image is \(imageWidth)px wide, wider "
                        + "than the \(Self.tilePixelWidth)px lot it reserves."
                )
                XCTAssertLessThanOrEqual(
                    contentWidth, Self.tilePixelWidth,
                    "\(building.imageID) declares a 1x1 footprint but its opaque art spans \(contentWidth)px, "
                        + "wider than the \(Self.tilePixelWidth)px lot it reserves."
                )
            }
        }

        XCTAssertEqual(twoByTwoCount, 3, "building_08, building_09 and building_11 are the three 2x2 buildings.")
        XCTAssertEqual(oneByOneCount, 9, "The other nine buildings are 1x1.")
    }
}
