import Foundation

// SCAFFOLDING(CYBERPUN-17-13): a bridge over a known gap, not permanent
// infrastructure. This whole file exists only because `.death` has no real
// in-game trigger yet -- AGENT.md/CLAUDE.md's own "HP-reaches-zero ->
// `.death`" outstanding-work note (the trigger has no ticket ID filed yet;
// see the `CYBERPUN-17-8` entry there) is the follow-up that removes the
// need for it. Once a player can actually die, a journey reaches `.death`
// by dying and this hook, its `GameViewController` call site and
// `LaunchGotoStateTests` should all be deleted together.

#if DEBUG
/// A DEBUG-only test entry point (`CYBERPUN-17-13` PR 2): lets a
/// `.mothership` journey (or any other launch-time driver) jump straight to
/// a `GameState` that is otherwise slow -- or, for `.death`, currently
/// impossible -- to reach by driving the UI. Without a hook like this no
/// journey could screenshot the death/high-scores content this PR ships:
/// there is no way to *reach* `.death` short of dying, which nothing in the
/// running app can currently do.
///
/// **Compiled out of Release entirely.** The whole type lives inside
/// `#if DEBUG`, as does `GameViewController`'s call into it, so a shipped
/// App Store binary launched with `GOTO_STATE=death` (or `-goto death`)
/// cannot jump past the menu into a state the product never exposes -- the
/// same gating every other test-only affordance in this scene uses
/// (`assertSceneInvariants()` is `#if DEBUG` at all four call sites). It
/// also changes nothing about a real DEBUG launch: absent both an argument
/// and the environment variable below, `resolve(...)` returns `nil` and
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
    /// The launch-argument spellings that carry the state inline. Matched
    /// as **prefixes**, never anywhere-in-the-string: a substring match
    /// would also fire on an unrelated argument that merely contains
    /// `goto=` (`--no-goto=death`, a bundled argument, a file path).
    private static let inlinePrefixes = ["goto=", "-goto=", "--goto="]

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
            for prefix in inlinePrefixes where argument.hasPrefix(prefix) {
                if let state = state(named: String(argument.dropFirst(prefix.count))) {
                    return state
                }
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
#endif
