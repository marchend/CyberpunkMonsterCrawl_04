import Foundation
import os

/// The app's `os.Logger` handles, in one place so every subsystem string is
/// spelled once.
///
/// Exists because a swallowed error is only acceptable when it is still
/// *diagnosable* (PR #50 review): `HighScoreStore`'s reads and writes throw,
/// and deliberately distinguish `storedDataUnreadable` (a quarantined
/// payload) from `encodingFailed` -- a screen that drops that distinction on
/// the floor to keep rendering must at least leave a trace, otherwise
/// "the table is empty" and "the table could not be read" are indis-
/// tinguishable from the outside.
enum GameLog {

    /// Matches the app's bundle identifier (`project.yml`'s
    /// `PRODUCT_BUNDLE_IDENTIFIER`), so Console filters on the subsystem
    /// behave the way an engineer expects.
    private static let subsystem = "com.example.cyberpunkmonstercrawl"

    /// `HighScoreStore` reads/writes and anything else that touches durable
    /// player data.
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
}
