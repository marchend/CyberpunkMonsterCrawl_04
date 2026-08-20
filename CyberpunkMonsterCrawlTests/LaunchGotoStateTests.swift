import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-13` PR 2: `LaunchGotoState`'s parsing of the two
/// independent sources (`-goto <state>` / `goto=<state>` launch arguments,
/// and the `GOTO_STATE` environment variable) that let a `.mothership`
/// journey reach `.death`/`.highScores` without a real in-game trigger.
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
}
