import os
import SpriteKit
import UIKit

/// The real `.death` screen (`CYBERPUN-17-13` PR 2): the eight run-summary
/// rows named in the design brief -- SURVIVED, RACCOONS DOWN, LEVEL,
/// RABIES, DAMAGE DEALT, KILL BONUS, SURVIVAL, SCORE -- computed via
/// `RunScoreCalculator` and persisted into `HighScoreStore` exactly once
/// per death.
///
/// The RUN AGAIN / back-to-menu navigation is unchanged from the skeleton
/// this replaces (`CYBERPUN-17-2`): both closures are still wired straight
/// to the shared `GameStateMachine` by `GameViewController`. Only the
/// `// SCAFFOLDING(CYBERPUN-17-13)` placeholder background + label are
/// gone -- replaced by the row content below.
final class DeathScreenNode: ScreenNode {

    let node = SKNode()

    /// Exposed for tests: proves death has a reachable path back into a run.
    let runAgainButton: ButtonNode

    /// Exposed for tests: proves death has a reachable path back to the menu.
    let backToMenuButton: ButtonNode

    /// The `HighScoreEntry.id` this screen's most recent `willEnter()`
    /// recorded into `highScoreStore`, if any. `GameViewController` threads
    /// this into `HighScoresScreenNode`'s `highlightedRunIDProvider` so a
    /// run that made the table is highlighted there -- matched by this
    /// stable id rather than by score, since two runs can tie.
    private(set) var lastRecordedRunID: UUID?

    private let background: SKSpriteNode
    private let titleLabel = SKLabelNode(text: "YOU DIED")

    /// The eight run-summary row labels, in the design brief's fixed order.
    /// Built once at construction -- unlike `HighScoresScreenNode`'s row
    /// count, this screen's row count never varies, so only each label's
    /// `.text` changes, on every `willEnter()`.
    private let summaryRowLabels: [SKLabelNode]

    /// Computes this run's summary on demand. `GameViewController` wires
    /// this to read `GameScene`'s live `runStats` / `playerCombat` /
    /// `runElapsedSeconds` at the moment this screen enters, so the values
    /// shown are exactly the ones the run just ended with -- never a stale
    /// snapshot taken earlier.
    ///
    /// `nil` means "no run happened" (`.death` entered without a player
    /// ever having been mounted -- a test, or the DEBUG `LaunchGotoState`
    /// hook). That case renders the zero placeholder below but records
    /// **nothing**: a fake `score: 0` row persisted into the player's real
    /// table is a far stronger side effect than a well-defined return
    /// value needs to be.
    private let runSummaryProvider: () -> RunSummary?

    /// The persisted high-score table `willEnter()` records this run's
    /// summary into.
    private let highScoreStore: HighScoreStore

    private static let rowCount = 8

    /// Rendered when `runSummaryProvider()` returns `nil` (no run
    /// happened). Display-only: `willEnter()` never records it, so it can
    /// never reach `HighScoreStore`.
    private static let noRunSummary = RunSummary(
        survivedSeconds: 0, raccoonsDown: 0, level: 1, rabies: 0,
        damageDealt: 0, killBonus: 0, survivalBonus: 0, score: 0
    )

    /// - Parameters:
    ///   - onRunAgain: run when RUN AGAIN is tapped. `GameViewController`
    ///     passes `stateMachine.transition(to: .gameplay)`.
    ///   - onBackToMenu: run when the back-to-menu entry is tapped.
    ///     `GameViewController` passes `stateMachine.transition(to: .menu)`.
    ///   - runSummaryProvider: computes the just-ended run's `RunSummary`,
    ///     or `nil` when no run happened. Called exactly once per
    ///     `willEnter()` -- never on a mere `layout(for:safeAreaInsets:)`
    ///     pass (a rotation) -- so a fixture closure in a test can assert
    ///     it is called the expected number of times.
    ///   - highScoreStore: the table `willEnter()` records into.
    init(
        onRunAgain: @escaping () -> Void,
        onBackToMenu: @escaping () -> Void,
        runSummaryProvider: @escaping () -> RunSummary?,
        highScoreStore: HighScoreStore
    ) {
        self.runSummaryProvider = runSummaryProvider
        self.highScoreStore = highScoreStore

        background = SKSpriteNode(color: PixelGritPalette.background, size: CGSize(width: 1, height: 1))

        runAgainButton = ButtonNode(
            title: "RUN AGAIN",
            size: CGSize(width: 220, height: 64),
            accentColor: PixelGritPalette.neonAccent,
            accessibilityIdentifier: "death.runAgainButton",
            action: onRunAgain
        )
        backToMenuButton = ButtonNode(
            title: "BACK TO MENU",
            size: CGSize(width: 220, height: 48),
            accessibilityIdentifier: "death.backToMenuButton",
            action: onBackToMenu
        )

        titleLabel.fontName = "Menlo-Bold"
        titleLabel.fontSize = 22
        titleLabel.fontColor = PixelGritPalette.neonAccent
        titleLabel.verticalAlignmentMode = .center
        titleLabel.horizontalAlignmentMode = .center

        summaryRowLabels = (0..<DeathScreenNode.rowCount).map { index in
            let label = SKLabelNode(text: "")
            label.name = "death.summaryRow.\(index)"
            label.fontName = "Menlo"
            label.fontSize = 15
            label.fontColor = .white
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = .center
            return label
        }

        node.name = "deathScreen"
        node.addChild(background)
        node.addChild(titleLabel)
        for label in summaryRowLabels {
            node.addChild(label)
        }
        node.addChild(runAgainButton)
        node.addChild(backToMenuButton)
    }

    func willEnter() {
        let summary = runSummaryProvider()
        for (label, text) in zip(summaryRowLabels, Self.rowTexts(for: summary ?? Self.noRunSummary)) {
            label.text = text
        }

        // Nothing to record when no run happened: `.death` reached without
        // a player having been mounted is a test/DEBUG-hook path, and
        // persisting its placeholder zeros would append a fake
        // `score: 0` / `SURVIVED 00:00` row to the player's real table --
        // permanently, and to a table that could then never show its
        // empty state again.
        guard let summary else {
            lastRecordedRunID = nil
            return
        }

        // Recorded exactly once per death: this method fires once per
        // genuine `.death` entry (`GameScene.transitionScreens(to:)`), and
        // never again for a mere `layout(for:safeAreaInsets:)` pass (a
        // rotation) -- so the only way to record a second entry is RUN
        // AGAIN followed by a second, separate death, which is correct.
        let runID = UUID()
        do {
            try highScoreStore.recordRun(summary, id: runID)
            lastRecordedRunID = runID
        } catch {
            // Persistence failing must not stop the summary from being
            // shown -- the player still sees what they earned this run,
            // there is simply nothing new to highlight on the high-scores
            // screen. Logged rather than merely swallowed: without this,
            // "this run didn't make the table" and "the write failed" look
            // identical from the outside, and `HighScoreStore` went to
            // some trouble to tell its failures apart.
            GameLog.persistence.error(
                "death screen could not record this run: \(String(describing: error), privacy: .public)"
            )
            lastRecordedRunID = nil
        }
    }

    func willExit() {}

    /// Stacks the title and all eight rows above a reserved, bottom-pinned
    /// block holding the two buttons, between the safe-area-adjusted top
    /// and bottom edges, so nothing is clipped or pushed under a
    /// notch/home indicator in either orientation.
    ///
    /// Delegated to `ScreenStackLayout.position(...)` -- see there for why
    /// the buttons get a height-aware reserved block instead of a share of
    /// one even spacing: an 852x393 landscape gave eleven evenly spaced
    /// items ~32.7pt between centres, which the 72pt RUN AGAIN and 48pt
    /// BACK TO MENU overlapped by ~23pt.
    func layout(for size: CGSize, safeAreaInsets: UIEdgeInsets) {
        background.size = size
        background.position = .zero

        ScreenStackLayout.position(
            flexibleItems: [titleLabel] + summaryRowLabels,
            pinnedToBottom: [runAgainButton, backToMenuButton],
            topLimit: size.height / 2 - safeAreaInsets.top,
            bottomLimit: -size.height / 2 + safeAreaInsets.bottom
        )
    }

    /// SURVIVED/SURVIVAL formatting: `RunScoreCalculator`'s own doc comment
    /// leaves the numeric-to-display formatting to the screen layer --
    /// SURVIVED renders as `mm:ss`, every other row as a plain integer.
    private static func rowTexts(for summary: RunSummary) -> [String] {
        [
            "SURVIVED: \(formattedDuration(summary.survivedSeconds))",
            "RACCOONS DOWN: \(summary.raccoonsDown)",
            "LEVEL: \(summary.level)",
            "RABIES: \(summary.rabies)",
            "DAMAGE DEALT: \(summary.damageDealt)",
            "KILL BONUS: \(summary.killBonus)",
            "SURVIVAL: \(summary.survivalBonus)",
            "SCORE: \(summary.score)",
        ]
    }

    private static func formattedDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}
