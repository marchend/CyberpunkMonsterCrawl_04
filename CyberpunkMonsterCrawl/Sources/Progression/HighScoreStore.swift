import Foundation

/// One persisted high-score table entry -- `score` plus enough of the
/// `RunSummary` a `HighScoreStore` recorded it from to render a highlighted
/// row on the high-scores screen (a later PR) without re-deriving anything
/// from run state that no longer exists once the run has ended.
struct HighScoreEntry: Codable, Equatable, Identifiable {
    let id: UUID
    let score: Int
    let survivedSeconds: Int
    let raccoonsDown: Int
    let level: Int
    let rabies: Int
    let damageDealt: Int
    let killBonus: Int
    let survivalBonus: Int

    init(id: UUID = UUID(), summary: RunSummary) {
        self.id = id
        self.score = summary.score
        self.survivedSeconds = summary.survivedSeconds
        self.raccoonsDown = summary.raccoonsDown
        self.level = summary.level
        self.rabies = summary.rabies
        self.damageDealt = summary.damageDealt
        self.killBonus = summary.killBonus
        self.survivalBonus = summary.survivalBonus
    }
}

/// `UserDefaults`-backed persisted high-score table (`CYBERPUN-17-13`),
/// consistent with the project's declared
/// `NSPrivacyAccessedAPICategoryUserDefaults` usage in `PrivacyInfo.xcprivacy`.
///
/// Always constructed over an explicit `UserDefaults` instance -- **never**
/// `.standard` implicitly -- so tests can hand each test case its own
/// isolated suite (a fresh `UserDefaults(suiteName:)`), proving both that a
/// brand-new suite starts empty and that entries survive a simulated
/// relaunch (a second `HighScoreStore` instance constructed over the same
/// suite) without leaking into any other test's storage.
final class HighScoreStore {

    /// Production suite name. `GameViewController` (a later PR) constructs
    /// the real store with `HighScoreStore(suiteName: HighScoreStore
    /// .productionSuiteName)` so every launch reads the same persisted
    /// table; tests always use their own unique suite name instead.
    static let productionSuiteName = "com.cyberpunkmonstercrawl.highScores"

    private static let storageKey = "CyberpunkMonsterCrawl.HighScoreStore.entries"

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Convenience initializer over a named `UserDefaults` suite. Falls back
    /// to `.standard` only if the suite genuinely cannot be constructed
    /// (`UserDefaults(suiteName:)` returns `nil` only for a malformed name),
    /// never as a silent default for production use.
    convenience init(suiteName: String) {
        self.init(defaults: UserDefaults(suiteName: suiteName) ?? .standard)
    }

    /// Appends a new entry built from `summary` and persists the updated
    /// table immediately.
    func recordRun(_ summary: RunSummary) {
        var entries = allEntries()
        entries.append(HighScoreEntry(summary: summary))
        persist(entries)
    }

    /// All persisted entries, sorted by `score` descending. Ties keep
    /// insertion order (a stable sort), so two equal scores read back in
    /// the order they were recorded.
    func sortedEntries() -> [HighScoreEntry] {
        allEntries().sorted { $0.score > $1.score }
    }

    private func allEntries() -> [HighScoreEntry] {
        guard let data = defaults.data(forKey: Self.storageKey) else { return [] }
        return (try? JSONDecoder().decode([HighScoreEntry].self, from: data)) ?? []
    }

    private func persist(_ entries: [HighScoreEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
