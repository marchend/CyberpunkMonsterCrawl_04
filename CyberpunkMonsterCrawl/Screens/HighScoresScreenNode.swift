import os
import SpriteKit
import UIKit

/// The real `.highScores` screen (`CYBERPUN-17-13` PR 2): the persisted
/// top-`HighScoreStore.defaultMaxEntries` table, sorted descending (per
/// `HighScoreStore.sortedEntries()`'s own deterministic ranking), with the
/// just-finished run's row highlighted when it made the table.
///
/// The back-to-menu navigation is unchanged from the skeleton this
/// replaces (`CYBERPUN-17-2`): still wired straight to the shared
/// `GameStateMachine` by `GameViewController`. The prior placeholder
/// background and label are gone -- replaced by the row content below.
final class HighScoresScreenNode: ScreenNode {

    let node = SKNode()

    /// Exposed for tests: proves high scores has a reachable path back to
    /// the menu.
    let backToMenuButton: ButtonNode

    private let background: SKSpriteNode
    private let titleLabel = SKLabelNode(text: "HIGH SCORES")

    /// Shown in place of the row list when the table has no entries yet.
    private let emptyStateLabel = SKLabelNode(text: "NO RUNS YET")

    /// One label per persisted entry, rebuilt on every `willEnter()` from
    /// `highScoreStore.sortedEntries()`. Unlike `DeathScreenNode`'s fixed
    /// eight rows, this table's row count varies with how many runs have
    /// been recorded (`0...HighScoreStore.defaultMaxEntries`), so the
    /// nodes themselves -- not just their text -- are rebuilt each time.
    private var rowLabels: [SKLabelNode] = []

    private let highScoreStore: HighScoreStore

    /// Supplies the `HighScoreEntry.id` (if any) to highlight -- the
    /// just-finished run's recorded id, threaded in by `GameViewController`
    /// from `DeathScreenNode.lastRecordedRunID`. Matched by id, never by
    /// score: two runs can tie, and only a stable identity tells them apart.
    private let highlightedRunIDProvider: () -> UUID?

    /// The most recent `layout(for:safeAreaInsets:)` arguments, cached so
    /// `willEnter()` (which rebuilds `rowLabels` to a new count) can
    /// reposition the freshly built rows without waiting for a fresh
    /// layout pass. `GameScene.transitionScreens(to:)` calls
    /// `layout(for:safeAreaInsets:)` *before* `willEnter()`, so by the time
    /// `willEnter()` runs these already hold real values.
    private var lastLayoutSize: CGSize = .zero
    private var lastLayoutSafeAreaInsets: UIEdgeInsets = .zero

    /// - Parameters:
    ///   - onBackToMenu: run when the back-to-menu entry is tapped.
    ///     `GameViewController` passes `stateMachine.transition(to: .menu)`.
    ///   - highScoreStore: the table read on every `willEnter()`.
    ///   - highlightedRunIDProvider: see the property of the same name.
    ///     Defaults to "nothing to highlight" so tests that don't care
    ///     about highlighting need not supply one.
    init(
        onBackToMenu: @escaping () -> Void,
        highScoreStore: HighScoreStore,
        highlightedRunIDProvider: @escaping () -> UUID? = { nil }
    ) {
        self.highScoreStore = highScoreStore
        self.highlightedRunIDProvider = highlightedRunIDProvider

        background = SKSpriteNode(color: PixelGritPalette.background, size: CGSize(width: 1, height: 1))

        backToMenuButton = ButtonNode(
            title: "BACK TO MENU",
            size: CGSize(width: 220, height: 48),
            accessibilityIdentifier: "highScores.backToMenuButton",
            action: onBackToMenu
        )

        titleLabel.fontName = "Menlo-Bold"
        titleLabel.fontSize = 20
        titleLabel.fontColor = .white
        titleLabel.verticalAlignmentMode = .center
        titleLabel.horizontalAlignmentMode = .center

        emptyStateLabel.name = "highScores.emptyState"
        emptyStateLabel.fontName = "Menlo"
        emptyStateLabel.fontSize = 15
        emptyStateLabel.fontColor = PixelGritPalette.neonSecondary
        emptyStateLabel.verticalAlignmentMode = .center
        emptyStateLabel.horizontalAlignmentMode = .center
        emptyStateLabel.isHidden = true

        node.name = "highScoresScreen"
        node.addChild(background)
        node.addChild(titleLabel)
        node.addChild(emptyStateLabel)
        node.addChild(backToMenuButton)
    }

    func willEnter() {
        rebuildRows()
        positionContent()
    }

    func willExit() {}

    func layout(for size: CGSize, safeAreaInsets: UIEdgeInsets) {
        lastLayoutSize = size
        lastLayoutSafeAreaInsets = safeAreaInsets
        background.size = size
        background.position = .zero
        positionContent()
    }

    /// Reads the persisted table and rebuilds `rowLabels` to match: one
    /// label per entry, in the store's own best-first order, highlighting
    /// whichever entry's `id` matches `highlightedRunIDProvider()`.
    ///
    /// An unreadable table (`HighScoreStoreError.storedDataUnreadable`)
    /// renders as empty rather than crashing this screen -- the player
    /// still sees the empty-state message and can navigate away.
    private func rebuildRows() {
        for label in rowLabels {
            label.removeFromParent()
        }
        rowLabels.removeAll()

        var entries: [HighScoreEntry] = []
        do {
            entries = try highScoreStore.sortedEntries()
        } catch {
            // Logged rather than merely swallowed: an unreadable (i.e.
            // quarantined, `HighScoreStoreError.storedDataUnreadable`)
            // payload renders below as the "NO RUNS YET" empty state, so
            // without this line the screen tells the player their table is
            // empty when it is in fact intact-but-unreadable, and nothing
            // anywhere records that the read failed.
            GameLog.persistence.error(
                "high-scores screen could not read the table: \(String(describing: error), privacy: .public)"
            )
        }
        emptyStateLabel.isHidden = !entries.isEmpty

        let highlightedID = highlightedRunIDProvider()

        for (index, entry) in entries.enumerated() {
            let label = SKLabelNode(text: "#\(index + 1)  SCORE \(entry.score)")
            label.name = "highScores.row.\(index)"
            label.fontName = "Menlo"
            label.fontSize = 15
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = .center
            label.fontColor = entry.id == highlightedID ? PixelGritPalette.neonAccent : .white
            node.addChild(label)
            rowLabels.append(label)
        }
    }

    /// Stacks the title and the row list (or the empty-state message when
    /// there are no entries) above a reserved, bottom-pinned block holding
    /// the back-to-menu button, between the safe-area-adjusted top and
    /// bottom edges -- the same `ScreenStackLayout.position(...)` call
    /// `DeathScreenNode.layout(for:safeAreaInsets:)` makes, now shared
    /// rather than restated, so a full table (twelve items in landscape,
    /// which the old even-spacing scheme squeezed to ~29.8pt between
    /// centres under a 48pt button) cannot overlap the button.
    ///
    /// A no-op before the first real `layout(for:safeAreaInsets:)` call
    /// (`lastLayoutSize == .zero`), which only a headless construction
    /// with no layout pass at all could observe.
    private func positionContent() {
        guard lastLayoutSize != .zero else { return }
        let size = lastLayoutSize
        let safeAreaInsets = lastLayoutSafeAreaInsets

        let middleItems: [SKNode] = rowLabels.isEmpty ? [emptyStateLabel] : rowLabels

        ScreenStackLayout.position(
            flexibleItems: [titleLabel] + middleItems,
            pinnedToBottom: [backToMenuButton],
            topLimit: size.height / 2 - safeAreaInsets.top,
            bottomLimit: -size.height / 2 + safeAreaInsets.bottom
        )
    }
}
