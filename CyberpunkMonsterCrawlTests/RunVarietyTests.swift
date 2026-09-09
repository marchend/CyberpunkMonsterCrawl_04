import CoreGraphics
import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-14-t4` (PR 4): gate-6 run-variety structural assertions.
///
/// `GameStateMachineTests` already exhaustively pins that `startNewRun()`
/// draws a distinct seed and a distinct starting junction on every
/// consecutive RUN AGAIN (`test_startNewRun_drawsADifferentSeed_...`,
/// `test_startNewRun_spawnsAtADifferentStreetIntersection_...`). What
/// neither of those checks is the thing gate 6's wording actually asks
/// about -- "two consecutive RUN AGAIN runs with **different cities**",
/// not merely a different junction tile inside an otherwise-identical
/// city. A hypothetical seed bug confined to `RunSpawnSelector`'s own hash
/// stream (wrong junction, same city everywhere else) would pass both of
/// those existing tests while still failing gate 6 outright. This file
/// classifies a real tile neighbourhood around each run's own spawn
/// junction and asserts the classification actually differs between
/// consecutive seeds -- the same "restate the claim against the
/// production seam, not just its inputs" discipline
/// `ChunkStreamingManagerTests` applies on top of
/// `CityLatticeGeneratorTests`'s own coverage of `classify` alone.
final class RunVarietyTests: XCTestCase {

    private func makeScene() -> GameScene {
        GameScene(size: CGSize(width: 400, height: 800))
    }

    /// Fingerprints "what does this run's city look like right where the
    /// player starts": the classified `TileKind` of a fixed 13x13 tile
    /// neighbourhood around the run's own spawn junction, plus every
    /// building `BuildingPlacement.generate` places on the blocks that
    /// neighbourhood covers, all in a stable order.
    ///
    /// **What this fingerprint can and cannot vary** (PR #67 review).
    /// `RunSpawnSelector.selectSpawnTile` always returns `blockN * period +
    /// junctionCentreOffset`, so every run's spawn tile sits at the same
    /// phase mod `CityLatticeGenerator.period` and the street/lot *lattice*
    /// structure of this window is invariant by construction -- street
    /// tiles never consult the seed at all (`CityLatticeGenerator`'s own
    /// "This branch never consults seed"). The genuinely seed-dependent
    /// bits are the per-block `.lot`-vs-`.buildingFootprint` decision and,
    /// added here rather than trusted from the tile kinds alone, *which of
    /// the 12 catalog buildings stands on each lot* -- the part a player
    /// actually reads as "a different city". A tile-kind-only fingerprint
    /// would be both narrower than gate 6's claim and, over ~9 blocks of
    /// 1-in-4 empty-lot decisions, coarse enough that two genuinely
    /// different seeds could collide; including the building selection
    /// makes a collision between different seeds vanishingly unlikely,
    /// which is what lets the assertions below demand *every* pair differ.
    private func citySignature(for scene: GameScene) -> String {
        let spawn = RunSpawnSelector.selectSpawnTile(seed: scene.worldSeed)
        var parts: [String] = []

        for dx in -6...6 {
            for dy in -6...6 {
                let info = CityLatticeGenerator.classify(
                    tileX: spawn.tileX + dx,
                    tileY: spawn.tileY + dy,
                    seed: scene.worldSeed
                )
                parts.append(String(describing: info.kind))
            }
        }

        let period = CityLatticeGenerator.period
        let blockIndex = { (tile: Int) -> Int in Int((Double(tile) / Double(period)).rounded(.down)) }
        for blockX in blockIndex(spawn.tileX - 6)...blockIndex(spawn.tileX + 6) {
            for blockY in blockIndex(spawn.tileY - 6)...blockIndex(spawn.tileY + 6) {
                let block = BlockCoordinate(x: blockX, y: blockY)
                for record in BuildingPlacement.generate(forBlock: block, seed: scene.worldSeed) {
                    parts.append(
                        "\(record.lotTile.tileX),\(record.lotTile.tileY):\(record.building.assetName)"
                    )
                }
            }
        }

        return parts.joined(separator: "|")
    }

    func test_consecutiveRunAgainInvocations_produceGenuinelyDifferentCityLayouts_notJustADifferentJunction() {
        let scene = makeScene()
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))
        XCTAssertTrue(scene.stateMachine.transition(to: .death))

        var signatures: [String] = []
        for _ in 0..<10 {
            XCTAssertTrue(scene.startNewRun())
            signatures.append(citySignature(for: scene))
            XCTAssertTrue(scene.stateMachine.transition(to: .death))
        }

        // Gate 6's wording is "**two consecutive** RUN AGAIN runs with
        // different cities", so every consecutive pair is asserted (PR #67
        // review). A "distinct count > 1" spelling would pass while runs
        // 2-10 were byte-identical and only run 1 differed -- exactly the
        // regression a partially-fixed seed produces.
        for (index, pair) in zip(signatures, signatures.dropFirst()).enumerated() {
            XCTAssertNotEqual(
                pair.0, pair.1,
                "RUN AGAIN runs \(index + 1) and \(index + 2) produced the identical city around the spawn "
                    + "junction -- gate 6 requires two consecutive runs to differ, not merely some pair "
                    + "somewhere in the sequence."
            )
        }

        XCTAssertEqual(
            Set(signatures).count, signatures.count,
            "two of the 10 RUN AGAIN runs produced the identical city signature -- with the per-lot "
                + "building selection included in the fingerprint, a repeat means a repeated seed, not a "
                + "coarse-fingerprint collision."
        )
    }

    /// The other literal half of gate 6's wording -- "and new starting
    /// street junction per run" -- restated at this file's own level
    /// (rather than only trusted from `GameStateMachineTests`) so this
    /// file's own city-layout claim above and the junction claim it is
    /// deliberately distinguished from both live together.
    ///
    /// Deliberately a "not all the same junction" assertion rather than the
    /// all-pairs-differ one the city signature above carries, and named for
    /// what it checks (PR #67 review): the junction is a single tile drawn
    /// from a bounded candidate set, so two different seeds landing on the
    /// same junction is a genuine -- if rare -- outcome rather than a bug,
    /// and demanding 10 distinct junctions would buy strength at the price
    /// of a flake. This mirrors `GameStateMachineTests
    /// .test_startNewRun_spawnsAtADifferentStreetIntersection_everyConsecutiveInvocation`'s
    /// own spelling; the city signature can afford the stronger form
    /// because it fingerprints per-lot building selection too.
    func test_consecutiveRunAgainInvocations_doNotAllShareOneStartJunction() {
        let scene = makeScene()
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))
        XCTAssertTrue(scene.stateMachine.transition(to: .death))

        var junctions: Set<TileCoordinate> = []
        for _ in 0..<10 {
            XCTAssertTrue(scene.startNewRun())
            junctions.insert(RunSpawnSelector.selectSpawnTile(seed: scene.worldSeed))
            XCTAssertTrue(scene.stateMachine.transition(to: .death))
        }

        XCTAssertGreaterThan(junctions.count, 1, "every RUN AGAIN produced the identical starting junction")
    }
}
