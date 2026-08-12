import XCTest

/// CYBERPUN-17-1 AC 7, closed out catalog-wide by this PR: no imageset
/// anywhere in `Assets.xcassets` (atlas sheets *or* building sprites) may
/// declare a `2x`/`3x` rendition, and the opaque `tileset_structure`
/// source-of-record showcase sheet — nor the "Asset Scales" preview art the
/// pack ships alongside it — may ever be imported as a second asset set.
///
/// This scans the whole `Assets.xcassets` tree at test-run time (both
/// `Atlas/` and `Buildings/`, plus anywhere else a future PR might add a
/// group) rather than re-asserting a fixed list of imagesets, so a
/// regression introduced by *either* asset family, or by a new one added
/// later, is caught without editing this file.
///
/// `#filePath` resolves, at compile time, to this file's own absolute path in
/// the checked-out repository; CI builds and runs tests from that same
/// checkout, so the path is still valid at run time. If the catalog is ever
/// unreachable at run time, `test_catalog_scansAtLeastTheKnownImageSets`
/// **fails** rather than the scan silently evaporating into a green suite.
final class AtlasCatalogNoExtraneousAssetsTests: XCTestCase {

    /// Names (normalized: lowercased, non-alphanumeric characters stripped)
    /// that must never appear as an imageset anywhere in the catalog.
    /// Matches "tileset_structure", "Tileset Structure", etc.
    private static let forbiddenExactNormalizedNames: Set<String> = [
        "tilesetstructure",
    ]

    /// Normalized substrings that must never appear together in an imageset
    /// name — catches "Asset Scales", "asset-scales-preview",
    /// "AssetScalesPreview", etc. without pinning one exact spelling of the
    /// pack's preview-art filename.
    private static let forbiddenSubstringPairs: [(String, String)] = [
        ("asset", "scale"),
    ]

    private var assetsXcassetsDirectory: URL {
        // ".../CyberpunkMonsterCrawlTests/AtlasCatalogNoExtraneousAssetsTests.swift"
        // -> repo root -> CyberpunkMonsterCrawl/Assets.xcassets
        let thisFile = URL(fileURLWithPath: #filePath)
        let repoRoot = thisFile
            .deletingLastPathComponent() // CyberpunkMonsterCrawlTests/
            .deletingLastPathComponent() // repo root
        return repoRoot
            .appendingPathComponent("CyberpunkMonsterCrawl")
            .appendingPathComponent("Assets.xcassets")
    }

    private func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    /// Every `*.imageset` directory anywhere under `Assets.xcassets`.
    private func imageSetDirectories(under directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        var directories: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "imageset" {
            directories.append(url)
        }
        return directories
    }

    private func normalized(_ name: String) -> String {
        name.lowercased().filter(\.isLetter)
    }

    /// Returns a human-readable violation reason, or `nil` if `imageSetName`
    /// is fine.
    private func nameViolation(_ imageSetName: String) -> String? {
        let normalizedName = normalized(imageSetName)

        if Self.forbiddenExactNormalizedNames.contains(normalizedName) {
            return "forbidden showcase/source-of-record imageset"
        }
        for (first, second) in Self.forbiddenSubstringPairs
        where normalizedName.contains(first) && normalizedName.contains(second) {
            return "forbidden Asset-Scales-preview imageset"
        }
        return nil
    }

    func test_catalog_scansAtLeastTheKnownImageSets() {
        guard directoryExists(assetsXcassetsDirectory) else {
            XCTFail(
                "\(assetsXcassetsDirectory.path) is not reachable on disk, so the whole-catalog "
                    + "extraneous-asset scan is not running at all."
            )
            return
        }

        let imageSets = imageSetDirectories(under: assetsXcassetsDirectory)
        // 10 atlas sheets + 12 building sprites, at minimum. Guards this
        // whole file against vacuously passing if the scan walked zero
        // directories.
        XCTAssertGreaterThanOrEqual(
            imageSets.count,
            22,
            "Expected at least 22 imagesets (10 atlas + 12 buildings) under "
                + "\(assetsXcassetsDirectory.path), found \(imageSets.count)."
        )
    }

    func test_noImageSetAnywhereInTheCatalog_declaresA2xOr3xRendition() throws {
        guard directoryExists(assetsXcassetsDirectory) else {
            throw XCTSkip("\(assetsXcassetsDirectory.path) not reachable; see test_catalog_scansAtLeastTheKnownImageSets.")
        }

        var offenders: [String] = []
        for imageSetDirectory in imageSetDirectories(under: assetsXcassetsDirectory) {
            let contentsURL = imageSetDirectory.appendingPathComponent("Contents.json")
            guard let data = try? Data(contentsOf: contentsURL),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let images = json["images"] as? [[String: Any]]
            else {
                offenders.append("\(imageSetDirectory.lastPathComponent): Contents.json missing or unreadable")
                continue
            }

            for image in images {
                guard let scale = image["scale"] as? String else { continue }
                if scale == "2x" || scale == "3x" {
                    offenders.append(
                        "\(imageSetDirectory.lastPathComponent) declares a \(scale) rendition "
                            + "(filename: \(image["filename"] as? String ?? "?")) — the pack is 1× art only."
                    )
                }
            }
        }

        XCTAssertTrue(
            offenders.isEmpty,
            "Stray @2x/@3x renditions found in the catalog:\n" + offenders.joined(separator: "\n")
        )
    }

    func test_noTilesetStructureOrAssetScalesPreviewImageSet_existsAnywhereInTheCatalog() throws {
        guard directoryExists(assetsXcassetsDirectory) else {
            throw XCTSkip("\(assetsXcassetsDirectory.path) not reachable; see test_catalog_scansAtLeastTheKnownImageSets.")
        }

        var offenders: [String] = []
        for imageSetDirectory in imageSetDirectories(under: assetsXcassetsDirectory) {
            let name = imageSetDirectory.deletingPathExtension().lastPathComponent
            if let violation = nameViolation(name) {
                offenders.append("\(name): \(violation)")
            }
        }

        XCTAssertTrue(
            offenders.isEmpty,
            "tileset_structure.png (opaque source-of-record showcase sheet) and the \"Asset Scales\" "
                + "preview art must never be imported into Assets.xcassets:\n" + offenders.joined(separator: "\n")
        )
    }

    /// Pins the name-matching rule itself, independent of what is currently
    /// in the catalog.
    func test_nameViolation_flagsTheForbiddenNames_andIgnoresRealSheetNames() {
        XCTAssertNotNil(nameViolation("tileset_structure"))
        XCTAssertNotNil(nameViolation("Tileset Structure"))
        XCTAssertNotNil(nameViolation("Asset Scales"))
        XCTAssertNotNil(nameViolation("asset-scales-preview"))
        XCTAssertNotNil(nameViolation("AssetScalesPreview"))

        XCTAssertNil(nameViolation("tileset_ground"))
        XCTAssertNil(nameViolation("sprite_signs"))
        XCTAssertNil(nameViolation("building_11"))
    }
}
