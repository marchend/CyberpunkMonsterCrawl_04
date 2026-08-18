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

        XCTAssertTrue(selected?.raccoon === near.raccoon, "must select the candidate at the smallest tile-space distance")
        XCTAssertEqual(selected?.position.x, near.position.x, "the winning candidate's tile position must travel with the selection")
        XCTAssertEqual(selected?.position.y, near.position.y)
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

        XCTAssertTrue(selected?.raccoon === inRange.raccoon)
    }

    // MARK: - The range boundary is inclusive

    func test_candidateAtExactlyMaxRange_isInRange() {
        let origin = TilePoint(x: 0, y: 0)
        let atBoundary = candidate(atTileX: 5)

        let selected = TargetSelection.nearestLivingTarget(
            from: origin,
            raccoons: [atBoundary],
            maxRange: 5
        )

        XCTAssertTrue(
            selected?.raccoon === atBoundary.raccoon,
            "the documented range rule is inclusive (distance <= maxRange): a candidate at exactly maxRange must be selectable"
        )
    }

    func test_candidateJustBeyondMaxRange_isExcluded() {
        let origin = TilePoint(x: 0, y: 0)
        let justOutside = candidate(atTileX: 5.0001)

        let selected = TargetSelection.nearestLivingTarget(
            from: origin,
            raccoons: [justOutside],
            maxRange: 5
        )

        XCTAssertNil(selected, "a candidate beyond maxRange must be excluded, pinning the boundary from the other side")
    }

    // MARK: - Ties resolve to the first candidate in the array

    func test_twoCandidatesAtEqualDistance_selectsWhicheverAppearsFirstInTheArray() {
        let origin = TilePoint(x: 0, y: 0)
        let first = candidate(atTileX: 3)
        let second = candidate(atTileX: -3)

        let selected = TargetSelection.nearestLivingTarget(
            from: origin,
            raccoons: [first, second],
            maxRange: 10
        )

        XCTAssertTrue(
            selected?.raccoon === first.raccoon,
            "an equal distance must never replace the current best: the documented tie-break is array order"
        )

        // Same pair, reversed: the rule is array order, not position sign.
        let reversed = TargetSelection.nearestLivingTarget(
            from: origin,
            raccoons: [second, first],
            maxRange: 10
        )

        XCTAssertTrue(
            reversed?.raccoon === second.raccoon,
            "reversing the array must reverse the winner -- otherwise the tie-break is not array order"
        )
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

        XCTAssertTrue(selected?.raccoon === alive.raccoon)
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
        XCTAssertTrue(firstSelection?.raccoon === nearest.raccoon)

        // Kill the previously-selected nearest raccoon, mid-tick.
        nearest.raccoon.takeDamage(nearest.raccoon.hp)
        XCTAssertTrue(nearest.raccoon.isDead)

        let secondSelection = TargetSelection.nearestLivingTarget(from: origin, raccoons: pool, maxRange: 10)
        XCTAssertTrue(secondSelection?.raccoon === nextNearest.raccoon, "must re-target to the next nearest living raccoon once the previous target has died")
    }
}
