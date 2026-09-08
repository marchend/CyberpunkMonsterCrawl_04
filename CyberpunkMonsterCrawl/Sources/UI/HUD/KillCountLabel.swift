import CoreGraphics
import SpriteKit
import UIKit

/// Kill counter: construct + `update(kills:)` only -- no positioning logic
/// (`HUDLayout` owns where this mounts).
final class KillCountLabel: SKNode {

    // MARK: - Nodes

    private let label: SKLabelNode

    // MARK: - State

    private(set) var kills: Int = 0

    /// The pure formatting function under test; `label.text` is kept in
    /// sync with it on every `update(kills:)` call.
    private(set) var formattedText: String = ""

    // MARK: - Init

    override init() {
        let label = SKLabelNode(text: "")
        label.fontName = "Menlo-Bold"
        label.fontSize = 20
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        self.label = label

        super.init()

        name = "killCountLabel"

        // Deliberately **not** an accessibility element, on this node and
        // on its label child -- see `HPSegmentBar`'s own rationale (and
        // `RunTimerLabel` for why the `SKLabelNode` child is the part that
        // matters).
        isAccessibilityElement = false
        label.isAccessibilityElement = false

        addChild(label)

        update(kills: 0)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Update

    /// Negative input is clamped to `0` rather than producing a negative
    /// kill count.
    func update(kills: Int) {
        self.kills = max(0, kills)
        formattedText = "KILLS \(self.kills)"
        label.text = formattedText
    }
}
