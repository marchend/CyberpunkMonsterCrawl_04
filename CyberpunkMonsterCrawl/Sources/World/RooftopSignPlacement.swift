import Foundation

/// One rooftop neon sign placed by `RooftopSignPlacement.generate`: which
/// block it belongs to, which building lot within that block carries it,
/// and which of the `sprite_signs` atlas's 12 sign variants it uses.
struct RooftopSignRecord: Equatable {
    let block: BlockCoordinate
    /// The `BuildingPlacementRecord.lotTile` of the building that carries
    /// this sign — always one of the lots in the `placements` array passed
    /// to `generate`, never an empty lot.
    let carrierLotTile: TileCoordinate
    /// Index into the `sprite_signs` atlas's 12 cells (4 cols x 3 rows,
    /// `AtlasCellIndex.signs` in `Sources/Assets`). A plain `Int` rather
    /// than that atlas's own cell-index type, so this pure `World`-layer
    /// record never imports `Sources/Assets` — a later rendering consumer
    /// translates.
    let signCellIndex: Int
}

/// Decides, per block, whether that block carries a rooftop neon sign and,
/// if so, which building lot and which of the 12 sign variants.
///
/// **Scope of this PR (`CYBERPUN-17-5-t1`):** pure logic only — no
/// SpriteKit, no rendering.
enum RooftopSignPlacement {
    /// Denominator of the seed-driven "is this block signed" decision:
    /// ~1-in-3 building blocks get a rooftop sign, per the story. (An empty
    /// block is never eligible at all — see the `placements.isEmpty` guard
    /// in `generate` — so this ratio is measured, and only meaningful,
    /// among *building* blocks.)
    static let signedBlockModulus: UInt64 = 3

    /// Number of sign variants in the `sprite_signs` atlas
    /// (`AtlasCellIndex.signs`: 4 cols x 3 rows = 12 cells).
    static let signCellCount = 12

    /// Distinct salts XORed into `WorldSeed.rawValue` before hashing, one
    /// per independent decision, so none of these three streams — nor
    /// `BuildingPlacement`'s own `buildingSelectionSalt` stream, nor
    /// `CityLatticeGenerator`'s empty-block stream — ever coincide. The
    /// story specifically calls for "an independent RNG stream from
    /// building selection" for the signed/not-signed decision; the carrier
    /// and sign-cell picks get their own salts too, so a future tweak to
    /// one decision (e.g. changing `signedBlockModulus`) can never
    /// accidentally correlate with which lot or which cell gets picked.
    private static let signedDecisionSalt: UInt64 = 0xB1D9_51A4_0002
    private static let carrierLotSalt: UInt64 = 0xB1D9_51A4_0003
    private static let signCellSalt: UInt64 = 0xB1D9_51A4_0004

    /// Decides block `block`'s rooftop sign, given the buildings
    /// `BuildingPlacement.generate` already placed there.
    ///
    /// Guards against signing a fully-empty block by construction: if
    /// `placements` is empty (the block was one of the lattice's ~1-in-4
    /// deliberately-empty blocks, or otherwise has no building placed),
    /// this returns `nil` unconditionally, without even consulting the
    /// signed/not-signed roll — there is no lot to hang a sign from.
    static func generate(
        forBlock block: BlockCoordinate,
        placements: [BuildingPlacementRecord],
        seed: WorldSeed
    ) -> RooftopSignRecord? {
        guard !placements.isEmpty else { return nil }

        let decisionRoll = SeedMixer.bounded(
            seed: seed.rawValue ^ signedDecisionSalt,
            tileX: block.x,
            tileY: block.y,
            modulus: signedBlockModulus
        )
        guard decisionRoll == 0 else { return nil }

        let carrierHash = SeedMixer.hash(seed: seed.rawValue ^ carrierLotSalt, tileX: block.x, tileY: block.y)
        let carrier = placements[Int(carrierHash % UInt64(placements.count))]

        let cellHash = SeedMixer.hash(seed: seed.rawValue ^ signCellSalt, tileX: block.x, tileY: block.y)
        let signCellIndex = Int(cellHash % UInt64(signCellCount))

        return RooftopSignRecord(block: block, carrierLotTile: carrier.lotTile, signCellIndex: signCellIndex)
    }
}
