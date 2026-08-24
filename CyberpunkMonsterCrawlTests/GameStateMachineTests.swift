import CoreGraphics
import SpriteKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// Exhaustive legal/illegal transition matrix for `GameStateMachine`, per
/// the table in docs/bootstrap.md / GameStateMachine.swift:
///   menu       -> gameplay    legal
///   menu       -> highScores  legal
///   gameplay   -> death       legal
///   death      -> gameplay    legal (RUN AGAIN)
///   death      -> menu        legal
///   highScores -> menu        legal
/// Every other ordered pair (including every self-transition) is illegal.
final class GameStateMachineTests: XCTestCase {

    // MARK: - Helpers

    /// Fresh machine positioned at `state` via a known-legal path from the
    /// default `.menu` starting state.
    private func makeMachine(at state: GameState) -> GameStateMachine {
        let machine = GameStateMachine()
        switch state {
        case .menu:
            break
        case .gameplay:
            XCTAssertTrue(machine.transition(to: .gameplay))
        case .death:
            XCTAssertTrue(machine.transition(to: .gameplay))
            XCTAssertTrue(machine.transition(to: .death))
        case .highScores:
            XCTAssertTrue(machine.transition(to: .highScores))
        }
        XCTAssertEqual(machine.currentState, state, "test setup failed to reach \(state)")
        return machine
    }

    private func assertLegal(from: GameState, to: GameState, file: StaticString = #filePath, line: UInt = #line) {
        let machine = makeMachine(at: from)
        XCTAssertTrue(machine.canTransition(to: to), "\(from) -> \(to) should be legal", file: file, line: line)
        XCTAssertTrue(machine.transition(to: to), "\(from) -> \(to) should succeed", file: file, line: line)
        XCTAssertEqual(machine.currentState, to, file: file, line: line)
    }

    private func assertIllegal(from: GameState, to: GameState, file: StaticString = #filePath, line: UInt = #line) {
        let machine = makeMachine(at: from)
        XCTAssertFalse(machine.canTransition(to: to), "\(from) -> \(to) should be illegal", file: file, line: line)
        XCTAssertFalse(machine.transition(to: to), "\(from) -> \(to) should fail", file: file, line: line)
        XCTAssertEqual(machine.currentState, from, "illegal transition must not change state", file: file, line: line)
    }

    // MARK: - Initial state

    func test_initialState_isMenu() {
        let machine = GameStateMachine()
        XCTAssertEqual(machine.currentState, .menu)
    }

    // MARK: - Legal transitions

    func test_menu_to_gameplay_isLegal() {
        assertLegal(from: .menu, to: .gameplay)
    }

    func test_menu_to_highScores_isLegal() {
        assertLegal(from: .menu, to: .highScores)
    }

    func test_gameplay_to_death_isLegal() {
        assertLegal(from: .gameplay, to: .death)
    }

    func test_death_to_gameplay_isLegal_runAgain() {
        assertLegal(from: .death, to: .gameplay)
    }

    func test_death_to_menu_isLegal() {
        assertLegal(from: .death, to: .menu)
    }

    func test_highScores_to_menu_isLegal() {
        assertLegal(from: .highScores, to: .menu)
    }

    // MARK: - Illegal transitions — full matrix of everything not above

    func test_menu_to_death_isIllegal() {
        assertIllegal(from: .menu, to: .death)
    }

    func test_menu_to_menu_isIllegal() {
        assertIllegal(from: .menu, to: .menu)
    }

    func test_gameplay_to_menu_isIllegal() {
        assertIllegal(from: .gameplay, to: .menu)
    }

    func test_gameplay_to_highScores_isIllegal() {
        assertIllegal(from: .gameplay, to: .highScores)
    }

    func test_gameplay_to_gameplay_isIllegal() {
        assertIllegal(from: .gameplay, to: .gameplay)
    }

    func test_death_to_highScores_isIllegal() {
        assertIllegal(from: .death, to: .highScores)
    }

    func test_death_to_death_isIllegal() {
        assertIllegal(from: .death, to: .death)
    }

    func test_highScores_to_gameplay_isIllegal() {
        assertIllegal(from: .highScores, to: .gameplay)
    }

    func test_highScores_to_death_isIllegal() {
        assertIllegal(from: .highScores, to: .death)
    }

    func test_highScores_to_highScores_isIllegal() {
        assertIllegal(from: .highScores, to: .highScores)
    }

    // MARK: - Full exhaustive matrix (belt-and-suspenders over the above)

    private static let legalPairs: Set<String> = [
        "menu->gameplay",
        "menu->highScores",
        "gameplay->death",
        "death->gameplay",
        "death->menu",
        "highScores->menu",
    ]

    private func key(_ a: GameState, _ b: GameState) -> String {
        "\(a)->\(b)"
    }

    func test_exhaustiveMatrix_matchesLegalTable() {
        for from in GameState.allCases {
            for to in GameState.allCases {
                let expectedLegal = Self.legalPairs.contains(key(from, to))
                if expectedLegal {
                    assertLegal(from: from, to: to)
                } else {
                    assertIllegal(from: from, to: to)
                }
            }
        }
    }

    // MARK: - Change observation (`onChange`)

    func test_init_onChange_receivesInitialMenuEntry() {
        var observed: [GameState] = []
        _ = GameStateMachine(onChange: { observed.append($0) })
        XCTAssertEqual(observed, [.menu], "a hook supplied to init must see the initial .menu entry")
    }

    func test_onChange_firesOncePerLegalTransition() {
        let machine = GameStateMachine()
        var observed: [GameState] = []
        machine.onChange = { observed.append($0) }

        XCTAssertTrue(machine.transition(to: .gameplay))
        XCTAssertTrue(machine.transition(to: .death))
        XCTAssertTrue(machine.transition(to: .gameplay))

        XCTAssertEqual(observed, [.gameplay, .death, .gameplay],
                       "consumers must be pushed each entry rather than polling currentState")
    }

    func test_onChange_doesNotFire_forIllegalTransition() {
        let machine = GameStateMachine()
        var observed: [GameState] = []
        machine.onChange = { observed.append($0) }

        XCTAssertFalse(machine.transition(to: .death))

        XCTAssertTrue(observed.isEmpty, "a rejected transition must not notify observers")
        XCTAssertEqual(machine.currentState, .menu)
    }

    // MARK: - Illegal-transition reporting (no silent no-ops)

    func test_illegalTransition_reportsFromAndTo() {
        let machine = GameStateMachine()
        var reported: [String] = []
        machine.onIllegalTransition = { from, to in reported.append("\(from)->\(to)") }

        XCTAssertFalse(machine.transition(to: .death))

        XCTAssertEqual(reported, ["menu->death"])
        XCTAssertEqual(machine.currentState, .menu, "reporting must not change state")
    }

    func test_legalTransition_reportsNothing() {
        let machine = GameStateMachine()
        var reported: [String] = []
        machine.onIllegalTransition = { from, to in reported.append("\(from)->\(to)") }

        XCTAssertTrue(machine.transition(to: .gameplay))

        XCTAssertTrue(reported.isEmpty)
    }

    /// The mis-wired-button case from review: every rejected pair must be
    /// observable by the consumer, not a silent no-op.
    func test_everyIllegalPair_isReportedExactlyOnce() {
        for from in GameState.allCases {
            for to in GameState.allCases where !Self.legalPairs.contains(key(from, to)) {
                let machine = makeMachine(at: from)
                var reported: [String] = []
                machine.onIllegalTransition = { f, t in reported.append("\(f)->\(t)") }

                XCTAssertFalse(machine.transition(to: to))

                XCTAssertEqual(reported, [key(from, to)],
                               "\(from) -> \(to) rejection must be reported, not silent")
                XCTAssertEqual(machine.currentState, from)
            }
        }
    }

    // MARK: - RUN AGAIN: new seed, new junction, full reset (`CYBERPUN-17-13` PR 3)
    //
    // `GameStateMachine` itself stays scene/rendering-agnostic (it knows
    // nothing of `WorldSeed`/`RunSpawnSelector`/`RunStats`/`XPLevelSystem`),
    // so the actual RUN AGAIN behaviour these tests pin -- fresh seed, fresh
    // junction, full reset -- lives on `GameScene.startNewRun()`, the
    // production entry point `GameViewController`'s `DeathScreenNode
    // .onRunAgain` calls. These tests drive it through the same
    // `stateMachine` this file otherwise tests in isolation, the same way
    // `GameViewControllerCompositionTests`/`PlayerMountTests` already do for
    // other scene-wiring behaviour keyed off state transitions.

    private func makeScene() -> GameScene {
        GameScene(size: CGSize(width: 400, height: 800))
    }

    func test_startNewRun_transitionsStraightToGameplay_fromDeath_noMenuDetour() {
        let scene = makeScene()
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))
        XCTAssertTrue(scene.stateMachine.transition(to: .death))

        XCTAssertTrue(scene.startNewRun())

        XCTAssertEqual(
            scene.stateMachine.currentState, .gameplay,
            "RUN AGAIN must land directly in .gameplay, with no menu detour"
        )
    }

    func test_startNewRun_isANoOp_whenGameplayIsNotALegalNextState() {
        let scene = makeScene()
        XCTAssertTrue(scene.stateMachine.transition(to: .highScores))
        let seedBefore = scene.worldSeed

        XCTAssertFalse(
            scene.startNewRun(),
            "RUN AGAIN is only legal from .death, not from .highScores"
        )

        XCTAssertEqual(scene.stateMachine.currentState, .highScores)
        XCTAssertEqual(
            scene.worldSeed, seedBefore,
            "an illegal RUN AGAIN attempt must not draw (and discard) a new seed"
        )
    }

    /// AC5: "RUN AGAIN yields a different seed and different starting
    /// junction every time, always a street intersection."
    func test_startNewRun_drawsADifferentSeed_everyConsecutiveInvocation() {
        let scene = makeScene()
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))
        XCTAssertTrue(scene.stateMachine.transition(to: .death))

        var seeds: Set<UInt64> = []
        for _ in 0..<20 {
            XCTAssertTrue(scene.startNewRun())
            seeds.insert(scene.worldSeed.rawValue)
            XCTAssertTrue(scene.stateMachine.transition(to: .death))
        }

        XCTAssertEqual(
            seeds.count, 20,
            "consecutive RUN AGAIN invocations must draw distinct seeds, not repeat one"
        )
    }

    func test_startNewRun_spawnsAtADifferentStreetIntersection_everyConsecutiveInvocation() {
        let scene = makeScene()
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))
        XCTAssertTrue(scene.stateMachine.transition(to: .death))

        var junctions: Set<TileCoordinate> = []
        for _ in 0..<20 {
            XCTAssertTrue(scene.startNewRun())

            let tile = RunSpawnSelector.selectSpawnTile(seed: scene.worldSeed)
            XCTAssertTrue(
                RunSpawnSelector.isIntersectionTile(tileX: tile.tileX, tileY: tile.tileY),
                "every RUN AGAIN must still spawn on a street intersection"
            )
            junctions.insert(tile)

            XCTAssertTrue(scene.stateMachine.transition(to: .death))
        }

        XCTAssertGreaterThan(
            junctions.count, 1,
            "consecutive RUN AGAIN invocations must land on different starting junctions, not the same one every time"
        )
    }

    /// AC8: "New run fully resets all run-scoped state with no
    /// bleed-through." Drives a run into a dirtied state across every
    /// system RUN AGAIN must clear -- HP, infection, kills (both counters:
    /// `RunSummaryStats` and the weapon system's own `RunStats`), gunfire
    /// damage, XP/level and the elapsed-run timer -- then asserts every one
    /// of them is back at its fresh-run starting value after `startNewRun()`.
    func test_startNewRun_fullyResetsEveryRunScopedCounter_withNoBleedThrough() throws {
        let scene = makeScene()
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))

        let player = try XCTUnwrap(scene.player, "entering .gameplay must mount the player")
        let playerCombat = try XCTUnwrap(scene.playerCombat, "entering .gameplay must build the combat composition")

        // Dirty every counter RUN AGAIN must clear.
        player.infect(stats: scene.runStats)
        player.takeDamage(40)
        scene.runStats.recordKill()
        playerCombat.runStats.recordDamage(120)
        playerCombat.runStats.recordKill()
        playerCombat.xpLevelSystem.awardXP(250)
        scene.update(1)
        scene.update(6) // a real elapsed delta -- `update(1)` alone has no prior frame to diff against

        XCTAssertLessThan(player.hp, player.maxHP, "test setup must actually damage the player")
        XCTAssertTrue(player.isInfected, "test setup must actually infect the player")
        XCTAssertGreaterThan(scene.runStats.killCount, 0, "test setup must actually record a kill")
        XCTAssertGreaterThan(scene.runStats.timesInfected, 0, "test setup must actually record an infection")
        XCTAssertGreaterThan(playerCombat.runStats.damageDealt, 0, "test setup must actually record gunfire damage")
        XCTAssertGreaterThan(playerCombat.runStats.killCount, 0, "test setup must actually record a gunfire kill")
        XCTAssertGreaterThan(playerCombat.xpLevelSystem.level, 1, "test setup must actually level up")
        XCTAssertGreaterThan(scene.runElapsedSeconds, 0, "test setup must actually advance the run timer")

        XCTAssertTrue(scene.stateMachine.transition(to: .death))
        XCTAssertTrue(scene.startNewRun())

        XCTAssertEqual(player.hp, player.maxHP, "HP must not bleed through into the new run")
        XCTAssertFalse(player.isInfected, "infection must not bleed through into the new run")
        XCTAssertEqual(scene.runStats.killCount, 0, "kills must not bleed through into the new run")
        XCTAssertEqual(scene.runStats.timesInfected, 0, "infections must not bleed through into the new run")
        XCTAssertEqual(playerCombat.runStats.damageDealt, 0, "damage dealt must not bleed through into the new run")
        XCTAssertEqual(playerCombat.runStats.killCount, 0, "gunfire kills must not bleed through into the new run")
        XCTAssertEqual(playerCombat.xpLevelSystem.level, 1, "level must not bleed through into the new run")
        XCTAssertEqual(playerCombat.xpLevelSystem.xp, 0, "XP must not bleed through into the new run")
        XCTAssertEqual(scene.runElapsedSeconds, 0, "the run timer must not bleed through into the new run")
    }
}
