import CoreGraphics
import SpriteKit
import UIKit

/// Elapsed-run-time label: construct + `update(elapsedSeconds:)` only -- no
/// positioning logic (`HUDLayout` owns where this mounts).
final class RunTimerLabel: SKNode {

    // MARK: - Nodes

    private let label: SKLabelNode

    // MARK: - State

    private(set) var elapsedSeconds: TimeInterval = 0

    /// `mm:ss`, always two digits each -- `formattedText(forElapsedSeconds:)`
    /// is the pure function under test; `label.text` is kept in sync with it
    /// on every `update(elapsedSeconds:)` call.
    private(set) var formattedText: String = "00:00"

    // MARK: - Init

    override init() {
        let label = SKLabelNode(text: "00:00")
        label.fontName = "Menlo-Bold"
        label.fontSize = 22
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        self.label = label

        super.init()

        name = "runTimerLabel"

        // Deliberately **not** an accessibility element, on this node and
        // on its label child -- see `HPSegmentBar`'s own rationale. The
        // label child matters most here: an `SKLabelNode` published in its
        // own right is exactly how a `ButtonNode`'s label once stole its
        // button's activation point.
        isAccessibilityElement = false
        label.isAccessibilityElement = false

        addChild(label)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Update

    /// Negative input is clamped to `0` rather than producing a negative
    /// clock face.
    func update(elapsedSeconds: TimeInterval) {
        let clamped = max(0, elapsedSeconds)
        self.elapsedSeconds = clamped
        formattedText = Self.formattedText(forElapsedSeconds: clamped)
        label.text = formattedText
    }

    /// `mm:ss`, both fields zero-padded to two digits. Minutes are not
    /// capped at 59 -- a run comfortably longer than an hour still reads as
    /// e.g. `"75:03"` rather than wrapping into an hours field nothing else
    /// in this HUD needs.
    static func formattedText(forElapsedSeconds elapsedSeconds: TimeInterval) -> String {
        let totalWholeSeconds = Int(elapsedSeconds.rounded(.down))
        let minutes = totalWholeSeconds / 60
        let seconds = totalWholeSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
