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
/// The rendition scan reads three independent signals per imageset, because
/// any one of them alone has a blind spot: the declared `scale` key (absent
/// entirely on single-scale imagesets), the referenced `filename` (a `@2x`
/// file can be declared `1x`), and the PNGs actually on disk (a stray import
/// `Contents.json` never mentions — including the showcase sheet dropped into
/// an existing imageset directory, which the name-based scan cannot see).
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

    /// Every `*.png` sitting on disk inside one imageset directory,
    /// regardless of whether `Contents.json` mentions it.
    private func pngFilesOnDisk(in imageSetDirectory: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: imageSetDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        return contents.filter { $0.pathExtension.lowercased() == "png" }
    }

    private func normalized(_ name: String) -> String {
        name.lowercased().filter(\.isLetter)
    }

    /// Returns a violation reason if `filename`'s stem carries an `@2x`/`@3x`
    /// suffix, or `nil` if it is a plain 1× filename.
    ///
    /// Checked independently of the `scale` key because Xcode writes
    /// single-scale imagesets with no `scale` at all ("Resizing → Single
    /// Scale"), so a `@2x` file dropped into such an entry — or referenced
    /// with `"scale": "1x"` — carries no `2x` marker anywhere but its name.
    private func scaleSuffixViolation(_ filename: String) -> String? {
        let stem = URL(fileURLWithPath: filename)
            .deletingPathExtension()
            .lastPathComponent
            .lowercased()

        for suffix in ["@2x", "@3x"] where stem.hasSuffix(suffix) {
            return "filename \(filename) carries a \(suffix) suffix"
        }
        return nil
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

    /// Covers three ways a non-1× or extraneous import can reach the catalog:
    /// a declared `2x`/`3x` scale, a `@2x`/`@3x` **filename** (referenced with
    /// any scale, or none at all), and a PNG sitting in an imageset directory
    /// that `Contents.json` never references.
    func test_noImageSetAnywhereInTheCatalog_declaresOrShipsA2xOr3xRendition_orAnUnreferencedPNG() throws {
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

            var referencedFilenames: Set<String> = []

            for image in images {
                // The `scale` key is checked when present, but its absence is
                // never a free pass: a single-scale entry has no `scale` at
                // all, so the filename below is the only evidence left.
                if let scale = image["scale"] as? String, scale == "2x" || scale == "3x" {
                    offenders.append(
                        "\(imageSetDirectory.lastPathComponent) declares a \(scale) rendition "
                            + "(filename: \(image["filename"] as? String ?? "?")) — the pack is 1× art only."
                    )
                }

                guard let filename = image["filename"] as? String else { continue }
                referencedFilenames.insert(filename)

                if let violation = scaleSuffixViolation(filename) {
                    offenders.append(
                        "\(imageSetDirectory.lastPathComponent) references a non-1× rendition: "
                            + "\(violation) (declared scale: \(image["scale"] as? String ?? "none")) "
                            + "— the pack is 1× art only."
                    )
                }
            }

            // The PNGs actually on disk, which `Contents.json` can hide two
            // ways: a `@2x` file referenced as 1×/unscaled, or a stray file
            // (e.g. the opaque `tileset_structure` showcase sheet) dropped
            // into an existing imageset directory under a name the
            // imageset-name scan below can never see.
            for pngURL in pngFilesOnDisk(in: imageSetDirectory) {
                let pngName = pngURL.lastPathComponent

                if let violation = scaleSuffixViolation(pngName) {
                    offenders.append(
                        "\(imageSetDirectory.lastPathComponent) ships \(violation) on disk "
                            + "— the pack is 1× art only."
                    )
                }

                if !referencedFilenames.contains(pngName) {
                    offenders.append(
                        "\(imageSetDirectory.lastPathComponent) ships \(pngName) on disk but does not "
                            + "reference it in Contents.json — an unreferenced import (stray rendition or "
                            + "showcase sheet) that no name-based scan can see."
                    )
                }
            }
        }

        XCTAssertTrue(
            offenders.isEmpty,
            "Stray @2x/@3x renditions or unreferenced PNG imports found in the catalog:\n"
                + offenders.joined(separator: "\n")
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

    /// Pins the filename-based rendition rule itself, independent of what is
    /// currently in the catalog — this is the check that catches a `@2x`
    /// import whose `Contents.json` entry claims `1x` or omits `scale`
    /// entirely, so it must hold on its own.
    func test_scaleSuffixViolation_flagsAtSuffixedFilenames_andIgnoresPlain1xNames() {
        XCTAssertNotNil(scaleSuffixViolation("building_00@2x.png"))
        XCTAssertNotNil(scaleSuffixViolation("building_00@3x.png"))
        XCTAssertNotNil(scaleSuffixViolation("tileset_ground@2X.PNG"))
        XCTAssertNotNil(scaleSuffixViolation("sprite_pulse@3x"))

        XCTAssertNil(scaleSuffixViolation("building_00.png"))
        XCTAssertNil(scaleSuffixViolation("tileset_ground.png"))
        // "@2x" only counts as a rendition marker at the end of the stem.
        XCTAssertNil(scaleSuffixViolation("building_@2x_concept.png"))
    }
}
