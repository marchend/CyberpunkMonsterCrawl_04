import XCTest
@testable import CyberpunkMonsterCrawl

// SCAFFOLDING(CYBERPUN-17-13): deleted together with `LaunchGotoState`
// itself once the HP-reaches-zero -> `.death` trigger lands (see that
// file's marker) -- these tests exist only to keep the bridge honest while
// it stands, and must not become a reason to keep it.

/// `CYBERPUN-17-13` PR 2: `LaunchGotoState`'s parsing of the two
/// independent sources (`-goto <state>` / `goto=<state>` launch arguments,
/// and the `GOTO_STATE` environment variable) that let a `.mothership`
/// journey reach `.death`/`.highScores` without a real in-game trigger.
///
/// DEBUG-only, like the hook itself: `LaunchGotoState` is compiled out of
/// Release entirely, so there is nothing to test in a shipping build.
final class LaunchGotoStateTests: XCTestCase {

    func test_resolve_withNoArgumentsOrEnvironment_returnsNil() {
        XCTAssertNil(LaunchGotoState.resolve(arguments: ["/path/to/app"], environment: [:]))
    }

    func test_resolve_withTwoElementDashGotoArgument_returnsTheState() {
        XCTAssertEqual(
            LaunchGotoState.resolve(arguments: ["/path/to/app", "-goto", "death"], environment: [:]),
            .death
        )
    }

    func test_resolve_withEqualsSignArgument_returnsTheState() {
        XCTAssertEqual(
            LaunchGotoState.resolve(arguments: ["/path/to/app", "goto=highScores"], environment: [:]),
            .highScores
        )
    }

    func test_resolve_withEnvironmentVariable_returnsTheState() {
        XCTAssertEqual(
            LaunchGotoState.resolve(arguments: ["/path/to/app"], environment: ["GOTO_STATE": "gameplay"]),
            .gameplay
        )
    }

    func test_resolve_environmentTakesPrecedenceOverArguments() {
        XCTAssertEqual(
            LaunchGotoState.resolve(
                arguments: ["/path/to/app", "-goto", "menu"],
                environment: ["GOTO_STATE": "death"]
            ),
            .death
        )
    }

    func test_resolve_isCaseInsensitive_andAcceptsHyphenatedHighScores() {
        XCTAssertEqual(
            LaunchGotoState.resolve(arguments: ["/path/to/app", "-goto", "HIGH-SCORES"], environment: [:]),
            .highScores
        )
    }

    func test_resolve_withUnrecognizedValue_returnsNil() {
        XCTAssertNil(
            LaunchGotoState.resolve(arguments: ["/path/to/app", "-goto", "nonsense"], environment: [:])
        )
    }

    func test_resolve_dashGotoAsLastArgument_withNoFollowingValue_returnsNil() {
        XCTAssertNil(LaunchGotoState.resolve(arguments: ["/path/to/app", "-goto"], environment: [:]))
    }

    /// The inline spellings are matched as prefixes, not anywhere in the
    /// string: an argument that merely *contains* `goto=` (a negated flag,
    /// a bundled argument, a file path) must not launch the app into
    /// another state.
    func test_resolve_withGotoEqualsEmbeddedMidArgument_returnsNil() {
        XCTAssertNil(
            LaunchGotoState.resolve(arguments: ["/path/to/app", "--no-goto=death"], environment: [:])
        )
        XCTAssertNil(
            LaunchGotoState.resolve(arguments: ["/tmp/goto=death/app"], environment: [:])
        )
    }

    /// The `-goto=<state>` / `--goto=<state>` spellings are still accepted:
    /// tightening the match to a prefix must not drop a legitimate one.
    func test_resolve_withDashPrefixedInlineArgument_returnsTheState() {
        XCTAssertEqual(
            LaunchGotoState.resolve(arguments: ["/path/to/app", "-goto=death"], environment: [:]),
            .death
        )
        XCTAssertEqual(
            LaunchGotoState.resolve(arguments: ["/path/to/app", "--goto=menu"], environment: [:]),
            .menu
        )
    }
}
