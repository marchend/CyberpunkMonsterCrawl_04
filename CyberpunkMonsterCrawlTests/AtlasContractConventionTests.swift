import XCTest

/// CYBERPUN-17-1 AC 8: cell indices are declared in exactly one owning list
/// per family, and no consumer constructs a raw cell rect of its own.
///
/// This scans the *whole production target* at test-run time and fails if any
/// file outside the atlas contract itself (`SpriteSheet.swift` /
/// `AtlasSheet.swift` / `AtlasCellIndex.swift`) crops a texture with a rect of
/// its own — the exact shape of the "magic numbers scattered across consumers"
/// the story forbids.
///
/// **Scope.** The scan walks `CyberpunkMonsterCrawl/` rather than
/// `CyberpunkMonsterCrawl/Sources/`, because the files most likely to
/// hand-roll a crop rect — `GameViewController.swift`, `BootScene.swift`, and
/// whatever scene files the renderer PRs add next — sit at the target root or
/// in new sibling directories, not under `Sources/`. Anything under a
/// `…Tests` directory is excluded: test code measures pixels deliberately.
///
/// **Patterns.** `SKTexture(rect:` and `textureRect` are forbidden outright.
/// `CGRect(` is only forbidden on lines that also mention a texture/sheet
/// symbol, so ordinary production geometry (node frames, HUD/safe-area
/// layout, camera viewports — `docs/bootstrap.md` §3 has all three coming)
/// does not trip the gate. A gate that fires on unrelated code gets defused
/// one `allowedFileNames` exemption at a time; this one stays narrow enough
/// that an exemption should never be the fix.
///
/// `#filePath` resolves, at compile time, to this file's own absolute path in
/// the checked-out repository; CI builds and runs tests from that same
/// checkout on the same machine, so the path is still valid at run time. If
/// the tree is ever unreachable at run time (a packaging change that stops
/// shipping source alongside the test binary) the scan skips — but
/// `test_productionTree_scansTheKnownAtlasContractAndSceneFiles` **fails**
/// in that case, so the gate cannot silently evaporate into a green suite.
final class AtlasContractConventionTests: XCTestCase {

    /// Files allowed to construct a raw cell-rect / `CGRect` for texture
    /// cropping — the atlas contract itself. Every other production source
    /// file must go through `SpriteSheet.texture(col:row:)` /
    /// `SpriteSheet.texture(forPixelRect:)` / `AtlasCellIndex` instead.
    private static let allowedFileNames: Set<String> = [
        "SpriteSheet.swift",
        "AtlasSheet.swift",
        "AtlasCellIndex.swift",
    ]

    /// Always a contract violation outside the allowed files: these only ever
    /// appear when a call site is cropping a texture itself.
    private static let forbiddenPatterns = [
        "textureRect",
        "SKTexture(rect:",
    ]

    /// `CGRect(` is forbidden only in texture-cropping context — a line that
    /// also names one of these symbols.
    private static let textureContextTokens = [
        "texture",
        "sheet",
        "atlas",
        "cell",
        "spritesheet",
        "crop",
    ]

    /// Directory names excluded from the scan.
    private static let excludedDirectorySuffixes = ["Tests"]

    /// Production files the scan must reach — the three contract files plus
    /// the target-root scene files that live outside `Sources/`. If the scope
    /// ever narrows back to `Sources/`, the root files drop out and this
    /// list goes red.
    private static let expectedScannedFileNames: Set<String> = [
        "SpriteSheet.swift",
        "AtlasSheet.swift",
        "AtlasCellIndex.swift",
        "TextureLoading.swift",
        "GameViewController.swift",
        "BootScene.swift",
        "SceneDelegate.swift",
    ]

    private var productionDirectory: URL {
        // ".../CyberpunkMonsterCrawlTests/AtlasContractConventionTests.swift"
        // -> repo root -> CyberpunkMonsterCrawl/
        let thisFile = URL(fileURLWithPath: #filePath)
        let repoRoot = thisFile
            .deletingLastPathComponent() // CyberpunkMonsterCrawlTests/
            .deletingLastPathComponent() // repo root
        return repoRoot.appendingPathComponent("CyberpunkMonsterCrawl")
    }

    private func swiftFiles(under directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            guard !isExcluded(url) else { continue }
            files.append(url)
        }
        return files
    }

    /// Excludes any file sitting under a `…Tests` directory.
    private func isExcluded(_ url: URL) -> Bool {
        let directoryComponents = url.deletingLastPathComponent().pathComponents
        return directoryComponents.contains { component in
            Self.excludedDirectorySuffixes.contains { component.hasSuffix($0) }
        }
    }

    private func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    /// Returns the pattern this line violates, or `nil` if the line is fine.
    private func violation(in line: String) -> String? {
        for pattern in Self.forbiddenPatterns where line.contains(pattern) {
            return pattern
        }

        guard line.contains("CGRect(") else { return nil }
        let lowercased = line.lowercased()
        guard Self.textureContextTokens.contains(where: { lowercased.contains($0) }) else {
            return nil // Node frames, HUD layout, viewports: not a crop rect.
        }
        return "CGRect( in texture-cropping context"
    }

    func test_productionTree_hasNoRawCellRectConstructionOutsideTheAtlasContract() throws {
        let directory = productionDirectory
        guard directoryExists(directory) else {
            throw XCTSkip(
                "\(directory.path) not reachable on disk; skipping the convention scan. "
                    + "test_productionTree_scansTheKnownAtlasContractAndSceneFiles fails in this case, "
                    + "so the gate does not silently evaporate."
            )
        }

        var offenders: [String] = []
        for file in swiftFiles(under: directory) {
            guard !Self.allowedFileNames.contains(file.lastPathComponent) else { continue }
            guard let contents = try? String(contentsOf: file, encoding: .utf8) else { continue }

            for (offset, line) in contents.components(separatedBy: .newlines).enumerated() {
                guard let pattern = violation(in: line) else { continue }
                offenders.append(
                    "\(file.lastPathComponent):\(offset + 1) [\(pattern)]: "
                        + line.trimmingCharacters(in: .whitespaces)
                )
            }
        }

        XCTAssertTrue(
            offenders.isEmpty,
            "Raw texture-crop rect construction found outside the atlas contract "
                + "(SpriteSheet.swift / AtlasSheet.swift / AtlasCellIndex.swift):\n"
                + offenders.joined(separator: "\n")
        )
    }

    /// Guards the scanner above against silently walking zero files — which
    /// would pass the assertion vacuously the moment the target moves, the
    /// enumerator stops finding anything, or the scan's scope narrows back to
    /// `Sources/` and stops covering the root scene files.
    ///
    /// This one fails rather than skips when the tree is unreachable: "the
    /// whole gate quietly disappeared" must not read as a green suite.
    func test_productionTree_scansTheKnownAtlasContractAndSceneFiles() {
        let directory = productionDirectory
        guard directoryExists(directory) else {
            XCTFail(
                "\(directory.path) is not reachable on disk, so the AC 8 convention scan is not "
                    + "running at all. Fix the scan's path (or the packaging change that hid the "
                    + "source tree) rather than leaving the gate unreported."
            )
            return
        }

        let scannedFiles = swiftFiles(under: directory)
        XCTAssertFalse(scannedFiles.isEmpty, "The convention scan walked zero Swift files under \(directory.path).")

        let scannedFileNames = Set(scannedFiles.map(\.lastPathComponent))
        for expectedFileName in Self.expectedScannedFileNames {
            XCTAssertTrue(
                scannedFileNames.contains(expectedFileName),
                "\(expectedFileName) was not reached by the convention scan under \(directory.path)."
            )
        }
    }

    /// Pins the two halves of the pattern rule so a future edit cannot quietly
    /// widen `CGRect(` back into "any rect anywhere" or drop the crop-specific
    /// patterns.
    func test_patternRule_flagsTextureCropRects_andIgnoresOrdinaryLayoutRects() {
        XCTAssertNotNil(violation(in: "let rect = CGRect(x: 0, y: 0, width: 36, height: 40) // cell"))
        XCTAssertNotNil(violation(in: "return SKTexture(rect: normalized, in: sheetTexture)"))
        XCTAssertNotNil(violation(in: "let r = node.textureRect()"))
        XCTAssertNotNil(violation(in: "let cropRect = CGRect(x: 96, y: 0, width: 96, height: 60)"))

        XCTAssertNil(violation(in: "hudContainer.frame = CGRect(x: 0, y: 0, width: 320, height: 44)"))
        XCTAssertNil(violation(in: "let viewport = CGRect(origin: .zero, size: view.bounds.size)"))
        XCTAssertNil(violation(in: "sprite.position = CGPoint(x: 10, y: 10)"))
    }
}
