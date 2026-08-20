import Foundation

/// A permanent, legitimate test-only entry point (`CYBERPUN-17-13` PR 2):
/// lets a `.mothership` journey (or any other launch-time driver) jump
/// straight to a `GameState` that is otherwise slow -- or, for `.death`,
/// currently impossible -- to reach by driving the UI. `.death` has no
/// real in-game trigger yet (see AGENT.md/CLAUDE.md's own
/// "HP-reaches-zero -> `.death`" outstanding-work note), so without a hook
/// like this no journey could ever screenshot the death/high-scores
/// content this PR ships -- there would be no way to *reach* `.death` at
/// all short of dying, which nothing in the running app can currently do.
///
/// This is deliberately **not** scaffolding: it is permanent testability
/// infrastructure with no removal owner, the same category as
/// `-UITestMode`-style launch configuration on other platforms. It changes
/// nothing about a real player's launch -- absent both an argument and the
/// environment variable below, `resolve(...)` returns `nil` and
/// `GameViewController` does not touch the state machine beyond its normal
/// `.menu` start.
///
/// Reads from two independent sources, so whichever mechanism a given
/// driver uses to inject a query, this still catches it:
/// - A launch argument: either `-goto death` (two array elements, the
///   `-UITestMode`/`-goto` convention XCUITest launch configuration
///   already uses elsewhere in this project) or a single `goto=death`
///   argument (the query-string shape a `.mothership` journey's `query`
///   field is passed through as).
/// - The environment variable `GOTO_STATE` (`GOTO_STATE=death`).
enum LaunchGotoState {
    /// - Parameters:
    ///   - arguments: defaults to the real process arguments; overridable
    ///     for tests.
    ///   - environment: defaults to the real process environment;
    ///     overridable for tests.
    static func resolve(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> GameState? {
        if let envValue = environment["GOTO_STATE"], let state = state(named: envValue) {
            return state
        }

        for (index, argument) in arguments.enumerated() {
            if argument == "-goto", index + 1 < arguments.count, let state = state(named: arguments[index + 1]) {
                return state
            }
            if let range = argument.range(of: "goto="), let state = state(named: String(argument[range.upperBound...])) {
                return state
            }
        }

        return nil
    }

    private static func state(named name: String) -> GameState? {
        switch name.lowercased() {
        case "menu": return .menu
        case "gameplay": return .gameplay
        case "death": return .death
        case "highscores", "high-scores", "high_scores": return .highScores
        default: return nil
        }
    }
}
