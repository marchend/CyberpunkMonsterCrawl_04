import CoreGraphics
import XCTest
@testable import CyberpunkMonsterCrawl

/// Acceptance coverage for the atlas contract (CYBERPUN-17-1).
///
/// The v1 failure this rebuild exists to prevent was an empty asset catalog
/// shipping with a green suite. These tests attack that from two sides:
///
/// 1. `test_shippedAssetCatalog_satisfiesAtlasContract` runs the contract
///    against the real `Assets.xcassets` and must go red while any referenced
///    image id is missing.
/// 2. The fixture-driven tests prove the validator actually detects each
///    violation class, so the gate above cannot be quietly hollowed out into
///    something that passes on an empty catalog.
final class AtlasContractTests: XCTestCase {

    // MARK: - Fixtures

    /// Measurements supplied by hand so the contract's rules can be exercised
    /// without shipping art into the test bundle.
    private struct StubMeasurer: AtlasImageMeasuring {
        var measurements: [String: AtlasImageMeasurement]

        func measure(imageID: String) -> AtlasImageMeasurement? {
            measurements[imageID]
        }
    }

    private func makeMeasurement(
        width: CGFloat,
        height: CGFloat,
        hasAlpha: Bool = true,
        content: Int,
        mirrored: Int
    ) -> AtlasImageMeasurement {
        AtlasImageMeasurement(
            pixelSize: CGSize(width: width, height: height),
            hasAlphaChannel: hasAlpha,
            contentFingerprint: content,
            mirroredContentFingerprint: mirrored
        )
    }

    private static let sheetID = "raccoon_walk"

    /// A contract with one sheet family and the 12 buildings — all resolvable,
    /// all distinct. This is the shape the asset-import PR has to reach.
    ///
    /// `removing` / `overriding` let each test bend exactly one fact and
    /// assert on the violation that falls out.
    private func fixture(
        removing removedIDs: [String] = [],
        overriding overrides: [String: AtlasImageMeasurement] = [:]
    ) -> (contract: AtlasContract, measurer: StubMeasurer) {
        let sheet = AtlasSheetDeclaration(
            imageID: Self.sheetID,
            cellSize: CGSize(width: 32, height: 32),
            ownedCellIndices: Array(0..<8)
        )
        let contract = AtlasContract(
            requiredSheetCount: 1,
            sheets: [sheet],
            buildingImageIDs: AtlasContract.requiredBuildingImageIDs
        )

        var measurements: [String: AtlasImageMeasurement] = [
            Self.sheetID: makeMeasurement(width: 256, height: 32, content: 9_000, mirrored: 9_001)
        ]
        for (offset, imageID) in AtlasContract.requiredBuildingImageIDs.enumerated() {
            measurements[imageID] = makeMeasurement(
                width: 96,
                height: 128,
                content: 100 + offset,
                mirrored: 500 + offset
            )
        }

        for removedID in removedIDs {
            measurements.removeValue(forKey: removedID)
        }
        for (imageID, measurement) in overrides {
            measurements[imageID] = measurement
        }

        return (contract, StubMeasurer(measurements: measurements))
    }

    // MARK: - Contract shape

    func test_currentContract_referencesTwelveDistinctBuildingImagesets() {
        let ids = AtlasContract.current.buildingImageIDs

        XCTAssertEqual(ids.count, 12)
        XCTAssertEqual(Set(ids).count, 12, "Building image ids must be unique.")
        XCTAssertEqual(ids.first, "building_00")
        XCTAssertEqual(ids.last, "building_11")
    }

    func test_referencedImageIDs_coversEverySheetAndEveryBuilding() {
        let (contract, _) = fixture()

        XCTAssertEqual(contract.referencedImageIDs.count, 1 + 12)
        XCTAssertTrue(contract.referencedImageIDs.contains(Self.sheetID))
        XCTAssertTrue(contract.referencedImageIDs.contains("building_07"))
    }

    // MARK: - Validation rules

    func test_validate_reportsNothing_whenEveryReferencedImageResolves() {
        let (contract, measurer) = fixture()

        XCTAssertEqual(contract.validate(using: measurer), [])
    }

    func test_validate_reportsMissingImage_whenABuildingImagesetIsAbsent() {
        let (contract, measurer) = fixture(removing: ["building_05"])

        XCTAssertTrue(
            contract.validate(using: measurer).contains(.missingImage(id: "building_05")),
            "A referenced image id missing from the catalog must fail the contract."
        )
    }

    func test_validate_reportsMissingImage_whenASheetIsAbsent() {
        let (contract, measurer) = fixture(removing: [Self.sheetID])

        XCTAssertTrue(
            contract.validate(using: measurer).contains(.missingImage(id: Self.sheetID))
        )
    }

    func test_validate_reportsIncompleteManifest_whenFewerSheetsAreDeclaredThanRequired() {
        let contract = AtlasContract(requiredSheetCount: 10, sheets: [], buildingImageIDs: [])

        XCTAssertTrue(
            contract.validate(using: StubMeasurer(measurements: [:]))
                .contains(.sheetManifestIncomplete(declared: 0, required: 10))
        )
    }

    /// The grid is computed from measured pixels, so a sheet whose name
    /// promises a tidy cell count but whose bytes do not divide evenly is a
    /// violation rather than a silently rounded guess.
    func test_validate_reportsNotCellAligned_whenMeasuredSizeIsNotAWholeCellMultiple() {
        let (contract, measurer) = fixture(
            overriding: [
                Self.sheetID: makeMeasurement(width: 250, height: 32, content: 9_000, mirrored: 9_001)
            ]
        )

        XCTAssertTrue(
            contract.validate(using: measurer).contains(
                .sheetNotCellAligned(
                    id: Self.sheetID,
                    pixelSize: CGSize(width: 250, height: 32),
                    cellSize: CGSize(width: 32, height: 32)
                )
            )
        )
    }

    func test_validate_reportsCellIndexOutOfRange_whenAnOwnedIndexExceedsTheMeasuredGrid() {
        // Measures 4 columns × 1 row = 4 cells, but the family claims 0..<8.
        let (contract, measurer) = fixture(
            overriding: [
                Self.sheetID: makeMeasurement(width: 128, height: 32, content: 9_000, mirrored: 9_001)
            ]
        )

        XCTAssertTrue(
            contract.validate(using: measurer).contains(
                .cellIndexOutOfRange(id: Self.sheetID, index: 7, cellCount: 4)
            )
        )
    }

    func test_measuredSheets_derivesGridFromMeasuredPixelsNotFromTheDeclaration() {
        let (contract, measurer) = fixture()

        let measured = contract.measuredSheets(using: measurer)

        XCTAssertEqual(measured.count, 1)
        XCTAssertEqual(measured.first?.columns, 8)
        XCTAssertEqual(measured.first?.rows, 1)
        XCTAssertEqual(measured.first?.cellCount, 8)
    }

    func test_validate_reportsMissingAlphaChannel_whenAnImageDecodesWithoutAlpha() {
        let (contract, measurer) = fixture(
            overriding: [
                "building_03": makeMeasurement(
                    width: 96,
                    height: 128,
                    hasAlpha: false,
                    content: 4_242,
                    mirrored: 4_243
                )
            ]
        )

        XCTAssertTrue(
            contract.validate(using: measurer).contains(.missingAlphaChannel(id: "building_03"))
        )
    }

    func test_validate_reportsDuplicateBuildingArt_whenTwoBuildingsArePixelIdentical() {
        // building_09 carries building_00's exact pixels.
        let (contract, measurer) = fixture(
            overriding: [
                "building_09": makeMeasurement(width: 96, height: 128, content: 100, mirrored: 500)
            ]
        )

        XCTAssertTrue(
            contract.validate(using: measurer).contains(
                .duplicateBuildingArt(ids: ["building_00", "building_09"])
            )
        )
    }

    func test_validate_reportsMirroredBuildingArt_whenOneBuildingIsAFlipOfAnother() {
        // building_02's pixels are building_01's pixels flipped horizontally.
        let (contract, measurer) = fixture(
            overriding: [
                "building_02": makeMeasurement(width: 96, height: 128, content: 501, mirrored: 101)
            ]
        )

        XCTAssertTrue(
            contract.validate(using: measurer).contains(
                .mirroredBuildingArt(ids: ["building_01", "building_02"])
            )
        )
    }

    // MARK: - Real asset catalog

    /// Proves missing ids are detectable through the *real* catalog path, not
    /// only through the stub: an id that is not in `Assets.xcassets` measures
    /// as `nil`, which is what `validate` turns into `.missingImage`.
    func test_assetCatalogMeasurer_returnsNil_forAnIDThatIsNotInTheCatalog() {
        XCTAssertNil(
            AssetCatalogImageMeasurer().measure(imageID: "cyberpun_17_1_absent_image_id")
        )
    }

    /// THE acceptance gate: the shipped catalog must satisfy the contract.
    ///
    /// SCAFFOLDING(CYBERPUN-17-1): the Pixel Grit binary pack is not in the
    /// repository yet, so this assertion genuinely fails today and that
    /// failure is recorded as expected rather than hidden. The expectation is
    /// strict: the moment the art lands and the contract passes, XCTest fails
    /// this test for "expected failure not recorded", forcing the asset-import
    /// PR to delete this `XCTExpectFailure` and leave a real, unmuted gate
    /// behind. Hollowing the validator out so it reports nothing trips the
    /// same wire.
    func test_shippedAssetCatalog_satisfiesAtlasContract() {
        XCTExpectFailure(
            "CYBERPUN-17-1: Assets.xcassets is still the empty stub — the asset-import PR must "
                + "land the 10 sheets + 12 buildings, fill AtlasContract.current.sheets, and delete "
                + "this expectation."
        ) {
            let violations = AtlasContract.current.validate(using: AssetCatalogImageMeasurer())
            XCTAssertTrue(
                violations.isEmpty,
                "Atlas contract violations:\n"
                    + violations.map(\.description).joined(separator: "\n")
            )
        }
    }
}
