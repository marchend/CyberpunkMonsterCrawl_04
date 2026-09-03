import XCTest
#if canImport(Darwin)
import Darwin
#endif
@testable import CyberpunkMonsterCrawl

// `CrashDiagnostics` itself is compiled only `#if DEBUG` (see its own doc
// comment); the test target builds in the Debug configuration, where
// `project.yml` defines `DEBUG` via `SWIFT_ACTIVE_COMPILATION_CONDITIONS`,
// so this suite mirrors that gating rather than assuming it.
#if DEBUG

/// Exercises `CrashDiagnostics.persist(_:to:)` and its stale-report cleanup
/// against explicit temp destinations only. Never opens or writes the real
/// `CrashDiagnostics.logFileURL()` (the Caches path): these tests must not
/// leave -- or depend on -- a real `last-crash.log`.
final class CrashDiagnosticsTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CrashDiagnosticsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        tempDirectory = nil
        try super.tearDownWithError()
    }

    // MARK: - persist(_:to:) report format

    func test_persist_writesTheExactReportBytesToTheGivenDestination() throws {
        let url = tempDirectory.appendingPathComponent("report.log")
        let fd = url.path.withCString { open($0, O_CREAT | O_WRONLY | O_TRUNC, 0o644) }
        XCTAssertGreaterThanOrEqual(fd, 0, "failed to open the explicit temp fd this test writes through")

        let report = "CrashDiagnostics report -- process launched 2024-01-01T00:00:00Z\nSignal: 11\n"
        CrashDiagnostics.persist(report, to: fd)
        close(fd)

        let written = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(written, report)
    }

    func test_persist_calledMultipleTimes_appendsInOrderToTheSameDestination() throws {
        // Mirrors production usage: the header is written first, then
        // backtrace/exception detail lines follow, all to the same fd.
        let url = tempDirectory.appendingPathComponent("report.log")
        let fd = url.path.withCString { open($0, O_CREAT | O_WRONLY | O_TRUNC, 0o644) }
        XCTAssertGreaterThanOrEqual(fd, 0)

        CrashDiagnostics.persist("line one\n", to: fd)
        CrashDiagnostics.persist("line two\n", to: fd)
        close(fd)

        let written = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(written, "line one\nline two\n")
    }

    func test_persist_withAnInvalidDestination_doesNothingAndNeverTraps() {
        // -1 is never a valid fd. `persist` must degrade quietly: a broken
        // destination must never be what turns a real crash into a second,
        // unrelated crash inside the handler itself.
        CrashDiagnostics.persist("unreachable", to: -1)
    }

    // MARK: - "no report on a clean run" invariant

    func test_cleanRun_leavesNoReportBehindAtAnExplicitDestination() {
        // A destination nothing ever calls `persist(_:to:)` against stays
        // absent, exactly like `last-crash.log` on a launch that never
        // crashes.
        let url = tempDirectory.appendingPathComponent("report.log")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func test_clearExistingReport_removesAStaleFileLeftByAPreviousRun() throws {
        let url = tempDirectory.appendingPathComponent("last-crash.log")
        try "stale crash report from a previous launch".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        CrashDiagnostics.clearExistingReport(at: url)

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: url.path),
            "a stale report from a previous run must not survive into a clean run"
        )
    }

    func test_clearExistingReport_isANoOpWhenNoStaleFileExists() {
        let url = tempDirectory.appendingPathComponent("last-crash.log")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))

        CrashDiagnostics.clearExistingReport(at: url) // must not throw or trap

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: - real destination shape (never opened/written here)

    func test_logFileURL_pointsAtTheExpectedNameInsideTheCachesDirectory() {
        let url = CrashDiagnostics.logFileURL()
        XCTAssertEqual(url.lastPathComponent, CrashDiagnostics.logFileName)
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        XCTAssertEqual(url.deletingLastPathComponent(), caches)
    }
}

#endif
