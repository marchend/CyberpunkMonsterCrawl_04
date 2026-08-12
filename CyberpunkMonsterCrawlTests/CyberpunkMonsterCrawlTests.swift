import XCTest
@testable import CyberpunkMonsterCrawl

final class CyberpunkMonsterCrawlTests: XCTestCase {
    /// Bootstrap proof-of-life: test target compiles + links against the
    /// app module. Real behavior tests (state machine, depth ordering,
    /// atlas contract, world generation) belong in feature stories.
    func test_rootViewController_initializes() {
        _ = GameViewController()
    }
}
