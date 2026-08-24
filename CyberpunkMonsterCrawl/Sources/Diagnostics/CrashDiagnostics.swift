import Foundation
#if canImport(Darwin)
import Darwin
#endif

// SCAFFOLDING(CYBERPUN-17-10): investigation support for one specific,
// still-unidentified crash -- not permanent crash infrastructure. This file
// exists only so the *next* `pulse-ability` probe run leaves a symbolicated
// trace naming the frame that tears the process down. Its removal owner is
// the crash-cause ticket AGENT.md/CLAUDE.md record as still unfiled ("raised
// on PR #52 review, NO TICKET ID - file one before closing the story"); no
// ticket ID is invented here. Once that ticket names the frame and closes,
// this file, the `CrashDiagnostics.install()` call in
// `AppDelegate.application(_:didFinishLaunchingWithOptions:)` and
// `CrashDiagnosticsTests` should all be deleted together.
//
// Gated `#if DEBUG` like `Sources/Debug/LaunchGotoState.swift`, the repo's
// existing convention for exactly this shape of artifact: a shipped App
// Store binary must not have its process-wide
// `NSSetUncaughtExceptionHandler` and six signal dispositions hijacked by a
// debugging aid nobody owns the removal of.

#if DEBUG
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
///
/// **DEBUG-only, and deliberately so** (see the `SCAFFOLDING` marker
/// above). The whole file is compiled out of Release, so `install()` does
/// not exist in a shipped binary and nothing here can displace a Release
/// build's exception/signal handlers. That is also why neither hook chains
/// to a previously-registered handler: the DEBUG/probe builds this runs in
/// have none worth preserving, and the signal handler restores the default
/// disposition and re-raises either way.
///
/// **What it cannot capture.** A stack-overflow `SIGSEGV` has no usable
/// stack left for a handler to run on, and this file deliberately installs
/// no `sigaltstack`, so that one crash class still yields "process gone,
/// no frame named". Out of scope for this task (nothing on the journey
/// under investigation recurses), recorded here so the next reader does
/// not assume coverage that is not there.
///
/// **Every report is dated, and a stale one is cleared at launch.**
/// `install()` deletes any `last-crash.log` a previous run left behind
/// *before* arming either hook, and both hooks stamp their report with
/// this process's launch time (`launchTimestamp`, rendered once at install
/// time -- the signal handler itself cannot format a date, see
/// `crashDiagnosticsWriteReport(signalNumber:toFileDescriptor:)`). So a
/// probe run that finds a report can tell whether it belongs to *this*
/// launch instead of reading three-runs-old evidence as a fresh trace --
/// and a run that does not crash leaves no report at all.
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

    /// ISO-8601 in UTC, so a stamped report sorts and compares without a
    /// locale or a device time zone in the picture.
    static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    /// When this process armed the handlers, rendered once by `install()`.
    /// Every report carries it, which is what lets the next probe run tell
    /// a trace from *this* launch apart from one left by an earlier run.
    /// Empty until `install()` has run.
    private(set) static var launchTimestamp = ""

    /// Deletes any report left behind by a previous launch. Called by
    /// `install()` before either hook is armed, so the mere presence of
    /// `last-crash.log` after a run means *that* run crashed -- otherwise a
    /// probe that happens not to crash still finds a file sitting where the
    /// investigation looks, and the wrong frame gets blamed.
    ///
    /// Takes an explicit destination (defaulted) so the suite can exercise
    /// it against a throwaway URL instead of the real Caches path.
    @discardableResult
    static func clearStaleReport(at url: URL = CrashDiagnostics.crashLogURL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        try? FileManager.default.removeItem(at: url)
        return !FileManager.default.fileExists(atPath: url.path)
    }

    /// Installs both the `NSException` handler and the POSIX signal
    /// handlers. Idempotent: only the first call takes effect.
    static func install() {
        guard !isInstalled else { return }
        isInstalled = true

        clearStaleReport()
        launchTimestamp = timestampFormatter.string(from: Date())

        crashLogPathBytes = ContiguousArray(crashLogURL.path.utf8CString)

        // Every buffer the signal handler touches is allocated *here*,
        // while allocation is still safe -- see
        // `crashDiagnosticsPrepareSignalHandlerBuffers(launchTimestamp:)`.
        crashDiagnosticsPrepareSignalHandlerBuffers(launchTimestamp: launchTimestamp)

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
    ///
    /// Stamped with both this process's launch time and the moment the
    /// exception was caught, so a reader can date the report rather than
    /// guess which run produced it.
    static func crashReportText(forException exception: NSException, at date: Date = Date()) -> String {
        let launch = launchTimestamp.isEmpty ? "<not installed>" : launchTimestamp
        return "[launch \(launch)] [crashed \(timestampFormatter.string(from: date))] "
            + "Uncaught NSException: \(exception.name.rawValue): \(exception.reason ?? "<no reason>")\n"
            + exception.callStackSymbols.joined(separator: "\n")
    }

    /// Writes `text` to `url` (`crashLogURL` by default), overwriting
    /// whatever was there before -- only the *most recent* crash matters
    /// for the next probe run to pick up.
    ///
    /// The destination is a parameter, not a hard-coded path, for the same
    /// reason `crashDiagnosticsWriteReport(signalNumber:toFileDescriptor:)`
    /// takes a file descriptor: it lets `CrashDiagnosticsTests` assert on
    /// the bytes this writes without ever depositing fabricated report text
    /// at the real Caches path a probe run reads.
    static func persist(_ text: String, to url: URL = CrashDiagnostics.crashLogURL) {
        try? text.write(to: url, atomically: true, encoding: .utf8)
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

/// How many stack frames the handler captures. Fixed, because the buffer
/// that holds them is allocated once at install time and never resized.
private let crashDiagnosticsMaxFrames = 64

/// The frame buffer `backtrace(_:_:)` fills, allocated once by
/// `crashDiagnosticsPrepareSignalHandlerBuffers(launchTimestamp:)` -- never
/// by the handler.
///
/// `[UnsafeMutableRawPointer?](repeating:count:)` *inside* the handler (as
/// this function used to do) heap-allocates on every signal, and `malloc`
/// is not async-signal-safe. For the two cases this file most needs to
/// survive -- a `SIGSEGV`/`SIGBUS` from memory corruption, or a `SIGABRT`
/// raised from inside the allocator -- the handler can deadlock on the
/// malloc lock and *hang* instead of dying, leaving the probe with neither
/// a trace nor a clean crash: strictly worse than today's "process gone",
/// and the exact hazard `crashLogPathBytes` above already went out of its
/// way to avoid.
private var crashDiagnosticsFrames: UnsafeMutablePointer<UnsafeMutableRawPointer?>?

/// The report header, pre-rendered up to (but not including) the signal
/// number: e.g. `"[launch 2026-08-20T03:33:05Z] Fatal signal "`. Neither
/// string interpolation nor date formatting is safe on a signal-handler
/// path -- both allocate -- so everything variable-length is rendered here
/// at install time and the handler only appends the signal's decimal digits
/// and a newline, byte by byte, into memory that already existed before the
/// signal arrived.
private var crashDiagnosticsHeaderBuffer: UnsafeMutablePointer<CChar>?
private var crashDiagnosticsHeaderPrefixLength = 0
private var crashDiagnosticsHeaderCapacity = 0
private var crashDiagnosticsHeaderHasLaunchStamp = false

/// Allocates every buffer the signal handler needs, ahead of any signal.
///
/// Called by `CrashDiagnostics.install()` (and by `CrashDiagnosticsTests`,
/// which drives `crashDiagnosticsWriteReport(signalNumber:toFileDescriptor:)`
/// directly), never from a handler. Idempotent, except that the first call
/// carrying a non-empty `launchTimestamp` re-renders the header so the
/// stamp is present -- the previous header buffer is deliberately *not*
/// freed, because nothing here can prove a handler is not mid-write against
/// it and one leaked ~48-byte allocation per process is a far better trade
/// than a dangling pointer on the crash path.
func crashDiagnosticsPrepareSignalHandlerBuffers(launchTimestamp: String = "") {
    if crashDiagnosticsFrames == nil {
        let frames = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(
            capacity: crashDiagnosticsMaxFrames
        )
        frames.initialize(repeating: nil, count: crashDiagnosticsMaxFrames)
        crashDiagnosticsFrames = frames
    }

    let carriesLaunchStamp = !launchTimestamp.isEmpty
    guard crashDiagnosticsHeaderBuffer == nil
        || (carriesLaunchStamp && !crashDiagnosticsHeaderHasLaunchStamp) else { return }

    let prefix = Array(
        (carriesLaunchStamp ? "[launch \(launchTimestamp)] Fatal signal " : "Fatal signal ").utf8
    )
    // Prefix + a sign + the widest decimal Int32 (10 digits) + '\n'.
    let capacity = prefix.count + 12
    let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: capacity)
    buffer.initialize(repeating: 0, count: capacity)
    for (index, byte) in prefix.enumerated() {
        buffer[index] = CChar(bitPattern: byte)
    }

    crashDiagnosticsHeaderPrefixLength = prefix.count
    crashDiagnosticsHeaderCapacity = capacity
    crashDiagnosticsHeaderHasLaunchStamp = carriesLaunchStamp
    crashDiagnosticsHeaderBuffer = buffer
}

/// Writes the pre-rendered header (launch stamp + `"Fatal signal N"`)
/// followed by the crashing thread's symbolicated backtrace to `fd`, using
/// only `backtrace(_:_:)`/`backtrace_symbols_fd(_:_:_:)` -- the standard
/// primitives for this -- plus a raw POSIX `write(2)` for the header.
///
/// **Allocation-free on purpose.** Every buffer it touches was allocated by
/// `crashDiagnosticsPrepareSignalHandlerBuffers(launchTimestamp:)` at
/// install time; nothing on this path calls `malloc`, which is not
/// async-signal-safe. If preparation never ran the function writes nothing
/// rather than allocating its way out.
///
/// Exposed at file scope (not folded into `crashDiagnosticsSignalHandler`)
/// so `CrashDiagnosticsTests` can drive it directly against a throwaway
/// file descriptor: that lets the suite assert on the exact bytes this
/// function writes without ever raising (and thereby terminating the test
/// process with) a real signal.
func crashDiagnosticsWriteReport(signalNumber: Int32, toFileDescriptor fd: Int32) {
    crashDiagnosticsWriteHeader(signalNumber: signalNumber, toFileDescriptor: fd)

    guard let frames = crashDiagnosticsFrames else { return }
    let frameCount = backtrace(frames, Int32(crashDiagnosticsMaxFrames))
    backtrace_symbols_fd(frames, frameCount, fd)
}

/// Renders `"<pre-rendered prefix>N\n"` into the pre-allocated header buffer
/// and emits it with a single `write(2)`. Hand-rolled decimal conversion,
/// never `"\(signalNumber)"`: Swift string interpolation heap-allocates,
/// and `withCString` may allocate a second buffer -- neither is safe on a
/// thread that may have trapped mid-allocation.
private func crashDiagnosticsWriteHeader(signalNumber: Int32, toFileDescriptor fd: Int32) {
    guard let header = crashDiagnosticsHeaderBuffer else { return }

    var length = crashDiagnosticsHeaderPrefixLength
    if signalNumber < 0, length < crashDiagnosticsHeaderCapacity {
        header[length] = CChar(bitPattern: UInt8(ascii: "-"))
        length += 1
    }

    // `magnitude` first, so `Int32.min` cannot trap on negation.
    let magnitude = UInt64(signalNumber.magnitude)
    var digitCount = 1
    var remainingDigits = magnitude / 10
    while remainingDigits > 0 {
        digitCount += 1
        remainingDigits /= 10
    }
    guard length + digitCount + 1 <= crashDiagnosticsHeaderCapacity else { return }

    var value = magnitude
    var index = length + digitCount
    for _ in 0..<digitCount {
        index -= 1
        header[index] = CChar(bitPattern: UInt8(ascii: "0") + UInt8(value % 10))
        value /= 10
    }
    length += digitCount
    header[length] = CChar(bitPattern: UInt8(ascii: "\n"))
    length += 1

    _ = write(fd, header, length)
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
#endif
