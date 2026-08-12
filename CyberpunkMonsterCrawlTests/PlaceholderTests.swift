import XCTest
@testable import CyberpunkMonsterCrawl

/// Bootstrap proof-of-life (PR 1 of CYBERPUN-17-1): a trivial, compiling
/// test that proves the `CyberpunkMonsterCrawlTests` target links against
/// the `CyberpunkMonsterCrawl` app module via `@testable import` before any
/// real feature coverage lands. Kept intentionally separate from
/// `CyberpunkMonsterCrawlTests.swift` (which already exercises
/// `GameViewController` from the earlier project bootstrap) so this file's
/// only job is the scaffold's own CI gate: does the test target compile and
/// pass at all.
final class PlaceholderTests: XCTestCase {
    func test_placeholder_trivialAssertionPasses() {
        XCTAssertEqual(1 + 1, 2)
    }

    func test_testTargetLinksAgainstAppModule() {
        // Referencing a real app-module symbol (not just a literal) proves
        // `@testable import CyberpunkMonsterCrawl` actually resolves.
        let scene = BootScene(size: CGSize(width: 100, height: 100))
        XCTAssertNotNil(scene)
    }
}
