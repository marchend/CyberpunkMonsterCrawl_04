import CoreGraphics
import UIKit

/// The six HUD elements `CYBERPUN-17-12` mounts, and the one name
/// `HUDLayout` computes a frame for.
enum HUDSlot: CaseIterable {
    case hpBar
    case levelXPBar
    case runTimer
    case killCount
    case pulseButton
    case swarmBanner
}

/// Pure layout-spec type: `(sceneSize, safeAreaInsets) -> [HUDSlot: CGRect]`.
///
/// No `SKNode`/SpriteKit import here on purpose -- this is the same split
/// `FloatingThumbstickNode`'s own static geometry helpers
/// (`leftRegion(forSize:safeAreaInsets:)`, `restingPosition(forSize:
/// safeAreaInsets:)`) already use: placement math is a pure function of
/// size + insets, testable with no scene, no view, no node.
///
/// **Coordinate space.** Every frame is in `GameScene.uiLayer`'s own space:
/// `(0, 0)` at the centre of the visible area, `x` increasing right, `y`
/// increasing up -- exactly the convention `FloatingThumbstickNode` and
/// `MenuScreenNode` already document and lay out in. A future mount simply
/// sets `node.position = CGPoint(x: frame.midX, y: frame.midY)` (or, for an
/// element with real width/height baked into its own children, positions
/// its children within `frame` directly) with no further coordinate
/// translation.
///
/// **Orientation.** There is no separate "portrait" / "landscape" branch:
/// every frame is derived from `sceneSize`/`safeAreaInsets` directly, and a
/// rotation is just a different `sceneSize` (width/height swapped) with
/// different insets (the notch moves from top to a side, the home indicator
/// stays at the bottom). `HUDLayoutTests` exercises both a representative
/// portrait and a representative landscape input rather than branching
/// logic here.
///
/// **Stays clear of the thumbstick's bottom-left region.** The movement
/// thumbstick (`FloatingThumbstickNode`) and the ability button it used to
/// reserve a slot for both live in the bottom-left "thumb quadrant"
/// (`FloatingThumbstickNode.leftRegion(forSize:safeAreaInsets:)`). This
/// story's pulse-button slot is bottom-**right** instead (per this ticket's
/// own wording -- see the still-open placement note in `AGENT.md`'s
/// `CYBERPUN-17-10` entry), and every other slot here is anchored at the
/// top of the safe area, so no slot this type produces can overlap that
/// region by construction; `HUDLayoutTests` still pins the non-overlap
/// directly (computed from `FloatingThumbstickNode`'s own geometry, so the
/// two can never silently drift apart) rather than leaving it as an
/// assumption about "top" and "bottom-left" never meeting.
enum HUDLayout {

    // MARK: - Element sizes

    static let hpBarSize = CGSize(width: 220, height: 28)
    static let levelXPBarSize = CGSize(width: 220, height: 20)
    static let runTimerSize = CGSize(width: 120, height: 32)
    static let killCountSize = CGSize(width: 120, height: 32)
    static let pulseButtonSize = CGSize(width: 72, height: 72)
    static let swarmBannerSize = CGSize(width: 280, height: 44)

    /// Gap kept between the safe area's own edge and any slot's outer edge.
    static let edgeMargin: CGFloat = 16

    /// Gap kept between two vertically stacked slots (HP -> XP, timer ->
    /// swarm banner).
    static let verticalSpacing: CGFloat = 8

    // MARK: - Safe content area

    /// The safe content rect in `uiLayer` space: `sceneSize` shrunk by
    /// `safeAreaInsets` on every edge, centred on the origin.
    static func safeContentRect(sceneSize: CGSize, safeAreaInsets: UIEdgeInsets) -> CGRect {
        let minX = -sceneSize.width / 2 + safeAreaInsets.left
        let maxX = sceneSize.width / 2 - safeAreaInsets.right
        let minY = -sceneSize.height / 2 + safeAreaInsets.bottom
        let maxY = sceneSize.height / 2 - safeAreaInsets.top
        return CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }

    /// The bottom-left region `FloatingThumbstickNode` claims for itself
    /// plus its own reserved (legacy, bottom-left) pulse-button slot --
    /// mirrored from that type's own geometry rather than re-declared, so
    /// this can never silently drift out of step with it.
    static func thumbstickReservedRegion(sceneSize: CGSize, safeAreaInsets: UIEdgeInsets) -> CGRect {
        let safeRect = safeContentRect(sceneSize: sceneSize, safeAreaInsets: safeAreaInsets)
        let reservedSlot = FloatingThumbstickNode.reservedPulseButtonSlot(
            forSize: sceneSize,
            safeAreaInsets: safeAreaInsets
        )
        return CGRect(
            x: safeRect.minX,
            y: safeRect.minY,
            width: FloatingThumbstickNode.leftRegion(forSize: sceneSize, safeAreaInsets: safeAreaInsets).width,
            height: reservedSlot.maxY - safeRect.minY
        )
    }

    // MARK: - Per-slot frames

    /// The anchor frame for `slot`, in `uiLayer` space.
    static func frame(for slot: HUDSlot, sceneSize: CGSize, safeAreaInsets: UIEdgeInsets) -> CGRect {
        let safeRect = safeContentRect(sceneSize: sceneSize, safeAreaInsets: safeAreaInsets)

        switch slot {
        case .hpBar:
            return CGRect(
                x: safeRect.minX + edgeMargin,
                y: safeRect.maxY - edgeMargin - hpBarSize.height,
                width: hpBarSize.width,
                height: hpBarSize.height
            )

        case .levelXPBar:
            let hp = frame(for: .hpBar, sceneSize: sceneSize, safeAreaInsets: safeAreaInsets)
            return CGRect(
                x: safeRect.minX + edgeMargin,
                y: hp.minY - verticalSpacing - levelXPBarSize.height,
                width: levelXPBarSize.width,
                height: levelXPBarSize.height
            )

        case .runTimer:
            return CGRect(
                x: -runTimerSize.width / 2,
                y: safeRect.maxY - edgeMargin - runTimerSize.height,
                width: runTimerSize.width,
                height: runTimerSize.height
            )

        case .killCount:
            return CGRect(
                x: safeRect.maxX - edgeMargin - killCountSize.width,
                y: safeRect.maxY - edgeMargin - killCountSize.height,
                width: killCountSize.width,
                height: killCountSize.height
            )

        case .pulseButton:
            return CGRect(
                x: safeRect.maxX - edgeMargin - pulseButtonSize.width,
                y: safeRect.minY + edgeMargin,
                width: pulseButtonSize.width,
                height: pulseButtonSize.height
            )

        case .swarmBanner:
            let timer = frame(for: .runTimer, sceneSize: sceneSize, safeAreaInsets: safeAreaInsets)
            return CGRect(
                x: -swarmBannerSize.width / 2,
                y: timer.minY - verticalSpacing - swarmBannerSize.height,
                width: swarmBannerSize.width,
                height: swarmBannerSize.height
            )
        }
    }

    /// Every slot's frame, computed once for a given `sceneSize` /
    /// `safeAreaInsets`.
    static func allFrames(sceneSize: CGSize, safeAreaInsets: UIEdgeInsets) -> [HUDSlot: CGRect] {
        Dictionary(
            uniqueKeysWithValues: HUDSlot.allCases.map {
                ($0, frame(for: $0, sceneSize: sceneSize, safeAreaInsets: safeAreaInsets))
            }
        )
    }
}
