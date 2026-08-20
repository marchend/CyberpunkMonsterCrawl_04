import Foundation
import XCTest
@testable import CyberpunkMonsterCrawl
#if canImport(Darwin)
import Darwin
#endif

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

    // MARK: - persist(_:) actually writes to crashLogURL

    func test_persist_writesTheGivenTextToCrashLogURL() throws {
        let marker = "CrashDiagnosticsTests marker \(UUID().uuidString)"
        CrashDiagnostics.persist(marker)

        let written = try String(contentsOf: CrashDiagnostics.crashLogURL, encoding: .utf8)
        XCTAssertEqual(written, marker)
    }

    func test_persist_overwritesAnyPreviouslyWrittenReport() throws {
        CrashDiagnostics.persist("first report")
        CrashDiagnostics.persist("second report")

        let written = try String(contentsOf: CrashDiagnostics.crashLogURL, encoding: .utf8)
        XCTAssertEqual(written, "second report", "only the most recent crash's report should survive")
    }

    // MARK: - crashDiagnosticsWriteReport(signalNumber:toFileDescriptor:)

    /// Drives the exact function the real signal handler calls, against a
    /// throwaway file, without ever raising a real signal -- see this
    /// file's own header note on why that would terminate the test process.
    func test_crashDiagnosticsWriteReport_writesASignalHeaderAndANonEmptyBacktrace() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CrashDiagnosticsTests-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let fd = open(tempURL.path, O_CREAT | O_WRONLY | O_TRUNC, 0o644)
        XCTAssertGreaterThanOrEqual(fd, 0, "precondition: the temp file must be openable")

        crashDiagnosticsWriteReport(signalNumber: SIGABRT, toFileDescriptor: fd)
        close(fd)

        let contents = try String(contentsOf: tempURL, encoding: .utf8)
        XCTAssertTrue(contents.hasPrefix("Fatal signal \(SIGABRT)\n"))
        XCTAssertGreaterThan(
            contents.count, "Fatal signal \(SIGABRT)\n".count,
            "backtrace_symbols_fd must have written at least one frame after the header"
        )
    }

    // MARK: - fatalSignals

    func test_fatalSignals_coversTheSignalsASwiftTrapOrMemoryViolationActuallyRaises() {
        let expected: Set<Int32> = [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGTRAP]
        XCTAssertEqual(Set(CrashDiagnostics.fatalSignals), expected)
    }
}
