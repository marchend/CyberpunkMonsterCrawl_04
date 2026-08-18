import CoreGraphics
import SpriteKit

/// Standalone SpriteKit visual composition for one ground pickup: an
/// untinted icon (sliced from `sprite_pickups.png`, `AtlasSheet.pickups` --
/// measured 48x24px, 24x24px cells: med kit at column 0, garbage can at
/// column 1, per `AtlasCellIndex.pickups`) layered over an accent-tinted
/// pad, with a gentle vertical bob and this repo's usual pixel-crispness /
/// depth-sort conventions.
///
/// **Scope of this PR (`CYBERPUN-17-11` PR 1).** Node assembly only -- no
/// scene mount. `PickupManager` (this same PR) is pure spawn/lifetime logic
/// with no SpriteKit dependency; a later PR is expected to mount one
/// `PickupNode` per `Pickup` the manager reports, the same "logic first,
/// mount later" split `ChunkStreamingManager`/`GroundPlaneStreamer` and
/// `RaccoonSpawnDirector`/`RaccoonNode` both already follow in this
/// codebase. The `CYBERPUN-17-11` entry in AGENT.md/CLAUDE.md is the
/// authoritative implemented-vs-outstanding list for that deferral (no
/// invented ticket ID here); until it lands, no pickup can appear in a real
/// build, so product gate 5 is unverifiable on a device.
final class PickupNode: SKNode {

    /// The icon's on-screen size, in points: the story's fixed 32x32pt icon
    /// drawn from `AtlasSheet.pickups`' **measured** 24x24px cell -- an
    /// effective 32/24 = 1.333x magnification, not a 1x draw.
    ///
    /// **This deliberately opts the icon out of `PixelCrispness`'s
    /// integer-scale rule**, the same way `RaccoonNode.scaledSize(forTier:
    /// deviceScale:)` records the elite's 1.6x opt-out: a non-integer
    /// magnification spreads 24 source pixels across 32 points with no
    /// whole-pixel correspondence, so the compositor resamples them
    /// unevenly -- precisely what `PixelCrispness`'s header warns about. It
    /// is the trade the story asks for (a legible 32pt icon), taken
    /// knowingly rather than left implicit.
    ///
    /// It is also *not* what the rest of the atlas does, so this must not be
    /// read as the house style: `PlayerNode.init` draws
    /// `PlayerSpriteSheet.cellSize` at an exact 1x and a base raccoon draws
    /// its cell at an exact 1x; the elite is the only other upscaled
    /// consumer in the repo.
    ///
    /// Unlike the elite's fractional 76.8pt raw width, 32pt is already a
    /// whole number of device pixels at every integer `deviceScale`, so
    /// `PixelCrispness.snappedPosition(for:scale:)` would have nothing to
    /// move here -- which is why this stays a constant instead of the
    /// `deviceScale`-taking function the raccoon needs. The magnification
    /// lives in `SKSpriteNode.size`, never in `xScale`/`yScale` (which
    /// `PixelCrispness.apply(to:)` rounds to whole integers), so
    /// `PickupNodeTests.test_icon_effectiveMagnification_isTheStorys32ptIconOverTheMeasured24pxCell`
    /// pins the *effective* magnification rather than an `xScale`
    /// assertion that is true no matter what this value says.
    static let iconSize = CGSize(width: 32, height: 32)

    /// The tinted backing pad's size, in points -- deliberately larger than
    /// `iconSize` so the accent tint reads as a glow/pad the icon sits on
    /// top of, rather than a hard-edged fill exactly matching the icon's own
    /// silhouette.
    static let padSize = CGSize(width: 40, height: 40)

    private static let padRelativeZ: CGFloat = 0
    private static let iconRelativeZ: CGFloat = 0.01

    /// This node's depth offset within `DepthBanding
    /// .nonPlayerActorOffsetRange` -- the exact same value
    /// `RaccoonNode.depthOffset` uses (that range's own lower bound), so a
    /// pickup always draws above ground/building content and strictly below
    /// the player when they share a tile, per that range's "player-max
    /// tie-break" contract.
    static let depthOffset: CGFloat = DepthBanding.nonPlayerActorOffsetRange.lowerBound

    /// One full up-then-down bob cycle, in seconds.
    static let bobDuration: TimeInterval = 1.2
    /// Vertical bob amplitude, in points -- applied to `icon` only, so `pad`
    /// stays visually anchored to the ground while the icon floats above it.
    static let bobAmplitude: CGFloat = 4

    /// The action key `runBobAction()` runs under, exposed so a test (or a
    /// future consumer) can look the animation up by name instead of
    /// guessing whether one was applied.
    static let bobActionKey = "pickupBob"

    /// `sprite_pickups`'s measured sheet contract, resolved once -- the same
    /// hoisted-off-the-hot-path reasoning `PlayerNode.cachedSheet` /
    /// `RaccoonNode.cachedWalkSheet` document, since a `PickupNode` is
    /// expected to be constructed far more often than the sheet needs
    /// re-measuring.
    private static let cachedSheet: SpriteSheet = AtlasSheet.pickups.sheet

    /// One `SKTexture` per atlas column, sliced on first use and reused
    /// thereafter -- the same cached-per-cell convention
    /// `PlayerNode.texture(row:column:)` / `RaccoonNode.texture(state:row:
    /// column:)` follow, exposed (not private) so tests can compare a
    /// produced icon's texture identity against the exact cache this node's
    /// production path uses.
    ///
    /// **Isolation:** mutable static state with no synchronization, safe
    /// only because every access happens on SpriteKit's main-thread update
    /// loop -- see those two types' own identical caveat.
    private static var textureCache: [Int: SKTexture] = [:]

    static func texture(forColumn column: Int) -> SKTexture {
        if let cached = textureCache[column] {
            return cached
        }
        let texture = cachedSheet.texture(col: column, row: 0)
        textureCache[column] = texture
        return texture
    }

    /// Which pickup this node represents -- fixed at construction.
    let kind: PickupKind

    /// The untinted icon child. Never tinted (`colorBlendFactor == 0`,
    /// `color == .clear`) -- the sheet's own pixel colors are the whole
    /// visual, per this pickup's "untinted icon over a tinted pad"
    /// composition.
    let icon: SKSpriteNode

    /// The accent-tinted backing pad. A plain color fill (no texture --
    /// there is no dedicated pad art in the pack), tinted per `kind` via
    /// `PixelGritPalette`.
    let pad: SKSpriteNode

    init(kind: PickupKind) {
        self.kind = kind

        let texture = Self.texture(forColumn: kind.atlasColumn)
        icon = SKSpriteNode(texture: texture)
        icon.size = Self.iconSize
        icon.color = .clear
        icon.colorBlendFactor = 0
        icon.zPosition = Self.iconRelativeZ

        pad = SKSpriteNode(color: Self.padColor(for: kind), size: Self.padSize)
        pad.zPosition = Self.padRelativeZ

        super.init()

        // Pad first, so the icon (added after) draws in front of it purely
        // by `zPosition` -- add order does not decide draw order in this
        // repo (`DepthModel`/`zPosition` does), but it mirrors the visual
        // stacking for readability, the same convention `PlayerNode.init`
        // documents for its own shadow/body pair.
        addChild(pad)
        addChild(icon)

        PixelCrispness.apply(to: pad)
        PixelCrispness.apply(to: icon)

        runBobAction()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("PickupNode does not support NSCoder deserialization.")
    }

    /// This node's absolute `zPosition` for a pickup standing at fractional
    /// tile-space `tilePosition`, via `DepthBanding.actorZPosition(
    /// forActorAt:offset:)` at `depthOffset` -- converted through
    /// `DepthModel.worldLayerRelativeZ(forAbsoluteZ:)` for a node parented
    /// **directly** under `GameScene.worldLayer`, the exact convention
    /// `PlayerNode.updateDepth(atTilePosition:)` /
    /// `RaccoonNode.updateDepth(atTilePosition:)` both use.
    func updateDepth(atTilePosition tilePosition: TilePoint) {
        let absoluteZ = DepthBanding.actorZPosition(forActorAt: tilePosition, offset: Self.depthOffset)
        zPosition = DepthModel.worldLayerRelativeZ(forAbsoluteZ: absoluteZ)
    }

    /// Sets this node's on-screen `position` for a pickup standing at
    /// fractional tile-space `tilePosition`, pixel-snapped to `deviceScale`
    /// (`PixelCrispness.snappedPosition(for:scale:)`, the same convention
    /// every other world-space node in this repo follows), and updates
    /// depth in the same call since the two are always derived from the
    /// same tile position.
    func updateScreenPosition(atTilePosition tilePosition: TilePoint, deviceScale: CGFloat) {
        let rawPosition = IsometricProjection.tileToScreen(tilePosition)
        position = PixelCrispness.snappedPosition(for: rawPosition, scale: deviceScale)
        updateDepth(atTilePosition: tilePosition)
    }

    private static func padColor(for kind: PickupKind) -> SKColor {
        switch kind {
        case .medKit: return PixelGritPalette.neonAccent
        case .garbageCan: return PixelGritPalette.neonSecondary
        }
    }

    private func runBobAction() {
        let up = SKAction.moveBy(x: 0, y: Self.bobAmplitude, duration: Self.bobDuration / 2)
        up.timingMode = .easeInEaseOut
        let down = up.reversed()
        icon.run(SKAction.repeatForever(SKAction.sequence([up, down])), withKey: Self.bobActionKey)
    }
}
