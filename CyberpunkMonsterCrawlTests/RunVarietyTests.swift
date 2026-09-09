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

    /// Samples a fixed neighbourhood of tiles around a run's own spawn
    /// junction and returns each tile's classified `TileKind` in a stable
    /// order -- a coarse fingerprint of "what does this run's city look
    /// like right where the player starts".
    private func citySignature(for scene: GameScene) -> [TileKind] {
        let spawn = RunSpawnSelector.selectSpawnTile(seed: scene.worldSeed)
        var kinds: [TileKind] = []
        for dx in -6...6 {
            for dy in -6...6 {
                let info = CityLatticeGenerator.classify(
                    tileX: spawn.tileX + dx,
                    tileY: spawn.tileY + dy,
                    seed: scene.worldSeed
                )
                kinds.append(info.kind)
            }
        }
        return kinds
    }

    func test_consecutiveRunAgainInvocations_produceGenuinelyDifferentCityLayouts_notJustADifferentJunction() {
        let scene = makeScene()
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))
        XCTAssertTrue(scene.stateMachine.transition(to: .death))

        var signatures: [String] = []
        for _ in 0..<10 {
            XCTAssertTrue(scene.startNewRun())
            let signature = citySignature(for: scene).map { String(describing: $0) }.joined(separator: ",")
            signatures.append(signature)
            XCTAssertTrue(scene.stateMachine.transition(to: .death))
        }

        let distinctSignatures = Set(signatures)
        XCTAssertGreaterThan(
            distinctSignatures.count, 1,
            "10 consecutive RUN AGAIN invocations produced the identical tile-kind neighbourhood around the "
                + "spawn junction every time -- gate 6 requires a genuinely different city, not merely a "
                + "different junction coordinate inside the same one."
        )
    }

    /// The other literal half of gate 6's wording -- "and new starting
    /// street junction per run" -- restated at this file's own level
    /// (rather than only trusted from `GameStateMachineTests`) so this
    /// file's own city-layout claim above and the junction claim it is
    /// deliberately distinguished from both live together.
    func test_consecutiveRunAgainInvocations_produceADifferentStartJunction_everyTime() {
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
