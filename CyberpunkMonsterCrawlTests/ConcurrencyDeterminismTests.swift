import Dispatch
import XCTest
@testable import CyberpunkMonsterCrawl

/// AC7: `CityLatticeGenerator.classify` must be side-effect free and
/// thread-safe \u2014 the same `(tileX, tileY, seed)` dispatched concurrently
/// from many threads must always agree with a single-threaded reference
/// call. `SeedMixer`/`classify` hold no shared mutable state, but this
/// exists to prove that property rather than assume it: a cache, a lazily
/// initialised global, or an accidental PRNG stream would only show up
/// under real concurrent access.
final class ConcurrencyDeterminismTests: XCTestCase {

    func test_classify_calledConcurrentlyForSameInput_alwaysReturnsIdenticalResult() {
        let seed = WorldSeed(rawValue: 0xC0FFEE_1234_5678)
        let tileX = 41
        let tileY = -17

        let reference = CityLatticeGenerator.classify(tileX: tileX, tileY: tileY, seed: seed)

        let iterations = 500
        let results = UnsafeMutableBufferPointer<TileInfo?>.allocate(capacity: iterations)
        results.initialize(repeating: nil)
        defer { results.deallocate() }

        // Each iteration writes to its own, distinct index, so there is no
        // data race on `results` itself \u2014 the concurrency under test is
        // purely inside `classify`.
        DispatchQueue.concurrentPerform(iterations: iterations) { index in
            results[index] = CityLatticeGenerator.classify(tileX: tileX, tileY: tileY, seed: seed)
        }

        for index in 0..<iterations {
            XCTAssertEqual(results[index], reference, "Mismatch at concurrent iteration \(index)")
        }
    }

    /// Same idea across many distinct tiles/seeds at once, spread over
    /// `DispatchQueue.concurrentPerform` so results land on whichever
    /// worker thread GCD schedules them on \u2014 proving there's no shared
    /// state that would make the answer depend on execution order (this is
    /// also the property `CYBERPUN-17-3-t3`'s chunk generator relies on:
    /// a chunk's tiles can be generated in any order, or on any thread,
    /// and must still agree with a standalone `classify` call).
    func test_classify_manyDistinctInputsConcurrently_matchSingleThreadedReference() {
        struct Input {
            let tileX: Int
            let tileY: Int
            let seed: WorldSeed
        }

        var inputs: [Input] = []
        for seedValue in 0..<10 {
            for tileX in stride(from: -15, through: 15, by: 3) {
                for tileY in stride(from: -15, through: 15, by: 3) {
                    inputs.append(Input(tileX: tileX, tileY: tileY, seed: WorldSeed(rawValue: UInt64(seedValue))))
                }
            }
        }

        let references = inputs.map {
            CityLatticeGenerator.classify(tileX: $0.tileX, tileY: $0.tileY, seed: $0.seed)
        }

        let results = UnsafeMutableBufferPointer<TileInfo?>.allocate(capacity: inputs.count)
        results.initialize(repeating: nil)
        defer { results.deallocate() }

        DispatchQueue.concurrentPerform(iterations: inputs.count) { index in
            let input = inputs[index]
            results[index] = CityLatticeGenerator.classify(tileX: input.tileX, tileY: input.tileY, seed: input.seed)
        }

        for index in 0..<inputs.count {
            XCTAssertEqual(
                results[index], references[index],
                "Mismatch at index \(index) for input (\(inputs[index].tileX), \(inputs[index].tileY))"
            )
        }
    }
}
