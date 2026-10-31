import CoreGraphics
import SpriteKit
import UIKit

/// The minimap radar widget (`CYBERPUN-17-23-t2`): a `SKCropNode`-clipped
/// 110x110pt dial showing the resident city's blocked/open tiles around the
/// player, plus live raccoon/med-kit markers, inside a 1pt border --
/// `HUDLayout.radarMapSize`'s 112x112pt outer frame.
///
/// Construct + `update(playerTile:raccoonTiles:medKitTiles:isTileBlocked:
/// deviceScale:)` only -- no positioning logic lives here (`HUDLayout` owns
/// where this mounts, the same convention every other HUD element follows).
/// The one exception is `radarScale`, this node's own points-per-tile
/// scale: unlike every other per-frame live-data reading, it is a function
/// of `sceneSize` alone (`RadarGeometry.radarScale(for:)`), so `HUDLayer
/// .applyLayout(for:safeAreaInsets:orientation:)` sets it directly rather
/// than threading it through `update(...)`'s live-data parameter list.
///
/// **Backdrop caching.** The backdrop texture
/// (`RadarBackdropRenderer.makeBackdropTexture`) is rebuilt only when one
/// of the raster's *own* inputs changes -- per that renderer's own doc
/// comment, a full rebuild walks `contentSquarePixelSize^2` pixels and is
/// *not* meant to run every frame. Since `update(...)` itself is called at
/// most once per `.gameplay` frame (`HUDLayer.refresh()`), "on an input
/// change" is automatically also "at most once per frame".
///
/// Those inputs are exactly `BackdropCacheKey`: `playerTile` (the raster's
/// centre), `radarScale` and `deviceScale` (its geometry and pixel
/// density), and `residencyRevision` -- a stand-in for the `isTileBlocked`
/// predicate's own captured state, which this node cannot inspect
/// directly. Keying on `playerTile` alone was narrower than
/// `RadarBackdropRenderer`'s stated cadence ("a rebuild when the player's
/// tile changes *or when the resident chunk window does*") and the missing
/// half was reachable at spawn: `GameScene.updateWorldContent(for:
/// .gameplay)` calls `hud.bind(to:)` -- and so this node's first,
/// always-rebuilding `update(...)` -- *before* `cameraController.update(
/// focus:)` has streamed a single chunk, so that first backdrop is built
/// against an empty record set. A player standing still at spawn then kept
/// a dial showing only the seeded lattice, with none of the chunk-placed
/// buildings the radar exists to reveal, until they happened to cross a
/// tile boundary (PR #79 review).
///
/// The key deliberately does *not* hash the records themselves: the whole
/// point of threading an O(1) revision counter down from
/// `ChunkStreamingManager.residencyRevision` is that neither this node nor
/// `HUDLayer` has to walk the resident window to notice it changed.
///
/// Widening the key makes rebuilds *more* frequent, so: the dominant
/// trigger is still a player-tile crossing (unchanged by this). A
/// residency change needs a whole *chunk* boundary (8 tiles) to be
/// crossed, and `radarScale`/`deviceScale` move only on a rotation or the
/// first mount into a real view -- so the added rebuilds are rare next to
/// the tile-crossing ones. That matters because one rebuild is **not**
/// cheap: ~25 ms at `@3x` over a full resident window in a Debug build,
/// measured (see `RadarBackdropRenderer`'s own cost note for the figure,
/// its Release caveat, and the off-thread escape it points at), and it
/// runs synchronously on the gameplay update thread.
///
/// **Marker pools.** `raccoonMarkers`/`medKitMarkers` grow on demand (a
/// fresh `SKSpriteNode` is appended only the first time a given pool index
/// is needed) and never shrink -- a marker beyond the currently-needed
/// count is hidden (`isHidden`), never removed, so repeated `update(...)`
/// calls settle at the pool's own high-water mark rather than allocating a
/// node per frame. `playerMarker` needs no pool: there is always exactly
/// one, and it never moves (see its own doc note).
///
/// **Paint order, with no `zPosition` anywhere:** `backdrop` -> med-kit
/// markers -> raccoon markers -> `playerMarker` -> `border`, which is
/// exactly `SKNode`'s own child-array draw order for the fixed-order
/// containers mounted in `init()`. Markers growing a pool mid-run append
/// *into* their own container (`medKitContainer`/`raccoonContainer`), never
/// onto `cropNode` directly, so a pool growing after the other has already
/// grown can never reorder the two categories relative to each other.
final class RadarMapNode: SKNode, AccessibilityOpaqueNode {

    // MARK: - Tunables

    /// Mirrors `HUDLayout.radarMapSize` rather than re-declaring it, the
    /// same convention every other HUD element's own `Self.*Size` constant
    /// already follows.
    static let outerSize = HUDLayout.radarMapSize

    /// The dial's own drawn content, inside the border --
    /// `RadarGeometry`'s 110x110 content square.
    static let contentSize = CGSize(
        width: RadarGeometry.contentSquareSize,
        height: RadarGeometry.contentSquareSize
    )

    static let borderWidth: CGFloat = 1
    static let markerSize = CGSize(width: 6, height: 6)

    // MARK: - Nodes

    private let border: SKShapeNode
    private let cropNode = SKCropNode()
    private let maskNode: SKSpriteNode
    private let backdrop: SKSpriteNode
    private let medKitContainer = SKNode()
    private let raccoonContainer = SKNode()
    private let playerMarker: SKSpriteNode

    private var raccoonMarkers: [SKSpriteNode] = []
    private var medKitMarkers: [SKSpriteNode] = []

    // MARK: - State

    /// The radar's own points-per-tile scale -- see this type's own doc
    /// comment for why it is a settable property rather than an
    /// `update(...)` parameter. Defaults to `1` so a headless unit test
    /// that never calls a layout entry point still gets a well-defined
    /// (if degenerate) scale rather than an implicit `0`.
    var radarScale: CGFloat = 1

    /// Every input the mounted backdrop raster is a function of -- see this
    /// type's own "Backdrop caching" doc note for why each member is here
    /// and why the blocked-tile predicate is represented by a revision
    /// counter rather than by its own captured state.
    private struct BackdropCacheKey: Equatable {
        let playerTile: TileCoordinate
        let radarScale: CGFloat
        let deviceScale: CGFloat
        let residencyRevision: Int
    }

    /// The input set the currently-mounted backdrop texture was built for
    /// -- `nil` before the first `update(...)` call, so that call always
    /// builds a texture rather than trusting an un-set default to compare
    /// unequal.
    private var cachedBackdropKey: BackdropCacheKey?

    // MARK: - Init

    override init() {
        maskNode = SKSpriteNode(color: .white, size: Self.contentSize)
        backdrop = SKSpriteNode(color: PixelGritPalette.background, size: Self.contentSize)
        playerMarker = SKSpriteNode(color: PixelGritPalette.neonAccent, size: Self.markerSize)
        border = SKShapeNode(rectOf: Self.outerSize)

        super.init()

        name = "radarMap"

        // Deliberately **not** an accessibility element -- on this node and
        // on every drawn child of it. See `HPSegmentBar`'s own rationale:
        // what actually binds is this type's `AccessibilityOpaqueNode`
        // conformance (`GameScene`'s walk skips a conformer's whole subtree
        // without consulting any descendant's flag); these assignments are
        // the second line of defence, stating the intent at the node
        // itself.
        isAccessibilityElement = false

        border.name = "radarMap.border"
        border.fillColor = .clear
        border.strokeColor = PixelGritPalette.neonSecondary
        border.lineWidth = Self.borderWidth
        border.isAccessibilityElement = false

        maskNode.isAccessibilityElement = false

        backdrop.name = "radarMap.backdrop"
        backdrop.isAccessibilityElement = false
        // No texture yet -- `update(...)`'s first call always rebuilds
        // (`cachedPlayerTile` starts `nil`), so this plain plate color is
        // only ever visible for the fraction of a frame before that.
        backdrop.colorBlendFactor = 1

        playerMarker.name = "radarMap.playerMarker"
        playerMarker.isAccessibilityElement = false
        // Always exactly centred: the radar is centred on the player by
        // definition, so the player's own marker never moves, whatever
        // `update(...)` is called with.
        playerMarker.position = .zero

        medKitContainer.name = "radarMap.medKitMarkers"
        medKitContainer.isAccessibilityElement = false
        raccoonContainer.name = "radarMap.raccoonMarkers"
        raccoonContainer.isAccessibilityElement = false

        cropNode.name = "radarMap.cropNode"
        cropNode.isAccessibilityElement = false
        cropNode.maskNode = maskNode

        // Paint order, fixed here and never reordered: backdrop -> med
        // kits -> raccoons -> player -- see this type's own doc comment.
        cropNode.addChild(backdrop)
        cropNode.addChild(medKitContainer)
        cropNode.addChild(raccoonContainer)
        cropNode.addChild(playerMarker)

        addChild(cropNode)
        addChild(border)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Update

    /// Forwards this frame's live radar data: rebuilds the backdrop only
    /// when one of its own raster inputs changed (see `BackdropCacheKey`),
    /// then repositions (growing each pool on demand) the raccoon/med-kit
    /// markers relative to `playerTile`.
    ///
    /// `raccoonTiles`/`medKitTiles` are each tile the swarm/med kits
    /// currently occupy, already rounded from their own fractional world
    /// positions by the caller (`HUDLayer.refresh()`) -- this node only
    /// ever deals in whole tiles, matching `RadarGeometry.radarPoint(
    /// forTileOffset:scale:)`'s own `Int` offset contract.
    ///
    /// `residencyRevision` is the caller's own "the blocked-tile predicate
    /// would now answer differently" signal -- in production
    /// `ChunkStreamingManager.residencyRevision`, threaded through
    /// `HUDRunModel.radarResidencyRevision`. It defaults to `0` for the
    /// same reason `radarScale` defaults to `1`: a headless unit test that
    /// models no chunk streaming at all still gets a well-defined (here,
    /// never-invalidating) value rather than having to invent one.
    func update(
        playerTile: TileCoordinate,
        raccoonTiles: [TileCoordinate],
        medKitTiles: [TileCoordinate],
        isTileBlocked: (_ tileX: Int, _ tileY: Int) -> Bool,
        deviceScale: CGFloat,
        residencyRevision: Int = 0
    ) {
        rebuildBackdropIfNeeded(
            playerTile: playerTile,
            isTileBlocked: isTileBlocked,
            deviceScale: deviceScale,
            residencyRevision: residencyRevision
        )

        syncMarkerPool(
            &medKitMarkers,
            in: medKitContainer,
            count: medKitTiles.count,
            color: PixelGritPalette.radarMedKitAccent,
            namePrefix: "radarMap.medKitMarker"
        )
        positionMarkers(medKitMarkers, tiles: medKitTiles, relativeTo: playerTile, deviceScale: deviceScale)

        syncMarkerPool(
            &raccoonMarkers,
            in: raccoonContainer,
            count: raccoonTiles.count,
            color: PixelGritPalette.neonSecondary,
            namePrefix: "radarMap.raccoonMarker"
        )
        positionMarkers(raccoonMarkers, tiles: raccoonTiles, relativeTo: playerTile, deviceScale: deviceScale)
    }

    // MARK: - Backdrop

    private func rebuildBackdropIfNeeded(
        playerTile: TileCoordinate,
        isTileBlocked: (_ tileX: Int, _ tileY: Int) -> Bool,
        deviceScale: CGFloat,
        residencyRevision: Int
    ) {
        let key = BackdropCacheKey(
            playerTile: playerTile,
            radarScale: radarScale,
            deviceScale: deviceScale,
            residencyRevision: residencyRevision
        )
        guard cachedBackdropKey != key else { return }
        cachedBackdropKey = key

        backdrop.texture = RadarBackdropRenderer.makeBackdropTexture(
            playerTile: playerTile,
            scale: radarScale,
            deviceScale: deviceScale,
            isTileBlocked: isTileBlocked
        )
        // The texture carries its own blocked/open coloring; this sprite's
        // own `color` (the plain plate it shows before the first build)
        // must never additionally tint it.
        backdrop.colorBlendFactor = 0
        PixelCrispness.apply(to: backdrop)
        // `PixelCrispness.apply(to:)` rounds `size`-independent state
        // (scale/position/filtering) only -- it never touches `size`, so
        // the backdrop keeps displaying at `contentSize` regardless of the
        // rasterized texture's own (device-pixel-scaled) dimensions.
        backdrop.size = Self.contentSize
    }

    // MARK: - Marker pools

    /// Grows `pool` (mounted under `container`) to at least `count` nodes,
    /// appending a freshly-built, hidden marker only when needed, then sets
    /// `isHidden` on every pool slot from its index against `count` -- a
    /// surplus slot (left over from a higher-water-mark frame) is hidden,
    /// never removed.
    private func syncMarkerPool(
        _ pool: inout [SKSpriteNode],
        in container: SKNode,
        count: Int,
        color: UIColor,
        namePrefix: String
    ) {
        while pool.count < count {
            let marker = SKSpriteNode(color: color, size: Self.markerSize)
            marker.name = "\(namePrefix).\(pool.count)"
            marker.isAccessibilityElement = false
            container.addChild(marker)
            pool.append(marker)
        }
        for (index, marker) in pool.enumerated() {
            marker.isHidden = index >= count
        }
    }

    /// Positions the first `tiles.count` entries of `pool` at their
    /// tile-offset-from-`playerTile` radar point, hiding any marker whose
    /// projected point falls outside the 110x110 content square
    /// (`RadarGeometry.isWithinContentSquare(_:)`) -- out-of-window
    /// raccoons/med kits are simply not drawn, on top of `cropNode`'s own
    /// visual clip.
    private func positionMarkers(
        _ pool: [SKSpriteNode],
        tiles: [TileCoordinate],
        relativeTo playerTile: TileCoordinate,
        deviceScale: CGFloat
    ) {
        for (index, tile) in tiles.enumerated() {
            let marker = pool[index]
            let offset = (x: tile.tileX - playerTile.tileX, y: tile.tileY - playerTile.tileY)
            let point = RadarGeometry.radarPoint(forTileOffset: offset, scale: radarScale)

            guard RadarGeometry.isWithinContentSquare(point) else {
                marker.isHidden = true
                continue
            }
            marker.position = PixelCrispness.snappedPosition(for: point, scale: deviceScale)
        }
    }
}
