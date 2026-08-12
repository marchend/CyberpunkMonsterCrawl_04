import CoreGraphics
import XCTest
@testable import CyberpunkMonsterCrawl

/// CYBERPUN-17-1: pins `AtlasGroundDiamond`'s `5×96 + 112` partition of
/// `tileset_ground` to the shipped pixels.
///
/// `AtlasCellIndexTests.test_groundDiamonds_allSixSubRectsFallWithinTheSheetBounds`
/// only proves the six sub-rects stay inside the sheet — a 6×98.67px
/// partition, 96px cells with padding, or the 112px cell sitting at x:0
/// instead of x:480 would all satisfy that assertion identically. These tests
/// re-derive the layout from the image's alpha channel at test time, so the
/// partition is a measured fact rather than a plausible hypothesis restated
/// in a doc comment. Every ground-tile renderer downstream inherits it.
final class AtlasGroundDiamondTests: XCTestCase {

    private static let sheetImageID = "tileset_ground"

    private func groundPixels() throws -> ImagePixelSampling.Pixels {
        try XCTUnwrap(
            ImagePixelSampling.pixels(ofImageNamed: Self.sheetImageID),
            "\(Self.sheetImageID) could not be decoded from Assets.xcassets — the alpha scan below "
                + "would otherwise measure nothing and pass vacuously."
        )
    }

    /// Reproduces the two measured facts the `AtlasGroundDiamond` doc comment
    /// cites (592×60 overall, content bounding box x:[0,586) / y:[6,54)), and
    /// doubles as the anti-vacuity guard for every other alpha assertion
    /// here: if the scan ever stops seeing real pixels, this goes red instead
    /// of the per-sub-rect checks passing on an empty image.
    func test_tilesetGround_alphaScan_reproducesTheDocumentedContentBoundingBox() throws {
        let pixels = try groundPixels()

        XCTAssertEqual(pixels.width, 592)
        XCTAssertEqual(pixels.height, 60)

        let bounds = try XCTUnwrap(
            pixels.contentBounds(inColumns: 0..<pixels.width),
            "\(Self.sheetImageID) decoded with no opaque pixels at all."
        )

        XCTAssertEqual(
            bounds.x.lowerBound, 0,
            "Content starts at column \(bounds.x.lowerBound); AtlasGroundDiamond's comment records x:[0,586)."
        )
        XCTAssertEqual(
            bounds.x.upperBound, 586,
            "Content ends at column \(bounds.x.upperBound); AtlasGroundDiamond's comment records x:[0,586). "
                + "Fix whichever of the art or the comment is wrong — never loosen this assertion."
        )
        XCTAssertEqual(
            bounds.y.lowerBound, 6,
            "Content starts at row \(bounds.y.lowerBound); the comment records a 6px overhang pad above."
        )
        XCTAssertEqual(
            bounds.y.upperBound, 54,
            "Content ends at row \(bounds.y.upperBound); the comment records y:[6,54)."
        )
        XCTAssertEqual(
            bounds.y.count, 48,
            "The comment records a 48px-tall content band inside the 60px sheet."
        )
    }

    /// The `5×96 + 112` claim, checked against the *measured* sheet width
    /// rather than the declared one: the six sub-rects must tile the sheet
    /// left to right with no gap and no overlap, five of them 96px wide, and
    /// the single 112px one (`overhangLot`) last.
    func test_groundDiamonds_partitionTheMeasuredSheetWidth_withNoGapOrOverlap() {
        let measured = SpriteSheet.measuredPixelSize(forImageNamed: Self.sheetImageID)
        let diamonds = AtlasGroundDiamond.allCases

        XCTAssertEqual(diamonds.count, 6)

        var nextX: CGFloat = 0
        for diamond in diamonds {
            let rect = diamond.pixelRect
            XCTAssertEqual(
                rect.minX, nextX,
                "\(diamond) starts at x:\(rect.minX) but the previous sub-rect ends at x:\(nextX) — "
                    + "the partition has a gap or an overlap."
            )
            XCTAssertEqual(rect.minY, 0, "\(diamond) must keep the full sheet height, starting at y:0.")
            XCTAssertEqual(
                rect.height, measured.height,
                "\(diamond) is \(rect.height)px tall; every sub-rect keeps the full \(measured.height)px "
                    + "sheet height so the overhang lip is not clipped."
            )
            nextX = rect.maxX
        }

        XCTAssertEqual(
            nextX, measured.width,
            "The six sub-rects cover \(nextX)px but \(Self.sheetImageID) measures \(measured.width)px wide."
        )

        let widths = diamonds.map(\.pixelRect.width)
        XCTAssertEqual(widths.filter { $0 == 96 }.count, 5, "Five diamonds must sit in a 96px world-tile cell.")
        XCTAssertEqual(widths.filter { $0 == 112 }.count, 1, "Exactly one diamond is the 112px overhang cell.")
        XCTAssertEqual(
            AtlasGroundDiamond.overhangLot.pixelRect.width, 112,
            "overhangLot is the 112px cell — kerbTransition is a standard 96px cell."
        )
        XCTAssertEqual(
            AtlasGroundDiamond.kerbTransition.pixelRect.minX, 384,
            "kerbTransition is the fifth 96px cell, at x:384."
        )
        XCTAssertEqual(
            AtlasGroundDiamond.overhangLot.pixelRect.minX, 480,
            "overhangLot is the last cell, at x:480."
        )
        XCTAssertEqual(widths.last, 112, "The 112px cell must be the last one on the sheet, not the first.")
    }

    /// The discriminating check: each declared sub-rect must hold its own
    /// diamond, measured from alpha. For every sub-rect the opaque content
    /// must (a) exist, (b) fill most of the sub-rect's width, and (c) sit
    /// centred in it.
    ///
    /// The 8px centring tolerance is deliberately loose enough to survive the
    /// asymmetric overhang lip while still discriminating between the
    /// candidate partitions: an even 6×98.67px split walks the seams off by
    /// up to ~13px by the last cell, and putting the 112px cell first
    /// displaces every later cell by 16px. Both break (c).
    func test_groundDiamonds_everySubRectHoldsItsOwnDiamond_measuredFromPixelAlpha() throws {
        let pixels = try groundPixels()

        for diamond in AtlasGroundDiamond.allCases {
            let rect = diamond.pixelRect
            let columns = Int(rect.minX)..<Int(rect.maxX)

            let bounds = try XCTUnwrap(
                pixels.contentBounds(inColumns: columns),
                "\(diamond)'s sub-rect \(rect) holds no opaque pixels at all — the declared partition "
                    + "does not match where the art actually sits."
            )

            XCTAssertGreaterThanOrEqual(
                CGFloat(bounds.x.count), rect.width * 0.6,
                "\(diamond)'s art spans only \(bounds.x.count)px of its \(rect.width)px sub-rect — the "
                    + "sub-rect is wider than the diamond it claims to crop."
            )

            let contentCentre = CGFloat(bounds.x.lowerBound + bounds.x.upperBound) / 2
            XCTAssertEqual(
                contentCentre, rect.midX, accuracy: 8,
                "\(diamond)'s art is centred at x:\(contentCentre) but its declared sub-rect \(rect) is "
                    + "centred at x:\(rect.midX) — the seams do not fall where AtlasGroundDiamond says."
            )
        }
    }
}
