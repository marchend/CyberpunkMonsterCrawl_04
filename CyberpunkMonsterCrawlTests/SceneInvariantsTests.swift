import XCTest
import SpriteKit
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-4-t6`: the scene-invariant audits must behave identically in
/// every build configuration.
///
/// Before this task the two audits (`nodesEscapingTheirLayerBand()`,
/// `nodesBypassingSceneTouchDispatch()`) were only ever *reached* through an
/// `#if DEBUG` `assertSceneInvariants()`, and CI only ever built Debug. That
/// left the app's whole structural safety net switched off in exactly the
/// configuration the shipped product and the scripted runtime probe use: a
/// regression that needs an optimized (or `#if DEBUG`-stripped) build to
/// manifest would trip loudly in every Debug test run and still ship in
/// silence - the "every unit test stayed green, the real app didn't" trap this
/// codebase's own comments keep calling out.
///
/// Two halves are pinned here:
///
/// 1. **Behaviour** - `reportSceneInvariantViolations()` (the *only* reaction
///    a Release build has, since `assert` is compiled out there) really runs,
///    really reports, and is non-fatal.
/// 2. **Compilation** - a source scan proving none of that machinery sits
///    inside an `#if DEBUG` region, in `SceneInvariants.swift` or at
///    `GameScene`'s call sites. A behavioural test can only ever observe the
///    configuration it was itself compiled in, so without the scan a future
///    edit could put the audits back behind `#if DEBUG` and this suite would
///    stay green while the gap reopened.
///
/// Note what is deliberately *not* tested: `enforceSceneInvariants()` against
/// a violating graph. In DEBUG that trips an `assert` and takes the test
/// process down - which is the intended behaviour, and is why the hostile-input
/// cases below drive `reportSceneInvariantViolations()` instead.
final class SceneInvariantsTests: XCTestCase {

    private func makeScene() -> GameScene {
        GameScene(size: CGSize(width: 400, height: 800))
    }

    // MARK: - The non-fatal reporting path (the Release reaction)

    func test_reportSceneInvariantViolations_reportsNothing_forAComposedScene() {
        let scene = makeScene()
        scene.register(PlaceholderScreenNode(label: "menu"), for: .menu)

        var hookFired = false
        scene.onSceneInvariantViolation = { _ in hookFired = true }

        XCTAssertTrue(
            scene.reportSceneInvariantViolations().isEmpty,
            "a composed scene must report no violations"
        )
        XCTAssertTrue(scene.sceneInvariantViolations().isEmpty)
        XCTAssertFalse(hookFired, "the violation hook must not fire for a clean graph")
    }

    func test_enforceSceneInvariants_returnsNoViolations_forAComposedScene() {
        let scene = makeScene()
        scene.register(PlaceholderScreenNode(label: "menu"), for: .menu)

        // Safe to call in DEBUG precisely because the graph is clean; a
        // violating graph would (correctly) trip the DEBUG assert.
        XCTAssertTrue(scene.enforceSceneInvariants().isEmpty)
    }

    func test_reportSceneInvariantViolations_reportsABandEscapee_throughTheHook_withoutTrapping() {
        let scene = makeScene()
        let sinker = SKNode()
        sinker.name = "uiSinker"
        // Cumulative: uiLayerZ (1_000) + (-5_000) = -4_000, i.e. below the
        // world layer's maximum - the v1 "world paints over UI" failure.
        sinker.zPosition = -5_000
        scene.uiLayer.addChild(sinker)

        var reported: [String] = []
        scene.onSceneInvariantViolation = { reported = $0 }

        let returned = scene.reportSceneInvariantViolations()

        // Returning at all is half the assertion: the Release path must
        // report, not trap.
        XCTAssertFalse(returned.isEmpty, "the band escapee must be reported")
        XCTAssertEqual(reported, returned, "the hook must receive exactly what the call returns")
        XCTAssertTrue(
            returned.contains { $0.contains("uiSinker") },
            "the report must name the offending node so it is actionable in a device log: \(returned)"
        )
        XCTAssertTrue(
            returned.contains { $0.contains("layer band") },
            "the report must say which invariant was violated: \(returned)"
        )
    }

    func test_reportSceneInvariantViolations_reportsANodeStealingTouchDelivery() {
        let scene = makeScene()
        let thief = SKNode()
        thief.name = "touchThief"
        // UIKit hands such a node the touch before `SKScene.touchesBegan`
        // runs, bypassing `GameScene.routeTouch(at:)` and the UI-first
        // guarantee with it - see `TouchResponder`.
        thief.isUserInteractionEnabled = true
        scene.uiLayer.addChild(thief)

        var reported: [String] = []
        scene.onSceneInvariantViolation = { reported = $0 }

        let returned = scene.reportSceneInvariantViolations()

        XCTAssertFalse(returned.isEmpty, "the touch-dispatch thief must be reported")
        XCTAssertEqual(reported, returned)
        XCTAssertTrue(
            returned.contains { $0.contains("touchThief") && $0.contains("touch dispatch") },
            "the report must name the offending node and the invariant: \(returned)"
        )
    }

    func test_sceneInvariantViolations_reportsBothInvariants_whenBothAreViolated() {
        let scene = makeScene()

        let riser = SKNode()
        riser.name = "worldRiser"
        riser.zPosition = 200_000 // cumulative 100_000: above uiMinZ
        scene.worldLayer.addChild(riser)

        let thief = SKNode()
        thief.name = "touchThief"
        thief.isUserInteractionEnabled = true
        scene.uiLayer.addChild(thief)

        let violations = scene.sceneInvariantViolations()

        XCTAssertTrue(violations.contains { $0.contains("worldRiser") }, "\(violations)")
        XCTAssertTrue(violations.contains { $0.contains("touchThief") }, "\(violations)")
        XCTAssertEqual(
            violations, scene.reportSceneInvariantViolations(),
            "reporting must not change what the audit found"
        )
    }

    // MARK: - The compilation gate: no audit machinery behind `#if DEBUG`
    //
    // A source scan, in the spirit of `AtlasContractConventionTests`: the
    // property under test ("this code is compiled into Release") is not
    // observable from a Debug test run any other way. `#filePath` resolves at
    // compile time to this file's path in the checked-out repository, and CI
    // builds and runs from that same checkout, so the tree is reachable at run
    // time. Unreachable files **fail** rather than skip - a gate that
    // evaporates must not read as a green suite.

    /// One source line plus its 1-based number, for readable failures.
    private typealias NumberedLine = (number: Int, text: String)

    /// Declarations in `SceneInvariants.swift` that must be compiled in every
    /// configuration. Losing any of them to an `#if DEBUG` block is precisely
    /// the regression this task exists to close.
    private static let mustCompileEverywhere = [
        "func nodesEscapingTheirLayerBand(",
        "func layerBandViolationReport(",
        "func nodesBypassingSceneTouchDispatch(",
        "func sceneInvariantViolations(",
        "func reportSceneInvariantViolations(",
        "func enforceSceneInvariants(",
        "invariantLog",
        "onSceneInvariantViolation?(",
    ]

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // CyberpunkMonsterCrawlTests/
            .deletingLastPathComponent() // repo root
    }

    private func source(at relativePath: String) -> String? {
        try? String(
            contentsOf: repoRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    /// Splits `source` into the lines compiled **only** in DEBUG (inside an
    /// `#if DEBUG` branch) and the lines compiled in every configuration.
    ///
    /// Comment-only lines are dropped from both, so prose *about* `#if DEBUG`
    /// (of which these files have plenty) can never be mistaken for code.
    /// Nesting is tracked with a stack, and `#else` flips the innermost
    /// branch, so an `#if DEBUG` wrapped in an unrelated `#if` is still
    /// classified correctly. Known simplification: `#if !DEBUG` is treated as
    /// DEBUG-only, which errs towards flagging - nothing in this codebase uses
    /// it, and a Release-only branch would be just as much of a
    /// configuration split as a Debug-only one.
    private func partitionByDebugGating(
        _ source: String
    ) -> (debugOnly: [NumberedLine], everyConfiguration: [NumberedLine]) {
        var debugOnly: [NumberedLine] = []
        var everyConfiguration: [NumberedLine] = []
        var branchIsDebugOnly: [Bool] = []

        for (offset, text) in source.components(separatedBy: .newlines).enumerated() {
            let line: NumberedLine = (number: offset + 1, text: text)
            let trimmed = text.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("#if") {
                branchIsDebugOnly.append(trimmed.contains("DEBUG"))
                continue
            }
            if trimmed.hasPrefix("#elseif") {
                if !branchIsDebugOnly.isEmpty {
                    branchIsDebugOnly[branchIsDebugOnly.count - 1] = trimmed.contains("DEBUG")
                }
                continue
            }
            if trimmed.hasPrefix("#else") {
                if !branchIsDebugOnly.isEmpty {
                    branchIsDebugOnly[branchIsDebugOnly.count - 1] = false
                }
                continue
            }
            if trimmed.hasPrefix("#endif") {
                if !branchIsDebugOnly.isEmpty {
                    branchIsDebugOnly.removeLast()
                }
                continue
            }

            guard !trimmed.isEmpty, !trimmed.hasPrefix("//") else { continue }

            if branchIsDebugOnly.contains(true) {
                debugOnly.append(line)
            } else {
                everyConfiguration.append(line)
            }
        }

        return (debugOnly, everyConfiguration)
    }

    func test_sceneInvariants_auditMachinery_isCompiledIntoEveryConfiguration() {
        guard let contents = source(at: "CyberpunkMonsterCrawl/Layers/SceneInvariants.swift") else {
            XCTFail("SceneInvariants.swift is not readable from the checkout; this gate is not running.")
            return
        }

        let (debugOnly, everyConfiguration) = partitionByDebugGating(contents)

        for needle in Self.mustCompileEverywhere {
            XCTAssertTrue(
                everyConfiguration.contains { $0.text.contains(needle) },
                "`\(needle)` is not compiled in every configuration. The scene-invariant audits and "
                    + "their non-fatal reporting path must never sit inside `#if DEBUG` - that is "
                    + "the Debug-only blind spot CYBERPUN-17-4-t6 closed."
            )
            XCTAssertFalse(
                debugOnly.contains { $0.text.contains(needle) },
                "`\(needle)` was found inside an `#if DEBUG` block in SceneInvariants.swift."
            )
        }

        // The only thing allowed to be DEBUG-only in this file is the
        // fail-fast reaction (`assert`) - never a declaration, so no audit,
        // report or logger can be moved back behind the flag.
        let debugOnlyDeclarations = debugOnly.filter { $0.text.contains("func ") || $0.text.contains("let ") }
        XCTAssertTrue(
            debugOnlyDeclarations.isEmpty,
            "SceneInvariants.swift declares something inside `#if DEBUG`: "
                + debugOnlyDeclarations
                    .map { "\($0.number): \($0.text.trimmingCharacters(in: .whitespaces))" }
                    .joined(separator: "; ")
        )
        let debugOnlyIsOnlyTheAssertReaction =
            debugOnly.isEmpty || debugOnly.contains(where: { $0.text.contains("assert(") })
        XCTAssertTrue(
            debugOnlyIsOnlyTheAssertReaction,
            "the only DEBUG-only code in SceneInvariants.swift should be the `assert` reaction."
        )
    }

    func test_gameScene_callsTheInvariantAudit_outsideAnyDebugOnlyBlock() {
        guard let contents = source(at: "CyberpunkMonsterCrawl/GameScene.swift") else {
            XCTFail("GameScene.swift is not readable from the checkout; this gate is not running.")
            return
        }

        let (debugOnly, everyConfiguration) = partitionByDebugGating(contents)
        let needle = "enforceSceneInvariants("

        let gatedCalls = debugOnly.filter { $0.text.contains(needle) }
        XCTAssertTrue(
            gatedCalls.isEmpty,
            "GameScene calls the scene-invariant audit inside an `#if DEBUG` block, so a Release "
                + "build would not audit at all: "
                + gatedCalls
                    .map { "\($0.number): \($0.text.trimmingCharacters(in: .whitespaces))" }
                    .joined(separator: "; ")
        )

        // didMove(to:), transitionScreens(to:), startGroundPlane() and
        // dispatchTouch(atScenePoint:) - the four moments the graph changes or
        // is about to be hit-tested. Asserted as a count so deleting a call
        // site fails here instead of quietly shrinking the audit's reach.
        let ungatedCalls = everyConfiguration.filter { $0.text.contains(needle) }
        XCTAssertEqual(
            ungatedCalls.count, 4,
            "expected 4 unconditional `enforceSceneInvariants()` call sites in GameScene "
                + "(scene presented, screen mounted, ground plane mounted, touch dispatched); "
                + "found \(ungatedCalls.count)."
        )
    }

    /// Pins the scanner itself, so a broken partitioner cannot make the two
    /// gates above pass vacuously.
    func test_debugGatingPartitioner_classifiesNestedDirectivesAndIgnoresComments() {
        let sample = """
        func always() {}
        // a comment mentioning #if DEBUG must be ignored
        #if DEBUG
        func debugOnly() {}
        #if os(iOS)
        func nestedDebugOnly() {}
        #endif
        #else
        func releaseOnly() {}
        #endif
        #if os(iOS)
        func platformGatedButNotDebugGated() {}
        #endif
        """

        let (debugOnly, everyConfiguration) = partitionByDebugGating(sample)
        let debugTexts = debugOnly.map { $0.text }
        let everyTexts = everyConfiguration.map { $0.text }

        XCTAssertTrue(debugTexts.contains { $0.contains("debugOnly()") })
        XCTAssertTrue(debugTexts.contains { $0.contains("nestedDebugOnly()") })
        XCTAssertFalse(debugTexts.contains { $0.contains("releaseOnly()") })
        XCTAssertTrue(everyTexts.contains { $0.contains("always()") })
        XCTAssertTrue(everyTexts.contains { $0.contains("platformGatedButNotDebugGated()") })
        XCTAssertFalse(
            everyTexts.contains { $0.contains("a comment mentioning") },
            "comment lines must be dropped, or prose about `#if DEBUG` could satisfy the gate"
        )
    }
}
