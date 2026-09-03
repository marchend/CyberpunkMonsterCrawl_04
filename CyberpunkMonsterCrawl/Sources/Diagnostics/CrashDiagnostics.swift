import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// SCAFFOLDING(CYBERPUN-17-11): temporary crash-capture harness, reintroduced
/// to close the evidence gap the runtime probe's `pickup-spawn` journey
/// exposed -- it reports the app process gone at step 6 (~12s past PLAY) and
/// step 9 (~18s past PLAY), both landing shortly after `PickupKind`'s frozen
/// 8s first-spawn delay fires, i.e. right around when the first `Pickup` is
/// created and the first `PickupNode` is constructed/mounted.
///
/// A full static read of the pickup path -- `PickupManager` (spawn timing,
/// placement search, collection queries), `PickupNode` (icon/pad
/// construction, texture cropping via `SpriteSheet.texture(col:row:)`,
/// already independently pinned for `AtlasSheet.pickups` by
/// `AtlasDimensionsTests`), `GameScene`'s pickup wiring, and
/// `RaccoonSpawnDirector`'s per-frame pickup queries -- found no reachable
/// force-unwrap, array-index, or `precondition`/`fatalError` trap. This
/// mirrors `CYBERPUN-17-10-t5`'s equally inconclusive static audit of its
/// own then-unidentified pulse-ability crash: static review alone was not
/// enough there either, and what closed the gap was a symbolicated crash log
/// from a real probe run.
///
/// This file exists ONLY to produce that evidence. It installs POSIX signal
/// handlers for the signals a Swift trap or memory violation actually
/// raises, plus an uncaught-`NSException` handler, and persists a
/// symbolicated backtrace of the crashing thread to `last-crash.log` in the
/// Caches directory before re-raising so the process still terminates
/// exactly as it would without this file. It does not change, and must not
/// be extended to change, any pickup spawn/placement/render behavior.
///
/// Removal owner: once a probe run leaves a `last-crash.log` naming the
/// actual crashing frame, file the real root-cause ticket, fix it, and
/// delete this file plus its `AppDelegate` call site -- mirroring
/// `CYBERPUN-17-10-t6`'s close-out of the identical harness filed against
/// that story.
///
/// Gated `#if DEBUG` at file scope (in addition to the `AppDelegate` call
/// site) so no release binary has its process-wide signal dispositions or
/// `NSSetUncaughtExceptionHandler` replaced by a debugging aid nobody owns.
#if DEBUG
enum CrashDiagnostics {

    /// Name of the crash report written under the Caches directory.
    static let logFileName = "last-crash.log"

    /// Signals a Swift `precondition`/`fatalError`/force-unwrap/array-out-
    /// of-bounds trap or a memory violation actually raises.
    ///
    /// A stack-overflow `SIGSEGV` is NOT reliably covered here: no
    /// `sigaltstack` is installed, so a handler invoked on an already-
    /// exhausted stack may itself fault before writing anything. Accepted
    /// for this scoped, temporary diagnostic -- recorded here so nobody
    /// assumes coverage it doesn't have.
    private static let handledSignals: [Int32] = [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGTRAP]

    /// Pre-allocated once, at `install()` time, so the signal handler body
    /// itself never calls `malloc` -- which is not async-signal-safe. A
    /// handler that deadlocks on the allocator's lock would leave the probe
    /// with neither a trace nor a clean crash.
    private static let frameBufferCapacity: Int32 = 64
    private static let frameBuffer = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(
        capacity: Int(frameBufferCapacity)
    )

    /// Small fixed buffer for the hand-rolled "Signal: N\n" line. 32 bytes
    /// comfortably covers "Signal: " (8) + the longest `Int32` decimal
    /// rendering (11, including a sign) + the trailing newline (1).
    private static let signalLineCapacity = 32
    private static let signalLineBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: signalLineCapacity)

    /// Opened once by `install()` and kept open for the process lifetime, so
    /// the signal handler only ever has to `write(2)`, never `open(2)`.
    private static var logFileDescriptor: Int32 = -1

    /// The report header's raw bytes, assembled once by `install()` --
    /// never inside a signal handler -- so no string formatting happens at
    /// crash time.
    private static var headerBuffer: UnsafeMutablePointer<UInt8>?
    private static var headerLength = 0

    /// Installs the crash-capture hooks. Call once, at launch, before any
    /// other subsystem stands up its own state (this repo's `AppDelegate`
    /// calls this before `SceneDelegate` builds `GameViewController`/
    /// `GameScene`).
    static func install() {
        let url = logFileURL()
        clearExistingReport(at: url)

        let descriptor = url.path.withCString { path in
            open(path, O_CREAT | O_WRONLY | O_TRUNC, 0o644)
        }
        guard descriptor >= 0 else { return }
        logFileDescriptor = descriptor

        let launchStamp = ISO8601DateFormatter().string(from: Date())
        let header = "CrashDiagnostics report -- process launched \(launchStamp)\n"
        let headerUTF8 = Array(header.utf8)
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: headerUTF8.count)
        buffer.update(from: headerUTF8, count: headerUTF8.count)
        headerBuffer = buffer
        headerLength = headerUTF8.count

        for signalNumber in handledSignals {
            signal(signalNumber, CrashDiagnostics.handleSignal)
        }
        NSSetUncaughtExceptionHandler(CrashDiagnostics.handleUncaughtException)
    }

    /// Where the report lives: `<Caches>/last-crash.log`.
    static func logFileURL() -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent(logFileName)
    }

    /// Deletes any report a previous launch left behind. Called by
    /// `install()` before either hook is armed, so a launch that does not
    /// crash leaves no report and a probe can never mistake a stale,
    /// multiple-runs-old trace for evidence of the current run.
    static func clearExistingReport(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Writes `report` to `fileDescriptor`, leaving it open (the caller owns
    /// closing it). Backed by a plain `write(2)`, which is itself
    /// async-signal-safe, so this is safe to call from the uncaught-
    /// exception handler and directly from tests against an explicit
    /// destination -- `CrashDiagnosticsTests` never opens the real Caches
    /// path.
    static func persist(_ report: String, to fileDescriptor: Int32) {
        guard fileDescriptor >= 0 else { return }
        let bytes = Array(report.utf8)
        bytes.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            _ = write(fileDescriptor, base, buffer.count)
        }
    }

    // MARK: - Signal handling (must stay allocation-free in the handler body)

    private static let handleSignal: @convention(c) (Int32) -> Void = { signalNumber in
        guard CrashDiagnostics.logFileDescriptor >= 0 else {
            signal(signalNumber, SIG_DFL)
            raise(signalNumber)
            return
        }

        CrashDiagnostics.writeHeaderBytes()
        CrashDiagnostics.writeSignalLine(signalNumber)

        let frameCount = backtrace(CrashDiagnostics.frameBuffer, CrashDiagnostics.frameBufferCapacity)
        backtrace_symbols_fd(CrashDiagnostics.frameBuffer, frameCount, CrashDiagnostics.logFileDescriptor)
        close(CrashDiagnostics.logFileDescriptor)

        // Restore the default disposition and re-raise so the process still
        // terminates exactly as it would have without this handler.
        signal(signalNumber, SIG_DFL)
        raise(signalNumber)
    }

    private static let handleUncaughtException: @convention(c) (NSException) -> Void = { exception in
        guard CrashDiagnostics.logFileDescriptor >= 0 else { return }
        CrashDiagnostics.writeHeaderBytes()
        CrashDiagnostics.persist(
            "Uncaught NSException: \(exception.name.rawValue): \(exception.reason ?? "")\n",
            to: CrashDiagnostics.logFileDescriptor
        )
        for symbol in exception.callStackSymbols {
            CrashDiagnostics.persist(symbol + "\n", to: CrashDiagnostics.logFileDescriptor)
        }
        close(CrashDiagnostics.logFileDescriptor)
    }

    /// Writes the precomputed header bytes. No formatting happens here --
    /// they were assembled once by `install()`.
    private static func writeHeaderBytes() {
        guard let buffer = headerBuffer else { return }
        _ = write(logFileDescriptor, buffer, headerLength)
    }

    /// Renders `signalNumber` as decimal digits by hand, into the
    /// pre-allocated `signalLineBuffer`. `String` interpolation routes
    /// through allocating formatting machinery, which is not
    /// async-signal-safe; this writes bytes directly instead.
    private static func writeSignalLine(_ signalNumber: Int32) {
        var length = 0

        let prefix: StaticString = "Signal: "
        prefix.withUTF8Buffer { utf8 in
            for byte in utf8 {
                signalLineBuffer[length] = byte
                length += 1
            }
        }

        let digitsStart = length
        var value = signalNumber
        if value <= 0 {
            signalLineBuffer[length] = UInt8(ascii: "0")
            length += 1
        } else {
            while value > 0 {
                signalLineBuffer[length] = UInt8(ascii: "0") + UInt8(value % 10)
                length += 1
                value /= 10
            }
            var left = digitsStart
            var right = length - 1
            while left < right {
                let tmp = signalLineBuffer[left]
                signalLineBuffer[left] = signalLineBuffer[right]
                signalLineBuffer[right] = tmp
                left += 1
                right -= 1
            }
        }

        signalLineBuffer[length] = UInt8(ascii: "\n")
        length += 1

        _ = write(logFileDescriptor, signalLineBuffer, length)
    }
}
#endif
