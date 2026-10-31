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

    // MARK: - Texture-backed fills (`CYBERPUN-17-23-t3`)

    /// `SKCropNode.maskNode` compositing a color-only `SKSpriteNode`
    /// against another color-only sprite (no `texture` on either side) is
    /// the known-unreliable combination on device -- unlike the *rebuilt*
    /// `backdrop`, which only ever showed correctly once it carried a real
    /// rasterized `texture` (`RadarBackdropRenderer.makeBackdropTexture`).
    /// Before this fix `maskNode` and every marker (`playerMarker`, the
    /// pooled raccoon/med-kit markers) were built via
    /// `SKSpriteNode(color:size:)` with no texture at all, which matched
    /// the reported symptom exactly: the textured backdrop rendered through
    /// the crop while the textureless mask + textureless marker children
    /// did not reliably composite. `makeSolidTexture(color:size:)` renders
    /// a plain, single-color `UIImage` once (`UIGraphicsImageRenderer`) and
    /// hands back an `SKTexture` from it.
    ///
    /// **Every child of `cropNode` is texture-backed by construction**,
    /// `backdrop` included (PR #80 review). `backdrop` used to be the one
    /// exception -- color-only from `init()` until the first
    /// `update(...)`, and *permanently* color-only on the path where
    /// `makeBackdropTexture` hands back a bare `SKTexture()` because
    /// `CGContext` creation failed. Both are the very combination this fix
    /// is predicated on being unreliable, so `backdropPlateTexture` gives
    /// it a real rasterized plate from the moment it is built and
    /// `rebuildBackdropIfNeeded` refuses to mount an empty texture over
    /// it.
    private static func makeSolidTexture(color: UIColor, size: CGSize) -> SKTexture {
        let image = UIGraphicsImageRenderer(size: size).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return SKTexture(image: image)
    }

    /// The crop mask's own backing texture -- solid white, `contentSize`
    /// across. `SKCropNode` reads only the mask's alpha channel, so the
    /// fill color itself is irrelevant; white matches the sentinel
    /// `SKSpriteNode(color: .white, size:...)` this replaces.
    private static let maskTexture = makeSolidTexture(color: .white, size: contentSize)

    /// The backdrop's own plain-plate texture -- `PixelGritPalette
    /// .background`, `contentSize` across. This is what the dial shows
    /// before the first `update(...)` rasterizes a real radar backdrop
    /// over it, and what it falls back to if that rasterization ever
    /// fails; baking the plate colour into a texture (rather than leaning
    /// on `color` + `colorBlendFactor = 1`) is what keeps *every* child of
    /// `cropNode` texture-backed on every path.
    private static let backdropPlateTexture = makeSolidTexture(
        color: PixelGritPalette.background,
        size: contentSize
    )

    /// The player marker's own backing texture -- built once and reused
    /// across every `RadarMapNode` instance, since the marker never
    /// changes color.
    private static let playerMarkerTexture = makeSolidTexture(
        color: PixelGritPalette.neonAccent,
        size: markerSize
    )

    /// The raccoon marker pool's shared backing texture -- built **once**,
    /// not per-marker: every pooled raccoon marker (`syncMarkerPool`) reuses
    /// this same `SKTexture` instance rather than rasterizing its own copy
    /// each time the pool grows.
    private static let raccoonMarkerTexture = makeSolidTexture(
        color: PixelGritPalette.neonSecondary,
        size: markerSize
    )

    /// The med-kit marker pool's shared backing texture -- see
    /// `raccoonMarkerTexture`'s own doc comment; same "once, reused across
    /// the pool" rule.
    private static let medKitMarkerTexture = makeSolidTexture(
        color: PixelGritPalette.radarMedKitAccent,
        size: markerSize
    )

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
        maskNode = SKSpriteNode(texture: Self.maskTexture, size: Self.contentSize)
        backdrop = SKSpriteNode(texture: Self.backdropPlateTexture, size: Self.contentSize)
        playerMarker = SKSpriteNode(texture: Self.playerMarkerTexture, size: Self.markerSize)
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
        // Already texture-backed (`backdropPlateTexture`) rather than
        // color-only, so the plate the dial shows for the fraction of a
        // frame before `update(...)`'s first (always-rebuilding) call is
        // itself a real rasterized texture -- never the color-only
        // combination this fix exists to remove. The texture carries the
        // plate colour, so this sprite's own `color` must not tint it.
        backdrop.colorBlendFactor = 0

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
            texture: Self.medKitMarkerTexture,
            namePrefix: "radarMap.medKitMarker"
        )
        positionMarkers(medKitMarkers, tiles: medKitTiles, relativeTo: playerTile, deviceScale: deviceScale)

        syncMarkerPool(
            &raccoonMarkers,
            in: raccoonContainer,
            count: raccoonTiles.count,
            texture: Self.raccoonMarkerTexture,
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

        let rebuilt = RadarBackdropRenderer.makeBackdropTexture(
            playerTile: playerTile,
            scale: radarScale,
            deviceScale: deviceScale,
            isTileBlocked: isTileBlocked
        )

        // `makeBackdropTexture` hands back a bare, zero-sized `SKTexture()`
        // when its `CGContext` creation failed (its only `nil` path).
        // Mounting that would leave the backdrop drawing *nothing* --
        // strictly worse than the plain plate the pre-`-t3` node showed on
        // the same path (PR #80 review) -- so keep whatever real texture is
        // already up (`backdropPlateTexture` on the very first call) and
        // leave `cachedBackdropKey` un-advanced, so the next `update(...)`
        // retries rather than caching the failure until the player happens
        // to cross a tile. The retry is cheap: the failure is detected at
        // `CGContext` creation, before the rasterizer's pixel walk.
        guard rebuilt.size().width > 0, rebuilt.size().height > 0 else { return }

        cachedBackdropKey = key
        backdrop.texture = rebuilt
        // The texture carries its own blocked/open coloring; this sprite's
        // own `color` must never additionally tint it. (Already `0` from
        // `init()`, since the plate it starts on is a texture too --
        // restated here so the invariant survives a future edit to either
        // side.)
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
    ///
    /// `texture` is the pool's own shared backing texture
    /// (`raccoonMarkerTexture`/`medKitMarkerTexture`), built once at the
    /// type level and reused by every marker this pool grows to -- not
    /// rasterized per-marker.
    private func syncMarkerPool(
        _ pool: inout [SKSpriteNode],
        in container: SKNode,
        count: Int,
        texture: SKTexture,
        namePrefix: String
    ) {
        while pool.count < count {
            let marker = SKSpriteNode(texture: texture, size: Self.markerSize)
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
