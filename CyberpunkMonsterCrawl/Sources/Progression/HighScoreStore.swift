import Foundation

/// One persisted high-score table entry -- `score` plus enough of the
/// `RunSummary` a `HighScoreStore` recorded it from to render a highlighted
/// row on the high-scores screen (a later PR) without re-deriving anything
/// from run state that no longer exists once the run has ended.
///
/// Decoding is deliberately **tolerant**: only `score` is required, every
/// other key falls back to a default when absent. That is what lets a table
/// written by an older build (which had fewer keys) keep decoding after this
/// story's UI PR adds a field -- without it, one added non-optional property
/// makes every previously-persisted table undecodable and silently wipes an
/// existing player's history on upgrade (PR #49 review).
struct HighScoreEntry: Codable, Equatable, Identifiable {
    let id: UUID

    /// Record order within the table, monotonically increasing per store:
    /// the tie-break that makes `sortedEntries()` a **deterministic** total
    /// order. `sorted(by:)` is an introsort with no stability guarantee, so
    /// without this two equal scores could swap places between two reads of
    /// the same data -- and the story's "highlight the current run" AC needs
    /// a row identity that does not move (PR #49 review).
    ///
    /// Entries decoded from a v1 payload (written before this key existed)
    /// default to `0` and fall back to the `id` tie-break below.
    let sequence: Int

    let score: Int
    let survivedSeconds: Int
    let raccoonsDown: Int
    let level: Int
    let rabies: Int
    let damageDealt: Int
    let killBonus: Int
    let survivalBonus: Int

    init(id: UUID = UUID(), sequence: Int, summary: RunSummary) {
        self.id = id
        self.sequence = sequence
        self.score = summary.score
        self.survivedSeconds = summary.survivedSeconds
        self.raccoonsDown = summary.raccoonsDown
        self.level = summary.level
        self.rabies = summary.rabies
        self.damageDealt = summary.damageDealt
        self.killBonus = summary.killBonus
        self.survivalBonus = summary.survivalBonus
    }

    private enum CodingKeys: String, CodingKey {
        case id, sequence, score, survivedSeconds, raccoonsDown, level
        case rabies, damageDealt, killBonus, survivalBonus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // `score` is the one key without a meaningful default -- a payload
        // missing it is not an older schema, it is corrupt, and the store
        // must be able to tell those apart.
        score = try container.decode(Int.self, forKey: .score)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        sequence = try container.decodeIfPresent(Int.self, forKey: .sequence) ?? 0
        survivedSeconds = try container.decodeIfPresent(Int.self, forKey: .survivedSeconds) ?? 0
        raccoonsDown = try container.decodeIfPresent(Int.self, forKey: .raccoonsDown) ?? 0
        level = try container.decodeIfPresent(Int.self, forKey: .level) ?? 1
        rabies = try container.decodeIfPresent(Int.self, forKey: .rabies) ?? 0
        damageDealt = try container.decodeIfPresent(Int.self, forKey: .damageDealt) ?? 0
        killBonus = try container.decodeIfPresent(Int.self, forKey: .killBonus) ?? 0
        survivalBonus = try container.decodeIfPresent(Int.self, forKey: .survivalBonus) ?? 0
    }
}

/// Why a `HighScoreStore` read or write did not do what the caller asked.
/// Surfaced rather than swallowed: this is the only durable copy of data the
/// player cares about, so "nothing was written" must never read as success
/// (PR #49 review).
enum HighScoreStoreError: Error, Equatable {
    /// A payload is present under the storage key but no supported schema
    /// decodes it. Deliberately distinct from "no scores yet" (`[]`).
    case storedDataUnreadable
    /// The table could not be encoded, so **nothing was persisted**.
    case encodingFailed
}

/// What `recordRun` actually did, beyond succeeding.
enum HighScoreRecordOutcome: Equatable {
    /// The run was appended to a table that read back cleanly.
    case recorded
    /// The stored payload could not be decoded, so it was copied to
    /// `HighScoreStore.unreadableBackupKey` (preserved, not destroyed) and
    /// the run was recorded into a fresh table.
    case recordedAfterQuarantiningUnreadableTable
}

/// `UserDefaults`-backed persisted high-score table (`CYBERPUN-17-13`),
/// consistent with the project's declared
/// `NSPrivacyAccessedAPICategoryUserDefaults` usage in `PrivacyInfo.xcprivacy`.
///
/// Always constructed over an explicit `UserDefaults` instance -- **never**
/// `.standard`, not even as a fallback -- so tests can hand each test case
/// its own isolated suite (a fresh `UserDefaults(suiteName:)`), proving both
/// that a brand-new suite starts empty and that entries survive a simulated
/// relaunch (a second `HighScoreStore` instance constructed over the same
/// suite) without leaking into any other test's storage.
///
/// This is a **bounded top-N table**, not a run log: `recordRun` ranks and
/// trims to `maxEntries` on every write, so the stored blob (decoded and
/// re-encoded on the main thread at death-screen entry) stays a fixed size
/// however many runs the player finishes.
final class HighScoreStore {

    /// Production suite name. `GameViewController` (a later PR) constructs
    /// the real store with `HighScoreStore(suiteName: HighScoreStore
    /// .productionSuiteName)` so every launch reads the same persisted
    /// table; tests always use their own unique suite name instead.
    ///
    /// Must not equal the app's bundle identifier or `NSGlobalDomain` --
    /// `UserDefaults(suiteName:)` returns `nil` for both, which the failable
    /// `init?(suiteName:)` below turns into a visible construction failure
    /// instead of scores quietly landing in `.standard`.
    static let productionSuiteName = "com.cyberpunkmonstercrawl.highScores"

    /// Rows kept by the table. The high-scores screen is a leaderboard, so
    /// history beyond this is discarded at write time rather than left to
    /// grow unbounded under a UI that only ever shows the top rows.
    static let defaultMaxEntries = 10

    /// Internal (not private) so `HighScoreStoreTests` can plant a v1-shaped
    /// payload and a corrupt blob directly under the real key.
    static let storageKey = "CyberpunkMonsterCrawl.HighScoreStore.entries"

    /// Where an undecodable payload is copied before it is replaced, so a
    /// decode failure never destroys data that a later build (or a support
    /// request) might still recover.
    static let unreadableBackupKey = "CyberpunkMonsterCrawl.HighScoreStore.entries.unreadable"

    let maxEntries: Int

    private let defaults: UserDefaults

    init(defaults: UserDefaults, maxEntries: Int = HighScoreStore.defaultMaxEntries) {
        precondition(maxEntries > 0, "a high-score table that holds no rows cannot record a score")
        self.defaults = defaults
        self.maxEntries = maxEntries
    }

    /// Convenience initializer over a named `UserDefaults` suite.
    ///
    /// **Failable on purpose.** `UserDefaults(suiteName:)` returns `nil` for
    /// a malformed name, for the app's own bundle identifier and for
    /// `NSGlobalDomain`; the previous revision fell back to `.standard`,
    /// which produced a working-looking store no caller could distinguish
    /// from a correctly configured one, with the player's scores landing in
    /// the shared standard domain forever. A misconfiguration is now visible
    /// at the call site instead of surfacing later as "my scores vanished".
    convenience init?(suiteName: String, maxEntries: Int = HighScoreStore.defaultMaxEntries) {
        guard let suite = UserDefaults(suiteName: suiteName) else { return nil }
        self.init(defaults: suite, maxEntries: maxEntries)
    }

    /// Records `summary`, then ranks and trims the table to `maxEntries`.
    ///
    /// - Returns: `.recorded`, or
    ///   `.recordedAfterQuarantiningUnreadableTable` when an undecodable
    ///   payload had to be set aside first (the old bytes are preserved
    ///   under `unreadableBackupKey`, never overwritten in place).
    /// - Throws: `HighScoreStoreError.encodingFailed` when the table cannot
    ///   be encoded -- the caller learns nothing was written rather than
    ///   being told the run was saved.
    @discardableResult
    func recordRun(_ summary: RunSummary) throws -> HighScoreRecordOutcome {
        var outcome = HighScoreRecordOutcome.recorded
        var entries: [HighScoreEntry]
        do {
            entries = try loadEntries()
        } catch HighScoreStoreError.storedDataUnreadable {
            quarantineUnreadablePayload()
            entries = []
            outcome = .recordedAfterQuarantiningUnreadableTable
        }

        // Strictly greater than every sequence currently in the table, so
        // record order stays unique even after a trim dropped earlier rows.
        let nextSequence = (entries.map(\.sequence).max() ?? -1) + 1
        entries.append(HighScoreEntry(sequence: nextSequence, summary: summary))

        try persist(Self.ranked(entries, limitedTo: maxEntries))
        return outcome
    }

    /// The table's rows, best first, capped at `maxEntries`.
    ///
    /// Ordering is a deterministic total order -- `score` descending, then
    /// `sequence` ascending (the earlier-recorded run wins a tie), then `id`
    /// -- so equal scores read back in the same order every time. This is
    /// enforced by the comparator, *not* assumed of `sorted(by:)`, which
    /// documents the order of equal elements as unspecified.
    ///
    /// - Throws: `HighScoreStoreError.storedDataUnreadable` when a payload
    ///   is present but undecodable.
    func sortedEntries() throws -> [HighScoreEntry] {
        Self.ranked(try loadEntries(), limitedTo: maxEntries)
    }

    /// Every persisted entry, in stored order.
    ///
    /// - Throws: `HighScoreStoreError.storedDataUnreadable`. "No payload at
    ///   all" returns `[]`; "a payload that will not decode" throws. The
    ///   previous revision collapsed both to `[]`, which let `recordRun`
    ///   append to the empty array and overwrite the undecodable blob.
    func loadEntries() throws -> [HighScoreEntry] {
        guard let data = defaults.data(forKey: Self.storageKey) else { return [] }

        let decoder = JSONDecoder()
        if let table = try? decoder.decode(StoredTable.self, from: data) {
            return table.entries
        }
        // v1 payloads were a bare `[HighScoreEntry]` array with no version
        // key. Still readable, and rewritten in the current shape on the
        // next `recordRun`.
        if let legacyEntries = try? decoder.decode([HighScoreEntry].self, from: data) {
            return legacyEntries
        }
        throw HighScoreStoreError.storedDataUnreadable
    }

    /// Removes the table and any quarantined payload -- the reset
    /// affordance; there was previously no way to remove an entry once
    /// written.
    func clear() {
        defaults.removeObject(forKey: Self.storageKey)
        defaults.removeObject(forKey: Self.unreadableBackupKey)
    }

    /// The deterministic ranking applied on every read and every write.
    static func ranked(_ entries: [HighScoreEntry], limitedTo maxEntries: Int) -> [HighScoreEntry] {
        Array(entries.sorted(by: isRankedBefore).prefix(maxEntries))
    }

    private static func isRankedBefore(_ lhs: HighScoreEntry, _ rhs: HighScoreEntry) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        if lhs.sequence != rhs.sequence { return lhs.sequence < rhs.sequence }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func quarantineUnreadablePayload() {
        guard let data = defaults.data(forKey: Self.storageKey) else { return }
        defaults.set(data, forKey: Self.unreadableBackupKey)
    }

    private func persist(_ entries: [HighScoreEntry]) throws {
        let table = StoredTable(version: StoredTable.currentVersion, entries: entries)
        guard let data = try? JSONEncoder().encode(table) else {
            throw HighScoreStoreError.encodingFailed
        }
        defaults.set(data, forKey: Self.storageKey)
    }

    /// The persisted payload: a schema `version` alongside the entries, so a
    /// future shape change can be detected and migrated rather than read as
    /// corruption.
    private struct StoredTable: Codable {
        static let currentVersion = 2
        let version: Int
        let entries: [HighScoreEntry]
    }
}
