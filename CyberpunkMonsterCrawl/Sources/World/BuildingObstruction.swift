import Foundation

/// Footprint-only building obstruction: whether a world tile is blocked by a
/// placed building, derived solely from `BuildingPlacementRecord
/// .footprintTiles` \u2014 never from a rendered sprite's bounding box.
///
/// `docs/bootstrap.md` \u00a71: "No physics engine for world collision. Buildings
/// are flat base-diamond footprints on a tile grid; collision is a tile
/// query, not `SKPhysicsBody`. Visual height must never affect collision."
/// `TileKind.buildingFootprint.isWalkable == false` already gives this for
/// free at generation time \u2014 `ChunkGenerator`/`CityLatticeGenerator` classify
/// every footprint tile solid before any building sprite is ever chosen for
/// it, so a tall four-storey `building_05` and a one-storey `building_10`
/// sharing an identical footprint obstruct identically
/// (`BuildingCollisionTests` pins that parity directly).
///
/// This type exists so a movement/collision consumer has one small, named,
/// footprint-only entry point to ask that same question against a specific
/// placement record \u2014 `CYBERPUN-17-7` ("wire the thumbstick, player
/// movement, building collision and camera") is the story that calls it from
/// a live actor \u2014 rather than reaching for a rendered node's
/// `calculateAccumulatedFrame()` / `SKSpriteNode.size`, which is exactly the
/// axis the brief says must never matter to collision.
enum BuildingObstruction {
    /// Whether `tile` is obstructed by `record`'s reserved footprint.
    static func isObstructed(_ tile: TileCoordinate, by record: BuildingPlacementRecord) -> Bool {
        record.footprintTiles.contains(tile)
    }

    /// Whether `tile` is obstructed by any of `records`' reserved footprints.
    static func isObstructed(_ tile: TileCoordinate, byAnyOf records: [BuildingPlacementRecord]) -> Bool {
        records.contains { isObstructed(tile, by: $0) }
    }
}
