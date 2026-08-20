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
    private let runSummaryProvider: () -> RunSummary

    /// The persisted high-score table `willEnter()` records this run's
    /// summary into.
    private let highScoreStore: HighScoreStore

    private static let rowCount = 8

    /// - Parameters:
    ///   - onRunAgain: run when RUN AGAIN is tapped. `GameViewController`
    ///     passes `stateMachine.transition(to: .gameplay)`.
    ///   - onBackToMenu: run when the back-to-menu entry is tapped.
    ///     `GameViewController` passes `stateMachine.transition(to: .menu)`.
    ///   - runSummaryProvider: computes the just-ended run's `RunSummary`.
    ///     Called exactly once per `willEnter()` -- never on a mere
    ///     `layout(for:safeAreaInsets:)` pass (a rotation) -- so a fixture
    ///     closure in a test can assert it is called the expected number
    ///     of times.
    ///   - highScoreStore: the table `willEnter()` records into.
    init(
        onRunAgain: @escaping () -> Void,
        onBackToMenu: @escaping () -> Void,
        runSummaryProvider: @escaping () -> RunSummary,
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
        for (label, text) in zip(summaryRowLabels, Self.rowTexts(for: summary)) {
            label.text = text
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
            // screen.
            lastRecordedRunID = nil
        }
    }

    func willExit() {}

    /// Stacks the title, all eight rows and both buttons in one evenly
    /// spaced vertical sequence between the safe-area-adjusted top and
    /// bottom edges, so nothing is clipped or pushed under a notch/home
    /// indicator in either orientation -- the same "position every item at
    /// a fixed fraction of the available height" shape that keeps this
    /// correct regardless of how tall or short `size` is, rather than a
    /// set of hand-picked offsets tuned for one aspect ratio.
    func layout(for size: CGSize, safeAreaInsets: UIEdgeInsets) {
        background.size = size
        background.position = .zero

        let topLimit = size.height / 2 - safeAreaInsets.top
        let bottomLimit = -size.height / 2 + safeAreaInsets.bottom
        let availableHeight = topLimit - bottomLimit

        let items: [SKNode] = [titleLabel] + summaryRowLabels + [runAgainButton, backToMenuButton]
        let margin = availableHeight * 0.06
        let usableHeight = max(0, availableHeight - margin * 2)
        let step = items.count > 1 ? usableHeight / CGFloat(items.count - 1) : 0

        for (index, item) in items.enumerated() {
            item.position = CGPoint(x: 0, y: topLimit - margin - step * CGFloat(index))
        }
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
