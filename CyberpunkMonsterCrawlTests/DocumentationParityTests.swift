import XCTest

/// `AGENT.md` and `CLAUDE.md` are the same document under two names — every
/// agent-facing edit has to land in both, and both are hand-edited today.
/// They have diverged zero times so far by luck, not by construction.
///
/// This turns the convention into a checked fact: the two files must stay
/// byte-identical, so a change made to one and forgotten in the other turns
/// the suite red instead of quietly leaving two disagreeing sets of
/// instructions in the repo. (A symlink or a generation step would remove the
/// hazard at the source; until the repo grows a doc build step, this is the
/// cheapest forcing function that lives inside the existing test target.)
///
/// Unreachable files fail rather than skip, for the same reason the AC 8
/// convention scan's anti-vacuity guard does: a gate that evaporates must not
/// read as a green suite.
final class DocumentationParityTests: XCTestCase {

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // CyberpunkMonsterCrawlTests/
            .deletingLastPathComponent() // repo root
    }

    func test_agentMarkdown_andClaudeMarkdown_areByteIdentical() {
        let agentURL = repoRoot.appendingPathComponent("AGENT.md")
        let claudeURL = repoRoot.appendingPathComponent("CLAUDE.md")

        guard let agent = try? Data(contentsOf: agentURL) else {
            XCTFail("AGENT.md is not readable at \(agentURL.path); the doc-parity gate is not running.")
            return
        }
        guard let claude = try? Data(contentsOf: claudeURL) else {
            XCTFail("CLAUDE.md is not readable at \(claudeURL.path); the doc-parity gate is not running.")
            return
        }

        XCTAssertFalse(agent.isEmpty, "AGENT.md is empty, so this comparison would pass vacuously.")

        guard agent != claude else { return }

        let agentLines = String(decoding: agent, as: UTF8.self).components(separatedBy: .newlines)
        let claudeLines = String(decoding: claude, as: UTF8.self).components(separatedBy: .newlines)
        let firstDifference = zip(agentLines, claudeLines)
            .enumerated()
            .first { $0.element.0 != $0.element.1 }

        if let difference = firstDifference {
            XCTFail(
                "AGENT.md and CLAUDE.md diverge at line \(difference.offset + 1):\n"
                    + "  AGENT.md:  \(difference.element.0)\n"
                    + "  CLAUDE.md: \(difference.element.1)\n"
                    + "They are the same document under two names — apply every edit to both."
            )
        } else {
            XCTFail(
                "AGENT.md (\(agentLines.count) lines) and CLAUDE.md (\(claudeLines.count) lines) "
                    + "share a common prefix but differ in length — apply every edit to both."
            )
        }
    }
}
