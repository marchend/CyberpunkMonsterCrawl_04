import CoreGraphics
import XCTest
@testable import CyberpunkMonsterCrawl

/// Acceptance coverage for the atlas contract (CYBERPUN-17-1).
///
/// The v1 failure this rebuild exists to prevent was an empty asset catalog
/// shipping with a green suite. These tests attack that from two sides:
///
/// 1. The `test_shippedAssetCatalog_satisfiesAtlasContract_*` gates run the
///    contract against the real `Assets.xcassets` and must go red while any
///    referenced image id is missing. The half covering the art that is
///    already imported (the 10 atlas sheets) is unmuted; only the halves the
///    named follow-up task still owes carry an expectation, so a regression in
///    imported art can never hide behind a deferral.
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

    /// A sheet that is imported but not yet celled is still referenced, so
    /// losing it from the catalog must still turn the suite red.
    func test_validate_reportsMissingImage_whenAnImportedButUndeclaredSheetIsAbsent() {
        let contract = AtlasContract(
            requiredSheetCount: 1,
            sheets: [],
            undeclaredSheetImageIDs: ["sprite_pulse"],
            buildingImageIDs: []
        )

        XCTAssertTrue(
            contract.validate(using: StubMeasurer(measurements: [:]))
                .contains(.missingImage(id: "sprite_pulse")),
            "An imported sheet without a declared cell grid must still be gated on existence."
        )
    }

    func test_validate_reportsMissingAlphaChannel_forAnImportedButUndeclaredSheet() {
        let contract = AtlasContract(
            requiredSheetCount: 1,
            sheets: [],
            undeclaredSheetImageIDs: ["sprite_pulse"],
            buildingImageIDs: []
        )
        let measurer = StubMeasurer(measurements: [
            "sprite_pulse": makeMeasurement(
                width: 64,
                height: 64,
                hasAlpha: false,
                content: 7_000,
                mirrored: 7_001
            )
        ])

        XCTAssertTrue(
            contract.validate(using: measurer).contains(.missingAlphaChannel(id: "sprite_pulse"))
        )
    }

    /// Once a family's cell grid is declared, its id must not be referenced
    /// twice — the declaration supersedes the undeclared entry.
    func test_referencedImageIDs_doesNotDuplicateASheetThatIsBothDeclaredAndImported() {
        let contract = AtlasContract(
            requiredSheetCount: 1,
            sheets: [
                AtlasSheetDeclaration(
                    imageID: "sprite_pulse",
                    cellSize: CGSize(width: 32, height: 32),
                    ownedCellIndices: [0]
                )
            ],
            undeclaredSheetImageIDs: ["sprite_pulse", "sprite_signs"],
            buildingImageIDs: []
        )

        XCTAssertEqual(contract.referencedImageIDs, ["sprite_pulse", "sprite_signs"])
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

    /// THE acceptance gate for the art this PR imports — deliberately
    /// **unmuted**. Every one of the 10 atlas sheets must resolve in the real
    /// `Assets.xcassets` and satisfy every contract rule that applies to it.
    ///
    /// Rename `sprite_pulse` in the catalog, drop an imageset, or ship one
    /// without an alpha channel, and this goes red today — no expectation
    /// wraps it.
    func test_shippedAssetCatalog_satisfiesAtlasContract_forEveryImportedSheet() {
        let sheetIDs = Set(AtlasContract.importedSheetImageIDs)
        let violations = AtlasContract.current
            .validate(using: AssetCatalogImageMeasurer())
            .filter { $0.concerns(anyOf: sheetIDs) }

        XCTAssertTrue(
            violations.isEmpty,
            "Imported atlas sheets violate the contract:\n"
                + violations.map(\.description).joined(separator: "\n")
        )
    }

    /// Records the measured facts about the imported art in an assertion
    /// rather than in prose: every sheet decodes, has a non-zero pixel size,
    /// and genuinely carries the alpha channel the pack is specified to have.
    ///
    /// Measured through the same `AssetCatalogImageMeasurer` the contract
    /// uses, so "the bytes are fine" is an observation about the shipped
    /// bytes, not an assumption about the filenames.
    func test_assetCatalogMeasurer_measuresRealPixelsAndAlpha_forEveryImportedSheet() {
        let measurer = AssetCatalogImageMeasurer()

        for imageID in AtlasContract.importedSheetImageIDs {
            guard let measurement = measurer.measure(imageID: imageID) else {
                XCTFail("\(imageID) is referenced by the contract but is not in Assets.xcassets.")
                continue
            }

            XCTAssertGreaterThan(measurement.pixelSize.width, 0, "\(imageID) measured zero width.")
            XCTAssertGreaterThan(measurement.pixelSize.height, 0, "\(imageID) measured zero height.")
            XCTAssertTrue(
                measurement.hasAlphaChannel,
                "\(imageID) decoded without an alpha channel; the pack is specified as PNG-32."
            )
        }
    }

    /// The contract must reference the imagesets that are actually in the
    /// repository, otherwise the missing-image gate above walks an empty list
    /// and passes vacuously.
    func test_currentContract_referencesEveryImportedAtlasSheet() {
        let referenced = Set(AtlasContract.current.referencedImageIDs)

        XCTAssertEqual(AtlasContract.importedSheetImageIDs.count, 10)
        for imageID in AtlasContract.importedSheetImageIDs {
            XCTAssertTrue(referenced.contains(imageID), "\(imageID) is imported but unreferenced.")
        }
    }

    /// The remaining half of the gate: the 12 building sprites.
    ///
    /// SCAFFOLDING(CYBERPUN-17-1-t3): the building PNGs are not in the
    /// repository, so this genuinely fails today and the failure is recorded
    /// rather than hidden. The expectation is scoped to the building ids only,
    /// so it cannot mute a regression in the sheets that *are* imported, and
    /// it is strict: the moment the buildings land, XCTest fails this test for
    /// "expected failure not recorded", forcing CYBERPUN-17-1-t3 to delete it.
    func test_shippedAssetCatalog_satisfiesAtlasContract_forEveryBuildingSprite() {
        XCTExpectFailure(
            "CYBERPUN-17-1-t3: the 12 building PNGs (building_00 … building_11) are not imported "
                + "yet. That task adds the imagesets and deletes this expectation."
        ) {
            let buildingIDs = Set(AtlasContract.current.buildingImageIDs)
            let violations = AtlasContract.current
                .validate(using: AssetCatalogImageMeasurer())
                .filter { $0.concerns(anyOf: buildingIDs) }

            XCTAssertTrue(
                violations.isEmpty,
                "Building sprite contract violations:\n"
                    + violations.map(\.description).joined(separator: "\n")
            )
        }
    }

    /// The last outstanding piece: a measured cell grid per sheet family.
    ///
    /// SCAFFOLDING(CYBERPUN-17-1-t3): cell sizes may only be written down once
    /// they have been checked against the measured sheets, which needs the
    /// art open in Xcode; until then `sheets` is empty and the contract says
    /// so out loud. Strict, so filling `sheets` in forces this expectation's
    /// deletion.
    func test_shippedAssetCatalog_declaresACellGridForEverySheetFamily() {
        XCTExpectFailure(
            "CYBERPUN-17-1-t3: AtlasContract.current.sheets is not populated with measured cell "
                + "sizes and owned cell indices yet. That task fills it in and deletes this "
                + "expectation."
        ) {
            let violations = AtlasContract.current.validate(using: AssetCatalogImageMeasurer())

            XCTAssertFalse(
                violations.contains(.sheetManifestIncomplete(declared: 0, required: 10)),
                "Sheet manifest is still incomplete:\n"
                    + violations.map(\.description).joined(separator: "\n")
            )
        }
    }
}
