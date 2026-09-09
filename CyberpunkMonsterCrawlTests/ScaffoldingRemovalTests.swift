import XCTest

/// `CYBERPUN-17-14` PR 1's removal-gate regression test for the
/// `// SCAFFOLDING:` marker convention `docs/bootstrap.md` established at
/// project bootstrap: "any temporary label, overlay or debug driver is
/// marked `// SCAFFOLDING:` so the final gate story can grep and remove all
/// of it." Later stories tagged individual markers more specifically as
/// `SCAFFOLDING(<ticket>)` (naming a removal owner) rather than the bare
/// convention string -- this scan matches the shared substring
/// `"SCAFFOLDING"` so either spelling trips it; the marker's exact
/// punctuation is never load-bearing, only its presence.
///
/// **Scope is the bundled app target only** (`CyberpunkMonsterCrawl/`),
/// never the whole repository -- and PR #64's review was right that an
/// earlier revision of this file used that scope to *exclude* the one live
/// marker in the tree, which would have let the story's acceptance criterion
/// ("a grep for the marker returns nothing, across the whole codebase") be
/// reported as met by a gate that never looked at it.
///
/// That marker is gone rather than excluded now. It tagged the
/// `CYBERPUN-17-11` pickup-spawn crash-bisection instrumentation in
/// `CyberpunkMonsterCrawlTests/JourneyManifestTests.swift` and
/// `.mothership/journeys/pickup-spawn.json`, named a root-cause ticket that
/// was never filed as its removal owner, and was held in place by a passing
/// test that failed if the instrumentation was deleted -- a temporary
/// artifact with a test protecting it, which is the shape this story exists
/// to end. This PR removed the two bracketing `assert_running` checkpoints
/// and that test; what is known about the still-unidentified crash is
/// recorded in `AGENT.md`'s `CYBERPUN-17-11` entry instead.
///
/// With that done, no artifact anywhere in the tree carries the marker, so
/// the app-target scope no longer hides anything. The scan stays scoped
/// there because the occurrences that remain in the repository are the ones
/// that *describe* the convention rather than tag anything: this file's own
/// `marker` constant and its anti-vacuity fixtures, `docs/bootstrap.md`'s
/// statement of the convention, `ScreensTests`' reference to it, and
/// `docs/evidence/`'s gate log. A whole-repository scan would fail on the
/// gate's own definition of what it scans for -- a vacuous red, not a real
/// one -- so the honest division is: this test enforces the shipped app
/// source, and `docs/evidence/gate-07-scaffolding-grep-output.txt` records
/// the full-tree state, including that list, for the human reviewer.
///
/// As of this PR, a full-tree grep for the marker inside
/// `CyberpunkMonsterCrawl/` (the app target) already returns zero matches --
/// every previously `// SCAFFOLDING:`/`SCAFFOLDING(...)`-tagged artifact this
/// codebase ever shipped (`PlayerScaffoldingDriver` and its debug camera pan,
/// `CrashDiagnostics`, `LaunchGotoState`) was already deleted by the story
/// that owned it. This test exists so that state is asserted and protected
/// going forward, not merely observed once.
final class ScaffoldingRemovalTests: XCTestCase {

    /// The marker substring this gate scans for. Deliberately just the bare
    /// word, not the full `// SCAFFOLDING:` string, so both the original
    /// bootstrap convention and the later `SCAFFOLDING(<ticket>)` tagging
    /// convention are caught by the same scan.
    static let marker = "SCAFFOLDING"

    private var appSourceDirectory: URL {
        // ".../CyberpunkMonsterCrawlTests/ScaffoldingRemovalTests.swift"
        // -> repo root -> CyberpunkMonsterCrawl/ (the bundled app target,
        // never the test target or `.mothership/`).
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // CyberpunkMonsterCrawlTests/
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("CyberpunkMonsterCrawl")
    }

    private func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    /// Every regular file under `directory`, at any depth, whose contents
    /// (best-effort UTF-8 decode) contain `Self.marker`. A file that cannot
    /// be decoded as UTF-8 (an image, an `.xcassets` binary blob) is silently
    /// skipped rather than reported as an offender -- this gate cares about
    /// source/resource text, not asset bytes.
    private func filesContainingMarker(under directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            return []
        }

        var offenders: [URL] = []
        for case let url as URL in enumerator {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue
            else {
                continue
            }
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else { continue }
            if contents.contains(Self.marker) {
                offenders.append(url)
            }
        }
        return offenders
    }

    func test_appSourceDirectory_isReachable() {
        XCTAssertTrue(
            directoryExists(appSourceDirectory),
            "\(appSourceDirectory.path) is not reachable, so this whole gate is not running."
        )
    }

    // MARK: - Gate 7: zero matches in the bundled app target

    func test_bundledAppSource_containsNoScaffoldingMarker() throws {
        guard directoryExists(appSourceDirectory) else {
            throw XCTSkip("App source directory not reachable; see test_appSourceDirectory_isReachable.")
        }

        let offenders = filesContainingMarker(under: appSourceDirectory)

        XCTAssertTrue(
            offenders.isEmpty,
            "The bundled app target (CyberpunkMonsterCrawl/) must carry no scaffolding marker -- no "
                + "debug overlay, smoke-test label or placeholder title left behind -- but found the "
                + "marker in: " + offenders.map(\.path).joined(separator: ", ")
        )
    }

    // MARK: - Anti-vacuity guard: the scanner really finds the marker

    /// Builds a throwaway directory tree under `NSTemporaryDirectory()`
    /// (never inside the repo, and removed again in `defer`) containing the
    /// marker both as a direct child file and nested two directories deep,
    /// then asserts `filesContainingMarker(under:)` -- the exact function
    /// `test_bundledAppSource_containsNoScaffoldingMarker` relies on --
    /// surfaces both, and does not flag a clean file sitting alongside them.
    ///
    /// Without this, a scanner that silently walked zero files (a wrong
    /// path, a `nil` enumerator swallowed by a `guard`, an encoding mismatch
    /// that always fails `String(contentsOf:encoding:)`) would report the
    /// same "zero offenders" as a genuinely clean tree -- the exact
    /// "gate passes vacuously" failure mode this project's other scan gates
    /// (`NoBuildingGeometryConstructionTests`, `AtlasCatalogNoExtraneousAssetsTests`)
    /// already guard against with their own minimum-file-count assertions.
    func test_scanner_findsTheMarker_bothAsADirectChildAndNested() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScaffoldingRemovalTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let nestedDirectory = root
            .appendingPathComponent("Sources")
            .appendingPathComponent("UI")
        try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)

        let directChildFile = root.appendingPathComponent("DirectChild.swift")
        let nestedFile = nestedDirectory.appendingPathComponent("Nested.swift")
        let cleanFile = root.appendingPathComponent("Clean.swift")

        try "// SCAFFOLDING: direct-child debug overlay\nfinal class DirectChild {}\n"
            .write(to: directChildFile, atomically: true, encoding: .utf8)
        try "final class Nested {\n    // SCAFFOLDING(CYBERPUN-99-t9): synthetic fixture marker\n}\n"
            .write(to: nestedFile, atomically: true, encoding: .utf8)
        try "final class Clean {}\n".write(to: cleanFile, atomically: true, encoding: .utf8)

        let offenders = Set(filesContainingMarker(under: root).map(\.standardizedFileURL))

        XCTAssertTrue(
            offenders.contains(directChildFile.standardizedFileURL),
            "Scanner did not find the marker in a direct child fixture file -- it would silently "
                + "miss real scaffolding sitting at the top of a directory too."
        )
        XCTAssertTrue(
            offenders.contains(nestedFile.standardizedFileURL),
            "Scanner did not find the marker in a nested fixture file -- it would silently miss "
                + "real scaffolding buried a few directories deep too."
        )
        XCTAssertFalse(
            offenders.contains(cleanFile.standardizedFileURL),
            "Scanner flagged a fixture file that contains no marker at all -- it would fail this "
                + "gate on innocent, unrelated code."
        )
        XCTAssertEqual(
            offenders.count, 2,
            "Expected exactly the two marker-bearing fixture files to be flagged, found "
                + "\(offenders.count): \(offenders.map(\.lastPathComponent).sorted())."
        )
    }
}
