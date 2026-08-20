import Foundation
import XCTest
@testable import CyberpunkMonsterCrawl
#if canImport(Darwin)
import Darwin
#endif

// SCAFFOLDING(CYBERPUN-17-10): deleted together with `CrashDiagnostics`
// itself (and its `AppDelegate` call site) once the still-unfiled
// crash-cause ticket names the frame the `pulse-ability` journey dies on --
// these tests exist only to keep the capture honest while it stands, and
// must not become a reason to keep it.

#if DEBUG
/// `CYBERPUN-17-10-t5`: the crash-diagnostic capture this task adds so a
/// probe run that loses the app process leaves a symbolicated trace behind
/// instead of only "process gone, no frame named"
/// (`CYBERPUN-17-10-t4`'s own recorded gap).
///
/// **Why this suite never actually raises a signal or an uncaught
/// exception.** Doing so would terminate the *test process* the same way it
/// would terminate the app -- there is no way to "catch and continue" a
/// real `SIGABRT`/`SIGSEGV`/uncaught `NSException` from inside the process
/// that raised it. `CrashDiagnostics` is therefore structured so its two
/// actually-dangerous entry points (`crashDiagnosticsSignalHandler`, the
/// `NSSetUncaughtExceptionHandler` closure) are the thinnest possible
/// wrappers around testable, pure(ish) functions --
/// `crashDiagnosticsWriteReport(signalNumber:toFileDescriptor:)` and
/// `CrashDiagnostics.crashReportText(forException:)` -- and this suite
/// drives those directly.
/// Swift only allows forming a `@convention(c)` function pointer from a
/// direct reference to a **global** `func` (or a literal closure) -- never
/// from an arbitrary expression that merely happens to already be
/// statically typed as a C function pointer (a local `var`, a stored
/// property read, an `unsafeBitCast` result), and, per the compiler, not
/// even from a type's `static func` (its implicit metatype context is
/// enough to disqualify it from "no captures"). That is what "a C function
/// pointer can only be formed from a reference to a 'func' or a literal
/// closure" means, and it is why handing `NSSetUncaughtExceptionHandler`
/// the `previousExceptionHandler` property (or a same-type static member)
/// directly can never compile. The fix: stash the previous handler in a
/// top-level (module-scope) var and restore through this top-level
/// trampoline func, which forwards the call on to whatever was stashed.
private var crashDiagnosticsTestsStoredPreviousExceptionHandler: NSUncaughtExceptionHandler?

private func crashDiagnosticsTestsPreviousExceptionHandlerTrampoline(_ exception: NSException) {
    crashDiagnosticsTestsStoredPreviousExceptionHandler?(exception)
}

final class CrashDiagnosticsTests: XCTestCase {

    private var previousExceptionHandler: NSUncaughtExceptionHandler?

    override func setUp() {
        super.setUp()
        // `install()` replaces whatever uncaught-exception handler is
        // already registered (XCTest itself may have installed one) -- save
        // it so `tearDown()` can put it back rather than leaving this test's
        // handler installed for the rest of the process's test run.
        previousExceptionHandler = NSGetUncaughtExceptionHandler()
    }

    override func tearDown() {
        crashDiagnosticsTestsStoredPreviousExceptionHandler = previousExceptionHandler
        if previousExceptionHandler != nil {
            NSSetUncaughtExceptionHandler(crashDiagnosticsTestsPreviousExceptionHandlerTrampoline)
        } else {
            NSSetUncaughtExceptionHandler(nil)
        }
        super.tearDown()
    }

    // MARK: - crashLogURL

    func test_crashLogURL_pointsAtLastCrashLogInsideTheCachesDirectory() {
        let url = CrashDiagnostics.crashLogURL
        XCTAssertEqual(url.lastPathComponent, "last-crash.log")

        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        if let caches {
            XCTAssertTrue(
                url.path.hasPrefix(caches.path),
                "the crash log must live under the Caches directory, not Documents or a user-visible location"
            )
        }
    }

    // MARK: - install() is safe and idempotent

    /// `install()` runs for real (it is what `AppDelegate` calls), so this
    /// pins that calling it -- even repeatedly, as a real launch plus this
    /// test both do -- neither crashes the test process nor throws.
    func test_install_isSafeToCallRepeatedly() {
        CrashDiagnostics.install()
        CrashDiagnostics.install()

        XCTAssertNotNil(
            NSGetUncaughtExceptionHandler(),
            "install() must leave an uncaught-exception handler registered"
        )
    }

    // MARK: - NSException report text

    func test_crashReportText_includesTheExceptionNameReasonAndCallStack() {
        let exception = NSException(
            name: NSExceptionName("com.example.testException"),
            reason: "something Objective-C-shaped went wrong",
            userInfo: nil
        )

        let text = CrashDiagnostics.crashReportText(forException: exception)

        XCTAssertTrue(text.contains("com.example.testException"))
        XCTAssertTrue(text.contains("something Objective-C-shaped went wrong"))
        // `NSException.callStackSymbols` is only populated for an exception
        // that was actually raised/thrown (`raise()`/`objc_exception_throw`)
        // -- an exception merely `init`'d, as this test does to avoid
        // terminating the test process, is documented to capture an empty
        // call stack on some runtimes/OS versions. So this suite cannot
        // assert the call stack is non-empty; it only pins that whichever
        // frames (if any) `exception.callStackSymbols` does report are
        // faithfully included in the formatted text.
        for frame in exception.callStackSymbols {
            XCTAssertTrue(text.contains(frame))
        }
    }

    func test_crashReportText_withNoReason_stillProducesReadableText() {
        let exception = NSException(name: NSExceptionName("com.example.noReason"), reason: nil, userInfo: nil)
        let text = CrashDiagnostics.crashReportText(forException: exception)

        XCTAssertTrue(text.contains("com.example.noReason"))
        XCTAssertTrue(text.contains("<no reason>"))
    }

    // MARK: - persist(_:to:) actually writes its report

    /// A throwaway destination, cleaned up after each use.
    ///
    /// These tests deliberately never write through the *default*
    /// destination (`CrashDiagnostics.crashLogURL`): on a simulator shared
    /// between this suite and a runtime-probe run, a test-written
    /// `last-crash.log` is a fabricated crash log sitting exactly where the
    /// investigation looks. `persist(_:to:)` takes the destination for the
    /// same reason `crashDiagnosticsWriteReport(signalNumber:toFileDescriptor:)`
    /// takes a file descriptor; `test_crashLogURL_...` above pins where the
    /// real default points without writing anything to it.
    private func makeThrowawayReportURL() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CrashDiagnosticsTests-\(UUID().uuidString).log")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func test_persist_writesTheGivenTextToTheGivenDestination() throws {
        let destination = makeThrowawayReportURL()
        let marker = "CrashDiagnosticsTests marker \(UUID().uuidString)"
        CrashDiagnostics.persist(marker, to: destination)

        let written = try String(contentsOf: destination, encoding: .utf8)
        XCTAssertEqual(written, marker)
    }

    func test_persist_overwritesAnyPreviouslyWrittenReport() throws {
        let destination = makeThrowawayReportURL()
        CrashDiagnostics.persist("first report", to: destination)
        CrashDiagnostics.persist("second report", to: destination)

        let written = try String(contentsOf: destination, encoding: .utf8)
        XCTAssertEqual(written, "second report", "only the most recent crash's report should survive")
    }

    // MARK: - A stale report is cleared, and every report is dated

    /// The evidence this whole file exists to produce is only trustworthy
    /// if a report found after a run belongs to *that* run -- so a report
    /// left by a previous launch must be gone before the handlers are
    /// armed, or a run that never crashed still yields a trace.
    func test_clearStaleReport_removesAReportLeftByAPreviousLaunch() {
        let destination = makeThrowawayReportURL()
        CrashDiagnostics.persist("a trace from three runs ago", to: destination)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path), "precondition")

        XCTAssertTrue(CrashDiagnostics.clearStaleReport(at: destination))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: destination.path),
            "a stale report must not survive into the next launch"
        )
    }

    func test_clearStaleReport_withNoReportPresent_isANoOp() {
        let destination = makeThrowawayReportURL()
        XCTAssertFalse(CrashDiagnostics.clearStaleReport(at: destination))
    }

    func test_install_stampsTheLaunchTimeOntoEveryReport() {
        CrashDiagnostics.install()
        XCTAssertFalse(
            CrashDiagnostics.launchTimestamp.isEmpty,
            "install() must record when this process armed the handlers"
        )

        let exception = NSException(name: NSExceptionName("com.example.dated"), reason: "dated", userInfo: nil)
        let text = CrashDiagnostics.crashReportText(forException: exception)
        XCTAssertTrue(
            text.hasPrefix("[launch \(CrashDiagnostics.launchTimestamp)] [crashed "),
            "a report must be datable to a launch, not just present: \(text.prefix(120))"
        )
    }

    // MARK: - crashDiagnosticsWriteReport(signalNumber:toFileDescriptor:)

    /// Drives the exact function the real signal handler calls, against a
    /// throwaway file, without ever raising a real signal -- see this
    /// file's own header note on why that would terminate the test process.
    func test_crashDiagnosticsWriteReport_writesASignalHeaderAndANonEmptyBacktrace() throws {
        // The function is allocation-free by design (see its doc comment):
        // it writes only into buffers allocated ahead of time, so the
        // preparation `install()` does at launch has to happen here too.
        crashDiagnosticsPrepareSignalHandlerBuffers()

        let tempURL = makeThrowawayReportURL()

        let fd = open(tempURL.path, O_CREAT | O_WRONLY | O_TRUNC, 0o644)
        XCTAssertGreaterThanOrEqual(fd, 0, "precondition: the temp file must be openable")

        crashDiagnosticsWriteReport(signalNumber: SIGABRT, toFileDescriptor: fd)
        close(fd)

        let header = "Fatal signal \(SIGABRT)\n"
        let contents = try String(contentsOf: tempURL, encoding: .utf8)
        // `contains`, not `hasPrefix`: once `install()` has run in this
        // process the header is prefixed with the launch stamp
        // (`[launch <ISO-8601>] `), and test order within the process is
        // not something this assertion should depend on.
        XCTAssertTrue(contents.contains(header), "the hand-rolled signal header must render exactly: \(contents.prefix(80))")
        XCTAssertGreaterThan(
            contents.count, header.count,
            "backtrace_symbols_fd must have written at least one frame after the header"
        )
    }

    /// The digits are rendered by hand (`crashDiagnosticsWriteHeader`), not
    /// by string interpolation -- which is the whole point, since
    /// interpolation allocates and `malloc` is not async-signal-safe. So
    /// pin a multi-digit signal too: a one-digit-only check would not catch
    /// a reversed or truncated conversion.
    func test_crashDiagnosticsWriteReport_rendersAMultiDigitSignalNumberCorrectly() throws {
        crashDiagnosticsPrepareSignalHandlerBuffers()

        let tempURL = makeThrowawayReportURL()
        let fd = open(tempURL.path, O_CREAT | O_WRONLY | O_TRUNC, 0o644)
        XCTAssertGreaterThanOrEqual(fd, 0, "precondition: the temp file must be openable")

        crashDiagnosticsWriteReport(signalNumber: SIGSEGV, toFileDescriptor: fd)
        close(fd)

        let contents = try String(contentsOf: tempURL, encoding: .utf8)
        XCTAssertTrue(
            contents.contains("Fatal signal \(SIGSEGV)\n"),
            "expected the decimal digits of \(SIGSEGV): \(contents.prefix(80))"
        )
    }

    // MARK: - fatalSignals

    func test_fatalSignals_coversTheSignalsASwiftTrapOrMemoryViolationActuallyRaises() {
        let expected: Set<Int32> = [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGTRAP]
        XCTAssertEqual(Set(CrashDiagnostics.fatalSignals), expected)
    }
}
#endif
