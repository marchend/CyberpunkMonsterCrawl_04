import CoreGraphics
import SpriteKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-14-t3` (PR 3): the runtime pixel-crispness sweep gate 9
/// calls for -- a pass over **constructed, production-shaped** scene nodes
/// from every sprite consumer in the repo, asserting `PixelCrispness`'s own
/// invariants (nearest filtering, no mipmaps, whole-integer magnification)
/// plus whole-point placement, in one consolidated file a reviewer can read
/// end to end instead of trusting each consumer's own doc comment. This
/// mirrors `AtlasSlicingTests`' role for atlas indices (`CYBERPUN-17-14-t2`):
/// that file is the single place every family's row/column table is
/// exercised at once; this one is the single place every family's *pixel
/// finish* is.
///
/// **What the sweep found (one deviation from the pattern, fixed).** Every
/// sprite consumer but one stamps `.nearest`/no-mipmaps directly onto a
/// texture the moment it slices one out of its sheet
/// (`PlayerNode.texture(row:column:)`,
/// `RaccoonNode.texture(state:row:column:)`, `BulletNode.texture(forTier:)`,
/// `HitEffects.texture(forColumn:)`, `WeaponOverlayRenderer.texture(tier:
/// direction:)`, `PulseRingNode.texture(forColumn:)`).
/// `PickupNode.texture(forColumn:)` was the one cache-population site that
/// skipped it; it now matches the others.
///
/// The first revision of this file justified that as a *blur* fix, on the
/// premise that `SKTexture(rect:in:)` does not inherit the parent sheet
/// texture's filtering/mipmap settings. PR #66's review asked for that
/// premise to be pinned rather than assumed -- and measuring it
/// (`test_aRawSheetCrop_carriesTheSheetsNearestFiltering_measuredNotAssumed`)
/// **falsified it**: a fresh crop out of a `TextureLoading`-stamped sheet
/// already reads back `.nearest` with mipmaps off. So the change is a
/// consistency fix (and a guard against undocumented `SKTexture` crop
/// behaviour changing under us), not a rescue from a live defect, and
/// `gate-09-pixel-crispness-sweep.txt` says so in those terms.
///
/// `GroundTileRenderer.configure`/`TileFieldRenderer.configure`/
/// `RooftopSignRenderer.makeSignNode` do not cache their sliced textures at
/// all (a fresh crop every call) and instead call `PixelCrispness.apply(to:
/// node)` immediately after assigning it, which is an equally sound pattern
/// -- the sweep below still exercises them directly so a future change
/// cannot silently drop that immediate `apply(to:)` call without a red test.
///
/// **Scale is asserted as *effective magnification*, not as `xScale`**
/// (PR #66 review). An `isIntegerScale(node.xScale)` assertion cannot fail
/// for any node in this file: every one of them has just been through
/// `PixelCrispness.apply(to:)`, whose `wholeScale(_:)` rounds `xScale`/
/// `yScale` to whole integers, so the check merely re-derives what the code
/// under test just did. Worse, it is structurally blind to the two
/// magnifications in this repo that gate 9's "whole-integer multiple of the
/// 1x art" wording actually cares about, because both deliberately route
/// their magnification through `SKSpriteNode.size` where `wholeScale` never
/// sees it. `assertPixelCrisp` therefore pins `node.size /
/// node.texture.size()` -- the same `effectiveMagnification` idiom
/// `RaccoonNodeTests`/`PickupNodeTests` established -- and keeps the
/// `xScale`/`yScale` integer checks only for what they *can* still prove:
/// that magnification never leaks into scale, and that `PulseRingNode`'s
/// scale-to-radius (the one consumer that legitimately carries
/// magnification in `xScale`/`yScale`) stays integral.
///
/// **Three accepted, named exceptions -- not netted out.** A human signing
/// off gate 9 should see these rather than read "no offender found":
///  1. `RaccoonNode.scaledSize(forTier:deviceScale:)` draws the elite's
///     48x28 cell at 77x45 -- a 1.604x/1.607x magnification, non-integer by
///     design (that method's own doc comment records the opt-out).
///     `test_raccoonNode_body_...` asserts it *as* an exception, so the
///     sweep sees it instead of missing it.
///  2. `PickupNode.iconSize` draws the 24x24 pickup cell at 32x32pt --
///     1.333x, likewise a documented opt-out.
///  3. `BulletNode` is placed at arbitrary sub-pixel positions in flight
///     and rotated off-axis -- see
///     `test_bulletNode_inFlightPlacement_isTheAcceptedSubPixelException`
///     for the full derivation from the real caller.
///
/// **Tolerances, per the project's float32-read-back rule.** Every scale/
/// position value below is read back off a live `SKSpriteNode`, which
/// SpriteKit stores as 32-bit floats internally regardless of the public
/// `CGFloat` type -- so every comparison uses `accuracy:`, sized to the
/// magnitude of the value being compared (a near-1 scale factor gets a tight
/// tolerance; a many-hundred-point world position gets a slightly looser
/// one), never bare `XCTAssertEqual` on a value that came out of a node.
final class PixelCrispnessSweepTests: XCTestCase {

    // MARK: - Shared assertion

    /// One documented, story-accepted departure from gate 9's
    /// whole-integer-magnification rule, passed in by the (few) call sites
    /// that have one so the sweep asserts the exception *explicitly*
    /// instead of being blind to it.
    ///
    /// `accuracy` is sized to the device-pixel snap the magnification goes
    /// through (`RaccoonNode.scaledSize(forTier:deviceScale:)` snaps its
    /// result), never picked -- the same derivation
    /// `RaccoonNodeTests.test_eliteBody_effectiveMagnification_...` uses.
    private struct AcceptedMagnification {
        let horizontal: CGFloat
        let vertical: CGFloat
        let accuracy: CGFloat
        /// Why this node is allowed out of the integer rule, quoted into
        /// the failure message so a red run explains itself.
        let reason: String
    }

    /// Asserts `node` satisfies every `PixelCrispness.apply(to:)` invariant:
    /// `.nearest` filtering + no mipmaps (only if textured -- an untextured
    /// color-fill node, like `PickupNode.pad`, has nothing to check there),
    /// a whole-integer **effective magnification** (drawn size over the
    /// source cell the texture was cropped to), no magnification leaking
    /// into `xScale`/`yScale`, and whole-point `position`.
    ///
    /// Pass `accepted` for a node the story deliberately draws at a
    /// non-integer magnification; that flips the magnification check into
    /// "is exactly this documented exception, and is still non-integral" --
    /// so an opt-out that quietly became integral (i.e. stale) fails here
    /// rather than passing silently.
    ///
    /// Pass `acceptedSubPixelPlacement` for the one node family whose real
    /// caller writes fractional positions every frame (`BulletNode` -- see
    /// `test_bulletNode_inFlightPlacement_isTheAcceptedSubPixelException`,
    /// which pins that behaviour explicitly rather than leaving it merely
    /// unchecked here).
    private func assertPixelCrisp(
        _ node: SKSpriteNode,
        _ label: String,
        accepted: AcceptedMagnification? = nil,
        acceptedSubPixelPlacement: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if let texture = node.texture {
            XCTAssertEqual(
                texture.filteringMode, .nearest,
                "\(label): texture must be nearest-filtered.", file: file, line: line
            )
            XCTAssertFalse(
                texture.usesMipmaps,
                "\(label): texture must not use mipmaps.", file: file, line: line
            )
            assertEffectiveMagnification(
                node, texture: texture, label, accepted: accepted, file: file, line: line
            )
        }
        // These two are NOT the magnification check (see the type doc):
        // `PixelCrispness.apply(to:)` rounds `xScale`/`yScale` itself, so
        // they cannot fail for a node that has just been through it. They
        // are kept for the one thing they still pin -- that a consumer
        // which *does* legitimately carry magnification in scale
        // (`PulseRingNode.xScale(forRadiusTiles:)`) keeps it integral, and
        // that no other consumer starts routing magnification through
        // scale where `wholeScale` would silently round 1.6x to 2x.
        XCTAssertTrue(
            PixelCrispness.isIntegerScale(node.xScale),
            "\(label): xScale \(node.xScale) is not a whole integer.", file: file, line: line
        )
        XCTAssertTrue(
            PixelCrispness.isIntegerScale(node.yScale),
            "\(label): yScale \(node.yScale) is not a whole integer.", file: file, line: line
        )
        guard !acceptedSubPixelPlacement else { return }
        XCTAssertEqual(
            node.position.x, node.position.x.rounded(), accuracy: 1e-3,
            "\(label): position.x (\(node.position.x)) must land on a whole point.", file: file, line: line
        )
        XCTAssertEqual(
            node.position.y, node.position.y.rounded(), accuracy: 1e-3,
            "\(label): position.y (\(node.position.y)) must land on a whole point.", file: file, line: line
        )
    }

    /// Gate 9's actual scale criterion: the drawn size over the source cell
    /// the texture was cropped to -- `size / texture.size()`, the
    /// `effectiveMagnification` idiom `RaccoonNodeTests`/`PickupNodeTests`
    /// already use. Nothing in the production path rounds this ratio, so
    /// unlike an `xScale` assertion it can genuinely fail.
    ///
    /// The tolerance on the integer case is a thousandth of a source pixel:
    /// `texture.size()` is read back off a live `SKTexture` (float32, per
    /// this file's tolerance note), so an exact 1:1 draw can come back as
    /// `0.9999999x`.
    private func assertEffectiveMagnification(
        _ node: SKSpriteNode,
        texture: SKTexture,
        _ label: String,
        accepted: AcceptedMagnification?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let cell = texture.size()
        guard cell.width > 0, cell.height > 0 else {
            XCTFail(
                "\(label): texture measured \(cell), so no magnification can be derived from it.",
                file: file, line: line
            )
            return
        }

        let horizontal = node.size.width / cell.width
        let vertical = node.size.height / cell.height

        guard let accepted else {
            XCTAssertEqual(
                horizontal, horizontal.rounded(), accuracy: 1e-3,
                "\(label): drawn width \(node.size.width) over the \(cell.width)px cell is \(horizontal)x -- "
                    + "not the whole-integer multiple of the 1x art gate 9 requires. If this is a "
                    + "deliberate story trade, declare it as an AcceptedMagnification here rather than "
                    + "loosening this assertion.",
                file: file, line: line
            )
            XCTAssertEqual(
                vertical, vertical.rounded(), accuracy: 1e-3,
                "\(label): drawn height \(node.size.height) over the \(cell.height)px cell is \(vertical)x -- "
                    + "not a whole-integer multiple of the 1x art.",
                file: file, line: line
            )
            XCTAssertGreaterThanOrEqual(
                horizontal.rounded(), 1,
                "\(label): \(horizontal)x draws the source art smaller than 1x, which resamples it away.",
                file: file, line: line
            )
            return
        }

        XCTAssertEqual(
            horizontal, accepted.horizontal, accuracy: accepted.accuracy,
            "\(label): drawn width \(node.size.width) over the \(cell.width)px cell is \(horizontal)x, not the "
                + "accepted \(accepted.horizontal)x. \(accepted.reason)",
            file: file, line: line
        )
        XCTAssertEqual(
            vertical, accepted.vertical, accuracy: accepted.accuracy,
            "\(label): drawn height \(node.size.height) over the \(cell.height)px cell is \(vertical)x, not the "
                + "accepted \(accepted.vertical)x. \(accepted.reason)",
            file: file, line: line
        )
        XCTAssertFalse(
            PixelCrispness.isIntegerScale(horizontal),
            "\(label): \(horizontal)x is integral, so the documented non-integer opt-out is stale and should "
                + "be removed rather than kept as an exception here. \(accepted.reason)",
            file: file, line: line
        )
    }

    /// SpriteKit-space (y-up) vectors for every `Direction8` case -- the
    /// same table `PlayerNodeTests`/`RaccoonNodeTests` use, restated here so
    /// this file drives real facing changes without depending on another
    /// test file's private helper.
    private static let spriteKitVectors: [(Direction8, CGVector)] = [
        (.south, CGVector(dx: 0, dy: -1)),
        (.southeast, CGVector(dx: 1, dy: -1)),
        (.east, CGVector(dx: 1, dy: 0)),
        (.northeast, CGVector(dx: 1, dy: 1)),
        (.north, CGVector(dx: 0, dy: 1)),
        (.northwest, CGVector(dx: -1, dy: 1)),
        (.west, CGVector(dx: -1, dy: 0)),
        (.southwest, CGVector(dx: -1, dy: -1)),
    ]

    // MARK: - The story's two accepted non-integer magnifications

    /// Accepted exception 1: the elite raccoon. `RaccoonNode.scaledSize(
    /// forTier:deviceScale:)` draws the measured 48x28 cell at 77x45 (at
    /// `deviceScale` 1) -- 1.604x/1.607x, non-integer by design, with
    /// device-pixel snapping as its only crispness guarantee. Tolerance is
    /// one whole device pixel of that snap on the shorter (28px) axis,
    /// derived from the snap rather than picked.
    private static let eliteAcceptedMagnification = AcceptedMagnification(
        horizontal: RaccoonTier.elite.scale,
        vertical: RaccoonTier.elite.scale,
        accuracy: 1 / RaccoonAnimationController.cellSize.height + 1e-6,
        reason: "AC4's 1.6x elite is a documented opt-out from the integer-scale rule "
            + "(see RaccoonNode.scaledSize(forTier:deviceScale:))."
    )

    /// Accepted exception 2: the pickup icon. `PickupNode.iconSize` draws
    /// the measured 24x24 cell at the story's fixed 32x32pt -- 1.333x.
    private static let pickupIconAcceptedMagnification = AcceptedMagnification(
        horizontal: 32.0 / 24.0,
        vertical: 32.0 / 24.0,
        accuracy: 1e-6,
        reason: "The story's fixed 32pt icon over the measured 24px cell is a documented opt-out "
            + "(see PickupNode.iconSize)."
    )

    // MARK: - Fixture

    override func setUp() {
        super.setUp()
        // `PickupNode.textureCache` is process-wide `static var` state, and
        // any earlier `PickupNode.init` in the process stamps the cached
        // instances `.nearest`/mipmap-free as a side effect of its own
        // `PixelCrispness.apply(to: icon)` call. Clearing it here is what
        // lets this file's factory-guarantee assertion
        // (`test_pickupNode_textureForColumn_...`) go red when that
        // guarantee is missing, instead of quietly reading back an
        // already-stamped instance a sibling test populated (PR #66
        // review).
        PickupNode.resetTextureCacheForTesting()
    }

    // MARK: - Actors

    func test_playerNode_body_isPixelCrisp_atConstruction_andForEveryFacing() {
        let fresh = PlayerNode()
        assertPixelCrisp(fresh.body, "PlayerNode.body (fresh)")

        for (direction, vector) in Self.spriteKitVectors {
            let player = PlayerNode()
            player.update(deltaTime: 0, movementVector: vector)
            assertPixelCrisp(player.body, "PlayerNode.body (\(direction))")
        }
    }

    /// The base tier is held to the whole-integer rule; the elite is held
    /// to its *named* exception (`eliteAcceptedMagnification`), so the
    /// sweep asserts the 1.6x opt-out rather than being structurally unable
    /// to see it -- the `xScale` check alone never could, since the elite
    /// routes its magnification through `size`.
    func test_raccoonNode_body_isPixelCrisp_forBothTiers_andEveryFacing_andEveryDeviceScale() {
        for tier in RaccoonTier.allCases {
            let accepted: AcceptedMagnification? = (tier == .elite) ? Self.eliteAcceptedMagnification : nil
            for scale: CGFloat in [1, 2, 3] {
                let raccoon = RaccoonNode(tier: tier, deviceScale: scale)
                assertPixelCrisp(
                    raccoon.body, "RaccoonNode.body (\(tier), @\(scale)x, fresh)", accepted: accepted
                )

                for (direction, _) in Self.spriteKitVectors {
                    raccoon.setDirection(direction)
                    raccoon.update(deltaTime: 0)
                    assertPixelCrisp(
                        raccoon.body,
                        "RaccoonNode.body (\(tier), @\(scale)x, \(direction))",
                        accepted: accepted
                    )
                }
            }
        }
    }

    func test_raccoonNode_attackAnimation_stayPixelCrisp() {
        let raccoon = RaccoonNode(tier: .elite)
        raccoon.playAttack()
        raccoon.update(deltaTime: 0)
        assertPixelCrisp(
            raccoon.body, "RaccoonNode.body (attack, frame 0)", accepted: Self.eliteAcceptedMagnification
        )

        raccoon.update(deltaTime: 1.0 / RaccoonAnimationController.attackFramesPerSecond)
        assertPixelCrisp(
            raccoon.body, "RaccoonNode.body (attack, frame 1)", accepted: Self.eliteAcceptedMagnification
        )
    }

    // MARK: - Ground plane

    func test_groundTileRenderer_node_isPixelCrisp_forEveryTileKind() {
        let coordinate = TileCoordinate(tileX: 4, tileY: -3)
        for kind in TileKind.allCases {
            let node = GroundTileRenderer.node(for: kind, at: coordinate)
            assertPixelCrisp(node, "GroundTileRenderer.node(\(kind))")
        }
    }

    // MARK: - Buildings + rooftop signs

    func test_tileFieldRenderer_buildingNode_isPixelCrisp_forEveryCatalogEntry() {
        for index in 0..<12 {
            let tile = TileCoordinate(tileX: 2, tileY: 1)
            let record = BuildingPlacementRecord(
                lotTile: tile,
                building: BuildingCatalog.entry(atIndex: index),
                footprintTiles: [tile],
                farCornerTile: tile
            )
            let node = TileFieldRenderer.makeBuildingNode(for: record)
            assertPixelCrisp(node, "TileFieldRenderer.makeBuildingNode(index \(index))")
        }
    }

    func test_rooftopSignRenderer_signNode_isPixelCrisp_forEveryCell() {
        let tile = TileCoordinate(tileX: 6, tileY: 6)
        let buildingRecord = BuildingPlacementRecord(
            lotTile: tile,
            building: BuildingCatalog.entry(atIndex: 2),
            footprintTiles: [tile],
            farCornerTile: tile
        )
        let buildingNode = TileFieldRenderer.makeBuildingNode(for: buildingRecord)

        for cellIndex in 0..<AtlasCellIndex.signs.count {
            let record = RooftopSignRecord(
                block: BlockCoordinate(x: 0, y: 0), carrierLotTile: tile, signCellIndex: cellIndex
            )
            let signNode = RooftopSignRenderer.makeSignNode(for: record, parent: buildingNode)
            assertPixelCrisp(signNode, "RooftopSignRenderer.makeSignNode(cell \(cellIndex))")
            signNode.removeFromParent()
        }
    }

    // MARK: - Pickups

    /// The icon carries the story's second named non-integer magnification
    /// (32pt drawn from a 24px cell), asserted here *as* an exception --
    /// the `xScale` check never saw it, since the magnification lives in
    /// `size`.
    func test_pickupNode_icon_isPixelCrisp_forEveryKind() {
        for kind in PickupKind.allCases {
            let node = PickupNode(kind: kind)
            assertPixelCrisp(
                node.icon, "PickupNode.icon(\(kind))", accepted: Self.pickupIconAcceptedMagnification
            )
            // `pad` is an untextured color fill -- `assertPixelCrisp` skips
            // the (vacuous) filtering checks for it, but scale/position
            // still apply since `PixelCrispness.apply(to:)` is called on it
            // too.
            assertPixelCrisp(node.pad, "PickupNode.pad(\(kind))")
        }
    }

    /// The premise every stamp site (and this PR's `PickupNode` change)
    /// rests on, **measured instead of assumed** -- and it does not hold
    /// the way this file's first revision asserted it (PR #66 review asked
    /// for exactly this check; running it is what corrected the record).
    ///
    /// The claim was: "`SpriteSheet.texture(col:row:)` crops a new
    /// `SKTexture` via `SKTexture(rect:in:)`, which does not inherit the
    /// parent sheet texture's filtering/mipmap settings." Measured on a
    /// real run, a fresh crop out of a `TextureLoading`-stamped sheet reads
    /// back `.nearest` with mipmaps off *without* any further stamping --
    /// `SKTexture(rect:in:)` carries the parent's settings across.
    ///
    /// So the explicit per-factory stamps are **consistency, not rescue**:
    /// `PickupNode.texture(forColumn:)`'s missing stamp was a deviation
    /// from the pattern every sibling factory follows, not a live blur on a
    /// device. The stamps are still worth keeping -- crop inheritance is
    /// undocumented `SKTexture` behaviour that a future SpriteKit release
    /// is free to change, and this test is the tripwire for that -- but
    /// `gate-09-pixel-crispness-sweep.txt` no longer calls that deviation
    /// "the one real offender", because this measurement does not support
    /// that wording.
    ///
    /// The identity assertion below is what makes this measurement
    /// trustworthy: the crop under test must be a genuinely fresh instance,
    /// never the already-stamped one `PickupNode`'s process-wide cache
    /// holds.
    func test_aRawSheetCrop_carriesTheSheetsNearestFiltering_measuredNotAssumed() {
        let sheet = AtlasSheet.pickups.sheet
        XCTAssertEqual(
            TextureLoading.texture(named: sheet.imageID).filteringMode, .nearest,
            "TextureLoading must stamp the whole-sheet texture nearest -- otherwise this test proves nothing."
        )

        PickupNode.resetTextureCacheForTesting()
        let crop = sheet.texture(col: 1, row: 0)
        let factoryTexture = PickupNode.texture(forColumn: 1)
        XCTAssertFalse(
            crop === factoryTexture,
            "This must measure a fresh crop, not the instance PickupNode's factory stamped and cached."
        )

        XCTAssertEqual(
            crop.filteringMode, .nearest,
            "Measured: a rect crop of a nearest-stamped sheet reads back .nearest with no stamp of its own. "
                + "If this ever goes red, SKTexture stopped propagating filtering to sub-textures and every "
                + "factory's explicit stamp becomes load-bearing -- restore the 'real offender' framing in "
                + "gate-09-pixel-crispness-sweep.txt at the same time."
        )
        XCTAssertFalse(
            crop.usesMipmaps,
            "Measured: a fresh rect crop does not enable mipmaps on its own."
        )
    }

    /// The one deviation this sweep found (see the type doc comment):
    /// `PickupNode.texture(forColumn:)` cached a crop it had never stamped
    /// itself. This asserts the *factory* now provides the guarantee
    /// directly -- independent both of any caller's follow-up `apply(to:)`
    /// call and of `SKTexture`'s undocumented crop-inheritance behaviour
    /// (which the test above measures, and which is why this is a
    /// consistency fix rather than a blur fix).
    ///
    /// **Why this can now fail with the fix reverted** (PR #66 review). The
    /// cache is process-wide `static var` state, so as first written this
    /// method read back an instance some earlier `PickupNode.init` in the
    /// process had already stamped -- it passed either way, and the suite
    /// would not have gone red if someone deleted the two lines in
    /// `PickupNode.texture(forColumn:)`. `setUp` now clears the cache
    /// through `PickupNode.resetTextureCacheForTesting()`, and this method
    /// re-clears it per kind, so every texture below is a genuinely fresh
    /// crop that only the factory has touched.
    func test_pickupNode_textureForColumn_isNearestFilteredAndMipmapFree_directlyFromTheFactory() {
        for kind in PickupKind.allCases {
            PickupNode.resetTextureCacheForTesting()
            let texture = PickupNode.texture(forColumn: kind.atlasColumn)
            XCTAssertEqual(texture.filteringMode, .nearest, "\(kind): factory-cached texture must be nearest-filtered.")
            XCTAssertFalse(texture.usesMipmaps, "\(kind): factory-cached texture must not use mipmaps.")
        }
    }

    // MARK: - Combat effects

    func test_bulletNode_isPixelCrisp_forEveryTier_freshAndAfterConfigure() {
        for tier in WeaponTier.allCases {
            let bullet = BulletNode(tier: tier)
            assertPixelCrisp(bullet, "BulletNode(\(tier), fresh)")

            // A whole-point origin, which pins only the texture/scale half
            // of the contract here: `configure(...)` writes `position`
            // through verbatim, so asserting this supplied point is whole
            // proves nothing about placement. What production actually
            // hands it is asserted in
            // `test_bulletNode_inFlightPlacement_isTheAcceptedSubPixelException`
            // below (PR #66 review).
            bullet.configure(tier: tier, position: CGPoint(x: 10, y: -20), spriteKitShotVector: CGVector(dx: 1, dy: 0))
            assertPixelCrisp(bullet, "BulletNode(\(tier), configured)")
        }
    }

    /// Accepted exception 3, pinned rather than netted out (PR #66 review).
    ///
    /// **Why bullets really are placed at sub-pixel positions.** The
    /// production caller is `Player.handleFire(target:origin:tier:)` plus
    /// `Player.advanceInFlightBullets(deltaTime:)`, and neither rounds:
    ///  - `IsometricProjection.tileToScreen(origin)` is integer-in/
    ///    integer-out, but `origin` is the player's *fractional*
    ///    `TilePoint` mid-walk, so the muzzle point is already fractional;
    ///  - `effectsSpacePoint(fromWorldSpace:)` then adds `worldLayer
    ///    .position`, which `CameraController` snaps to the **device pixel**
    ///    grid, not the whole-point grid;
    ///  - `advanceInFlightBullets(deltaTime:)` rewrites `bulletNode
    ///    .position` every frame to a linear interpolation by
    ///    `elapsed / travelDuration`, with no rounding anywhere on that
    ///    path.
    ///
    /// **Why it is accepted rather than "fixed" here.** `BulletNode` also
    /// sets `zRotation` from `atan2` (AC5: the round points along its shot
    /// vector), so an in-flight bullet's texels are resampled off-axis
    /// whatever its position -- snapping the position to whole points would
    /// not make a rotated sprite pixel-exact, it would only make a
    /// fast-moving projectile step visibly. So the trade is recorded as a
    /// named gate-9 exception in `gate-09-pixel-crispness-sweep.txt`, and
    /// the real behaviour is pinned below so any future change to it is a
    /// deliberate one.
    func test_bulletNode_inFlightPlacement_isTheAcceptedSubPixelException() {
        let subPixelPoint = CGPoint(x: 10.37, y: -20.62)
        let diagonalShot = CGVector(dx: 1, dy: 1)

        for tier in WeaponTier.allCases {
            let bullet = BulletNode(tier: tier)
            bullet.configure(tier: tier, position: subPixelPoint, spriteKitShotVector: diagonalShot)

            // Everything else about a bullet is still held to the rule:
            // nearest filtering, no mipmaps, 1x magnification, no
            // magnification in scale.
            assertPixelCrisp(bullet, "BulletNode(\(tier), sub-pixel)", acceptedSubPixelPlacement: true)

            // The exception itself, asserted rather than skipped:
            // `configure` writes the caller's fractional point through
            // untouched. If a later PR adds snapping (in `configure` or in
            // `advanceInFlightBullets`), this is the assertion that should
            // be inverted -- and the gate-9 trace's bullet exception
            // removed at the same time.
            XCTAssertEqual(
                bullet.position.x, subPixelPoint.x, accuracy: 1e-3,
                "\(tier): configure(...) must pass the caller's x through unrounded (see this test's doc)."
            )
            XCTAssertEqual(
                bullet.position.y, subPixelPoint.y, accuracy: 1e-3,
                "\(tier): configure(...) must pass the caller's y through unrounded (see this test's doc)."
            )
            XCTAssertNotEqual(
                bullet.position.x, bullet.position.x.rounded(), accuracy: 1e-3,
                "\(tier): this test is meaningless unless the supplied point really is off the whole-point grid."
            )

            // The other half of the exception: a bullet is rotated
            // off-axis by design (AC5), which `assertPixelCrisp` does not
            // look at -- so gate 9's crispness claim never covered a
            // bullet's rasterization to begin with.
            XCTAssertEqual(
                bullet.zRotation, atan2(diagonalShot.dy, diagonalShot.dx), accuracy: 1e-6,
                "\(tier): a bullet points along its shot vector, so its texels are resampled off-axis."
            )
            XCTAssertNotEqual(
                bullet.zRotation.truncatingRemainder(dividingBy: .pi / 2), 0, accuracy: 1e-6,
                "\(tier): a diagonal shot must not land on an axis-aligned rotation, or this proves nothing."
            )
        }
    }

    func test_hitEffects_muzzleFlashAndHitPuff_arePixelCrisp() {
        let muzzle = HitEffects.spawnMuzzleFlash(at: CGPoint(x: 3, y: -4))
        assertPixelCrisp(muzzle, "HitEffects.spawnMuzzleFlash")

        let puff = HitEffects.spawnHitPuff(at: CGPoint(x: -7, y: 8))
        assertPixelCrisp(puff, "HitEffects.spawnHitPuff")
    }

    func test_pulseRingNode_isPixelCrisp_atConstruction_andAfterPlay() {
        let ring = PulseRingNode()
        assertPixelCrisp(ring, "PulseRingNode(fresh)")

        ring.play(radiusTiles: 3, at: CGPoint(x: 12, y: -6))
        assertPixelCrisp(ring, "PulseRingNode(after play)")
    }

    func test_weaponOverlayRenderer_overlay_isPixelCrisp_forEveryTierAndDirection() {
        let body = SKSpriteNode(texture: nil, color: .clear, size: PlayerSpriteSheet.cellSize)
        body.anchorPoint = PlayerSpriteSheet.anchorPointNormalized

        for tier in WeaponTier.allCases {
            for direction in Direction8.allCases {
                let renderer = WeaponOverlayRenderer(body: body, tier: tier, direction: direction)
                assertPixelCrisp(renderer.overlay, "WeaponOverlayRenderer.overlay(\(tier), \(direction))")
                renderer.overlay.removeFromParent()
            }
        }
    }
}
