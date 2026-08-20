import XCTest
import SpriteKit
import UIKit
@testable import CyberpunkMonsterCrawl

/// Unit coverage for the concrete `ScreenNode` conformers this PR ships:
/// `MenuScreenNode` (real PLAY/HIGH SCORES wiring, accessibility surface)
/// and the three skeleton screens (`GameplayScreenNode`, `DeathScreenNode`,
/// `HighScoresScreenNode`), whose *navigation* is real even though their
/// visual content is `// SCAFFOLDING:`-marked. `GameSceneScreenSwitchingTests`
/// and `GameViewControllerCompositionTests` already exercise these through
/// `GameScene`'s registry and touch dispatch; these tests drive the screens
/// directly so a regression in a screen's own wiring or layout is pinned
/// independent of the scene plumbing around it.
final class ScreensTests: XCTestCase {

    // MARK: - ButtonNode

    func test_buttonNode_defaultsAccessibilityIdentifier_toItsTitle() {
        let button = ButtonNode(title: "PLAY", size: CGSize(width: 100, height: 40)) {}
        XCTAssertEqual(button.accessibilityIdentifier, "PLAY")
        XCTAssertEqual(button.accessibilityLabel, "PLAY")
        XCTAssertTrue(button.isAccessibilityElement)
    }

    func test_buttonNode_usesExplicitAccessibilityIdentifier_whenSupplied() {
        let button = ButtonNode(
            title: "PLAY",
            size: CGSize(width: 100, height: 40),
            accessibilityIdentifier: "menu.playButton"
        ) {}
        XCTAssertEqual(button.accessibilityIdentifier, "menu.playButton")
    }

    func test_buttonNode_withAccentColor_addsAnAccentFrameChild() {
        let plain = ButtonNode(title: "BACK", size: CGSize(width: 100, height: 40)) {}
        let accented = ButtonNode(
            title: "PLAY",
            size: CGSize(width: 100, height: 40),
            accentColor: PixelGritPalette.neonAccent
        ) {}

        XCTAssertFalse(
            plain.children.contains { $0.name == "button.BACK.accentFrame" }
        )
        XCTAssertTrue(
            accented.children.contains { $0.name == "button.PLAY.accentFrame" },
            "an accent color must add a neon frame node behind the plate"
        )
    }

    // MARK: - MenuScreenNode

    func test_menuScreenNode_exposesAccessibilityIdentifiers_onPlayAndContainer() {
        let menu = MenuScreenNode(onPlay: {}, onHighScores: {})

        XCTAssertEqual(menu.playButton.accessibilityIdentifier, "menu.playButton")
        XCTAssertEqual(menu.highScoresButton.accessibilityIdentifier, "menu.highScoresButton")
        let marker = menu.node.children.first { $0.accessibilityIdentifier == "menu.container" }
        XCTAssertNotNil(
            marker,
            "the menu must expose a container accessibility anchor independent of any one button"
        )
        // The identifier is Swift-side bookkeeping only (see
        // `SKNodeAccessibilityIdentifier`), so the label is what any UI test
        // or VoiceOver can actually observe.
        XCTAssertTrue(marker?.isAccessibilityElement == true)
        XCTAssertEqual(marker?.accessibilityLabel, "Menu")
    }

    func test_menuScreenNode_playButton_runsTheSuppliedClosure() {
        var playTapped = false
        let menu = MenuScreenNode(onPlay: { playTapped = true }, onHighScores: {})

        menu.playButton.handleTouch()

        XCTAssertTrue(playTapped)
    }

    func test_menuScreenNode_highScoresButton_runsTheSuppliedClosure() {
        var highScoresTapped = false
        let menu = MenuScreenNode(onPlay: {}, onHighScores: { highScoresTapped = true })

        menu.highScoresButton.handleTouch()

        XCTAssertTrue(highScoresTapped)
    }

    /// AC5: "rotation re-lays out the current screen with no clipped or
    /// off-screen controls." The screen is camera-pinned, so its own
    /// coordinate space is centred on `(0, 0)` and the visible viewport is
    /// `size` centred on the origin - a control is on-screen exactly when
    /// its accumulated frame sits inside that rect. Driven in both a
    /// portrait and a landscape size so a layout that only holds in one
    /// orientation fails here.
    func test_menuScreenNode_layout_resizesBackground_andKeepsButtonsWithinBounds() {
        let orientations: [(name: String, size: CGSize, insets: UIEdgeInsets)] = [
            ("portrait", CGSize(width: 400, height: 800), UIEdgeInsets(top: 20, left: 0, bottom: 30, right: 0)),
            ("landscape", CGSize(width: 800, height: 400), UIEdgeInsets(top: 0, left: 44, bottom: 21, right: 44)),
        ]

        for orientation in orientations {
            let menu = MenuScreenNode(onPlay: {}, onHighScores: {})

            menu.layout(for: orientation.size, safeAreaInsets: orientation.insets)

            let background = menu.node.children.compactMap { $0 as? SKSpriteNode }.first
            XCTAssertEqual(
                background?.size, orientation.size,
                "\(orientation.name): the full-bleed backdrop must be resized to the scene size, or "
                    + "rotation leaves SpriteKit's default background showing at the edges"
            )

            let viewport = CGRect(
                x: -orientation.size.width / 2, y: -orientation.size.height / 2,
                width: orientation.size.width, height: orientation.size.height
            )
            for button in [menu.playButton, menu.highScoresButton] {
                let frame = button.calculateAccumulatedFrame()
                XCTAssertFalse(
                    frame.isEmpty,
                    "\(orientation.name): \(button.title) has an empty frame, so containment below "
                        + "would pass vacuously"
                )
                XCTAssertTrue(
                    viewport.contains(frame),
                    "\(orientation.name): \(button.title) at \(frame) is clipped or off-screen "
                        + "relative to the \(viewport) viewport"
                )
            }

            XCTAssertNotEqual(
                menu.playButton.position.y, menu.highScoresButton.position.y,
                "\(orientation.name): PLAY and HIGH SCORES must not land on top of each other"
            )
        }
    }

    // MARK: - GameplayScreenNode

    /// The gameplay screen is the one screen the world must show *through*,
    /// so unlike menu/death/high-scores it must mount nothing that blankets
    /// the viewport: `GameScene.routeTouch(at:)` returns any non-`uiLayer`
    /// hit before it looks at `worldLayer`, so a full-bleed backdrop here
    /// would swallow every touch (AC4) and paint over `worldLayer` from
    /// CYBERPUN-17-3 on.
    /// `TouchRoutingTests.test_mountedGameplayScreen_doesNotBlockWorldTouches`
    /// pins the routing consequence; this pins the structure.
    func test_gameplayScreenNode_mountsNoViewportBlanketingBackdrop() {
        let gameplay = GameplayScreenNode()
        let size = CGSize(width: 800, height: 400)

        gameplay.layout(for: size, safeAreaInsets: .zero)

        // Direct structural fact, stated rather than inferred from an empty
        // loop: the gameplay screen mounts no children at all, so there is
        // nothing that could blanket the viewport in the first place.
        XCTAssertTrue(
            gameplay.node.children.isEmpty,
            "the gameplay screen must mount no children at all; the world must stay reachable "
                + "behind it"
        )

        // Walked over the whole subtree so a future HUD container nesting a
        // full-bleed plate inside it still fails this gate, not just a
        // direct-children check.
        let sprites = Self.spriteNodes(in: gameplay.node)
        XCTAssertTrue(
            sprites.isEmpty,
            "the gameplay screen must mount no backdrop sprite anywhere in its subtree; the "
                + "scene's own backgroundColor supplies the dark base and the world renders "
                + "through this screen: found "
                + "\(sprites.map { $0.name ?? "an unnamed SKSpriteNode" })"
        )
    }

    /// The gameplay screen used to mount a neon "GAMEPLAY - WORLD COMING
    /// SOON" label from the days when `worldLayer` was empty on entry to
    /// `.gameplay`. The streamed ground plane (CYBERPUN-17-4), the building
    /// and rooftop-sign nodes (CYBERPUN-17-5) and the player actor
    /// (CYBERPUN-17-6) now all render there, so that label sat on top of the
    /// very content it denied - a screen that visually contradicts itself
    /// reads as "feature not delivered" to a human or a screenshot-driven
    /// verification, however correct the rendering behind it is.
    ///
    /// This pins the removal (CYBERPUN-17-5-t4) rather than trusting a
    /// deleted line to stay deleted. It walks the whole subtree, not just the
    /// immediate children, so re-introducing the text inside a HUD container
    /// fails here too. It deliberately does *not* forbid `SKLabelNode`
    /// outright: CYBERPUN-17-12 adds real HUD text (HP, XP, timer), which
    /// must not have to fight this gate.
    func test_gameplayScreenNode_mountsNoComingSoonText() {
        let gameplay = GameplayScreenNode()

        // Both before and after layout: the removal must not be something a
        // layout pass could put back.
        for insets in [UIEdgeInsets.zero, UIEdgeInsets(top: 20, left: 0, bottom: 40, right: 0)] {
            gameplay.layout(for: CGSize(width: 800, height: 400), safeAreaInsets: insets)

            for label in Self.labelNodes(in: gameplay.node) {
                let text = label.text ?? ""
                XCTAssertFalse(
                    text.uppercased().contains("COMING SOON"),
                    "the gameplay screen must not mount placeholder text over the rendered city: "
                        + "found \"\(text)\" on \(label.name ?? "an unnamed SKLabelNode")"
                )
            }
        }
    }

    /// The wording-agnostic half of the CYBERPUN-17-5-t4 pin. The gate above
    /// matches the literal text, which a *reworded* placeholder ("WORLD
    /// PENDING", "TODO: world") would slip straight past. This states the
    /// structural fact instead: the screen mounts no children at all, and no
    /// text anywhere in its subtree.
    ///
    /// This is the assertion CYBERPUN-17-12 is expected to *rewrite* when it
    /// adds real HUD content; the `mountsNoComingSoonText` gate above is the
    /// one that must survive it.
    func test_gameplayScreenNode_mountsNoChildren_andNoTextAnywhere() {
        let gameplay = GameplayScreenNode()

        // Before and after layout: neither construction nor a layout pass
        // may put content back.
        for insets in [UIEdgeInsets.zero, UIEdgeInsets(top: 20, left: 0, bottom: 40, right: 0)] {
            gameplay.layout(for: CGSize(width: 800, height: 400), safeAreaInsets: insets)

            XCTAssertTrue(
                gameplay.node.children.isEmpty,
                "the gameplay screen must mount no children at all; found "
                    + "\(gameplay.node.children.map { $0.name ?? "\(type(of: $0))" })"
            )

            let labels = Self.labelNodes(in: gameplay.node)
            XCTAssertTrue(
                labels.isEmpty,
                "the skeleton gameplay screen must mount no text at all - a reworded placeholder "
                    + "is still a placeholder painted over the rendered city: found "
                    + "\(labels.map { $0.text ?? "" })"
            )
        }
    }

    /// Anti-vacuity guard for the gate above: `GameplayScreenNode` mounts no
    /// labels at all now, so that assertion iterates an empty collection and
    /// would stay green even if `labelNodes(in:)` were blind. This proves the
    /// walk really does surface a label, including one nested inside a
    /// container (the shape a future HUD would use).
    func test_labelNodeWalk_findsNestedLabels_soTheComingSoonGateIsNotVacuous() {
        let root = SKNode()
        let container = SKNode()
        let nested = SKLabelNode(text: "WORLD COMING SOON")
        nested.name = "nestedPlaceholder"
        container.addChild(nested)
        root.addChild(container)
        root.addChild(SKLabelNode(text: "TOP LEVEL"))

        let found = Self.labelNodes(in: root)

        XCTAssertEqual(
            Set(found.map { $0.text ?? "" }), ["WORLD COMING SOON", "TOP LEVEL"],
            "the label walk must reach both a direct child and one nested inside a container"
        )
    }

    /// Anti-vacuity guard for the backdrop gate, which now shares the label
    /// gate's depth: `GameplayScreenNode` mounts no sprites at all, so that
    /// assertion also iterates an empty collection. This proves the walk
    /// really does surface a sprite nested inside a container - the shape a
    /// full-bleed HUD plate would take once CYBERPUN-17-12 adds a HUD
    /// container, and the case a direct-children check would miss.
    func test_spriteNodeWalk_findsNestedSprites_soTheBackdropGateIsNotVacuous() {
        let root = SKNode()
        let container = SKNode()
        let nested = SKSpriteNode(color: .black, size: CGSize(width: 800, height: 400))
        nested.name = "nestedPlate"
        container.addChild(nested)
        root.addChild(container)

        let found = Self.spriteNodes(in: root)

        XCTAssertEqual(
            found.map { $0.name ?? "" }, ["nestedPlate"],
            "the sprite walk must reach a plate nested inside a container, or the backdrop gate "
                + "is shallower than the label gate it sits beside"
        )
    }

    /// Recursive so a node nested inside a future HUD container is still seen
    /// by the gates above. Both the label gate and the backdrop gate are
    /// derived from this one walk so they cannot drift apart in depth.
    private static func descendants(of root: SKNode) -> [SKNode] {
        root.children.flatMap { [$0] + descendants(of: $0) }
    }

    private static func labelNodes(in root: SKNode) -> [SKLabelNode] {
        descendants(of: root).compactMap { $0 as? SKLabelNode }
    }

    private static func spriteNodes(in root: SKNode) -> [SKSpriteNode] {
        descendants(of: root).compactMap { $0 as? SKSpriteNode }
    }

    func test_gameplayScreenNode_willEnterAndWillExit_areNoOps() {
        let gameplay = GameplayScreenNode()
        gameplay.willEnter()
        gameplay.willExit()
        // Nothing to assert beyond "did not crash" \u2014 the skeleton screen has
        // no state machine of its own yet.
    }

    // MARK: - DeathScreenNode / HighScoresScreenNode fixtures (CYBERPUN-17-13 PR 2)

    /// A uniquely-named, per-test-isolated `HighScoreStore` -- the same
    /// per-test isolation shape `HighScoreStoreTests.makeIsolatedDefaults()`
    /// establishes, restated here so this file does not reach into that
    /// one's private helper. `cleanup()` removes the suite's persistent
    /// domain so nothing survives the test itself.
    private func makeIsolatedHighScoreStore() -> (store: HighScoreStore, cleanup: () -> Void) {
        let suiteName = "com.cyberpunkmonstercrawl.tests.screens.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (HighScoreStore(defaults: defaults), { defaults.removePersistentDomain(forName: suiteName) })
    }

    /// A fixture `RunSummary` computed through the real `RunScoreCalculator`
    /// from fixture `RunSummaryStats`/`RunStats`/`XPLevelSystem` state --
    /// per the story's own "using fixture ... state" test guidance -- with
    /// a distinct, individually recognisable value in every field, so a
    /// mixed-up row mapping (e.g. RABIES showing damage dealt) fails a
    /// value-based assertion instead of passing by coincidence.
    private func makeFixtureRunSummary() -> RunSummary {
        let runSummaryStats = RunSummaryStats()
        for _ in 0..<4 { runSummaryStats.recordKill() }
        runSummaryStats.recordInfection()
        runSummaryStats.recordInfection()

        let runStats = RunStats()
        runStats.recordDamage(88)

        let xpLevelSystem = XPLevelSystem()
        xpLevelSystem.awardXP(2 * XPLevelSystem.xpPerLevel) // level 3

        return RunScoreCalculator.summarize(
            runSummaryStats: runSummaryStats,
            runStats: runStats,
            xpLevelSystem: xpLevelSystem,
            elapsedSeconds: 125 // 2:05 -- exercises the mm:ss formatting
        )
    }

    private func makeDeathScreen(
        onRunAgain: @escaping () -> Void = {},
        onBackToMenu: @escaping () -> Void = {},
        runSummary: RunSummary? = nil,
        highScoreStore: HighScoreStore
    ) -> DeathScreenNode {
        let summary = runSummary ?? makeFixtureRunSummary()
        return DeathScreenNode(
            onRunAgain: onRunAgain,
            onBackToMenu: onBackToMenu,
            runSummaryProvider: { summary },
            highScoreStore: highScoreStore
        )
    }

    // MARK: - DeathScreenNode

    func test_deathScreenNode_runAgainButton_runsTheSuppliedClosure() {
        let (store, cleanup) = makeIsolatedHighScoreStore()
        defer { cleanup() }
        var runAgainTapped = false
        let death = makeDeathScreen(onRunAgain: { runAgainTapped = true }, highScoreStore: store)

        death.runAgainButton.handleTouch()

        XCTAssertTrue(runAgainTapped)
    }

    func test_deathScreenNode_backToMenuButton_runsTheSuppliedClosure() {
        let (store, cleanup) = makeIsolatedHighScoreStore()
        defer { cleanup() }
        var backToMenuTapped = false
        let death = makeDeathScreen(onBackToMenu: { backToMenuTapped = true }, highScoreStore: store)

        death.backToMenuButton.handleTouch()

        XCTAssertTrue(backToMenuTapped)
    }

    func test_deathScreenNode_layout_keepsButtonsDistinct() {
        let (store, cleanup) = makeIsolatedHighScoreStore()
        defer { cleanup() }
        let death = makeDeathScreen(highScoreStore: store)

        death.layout(for: CGSize(width: 400, height: 800), safeAreaInsets: .zero)

        XCTAssertNotEqual(death.runAgainButton.position.y, death.backToMenuButton.position.y)
    }

    /// AC1: dying shows all eight rows with the run's real values, computed
    /// via `RunScoreCalculator` from fixture `RunSummaryStats`/`RunStats`/
    /// `XPLevelSystem` state (see `makeFixtureRunSummary()`).
    func test_deathScreenNode_willEnter_populatesAllEightRowsWithTheRunsRealValues() {
        let (store, cleanup) = makeIsolatedHighScoreStore()
        defer { cleanup() }
        let summary = makeFixtureRunSummary()
        let death = makeDeathScreen(runSummary: summary, highScoreStore: store)

        death.willEnter()

        let rowTexts = Self.labelNodes(in: death.node).map { $0.text ?? "" }
        let expectedFragments = [
            "SURVIVED: 02:05",
            "RACCOONS DOWN: \(summary.raccoonsDown)",
            "LEVEL: \(summary.level)",
            "RABIES: \(summary.rabies)",
            "DAMAGE DEALT: \(summary.damageDealt)",
            "KILL BONUS: \(summary.killBonus)",
            "SURVIVAL: \(summary.survivalBonus)",
            "SCORE: \(summary.score)",
        ]
        for expected in expectedFragments {
            XCTAssertTrue(
                rowTexts.contains(expected),
                "expected a row reading \"\(expected)\", found \(rowTexts)"
            )
        }
    }

    /// The death screen must record into `HighScoreStore` exactly once per
    /// death: `willEnter()` fires once per genuine `.death` entry, but a
    /// rotation drives `layout(for:safeAreaInsets:)` too, and that must
    /// never record a second entry for the same death.
    func test_deathScreenNode_willEnter_recordsExactlyOneEntryPerDeath() throws {
        let (store, cleanup) = makeIsolatedHighScoreStore()
        defer { cleanup() }
        let death = makeDeathScreen(highScoreStore: store)

        death.willEnter()
        death.layout(for: CGSize(width: 400, height: 800), safeAreaInsets: .zero)
        death.layout(for: CGSize(width: 800, height: 400), safeAreaInsets: .zero)

        XCTAssertEqual(try store.sortedEntries().count, 1)
    }

    /// A second, separate death (RUN AGAIN then die again) is a genuinely
    /// new entry into `.death`, so it must record a second row.
    func test_deathScreenNode_secondWillEnter_recordsASecondEntry() throws {
        let (store, cleanup) = makeIsolatedHighScoreStore()
        defer { cleanup() }
        let death = makeDeathScreen(highScoreStore: store)

        death.willEnter()
        death.willEnter()

        XCTAssertEqual(try store.sortedEntries().count, 2)
    }

    /// `lastRecordedRunID` is what `GameViewController` threads into
    /// `HighScoresScreenNode`'s highlight -- it must match the entry that
    /// was actually just persisted, not merely be non-nil.
    func test_deathScreenNode_willEnter_lastRecordedRunID_matchesThePersistedEntry() throws {
        let (store, cleanup) = makeIsolatedHighScoreStore()
        defer { cleanup() }
        let death = makeDeathScreen(highScoreStore: store)

        death.willEnter()

        let recordedID = try XCTUnwrap(death.lastRecordedRunID)
        let entries = try store.sortedEntries()
        XCTAssertEqual(entries.map(\.id), [recordedID])
    }

    // MARK: - HighScoresScreenNode

    func test_highScoresScreenNode_backToMenuButton_runsTheSuppliedClosure() {
        let (store, cleanup) = makeIsolatedHighScoreStore()
        defer { cleanup() }
        var backToMenuTapped = false
        let highScores = HighScoresScreenNode(
            onBackToMenu: { backToMenuTapped = true },
            highScoreStore: store
        )

        highScores.backToMenuButton.handleTouch()

        XCTAssertTrue(backToMenuTapped)
    }

    func test_highScoresScreenNode_layout_resizesBackgroundToSceneSize() {
        let (store, cleanup) = makeIsolatedHighScoreStore()
        defer { cleanup() }
        let highScores = HighScoresScreenNode(onBackToMenu: {}, highScoreStore: store)
        let size = CGSize(width: 400, height: 800)

        highScores.layout(for: size, safeAreaInsets: .zero)

        let background = highScores.node.children.compactMap { $0 as? SKSpriteNode }.first
        XCTAssertEqual(background?.size, size)
    }

    /// AC4: the high-scores screen displays the persisted table sorted
    /// descending by score, matching `HighScoreStore.sortedEntries()`'s own
    /// order exactly.
    func test_highScoresScreenNode_willEnter_rendersEntries_sortedDescending() throws {
        let (store, cleanup) = makeIsolatedHighScoreStore()
        defer { cleanup() }
        for score in [100, 900, 450] {
            try store.recordRun(RunSummary(
                survivedSeconds: 10, raccoonsDown: 1, level: 1, rabies: 0,
                damageDealt: score, killBonus: 0, survivalBonus: 0, score: score
            ))
        }
        let highScores = HighScoresScreenNode(onBackToMenu: {}, highScoreStore: store)
        highScores.layout(for: CGSize(width: 400, height: 800), safeAreaInsets: .zero)

        highScores.willEnter()

        let rowTexts = (0..<3).map { index in
            Self.labelNodes(in: highScores.node).first { $0.name == "highScores.row.\(index)" }?.text ?? ""
        }
        XCTAssertEqual(rowTexts, ["#1  SCORE 900", "#2  SCORE 450", "#3  SCORE 100"])
    }

    /// A fresh table shows the empty-state message, not a zero-row table
    /// that could be mistaken for "not implemented".
    func test_highScoresScreenNode_willEnter_emptyTable_showsEmptyState() {
        let (store, cleanup) = makeIsolatedHighScoreStore()
        defer { cleanup() }
        let highScores = HighScoresScreenNode(onBackToMenu: {}, highScoreStore: store)
        highScores.layout(for: CGSize(width: 400, height: 800), safeAreaInsets: .zero)

        highScores.willEnter()

        let emptyState = highScores.node.children.first { $0.name == "highScores.emptyState" } as? SKLabelNode
        XCTAssertEqual(emptyState?.isHidden, false)
    }

    /// AC4's highlight must key off the entry's stable `id`, not its score:
    /// two tied entries are otherwise indistinguishable, and the wrong one
    /// highlighting would silently misreport whose run just finished.
    func test_highScoresScreenNode_willEnter_highlightsByID_evenWithATiedScore() throws {
        let (store, cleanup) = makeIsolatedHighScoreStore()
        defer { cleanup() }

        let tiedSummary = RunSummary(
            survivedSeconds: 10, raccoonsDown: 1, level: 1, rabies: 0,
            damageDealt: 250, killBonus: 0, survivalBonus: 0, score: 250
        )
        let firstID = UUID()
        let secondID = UUID()
        try store.recordRun(tiedSummary, id: firstID)
        try store.recordRun(tiedSummary, id: secondID)

        let highScores = HighScoresScreenNode(
            onBackToMenu: {},
            highScoreStore: store,
            highlightedRunIDProvider: { secondID }
        )
        highScores.layout(for: CGSize(width: 400, height: 800), safeAreaInsets: .zero)

        highScores.willEnter()

        let rows = (0..<2).compactMap { index in
            Self.labelNodes(in: highScores.node).first { $0.name == "highScores.row.\(index)" }
        }
        XCTAssertEqual(rows.count, 2)
        let entries = try store.sortedEntries()
        let firstRowEntryIsSecondID = entries[0].id == secondID
        let highlightedRow = firstRowEntryIsSecondID ? rows[0] : rows[1]
        let otherRow = firstRowEntryIsSecondID ? rows[1] : rows[0]

        Self.assertColorsEqual(highlightedRow.fontColor, PixelGritPalette.neonAccent)
        Self.assertColorsNotEqual(otherRow.fontColor, PixelGritPalette.neonAccent)
    }

    /// `UIColor` equality (and even its `description`) can disagree for two
    /// colors that were constructed identically, because the components are
    /// stored as float32 under the hood — comparing the `UIColor` objects
    /// directly is flaky. Compare the RGBA components with a tolerance instead.
    private static func rgbaComponents(_ color: UIColor?) -> (CGFloat, CGFloat, CGFloat, CGFloat)? {
        guard let color else { return nil }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return (r, g, b, a)
    }

    private static func assertColorsEqual(
        _ lhs: UIColor?, _ rhs: UIColor?, accuracy: CGFloat = 1e-4,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        guard let l = rgbaComponents(lhs), let r = rgbaComponents(rhs) else {
            XCTFail("expected both colors to be convertible to RGBA components", file: file, line: line)
            return
        }
        XCTAssertEqual(l.0, r.0, accuracy: accuracy, "red component mismatch", file: file, line: line)
        XCTAssertEqual(l.1, r.1, accuracy: accuracy, "green component mismatch", file: file, line: line)
        XCTAssertEqual(l.2, r.2, accuracy: accuracy, "blue component mismatch", file: file, line: line)
        XCTAssertEqual(l.3, r.3, accuracy: accuracy, "alpha component mismatch", file: file, line: line)
    }

    private static func assertColorsNotEqual(
        _ lhs: UIColor?, _ rhs: UIColor?, accuracy: CGFloat = 1e-4,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        guard let l = rgbaComponents(lhs), let r = rgbaComponents(rhs) else {
            XCTFail("expected both colors to be convertible to RGBA components", file: file, line: line)
            return
        }
        let isEqual = abs(l.0 - r.0) < accuracy && abs(l.1 - r.1) < accuracy
            && abs(l.2 - r.2) < accuracy && abs(l.3 - r.3) < accuracy
        XCTAssertFalse(isEqual, "expected colors to differ, but they matched within tolerance", file: file, line: line)
    }
}
