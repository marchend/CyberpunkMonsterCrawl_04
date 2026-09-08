import CoreGraphics
import SpriteKit
import UIKit

/// Level label + XP fill bar: construct + `update(level:currentXP:
/// xpForNextLevel:)` only -- no positioning logic (`HUDLayout` owns where
/// this mounts).
final class LevelXPBar: SKNode {

    // MARK: - Tunables

    /// Mirrors `HUDLayout.levelXPBarSize` rather than re-declaring it -- see
    /// `HPSegmentBar.barSize`'s doc comment for why.
    static let barSize = HUDLayout.levelXPBarSize

    // MARK: - Nodes

    private let plate: SKSpriteNode
    private let fill: SKSpriteNode
    private let levelLabel: SKLabelNode

    // MARK: - State

    private(set) var level: Int = 1
    private(set) var currentXP: Int = 0
    private(set) var xpForNextLevel: Int = 1

    /// `currentXP / xpForNextLevel`, clamped to `0...1`. Exposed so a test
    /// (or a future consumer) can read the discretized fraction directly
    /// rather than re-deriving it.
    private(set) var xpFraction: CGFloat = 0

    // MARK: - Init

    override init() {
        plate = SKSpriteNode(color: PixelGritPalette.plate, size: Self.barSize)
        fill = SKSpriteNode(color: PixelGritPalette.neonAccent, size: CGSize(width: 0, height: Self.barSize.height))

        let label = SKLabelNode(text: "LV 1")
        label.fontName = "Menlo-Bold"
        label.fontSize = 14
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .left
        label.position = CGPoint(x: Self.barSize.width / 2 + 8, y: 0)
        levelLabel = label

        super.init()

        name = "levelXPBar"
        plate.name = "levelXPBar.plate"
        fill.name = "levelXPBar.fill"

        // Deliberately **not** an accessibility element, on this node and
        // on each of its drawn children -- see `HPSegmentBar`'s own
        // rationale (same top-left position inside the floating stick's
        // touch-acceptance box, same "a published mirror wins the hit test
        // for its rect" consequence). A passive read-out publishes nothing.
        isAccessibilityElement = false
        plate.isAccessibilityElement = false
        fill.isAccessibilityElement = false
        levelLabel.isAccessibilityElement = false

        fill.anchorPoint = CGPoint(x: 0, y: 0.5)
        fill.position = CGPoint(x: -Self.barSize.width / 2, y: 0)

        addChild(plate)
        addChild(fill)
        addChild(levelLabel)

        update(level: 1, currentXP: 0, xpForNextLevel: 1)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Update

    /// Clamps `xpForNextLevel` to at least `1` (never divide by zero) and
    /// `currentXP` to `0...xpForNextLevel`. A level-up simply arrives here
    /// as a lower `currentXP` alongside a higher `level` -- the fill bar
    /// re-derives its width fresh from the new fraction every call, so no
    /// separate "reset" path is needed for the fill to visibly shrink back
    /// down on a level-up.
    func update(level: Int, currentXP: Int, xpForNextLevel: Int) {
        self.level = level
        let clampedNext = max(1, xpForNextLevel)
        let clampedCurrent = min(max(0, currentXP), clampedNext)
        self.xpForNextLevel = clampedNext
        self.currentXP = clampedCurrent

        xpFraction = CGFloat(clampedCurrent) / CGFloat(clampedNext)
        fill.size = CGSize(width: Self.barSize.width * xpFraction, height: Self.barSize.height)
        levelLabel.text = "LV \(level)"
    }
}
