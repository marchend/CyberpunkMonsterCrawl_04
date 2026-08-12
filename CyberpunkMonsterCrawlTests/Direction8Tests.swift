import CoreGraphics
import XCTest
@testable import CyberpunkMonsterCrawl

/// CYBERPUN-17-6 PR 1: direction binning at the 8 principal vectors, plus
/// the sector-boundary angles between each pair of neighbours.
final class Direction8Tests: XCTestCase {

    // MARK: - The 8 principal vectors

    func test_from_south_binsToSouth() {
        XCTAssertEqual(Direction8.from(vector: CGVector(dx: 0, dy: 1)), .south)
    }

    func test_from_southeast_binsToSoutheast() {
        XCTAssertEqual(Direction8.from(vector: CGVector(dx: 1, dy: 1)), .southeast)
    }

    func test_from_east_binsToEast() {
        XCTAssertEqual(Direction8.from(vector: CGVector(dx: 1, dy: 0)), .east)
    }

    func test_from_northeast_binsToNortheast() {
        XCTAssertEqual(Direction8.from(vector: CGVector(dx: 1, dy: -1)), .northeast)
    }

    func test_from_north_binsToNorth() {
        XCTAssertEqual(Direction8.from(vector: CGVector(dx: 0, dy: -1)), .north)
    }

    func test_from_northwest_binsToNorthwest() {
        XCTAssertEqual(Direction8.from(vector: CGVector(dx: -1, dy: -1)), .northwest)
    }

    func test_from_west_binsToWest() {
        XCTAssertEqual(Direction8.from(vector: CGVector(dx: -1, dy: 0)), .west)
    }

    func test_from_southwest_binsToSouthwest() {
        XCTAssertEqual(Direction8.from(vector: CGVector(dx: -1, dy: 1)), .southwest)
    }

    // MARK: - Magnitude independence

    func test_from_scalesTheSameVectorLarger_stillBinsToTheSameSector() {
        XCTAssertEqual(Direction8.from(vector: CGVector(dx: 0, dy: 100)), .south)
        XCTAssertEqual(Direction8.from(vector: CGVector(dx: -0.01, dy: 0.01)), .southwest)
    }

    // MARK: - Zero vector leaves facing unchanged

    func test_from_zeroVector_returnsNil() {
        XCTAssertNil(Direction8.from(vector: CGVector(dx: 0, dy: 0)))
    }

    // MARK: - Sector boundaries

    /// Builds a vector whose "clockwise-from-south" angle is exactly
    /// `degreesFromSouth`, using the same `atan2(dy, dx) - 90\u00b0` convention
    /// `Direction8.from(vector:)` uses internally \u2014 i.e. this is the exact
    /// inverse of that transform, not a second, independently-guessed one.
    private func vector(degreesFromSouth: Double) -> CGVector {
        let theta = (degreesFromSouth + 90) * .pi / 180
        return CGVector(dx: CGFloat(cos(theta)), dy: CGFloat(sin(theta)))
    }

    /// Every boundary sits exactly halfway between two neighbouring
    /// directions' 45\u00b0-spaced centers (22.5\u00b0, 67.5\u00b0, \u2026). The production
    /// rule rounds half away from zero, so each boundary resolves to the
    /// **next** direction clockwise, never the previous one \u2014 this is what
    /// pins the 22.5\u00b0 sector offset the story calls for, rather than just
    /// re-testing the 8 sector centers a second time.
    func test_sectorBoundaries_resolveToTheNextDirectionClockwise() {
        let boundaries: [(degrees: Double, expected: Direction8)] = [
            (22.5, .southwest),
            (67.5, .west),
            (112.5, .northwest),
            (157.5, .north),
            (202.5, .northeast),
            (247.5, .east),
            (292.5, .southeast),
            (337.5, .south),
        ]

        for (degrees, expected) in boundaries {
            let resolved = Direction8.from(vector: vector(degreesFromSouth: degrees))
            XCTAssertEqual(
                resolved,
                expected,
                "Boundary at \(degrees)\u{00b0} from south should resolve to \(expected), got \(String(describing: resolved))."
            )
        }
    }

    /// A point just short of a boundary stays on the earlier side.
    func test_justShortOfABoundary_staysOnTheEarlierSide() {
        XCTAssertEqual(Direction8.from(vector: vector(degreesFromSouth: 22.4)), .south)
        XCTAssertEqual(Direction8.from(vector: vector(degreesFromSouth: 67.4)), .southwest)
        XCTAssertEqual(Direction8.from(vector: vector(degreesFromSouth: 337.4)), .southeast)
    }

    /// A point just past a boundary moves to the later side.
    func test_justPastABoundary_movesToTheLaterSide() {
        XCTAssertEqual(Direction8.from(vector: vector(degreesFromSouth: 22.6)), .southwest)
        XCTAssertEqual(Direction8.from(vector: vector(degreesFromSouth: 67.6)), .west)
    }

    // MARK: - No player-specific coupling

    /// `Direction8` must be importable by future actor code (raccoons,
    /// CYBERPUN-17-8) unchanged \u2014 pinned here by asserting it carries no
    /// sprite-sheet knowledge of its own: exactly 8 cases, nothing else.
    func test_direction8_hasExactlyEightCasesAndNoAssociatedData() {
        XCTAssertEqual(Direction8.allCases.count, 8)
    }
}
