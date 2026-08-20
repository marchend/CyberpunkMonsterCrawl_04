import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Persists a symbol-rich crash trace to disk *before* the process
/// terminates, so a probe run that loses the app process leaves more than
/// "process gone, no frame named" behind (`CYBERPUN-17-10-t4`'s own recorded
/// gap: the `pulse-ability` journey lost the process at two points and
/// nothing captured why).
///
/// **Two independent hooks, because Swift's own traps and Objective-C
/// exceptions terminate the process through entirely different
/// mechanisms.** `precondition`/`fatalError`/a force-unwrap/an
/// array-out-of-bounds access never raise an `NSException` -- they call
/// the Swift runtime's trap path, which raises a POSIX signal directly
/// (`SIGILL`/`SIGTRAP` on the platforms this app ships to; `SIGABRT` for an
/// explicit `abort()`). A small number of crashes elsewhere in the app's
/// dependency graph (an Objective-C runtime misuse, a KVO contract
/// violation) instead raise a genuine `NSException` that unwinds until
/// nothing catches it. Installing only one of the two hooks below would
/// silently miss whichever failure mode did not happen to be the cause.
///
/// **Neither hook changes behavior on the non-crashing path.** Both are
/// no-ops that only run once the process is already unwinding/trapping; the
/// signal handler re-raises the same signal with its default disposition
/// once it has written its report, so the process still terminates exactly
/// the way it would have without this file existing -- this is diagnostic
/// capture, not crash suppression (per the story's own "never silence this
/// check" convention for `SpriteSheet.init`'s precondition, which this
/// file's whole purpose is to leave a trace for, not to weaken).
///
/// **Installed as early as possible.** `AppDelegate.application(_:didFinishLaunchingWithOptions:)`
/// calls `CrashDiagnostics.install()` before `SceneDelegate` ever
/// constructs `GameViewController`/`GameScene` -- i.e. before
/// `GameScene.commonInit()` ever mounts a `PulseRingNode` -- so a crash at
/// first `.gameplay` entry (or at the first pulse-button press) is already
/// covered by both handlers.
enum CrashDiagnostics {

    /// Where the last captured crash trace is written. Caches, not
    /// Documents: this is disposable diagnostic data (overwritten on every
    /// crash, never read by the app itself), not user data, so it has no
    /// business being backed up or exposed to the user's file browser the
    /// way `HighScoreStore`'s persisted table is.
    static var crashLogURL: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches.appendingPathComponent("last-crash.log")
    }

    /// Guards against double-installing the POSIX signal handlers (installing
    /// twice is harmless -- `signal(_:_:)` simply replaces the previous
    /// handler with an identical one -- but re-snapshotting `crashLogURL`'s
    /// UTF-8 bytes on every call is pointless work `install()` should not
    /// repeat).
    private static var isInstalled = false

    /// Installs both the `NSException` handler and the POSIX signal
    /// handlers. Idempotent: only the first call takes effect.
    static func install() {
        guard !isInstalled else { return }
        isInstalled = true

        crashLogPathBytes = ContiguousArray(crashLogURL.path.utf8CString)

        NSSetUncaughtExceptionHandler { exception in
            CrashDiagnostics.persist(CrashDiagnostics.crashReportText(forException: exception))
        }

        for signalNumber in fatalSignals {
            signal(signalNumber, crashDiagnosticsSignalHandler)
        }
    }

    /// The signals a Swift runtime trap (`precondition`, `fatalError`, a
    /// force-unwrap, an array-out-of-bounds access, an integer overflow) or
    /// a memory violation actually raises. `SIGTRAP`/`SIGILL` cover the
    /// Swift-trap path (which of the two fires is platform/architecture
    /// dependent); `SIGABRT` covers an explicit `abort()` (including the
    /// one `NSException`'s own default top-level handler calls); `SIGSEGV`/
    /// `SIGBUS` cover a memory violation; `SIGFPE` covers integer
    /// divide-by-zero.
    static let fatalSignals: [Int32] = [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGTRAP]

    /// Human-readable text for an uncaught `NSException`, extracted from the
    /// handler closure so `CrashDiagnosticsTests` can pin its exact format
    /// without needing to actually raise (and thereby terminate the test
    /// process with) a real uncaught exception.
    static func crashReportText(forException exception: NSException) -> String {
        "Uncaught NSException: \(exception.name.rawValue): \(exception.reason ?? "<no reason>")\n"
            + exception.callStackSymbols.joined(separator: "\n")
    }

    /// Writes `text` to `crashLogURL`, overwriting whatever was there before
    /// -- only the *most recent* crash matters for the next probe run to
    /// pick up.
    static func persist(_ text: String) {
        try? text.write(to: crashLogURL, atomically: true, encoding: .utf8)
    }
}

/// The crash-log path's UTF-8 bytes, snapshotted once by `install()` so the
/// POSIX signal handler never has to call into Foundation's `URL`/
/// `FileManager` while a signal is actually being handled -- those APIs may
/// allocate or lock, which is not guaranteed safe to do on a thread that
/// just trapped mid-allocation itself. A top-level `var`, not a type
/// property: `signal(_:_:)` takes a plain C function pointer
/// (`crashDiagnosticsSignalHandler` below), which cannot capture any
/// context, so both it and the state it reads have to live at file scope.
private var crashLogPathBytes: ContiguousArray<CChar> = []

/// Writes a "Fatal signal N" header followed by the crashing thread's
/// symbolicated backtrace to `fd`, using only `backtrace(_:_:)`/
/// `backtrace_symbols_fd(_:_:_:)` -- the standard primitives for this --
/// plus a raw POSIX `write(2)` for the header.
///
/// Exposed at file scope (not folded into `crashDiagnosticsSignalHandler`)
/// so `CrashDiagnosticsTests` can drive it directly against a throwaway
/// file descriptor: that lets the suite assert on the exact bytes this
/// function writes without ever raising (and thereby terminating the test
/// process with) a real signal.
func crashDiagnosticsWriteReport(signalNumber: Int32, toFileDescriptor fd: Int32) {
    let header = "Fatal signal \(signalNumber)\n"
    header.withCString { cString in
        _ = write(fd, cString, strlen(cString))
    }

    var frames = [UnsafeMutableRawPointer?](repeating: nil, count: 64)
    let frameCount = frames.withUnsafeMutableBufferPointer { buffer -> Int32 in
        guard let base = buffer.baseAddress else { return 0 }
        return backtrace(base, Int32(buffer.count))
    }
    frames.withUnsafeMutableBufferPointer { buffer in
        backtrace_symbols_fd(buffer.baseAddress, frameCount, fd)
    }
}

/// The actual signal handler `CrashDiagnostics.install()` registers via
/// `signal(_:_:)`. A top-level function, never a closure: `signal(_:_:)`'s
/// second parameter is a C function pointer, and a Swift closure that
/// captures context cannot be converted to one.
///
/// Opens the file at `crashLogPathBytes` (snapshotted at install time),
/// delegates the actual report content to
/// `crashDiagnosticsWriteReport(signalNumber:toFileDescriptor:)`, then
/// restores the signal's default disposition and re-raises it -- so the
/// process still terminates exactly as it would have if this handler had
/// never been installed. This is diagnostic capture, not crash suppression.
private func crashDiagnosticsSignalHandler(_ signalNumber: Int32) {
    if !crashLogPathBytes.isEmpty {
        let fd = crashLogPathBytes.withUnsafeBufferPointer { buffer -> Int32 in
            guard let base = buffer.baseAddress else { return -1 }
            return open(base, O_CREAT | O_WRONLY | O_TRUNC, 0o644)
        }
        if fd >= 0 {
            crashDiagnosticsWriteReport(signalNumber: signalNumber, toFileDescriptor: fd)
            close(fd)
        }
    }

    signal(signalNumber, SIG_DFL)
    raise(signalNumber)
}
