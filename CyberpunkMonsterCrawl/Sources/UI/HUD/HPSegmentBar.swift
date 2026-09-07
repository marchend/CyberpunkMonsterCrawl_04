import CoreGraphics
import SpriteKit
import UIKit

/// Segmented HP node: construct + `update(currentHP:maxHP:)` only -- no
/// positioning logic lives here (`HUDLayout` owns where this mounts).
///
/// "Pixel Grit" styling: a dark plate (`PixelGritPalette.plate`) behind a
/// fixed row of `segmentCount` blocky segments, each either lit
/// (`PixelGritPalette.neonAccent`, a hot cyan -- reserved for the player's
/// own vitals the same way `ButtonNode`'s accent frame reserves it for the
/// primary action) or "weathered": a dim, desaturated fill
/// (`emptySegmentColor`) rather than fully black, so a spent segment still
/// reads as part of the same worn plate instead of a hole punched out of it.
/// Thin gaps (`segmentSpacing`) between segments read as the plate's own
/// grime/wear lines rather than smooth, continuous fill.
final class HPSegmentBar: SKNode {

    // MARK: - Tunables

    /// Mirrors `HUDLayout.hpBarSize` rather than re-declaring it, so the
    /// element's own drawn size and the slot `HUDLayout` reserves for it can
    /// never silently drift apart (the same convention the old
    /// `Sources/UI/PulseButton.swift` used for its own `size`).
    static let barSize = HUDLayout.hpBarSize
    static let segmentCount = 10
    static let segmentSpacing: CGFloat = 3

    /// Dim fill for a spent segment -- deliberately not fully black, so the
    /// segment still reads as "weathered plate", not "missing".
    static let emptySegmentColor = UIColor(white: 0.18, alpha: 1.0)

    // MARK: - Nodes

    private let plate: SKSpriteNode
    private var segments: [SKSpriteNode] = []

    // MARK: - State

    private(set) var currentHP: Int = 0
    private(set) var maxHP: Int = 1

    /// How many of `segmentCount` segments are currently lit. Exposed so
    /// tests (and a future consumer) can read the discretized value
    /// directly rather than re-deriving it from `currentHP`/`maxHP`.
    private(set) var filledSegments: Int = 0

    // MARK: - Init

    override init() {
        plate = SKSpriteNode(color: PixelGritPalette.plate, size: Self.barSize)
        super.init()

        name = "hpSegmentBar"
        plate.name = "hpSegmentBar.plate"
        addChild(plate)

        let segmentWidth = (Self.barSize.width - Self.segmentSpacing * CGFloat(Self.segmentCount - 1))
            / CGFloat(Self.segmentCount)
        let segmentSize = CGSize(width: segmentWidth, height: Self.barSize.height - 6)
        let leftEdge = -Self.barSize.width / 2

        for index in 0..<Self.segmentCount {
            let segment = SKSpriteNode(color: Self.emptySegmentColor, size: segmentSize)
            segment.name = "hpSegmentBar.segment.\(index)"
            segment.anchorPoint = CGPoint(x: 0, y: 0.5)
            segment.position = CGPoint(
                x: leftEdge + CGFloat(index) * (segmentWidth + Self.segmentSpacing),
                y: 0
            )
            addChild(segment)
            segments.append(segment)
        }

        update(currentHP: 0, maxHP: 1)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Update

    /// Clamps `currentHP` to `0...maxHP` (and `maxHP` to at least `1`, so a
    /// caller can never divide by zero), then lights the proportional whole
    /// number of segments -- rounded to the nearest segment, so a sliver of
    /// remaining HP still shows as at least a rounding-consistent read of
    /// the player's state rather than only ever flooring towards empty.
    func update(currentHP: Int, maxHP: Int) {
        let clampedMax = max(1, maxHP)
        let clampedCurrent = min(max(0, currentHP), clampedMax)
        self.maxHP = clampedMax
        self.currentHP = clampedCurrent

        let fraction = CGFloat(clampedCurrent) / CGFloat(clampedMax)
        filledSegments = Int((fraction * CGFloat(Self.segmentCount)).rounded())

        for (index, segment) in segments.enumerated() {
            segment.color = index < filledSegments ? PixelGritPalette.neonAccent : Self.emptySegmentColor
        }
    }
}
