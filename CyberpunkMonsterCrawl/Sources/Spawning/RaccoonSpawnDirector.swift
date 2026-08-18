import CoreGraphics
import Foundation
import SpriteKit

/// A small, deterministic `RandomNumberGenerator` seeded from a single
/// `UInt64` -- used by `RaccoonSpawnDirector` instead of
/// `SystemRandomNumberGenerator` so spawn selection is reproducible in
/// tests without a live `SKView`. The mixing step is the same splitmix64
/// round `SeedMixer` uses for its own per-coordinate hash, iterated here
/// into a stream rather than applied once to a fixed input.
struct SplitMix64RandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    /// A zero seed is remapped to the golden-gamma constant so the very
    /// first output isn't the same fixed value `mix(0)` would otherwise
    /// produce from an all-zero state.
    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z = z ^ (z >> 31)
        return z
    }
}

/// Off-screen street-tile spawn selection and swarm-size/cadence
/// management for the raccoon swarm (`CYBERPUN-17-8` PR 2).
///
/// **Scope of this PR.** Spawning and per-frame seek movement only -- no
/// bite/damage/rabies (a later part of the `CYBERPUN-17-8` story) and no
/// death/despawn, so a raccoon mounted here only ever leaves
/// `activeRaccoons` via `reset()` (a new run starting). The swarm therefore
/// only ever grows toward `maxConcurrentSwarmSize` within one run; a later
/// PR's `takeDamage`/death entry point is what shrinks it back down.
///
/// **Single production caller.** `GameScene` constructs one of these in
/// `commonInit()` and calls `update(deltaTime:playerPosition:obstructions:)`
/// once per frame from `advanceMovementAndCamera(currentTime:)`, mirroring
/// `GroundPlaneStreamer`/`CameraController`'s own "a factory nothing calls
/// renders nothing in a real build" rule.
final class RaccoonSpawnDirector {

    // MARK: - Tunable constants
    //
    // `CYBERPUN-17-8`: "Tune spawn cadence and swarm size in playtesting;
    // expose the numbers as named constants." These are the initial
    // values; a later playtesting pass is expected to retune them.

    /// Seconds between spawn attempts at the very start of a run (elapsed
    /// time `0`). `spawnInterval(atElapsedTime:)` ramps this down as the
    /// run continues -- the story's "pressure ramps with run time".
    static let initialSpawnInterval: TimeInterval = 3.0

    /// The floor `spawnInterval(atElapsedTime:)`'s ramp decays toward, so
    /// an arbitrarily long run cannot spawn every single frame.
    static let minimumSpawnInterval: TimeInterval = 0.6

    /// How many seconds of elapsed run time it takes the spawn interval to
    /// halve the remaining distance between `initialSpawnInterval` and
    /// `minimumSpawnInterval` -- the ramp curve's own time constant.
    static let spawnIntervalHalfLife: TimeInterval = 45.0

    /// Hard cap on live raccoons at any one time.
    static let maxConcurrentSwarmSize = 40

    /// Fraction of spawns promoted to `.elite`.
    static let eliteSpawnFraction: Double = 0.15

    /// Minimum magnitude (tiles), on whichever tile axis a candidate spawn
    /// tile leaves unconstrained by the street-lane snap (see
    /// `nearestStreetLaneIndex(_:)`), a spawn's offset from the camera is
    /// drawn from. `farAxisMaximumTiles` is the range's upper bound.
    ///
    /// **Why this is enough to guarantee off-screen.** `IsometricProjection`
    /// projects a tile-space delta `(dx, dy)` to screen space as
    /// `screenX = (dx - dy) * 48`. The *other* axis (the one snapped to a
    /// street lane) is drawn from `nearAxisRange` and then moved by at most
    /// `CityLatticeGenerator.period / 2` (3) more tiles by the snap itself
    /// (`nearestStreetLaneIndex`'s own doc comment), so its total magnitude
    /// never exceeds `nearAxisRange`'s bound plus `3`. With the far axis at
    /// least `farAxisMinimumTiles` in magnitude, `|dx - dy|` is therefore at
    /// least `farAxisMinimumTiles - (nearAxisRange bound + 3)` --
    /// `40 - (15 + 3) = 22` tiles at the values below, i.e. at least
    /// `22 * 48 = 1_056` screen points. That comfortably exceeds half the
    /// width of the largest supported viewport
    /// (`ChunkStreamingManager.referenceViewportPoints`, `683pt`), in
    /// either screen axis and either device orientation, so a spawn is
    /// never visible on the frame it lands. `RaccoonSpawnDirectorTests`
    /// checks this directly against `isOnScreen(tile:cameraPosition:
    /// viewportSize:)` rather than trusting the arithmetic in prose.
    static let farAxisMinimumTiles: Double = 40
    static let farAxisMaximumTiles: Double = 56

    /// Range the *near* (lane-snapped) axis's pre-snap target is drawn
    /// from, giving spawns some spread along the corridor rather than all
    /// landing directly ahead of or behind the camera on that axis.
    static let nearAxisRange: ClosedRange<Double> = -15...15

    // MARK: - Dependencies

    private weak var worldLayer: SKNode?
    private let deviceScale: () -> CGFloat
    private var rng: SplitMix64RandomNumberGenerator

    // MARK: - State

    private struct ActiveRaccoon {
        let node: RaccoonNode
        var position: TilePoint
    }

    private var activeRaccoons: [ActiveRaccoon] = []
    private var elapsedRunTime: TimeInterval = 0
    private var timeUntilNextSpawn: TimeInterval

    /// Live raccoon count, exposed for tests and for a future HUD.
    var swarmCount: Int { activeRaccoons.count }

    /// - Parameters:
    ///   - worldLayer: the node raccoon nodes are parented into, mirroring
    ///     `GroundPlaneStreamer`/`PlayerNode`'s own direct-child convention
    ///     (their `zPosition` is `worldLayer`-relative).
    ///   - deviceScale: the device pixel grid a spawned raccoon's tier
    ///     scale and screen position are snapped to, read live per call
    ///     like `GameScene.deviceScale`. Defaults to `1`, the whole-point
    ///     fallback for a headless, view-less scene (unit tests).
    ///   - rng: the spawn-selection random source. Defaults to a
    ///     freshly-seeded generator (real gameplay variety needs no
    ///     determinism); tests inject a fixed seed instead.
    init(
        worldLayer: SKNode,
        deviceScale: @escaping () -> CGFloat = { 1 },
        rng: SplitMix64RandomNumberGenerator = SplitMix64RandomNumberGenerator(
            seed: UInt64.random(in: UInt64.min...UInt64.max)
        )
    ) {
        self.worldLayer = worldLayer
        self.deviceScale = deviceScale
        self.rng = rng
        self.timeUntilNextSpawn = Self.initialSpawnInterval
    }

    /// Advances the swarm by one frame: ramps the spawn timer, spawns a new
    /// raccoon (off-screen, on a street tile) whenever it elapses and the
    /// swarm has room, and steers every live raccoon toward
    /// `playerPosition` through `RaccoonSeekBehavior`/`BuildingAvoidance`.
    ///
    /// At most one raccoon is spawned per call, however large `deltaTime`
    /// is -- a stalled frame catches up on the *next* call rather than
    /// bursting every missed spawn out at once, the same bounded-work-per-
    /// frame discipline `GroundPlaneStreamer.advanceIncrementalMount()`
    /// follows.
    func update(deltaTime: TimeInterval, playerPosition: TilePoint, obstructions: [CollisionResolver.FootprintBounds]) {
        guard deltaTime > 0 else { return }
        elapsedRunTime += deltaTime
        timeUntilNextSpawn -= deltaTime

        if timeUntilNextSpawn <= 0 {
            if activeRaccoons.count < Self.maxConcurrentSwarmSize {
                spawnRaccoon(near: playerPosition)
                timeUntilNextSpawn = Self.spawnInterval(atElapsedTime: elapsedRunTime)
            } else {
                // No room: hold the timer at zero so a slot freeing up next
                // frame (a future PR's death/despawn) is spawned into
                // immediately, without a backlog of missed spawns bursting
                // out all at once.
                timeUntilNextSpawn = 0
            }
        }

        for index in activeRaccoons.indices {
            let resolved = RaccoonSeekBehavior.update(
                raccoon: activeRaccoons[index].node,
                currentPosition: activeRaccoons[index].position,
                playerPosition: playerPosition,
                obstructions: obstructions,
                deltaTime: deltaTime
            )
            activeRaccoons[index].position = resolved
            applyScreenPosition(resolved, to: activeRaccoons[index].node)
        }
    }

    /// Tears down every live raccoon and restarts the spawn timer/ramp
    /// clock from scratch. `GameScene.updateWorldContent(for:)` calls this
    /// on every fresh entry to `.gameplay`, the same way it restarts
    /// `groundPlane`/`player` -- without it, a RUN AGAIN would inherit the
    /// previous run's swarm instead of starting clean.
    func reset() {
        for raccoon in activeRaccoons {
            raccoon.node.removeFromParent()
        }
        activeRaccoons.removeAll()
        elapsedRunTime = 0
        timeUntilNextSpawn = Self.initialSpawnInterval
    }

    // MARK: - Spawning

    private func spawnRaccoon(near cameraPosition: TilePoint) {
        guard let worldLayer else { return }

        let tile = Self.selectSpawnTile(near: cameraPosition, rng: &rng)
        let position = TilePoint(x: Double(tile.tileX), y: Double(tile.tileY))
        let tier = Self.selectTier(rng: &rng)

        let raccoon = RaccoonNode(tier: tier, deviceScale: deviceScale())
        worldLayer.addChild(raccoon)
        applyScreenPosition(position, to: raccoon)

        activeRaccoons.append(ActiveRaccoon(node: raccoon, position: position))
    }

    private func applyScreenPosition(_ position: TilePoint, to raccoon: RaccoonNode) {
        let rawPosition = IsometricProjection.tileToScreen(position)
        raccoon.position = PixelCrispness.snappedPosition(for: rawPosition, scale: deviceScale())
        raccoon.updateDepth(atTilePosition: position)
    }

    /// Samples `.elite` with probability `eliteSpawnFraction`, `.base`
    /// otherwise. A pure `static` function (rather than folded into
    /// `spawnRaccoon`) so tests can sample it directly, many times, without
    /// needing a live `RaccoonSpawnDirector`/`SKNode` -- the swarm-size cap
    /// otherwise limits how many spawns a single instance ever produces in
    /// one run, which is too few draws for a statistically meaningful
    /// fraction check.
    static func selectTier(rng: inout SplitMix64RandomNumberGenerator) -> RaccoonTier {
        Double.random(in: 0..<1, using: &rng) < eliteSpawnFraction ? .elite : .base
    }

    // MARK: - Ramp curve

    /// The spawn interval `elapsed` seconds into a run: exponential decay
    /// from `initialSpawnInterval` toward `minimumSpawnInterval`, halving
    /// the remaining gap every `spawnIntervalHalfLife` seconds. Pure and
    /// exposed (rather than folded into `update`) so tests can pin the
    /// ramp curve directly against fixed elapsed times.
    static func spawnInterval(atElapsedTime elapsed: TimeInterval) -> TimeInterval {
        guard elapsed > 0 else { return initialSpawnInterval }
        let decay = pow(0.5, elapsed / spawnIntervalHalfLife)
        return minimumSpawnInterval + (initialSpawnInterval - minimumSpawnInterval) * decay
    }

    // MARK: - Spawn tile selection

    /// Selects an off-screen street tile near `cameraPosition`: a random
    /// compass direction with a large offset on one tile axis (guaranteeing
    /// off-screen -- see `farAxisMinimumTiles`'s doc comment) and a small
    /// offset on the other, snapped to the nearest street-corridor lane
    /// (guaranteeing the tile is street, connected to the rest of the
    /// lattice -- see `nearestStreetLaneIndex(_:)`).
    ///
    /// Exposed as a `static` function taking its `rng` by `inout` so tests
    /// can drive it deterministically without constructing a whole
    /// director instance.
    static func selectSpawnTile(near cameraPosition: TilePoint, rng: inout SplitMix64RandomNumberGenerator) -> TileCoordinate {
        let farMagnitude = Double.random(in: farAxisMinimumTiles...farAxisMaximumTiles, using: &rng)
        let farOffset = Bool.random(using: &rng) ? farMagnitude : -farMagnitude
        let nearTarget = Double.random(in: nearAxisRange, using: &rng)
        let useHorizontalCorridor = Bool.random(using: &rng)

        if useHorizontalCorridor {
            // The far offset lands on the X axis; Y is snapped to the
            // nearest street lane, which guarantees the whole row is
            // street regardless of X (see `nearestStreetLaneIndex`'s doc
            // comment).
            let tileX = Int((cameraPosition.x + farOffset).rounded())
            let tileY = nearestStreetLaneIndex(cameraPosition.y + nearTarget)
            return TileCoordinate(tileX: tileX, tileY: tileY)
        } else {
            let tileY = Int((cameraPosition.y + farOffset).rounded())
            let tileX = nearestStreetLaneIndex(cameraPosition.x + nearTarget)
            return TileCoordinate(tileX: tileX, tileY: tileY)
        }
    }

    /// Rounds `coordinate` to the nearest street-corridor driving-lane
    /// index on a single axis: the nearest multiple of
    /// `CityLatticeGenerator.period` offset by
    /// `RunSpawnSelector.junctionCentreOffset` -- the exact lane-centre
    /// arithmetic `RunSpawnSelector` uses for its own crossing centre,
    /// reused here as a single *axis* rather than a full crossing: with
    /// this axis pinned to its band, `CityLatticeGenerator.classify`
    /// returns a street kind for **any** value of the other axis (its
    /// `isStreetX || isStreetY` test only needs one axis in the band), so
    /// the far axis in `selectSpawnTile` can range freely while this one
    /// guarantees the whole line is street -- independent of `WorldSeed`,
    /// since a street tile's classification never consults the seed
    /// (`CityLatticeGenerator`'s own doc comment: "This branch never
    /// consults seed").
    ///
    /// The result is never more than `period / 2` (3) tiles from
    /// `coordinate` -- the bound `farAxisMinimumTiles`'s doc comment relies
    /// on.
    private static func nearestStreetLaneIndex(_ coordinate: Double) -> Int {
        let period = Double(CityLatticeGenerator.period)
        let offset = Double(RunSpawnSelector.junctionCentreOffset)
        let blockIndex = ((coordinate - offset) / period).rounded()
        return Int(blockIndex * period + offset)
    }

    /// Whether tile `tile` would fall inside a `viewportSize`-sized
    /// viewport centred on `cameraPosition` -- the real screen-space
    /// geometry (not a tile-space radius approximation, which does not
    /// correspond to a screen-space rectangle on this uneven 2:1
    /// projection). Exposed so tests can audit `selectSpawnTile`'s actual
    /// output against the same definition of "on screen" the spawn
    /// distance constants are derived from.
    static func isOnScreen(tile: TileCoordinate, cameraPosition: TilePoint, viewportSize: CGSize) -> Bool {
        let tileScreen = IsometricProjection.tileToScreen(
            tileX: Double(tile.tileX), tileY: Double(tile.tileY)
        )
        let cameraScreen = IsometricProjection.tileToScreen(cameraPosition)
        let dx = abs(tileScreen.x - cameraScreen.x)
        let dy = abs(tileScreen.y - cameraScreen.y)
        return dx <= viewportSize.width / 2 && dy <= viewportSize.height / 2
    }
}
