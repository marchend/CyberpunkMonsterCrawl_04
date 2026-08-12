import XCTest

/// CYBERPUN-17-1 AC 8: cell indices are declared in exactly one owning list
/// per family, and no consumer constructs a raw cell rect of its own.
///
/// This scans the *production* source tree at test-run time and fails if any
/// file outside the atlas contract itself (`SpriteSheet.swift` /
/// `AtlasSheet.swift` / `AtlasCellIndex.swift`) builds a `CGRect` (or calls
/// `SKTexture(rect:in:)` / references `textureRect`) for texture cropping —
/// the exact shape of the "magic numbers scattered across consumers" the
/// story forbids.
///
/// `#filePath` resolves, at compile time, to this file's own absolute path in
/// the checked-out repository; CI builds and runs tests from that same
/// checkout on the same machine, so the path is still valid at run time. If
/// the source tree is ever unreachable at run time (a packaging change that
/// stops shipping source alongside the test binary), the scan skips rather
/// than silently reporting a clean bill of health.
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

    /// Substrings that indicate a call site is rolling its own crop rect
    /// rather than going through the contract.
    private static let forbiddenPatterns = [
        "CGRect(",
        "textureRect",
        "SKTexture(rect:",
    ]

    private var sourcesDirectory: URL {
        // ".../CyberpunkMonsterCrawlTests/AtlasContractConventionTests.swift"
        // -> repo root -> CyberpunkMonsterCrawl/Sources
        let thisFile = URL(fileURLWithPath: #filePath)
        let repoRoot = thisFile
            .deletingLastPathComponent() // CyberpunkMonsterCrawlTests/
            .deletingLastPathComponent() // repo root
        return repoRoot
            .appendingPathComponent("CyberpunkMonsterCrawl")
            .appendingPathComponent("Sources")
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
            files.append(url)
        }
        return files
    }

    private func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    func test_sourcesTree_hasNoRawCellRectConstructionOutsideTheAtlasContract() throws {
        let directory = sourcesDirectory
        guard directoryExists(directory) else {
            throw XCTSkip("Sources/ not reachable on disk at \(directory.path); skipping the convention scan.")
        }

        var offenders: [String] = []
        for file in swiftFiles(under: directory) {
            guard !Self.allowedFileNames.contains(file.lastPathComponent) else { continue }
            guard let contents = try? String(contentsOf: file, encoding: .utf8) else { continue }

            for (offset, line) in contents.components(separatedBy: .newlines).enumerated() {
                for pattern in Self.forbiddenPatterns where line.contains(pattern) {
                    offenders.append(
                        "\(file.lastPathComponent):\(offset + 1): \(line.trimmingCharacters(in: .whitespaces))"
                    )
                }
            }
        }

        XCTAssertTrue(
            offenders.isEmpty,
            "Raw cell-rect construction found outside the atlas contract "
                + "(SpriteSheet.swift / AtlasSheet.swift / AtlasCellIndex.swift):\n"
                + offenders.joined(separator: "\n")
        )
    }

    /// Guards the scanner above against silently walking zero files — which
    /// would pass the assertion vacuously the moment `Sources/` moves or the
    /// enumerator stops finding anything.
    func test_sourcesTree_scansAtLeastTheKnownAtlasContractFiles() throws {
        let directory = sourcesDirectory
        guard directoryExists(directory) else {
            throw XCTSkip("Sources/ not reachable on disk at \(directory.path); skipping the convention scan.")
        }

        let scannedFileNames = Set(swiftFiles(under: directory).map(\.lastPathComponent))
        for allowedFileName in Self.allowedFileNames {
            XCTAssertTrue(
                scannedFileNames.contains(allowedFileName),
                "\(allowedFileName) was not found under \(directory.path)."
            )
        }
    }
}
