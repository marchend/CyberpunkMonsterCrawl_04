import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-9` PR 1: `TargetSelection`'s pure nearest-living-raccoon
/// rule \u2014 the targeting half of the auto-fire decision layer.
final class TargetSelectionTests: XCTestCase {

    private func candidate(atTileX tileX: Double, tileY: Double = 0, hp: Int? = nil) -> TargetSelection.Candidate {
        let raccoon = RaccoonNode(tier: .base, hp: hp)
        return TargetSelection.Candidate(raccoon: raccoon, position: TilePoint(x: tileX, y: tileY))
    }

    // MARK: - Nearest-living selection among several distances

    func test_selectsTheNearestCandidate_amongSeveralAtVaryingDistances() {
        let origin = TilePoint(x: 0, y: 0)
        let near = candidate(atTileX: 2)
        let mid = candidate(atTileX: 4)
        let far = candidate(atTileX: 6)

        let selected = TargetSelection.nearestLivingTarget(
            from: origin,
            raccoons: [far, mid, near],
            maxRange: 10
        )

        XCTAssertTrue(selected === near.raccoon, "must select the candidate at the smallest tile-space distance")
    }

    // MARK: - Out-of-range candidates excluded

    func test_outOfRangeCandidate_isExcluded_inFavorOfAnInRangeCandidate() {
        let origin = TilePoint(x: 0, y: 0)
        let inRange = candidate(atTileX: 4)
        let outOfRange = candidate(atTileX: 6)

        let selected = TargetSelection.nearestLivingTarget(
            from: origin,
            raccoons: [outOfRange, inRange],
            maxRange: 5
        )

        XCTAssertTrue(selected === inRange.raccoon)
    }

    func test_allCandidatesOutOfRange_returnsNil() {
        let origin = TilePoint(x: 0, y: 0)
        let far1 = candidate(atTileX: 20)
        let far2 = candidate(atTileX: -30)

        let selected = TargetSelection.nearestLivingTarget(
            from: origin,
            raccoons: [far1, far2],
            maxRange: 5
        )

        XCTAssertNil(selected)
    }

    func test_emptyCandidateList_returnsNil() {
        let selected = TargetSelection.nearestLivingTarget(
            from: TilePoint(x: 0, y: 0),
            raccoons: [],
            maxRange: 10
        )

        XCTAssertNil(selected)
    }

    // MARK: - Dead raccoons are never selected

    func test_deadCandidate_isExcluded_evenWhenItIsTheNearestOverall() {
        let origin = TilePoint(x: 0, y: 0)
        let dead = candidate(atTileX: 1, hp: 0)
        let alive = candidate(atTileX: 5)

        let selected = TargetSelection.nearestLivingTarget(
            from: origin,
            raccoons: [dead, alive],
            maxRange: 10
        )

        XCTAssertTrue(selected === alive.raccoon)
    }

    func test_onlyDeadCandidatesInRange_returnsNil() {
        let origin = TilePoint(x: 0, y: 0)
        let dead = candidate(atTileX: 1, hp: 0)

        let selected = TargetSelection.nearestLivingTarget(
            from: origin,
            raccoons: [dead],
            maxRange: 10
        )

        XCTAssertNil(selected)
    }

    // MARK: - Re-targeting when the current nearest target dies mid-tick

    func test_whenTheCurrentNearestRaccoonDies_theNextCallSelectsTheNextNearestLivingOne() {
        let origin = TilePoint(x: 0, y: 0)
        let nearest = candidate(atTileX: 2)
        let nextNearest = candidate(atTileX: 4)
        let pool = [nearest, nextNearest]

        let firstSelection = TargetSelection.nearestLivingTarget(from: origin, raccoons: pool, maxRange: 10)
        XCTAssertTrue(firstSelection === nearest.raccoon)

        // Kill the previously-selected nearest raccoon, mid-tick.
        nearest.raccoon.takeDamage(nearest.raccoon.hp)
        XCTAssertTrue(nearest.raccoon.isDead)

        let secondSelection = TargetSelection.nearestLivingTarget(from: origin, raccoons: pool, maxRange: 10)
        XCTAssertTrue(secondSelection === nextNearest.raccoon, "must re-target to the next nearest living raccoon once the previous target has died")
    }
}
