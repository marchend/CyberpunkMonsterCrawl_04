import CoreGraphics
import XCTest
@testable import CyberpunkMonsterCrawl

/// CYBERPUN-17-4-t2: pins the **meaning** of `GroundTileCatalog`'s six
/// assignments against the shipped pixels, not against a second copy of the
/// same table.
///
/// `GroundTileCatalogTests` compares `GroundTileCatalog.diamond(for:)` to a
/// literal table written out by hand, so it guards typos and drift on the
/// *arithmetic* axis only: swapping `.asphaltEastWest` and
/// `.asphaltNorthSouth` in both places leaves it green while every corridor
/// in the city renders with its lane markings running across the direction of
/// travel. `AtlasGroundDiamondTests` does not help either — it measures
/// geometry (the `5x96 + 112` partition, each sub-rect's content non-empty
/// and centred), and geometry cannot say which crop *depicts* an east-west
/// lane.
///
/// So these tests re-measure the art at test time, in the spirit
/// `AtlasGroundDiamondTests` already sets:
///  1. every kind crops art no other kind also crops (fingerprint over the
///     decoded RGBA of the crop itself);
///  2. each lane crop's painted marking is elongated along the tile axis its
///     case name claims, measured in the diamond's own axis frame, which is
///     derived from `IsometricProjection`'s constants rather than eyeballed.
///
/// **If (2) fails, do not loosen it.** Either the two lane assignments in
/// `GroundTileCatalog` are swapped relative to the art (fix the catalog), or
/// the crops at x:0 / x:96 are not a directional lane pair at all (fix the
/// art). Both are real, on-screen bugs — the failure message reports the
/// measured numbers so the reader can tell which.
final class GroundTileSemanticsTests: XCTestCase {

    private static let sheetImageID = "tileset_ground"

    private func groundPixels() throws -> ImagePixelSampling.Pixels {
        try XCTUnwrap(
            ImagePixelSampling.pixels(ofImageNamed: Self.sheetImageID),
            "\(Self.sheetImageID) could not be decoded from Assets.xcassets — every measurement below "
                + "would otherwise pass vacuously on an empty image."
        )
    }

    // MARK: - Distinct art per kind

    /// No two `GroundTileKind`s may crop the same art. Rect distinctness
    /// (`GroundTileCatalogTests.test_allSixRects_areDistinct`) cannot catch a
    /// sheet that ships the same diamond twice; this compares the decoded
    /// pixels behind each rect.
    func test_everyGroundTileKind_cropsArtNoOtherKindCrops_measuredFromPixels() throws {
        let pixels = try groundPixels()

        var fingerprints: [GroundTileKind: UInt64] = [:]
        for kind in GroundTileKind.allCases {
            let crop = Crop(kind: kind, pixels: pixels)
            XCTAssertGreaterThan(
                crop.paintedPixels.count, 0,
                "\(kind)'s crop \(crop.rect) decoded with no opaque pixels — the semantic measurements "
                    + "below would be vacuous."
            )
            fingerprints[kind] = crop.fingerprint
        }

        let kinds = GroundTileKind.allCases
        for (index, kind) in kinds.enumerated() {
            for other in kinds.dropFirst(index + 1) {
                XCTAssertNotEqual(
                    fingerprints[kind], fingerprints[other],
                    "\(kind) and \(other) crop pixel-identical art, so one of the two semantic "
                        + "assignments in GroundTileCatalog is pointing at the wrong diamond."
                )
            }
        }
    }

    // MARK: - The lane pair's orientation

    /// The discriminating semantic check: `.asphaltEastWest`'s crop must
    /// carry paint stretched along the **tile-X** axis and
    /// `.asphaltNorthSouth`'s along the **tile-Y** axis, which is what their
    /// case names (and `GroundTileRenderer.asphaltOrientation(at:)`, which
    /// picks between them from the corridor's lattice band) claim.
    ///
    /// A corridor running along tile X projects to one screen diagonal and a
    /// corridor along tile Y to the *other* (`IsometricProjection
    /// .tileToScreen`), so the two readings are opposite and a swapped pair
    /// cannot satisfy both assertions.
    func test_eachLaneCrop_carriesPaintElongatedAlongTheAxisItsCaseNameClaims() throws {
        let pixels = try groundPixels()

        let eastWest = Crop(kind: .asphaltEastWest, pixels: pixels).paintSpread()
        let northSouth = Crop(kind: .asphaltNorthSouth, pixels: pixels).paintSpread()

        XCTAssertGreaterThan(
            eastWest.totalWeight, 0,
            "asphaltEastWest's crop has no pixel brighter than its own median — no painted marking to "
                + "measure, so its orientation cannot be pinned to the art at all."
        )
        XCTAssertGreaterThan(
            northSouth.totalWeight, 0,
            "asphaltNorthSouth's crop has no pixel brighter than its own median — no painted marking to "
                + "measure, so its orientation cannot be pinned to the art at all."
        )

        XCTAssertGreaterThan(
            eastWest.elongationRatio, 1,
            "asphaltEastWest maps to \(GroundTileCatalog.diamond(for: .asphaltEastWest)), whose paint "
                + "measures more spread along tile Y than tile X "
                + "(spread along X \(eastWest.alongTileX), along Y \(eastWest.alongTileY)). An east-west "
                + "corridor runs along tile X, so this crop reads as the north-south lane: the two lane "
                + "assignments in GroundTileCatalog look swapped."
        )
        XCTAssertLessThan(
            northSouth.elongationRatio, 1,
            "asphaltNorthSouth maps to \(GroundTileCatalog.diamond(for: .asphaltNorthSouth)), whose paint "
                + "measures more spread along tile X than tile Y "
                + "(spread along X \(northSouth.alongTileX), along Y \(northSouth.alongTileY)). A "
                + "north-south corridor runs along tile Y, so this crop reads as the east-west lane: the "
                + "two lane assignments in GroundTileCatalog look swapped."
        )
        XCTAssertGreaterThan(
            eastWest.elongationRatio, northSouth.elongationRatio,
            "The two lane crops measure the same dominant paint axis, so they are not the two corridor "
                + "orientations the catalog treats them as."
        )
    }

    /// Pins the axis frame the measurement above is expressed in, straight
    /// off `IsometricProjection`'s constants: one tile step along +X projects
    /// up-and-right on screen, one along +Y up-and-left, and image rows count
    /// *down* while screen y counts up. So in the decoded sheet's top-left
    /// origin space, tile +X is `(+tileHalfWidth, -tileHalfHeight)` and tile
    /// +Y is `(-tileHalfWidth, -tileHalfHeight)` — the two opposite diagonals
    /// `paintSpread()` projects onto.
    func test_tileAxisFrame_isDerivedFromTheProjectionsOwnDiagonals() {
        let oneStepAlongX = IsometricProjection.tileToScreen(tileX: 1, tileY: 0)
        XCTAssertEqual(Double(oneStepAlongX.x), IsometricProjection.tileHalfWidth, accuracy: 1e-9)
        XCTAssertEqual(Double(oneStepAlongX.y), IsometricProjection.tileHalfHeight, accuracy: 1e-9)

        let oneStepAlongY = IsometricProjection.tileToScreen(tileX: 0, tileY: 1)
        XCTAssertEqual(Double(oneStepAlongY.x), -IsometricProjection.tileHalfWidth, accuracy: 1e-9)
        XCTAssertEqual(Double(oneStepAlongY.y), IsometricProjection.tileHalfHeight, accuracy: 1e-9)

        // A pixel offset one whole tile step along +X (image space: right and
        // up) must move only the "along tile X" coordinate, and vice versa.
        let alongX = Crop.axisCoordinates(
            imageOffsetX: IsometricProjection.tileHalfWidth,
            imageOffsetY: -IsometricProjection.tileHalfHeight
        )
        XCTAssertEqual(alongX.alongTileX, 2, accuracy: 1e-9)
        XCTAssertEqual(alongX.alongTileY, 0, accuracy: 1e-9)

        let alongY = Crop.axisCoordinates(
            imageOffsetX: -IsometricProjection.tileHalfWidth,
            imageOffsetY: -IsometricProjection.tileHalfHeight
        )
        XCTAssertEqual(alongY.alongTileX, 0, accuracy: 1e-9)
        XCTAssertEqual(alongY.alongTileY, 2, accuracy: 1e-9)
    }

    // MARK: - TEMPORARY diagnostic (removed before the PR opens)

    func test_TEMPORARY_dumpLanePairMeasurements() throws {
        XCTFail(try temporaryDump(of: [.asphaltEastWest, .asphaltNorthSouth]))
    }

    func test_TEMPORARY_dumpOtherCropMeasurements() throws {
        XCTFail(try temporaryDump(of: [.junctionStopLine, .kerbSidewalk, .lot, .buildingFootprint]))
    }

    private func temporaryDump(of kinds: [GroundTileKind]) throws -> String {
        let pixels = try groundPixels()
        var report = "\nTEMP DUMP\n"

        for kind in kinds {
            let crop = Crop(kind: kind, pixels: pixels)
            let painted = crop.paintedPixels
            guard !painted.isEmpty else {
                report += "\(kind) \(crop.rect): NO OPAQUE PIXELS\n"
                continue
            }
            let lums = painted.map(\.luminance).sorted()
            let centreX = Double(painted.map(\.x).min()! + painted.map(\.x).max()!) / 2
            let centreY = Double(painted.map(\.y).min()! + painted.map(\.y).max()!) / 2
            report += "\(kind) rect=\(crop.rect) opaque=\(painted.count)"
                + " lum[min=\(lums.first!) med=\(lums[lums.count / 2]) max=\(lums.last!)]\n"

            for quantile in [0.5, 0.9, 0.98] {
                let index = Swift.min(lums.count - 1, Int(Double(lums.count - 1) * quantile))
                let threshold = lums[index]
                var totalWeight = 0.0
                var samples: [(u: Double, v: Double, weight: Double, x: Int, y: Int)] = []
                for pixel in painted {
                    let weight = Swift.max(0, pixel.luminance - threshold)
                    guard weight > 0 else { continue }
                    let axis = Crop.axisCoordinates(
                        imageOffsetX: Double(pixel.x) - centreX,
                        imageOffsetY: Double(pixel.y) - centreY
                    )
                    samples.append((u: axis.alongTileX, v: axis.alongTileY, weight: weight, x: pixel.x, y: pixel.y))
                    totalWeight += weight
                }
                guard totalWeight > 0 else {
                    report += "  q=\(quantile) thr=\(threshold): no paint above threshold\n"
                    continue
                }
                let meanU = samples.reduce(0) { $0 + $1.u * $1.weight } / totalWeight
                let meanV = samples.reduce(0) { $0 + $1.v * $1.weight } / totalWeight
                let varU = samples.reduce(0) { $0 + $1.weight * ($1.u - meanU) * ($1.u - meanU) } / totalWeight
                let varV = samples.reduce(0) { $0 + $1.weight * ($1.v - meanV) * ($1.v - meanV) } / totalWeight
                let boxX = "\(samples.map(\.x).min()!)...\(samples.map(\.x).max()!)"
                let boxY = "\(samples.map(\.y).min()!)...\(samples.map(\.y).max()!)"
                report += "  q=\(quantile) thr=\(threshold) n=\(samples.count)"
                    + " u=\(varU) v=\(varV) ratio=\(varU / varV) box x:\(boxX) y:\(boxY)\n"
            }

            // Same measurement keyed on chroma (max-min channel) instead of
            // luminance, in case the lane markings are a saturated accent
            // rather than the brightest thing on the crop.
            var chromas: [(x: Int, y: Int, chroma: Double)] = []
            for pixel in painted {
                let base = (pixel.y * pixels.width + pixel.x) * 4
                let red = Double(pixels.rgba[base])
                let green = Double(pixels.rgba[base + 1])
                let blue = Double(pixels.rgba[base + 2])
                chromas.append((x: pixel.x, y: pixel.y, chroma: Swift.max(red, green, blue) - Swift.min(red, green, blue)))
            }
            let sortedChroma = chromas.map(\.chroma).sorted()
            for quantile in [0.9] {
                let index = Swift.min(sortedChroma.count - 1, Int(Double(sortedChroma.count - 1) * quantile))
                let threshold = sortedChroma[index]
                var totalWeight = 0.0
                var samples: [(u: Double, v: Double, weight: Double)] = []
                for pixel in chromas {
                    let weight = Swift.max(0, pixel.chroma - threshold)
                    guard weight > 0 else { continue }
                    let axis = Crop.axisCoordinates(
                        imageOffsetX: Double(pixel.x) - centreX,
                        imageOffsetY: Double(pixel.y) - centreY
                    )
                    samples.append((u: axis.alongTileX, v: axis.alongTileY, weight: weight))
                    totalWeight += weight
                }
                guard totalWeight > 0 else {
                    report += "  chroma q=\(quantile) thr=\(threshold): none\n"
                    continue
                }
                let meanU = samples.reduce(0) { $0 + $1.u * $1.weight } / totalWeight
                let meanV = samples.reduce(0) { $0 + $1.v * $1.weight } / totalWeight
                let varU = samples.reduce(0) { $0 + $1.weight * ($1.u - meanU) * ($1.u - meanU) } / totalWeight
                let varV = samples.reduce(0) { $0 + $1.weight * ($1.v - meanV) * ($1.v - meanV) } / totalWeight
                report += "  chroma q=\(quantile) thr=\(threshold) n=\(samples.count)"
                    + " u=\(varU) v=\(varV) ratio=\(varU / varV)\n"
            }
        }

        return report
    }

    // MARK: - Measurement helpers

    /// One `GroundTileKind`'s crop of the decoded sheet, addressed in the
    /// same top-left-origin pixel space `AtlasGroundDiamond.pixelRect` uses.
    private struct Crop {
        let kind: GroundTileKind
        let pixels: ImagePixelSampling.Pixels

        var rect: CGRect { GroundTileCatalog.pixelRect(for: kind) }

        private var columns: Range<Int> {
            max(0, Int(rect.minX))..<min(pixels.width, Int(rect.maxX))
        }

        private var rows: Range<Int> {
            max(0, Int(rect.minY))..<min(pixels.height, Int(rect.maxY))
        }

        /// Every opaque pixel in the crop, with its luminance.
        var paintedPixels: [(x: Int, y: Int, luminance: Double)] {
            var result: [(x: Int, y: Int, luminance: Double)] = []
            for y in rows {
                for x in columns where pixels.isOpaque(x: x, y: y) {
                    result.append((x: x, y: y, luminance: luminance(x: x, y: y)))
                }
            }
            return result
        }

        /// Content fingerprint of just this crop's pixels.
        var fingerprint: UInt64 {
            var bytes: [UInt8] = []
            bytes.reserveCapacity(columns.count * rows.count * 4)
            for y in rows {
                for x in columns {
                    let base = (y * pixels.width + x) * 4
                    bytes.append(contentsOf: pixels.rgba[base..<(base + 4)])
                }
            }
            return ImagePixelSampling.fingerprint(width: columns.count, height: rows.count, bytes: bytes)
        }

        /// Rec. 601 luminance of the pixel at top-left-origin `(x, y)`.
        private func luminance(x: Int, y: Int) -> Double {
            let base = (y * pixels.width + x) * 4
            let red = Double(pixels.rgba[base])
            let green = Double(pixels.rgba[base + 1])
            let blue = Double(pixels.rgba[base + 2])
            return 0.299 * red + 0.587 * green + 0.114 * blue
        }

        /// How far a pixel sits along each of the two **tile axes**, given
        /// its offset from the diamond's centre in image pixels.
        ///
        /// Normalising by `tileHalfWidth`/`tileHalfHeight` turns the 2:1
        /// diamond back into a square rotated 45 degrees, in which the two
        /// tile axes are the coordinate axes: an offset of one whole tile
        /// step along +X (image space `(+48, -24)`) moves `alongTileX` only,
        /// and one along +Y (`(-48, -24)`) moves `alongTileY` only. Pinned by
        /// `test_tileAxisFrame_isDerivedFromTheProjectionsOwnDiagonals`.
        static func axisCoordinates(
            imageOffsetX: Double,
            imageOffsetY: Double
        ) -> (alongTileX: Double, alongTileY: Double) {
            let normalisedX = imageOffsetX / IsometricProjection.tileHalfWidth
            let normalisedY = imageOffsetY / IsometricProjection.tileHalfHeight
            return (
                alongTileX: normalisedX - normalisedY,
                alongTileY: -normalisedX - normalisedY
            )
        }

        /// Brightness-weighted spread of the crop's paint along each tile
        /// axis.
        ///
        /// Every opaque pixel is weighted by how much brighter it is than the
        /// crop's own median pixel, so the lane's painted markings (the
        /// brightest thing on a road tile) dominate and the asphalt base
        /// contributes nothing — no palette literal and no hand-picked
        /// threshold. Features that are symmetric about the diamond's centre
        /// contribute equally to both axes, so they cannot decide the
        /// comparison; only directional paint can.
        func paintSpread() -> PaintSpread {
            let painted = paintedPixels
            guard !painted.isEmpty else { return PaintSpread(alongTileX: 0, alongTileY: 0, totalWeight: 0) }

            let luminances = painted.map(\.luminance).sorted()
            let median = luminances[luminances.count / 2]

            // The diamond's centre, measured from the crop's own opaque
            // content rather than assumed to be the rect's midpoint.
            let centreX = Double(painted.map(\.x).min()! + painted.map(\.x).max()!) / 2
            let centreY = Double(painted.map(\.y).min()! + painted.map(\.y).max()!) / 2

            var totalWeight = 0.0
            var samples: [(alongTileX: Double, alongTileY: Double, weight: Double)] = []
            for pixel in painted {
                let weight = max(0, pixel.luminance - median)
                guard weight > 0 else { continue }
                let axis = Self.axisCoordinates(
                    imageOffsetX: Double(pixel.x) - centreX,
                    imageOffsetY: Double(pixel.y) - centreY
                )
                samples.append((alongTileX: axis.alongTileX, alongTileY: axis.alongTileY, weight: weight))
                totalWeight += weight
            }
            guard totalWeight > 0 else { return PaintSpread(alongTileX: 0, alongTileY: 0, totalWeight: 0) }

            let meanAlongX = samples.reduce(0) { $0 + $1.alongTileX * $1.weight } / totalWeight
            let meanAlongY = samples.reduce(0) { $0 + $1.alongTileY * $1.weight } / totalWeight
            let varianceAlongX = samples.reduce(0) {
                $0 + $1.weight * ($1.alongTileX - meanAlongX) * ($1.alongTileX - meanAlongX)
            } / totalWeight
            let varianceAlongY = samples.reduce(0) {
                $0 + $1.weight * ($1.alongTileY - meanAlongY) * ($1.alongTileY - meanAlongY)
            } / totalWeight

            return PaintSpread(alongTileX: varianceAlongX, alongTileY: varianceAlongY, totalWeight: totalWeight)
        }
    }

    /// A crop's measured paint spread along the two tile axes.
    private struct PaintSpread {
        let alongTileX: Double
        let alongTileY: Double
        /// Total brightness weight the spread was measured from; `0` means
        /// there was nothing brighter than the crop's median to measure, and
        /// the two variances above are meaningless rather than equal.
        let totalWeight: Double

        /// `> 1` when the paint is stretched along **tile X** (an east-west
        /// corridor), `< 1` when it is stretched along **tile Y** (a
        /// north-south corridor).
        var elongationRatio: Double {
            guard alongTileY > 0 else { return .infinity }
            return alongTileX / alongTileY
        }
    }
}
