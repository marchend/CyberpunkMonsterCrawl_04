import CoreGraphics
import SpriteKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-9` PR 2: `HitEffects`' muzzle-flash (frame 0 only) and
/// hit-puff (full animation) node construction.
final class HitEffectsTests: XCTestCase {

    func test_spawnMuzzleFlash_usesFrameZero_atTheGivenPosition() {
        let position = CGPoint(x: 12, y: 34)
        let node = HitEffects.spawnMuzzleFlash(at: position)

        XCTAssertTrue(node.texture === HitEffects.texture(forColumn: 0))
        XCTAssertEqual(node.position, position)
        XCTAssertNil(
            node.action(forKey: HitEffects.hitPuffAnimationActionKey),
            "a muzzle flash is a single static frame; it must not run the hit-puff animation."
        )
    }

    func test_spawnHitPuff_startsOnFrameZero_atTheImpactPoint_andRunsTheAnimation() {
        let position = CGPoint(x: 1, y: 2)
        let node = HitEffects.spawnHitPuff(at: position)

        XCTAssertTrue(node.texture === HitEffects.texture(forColumn: 0))
        XCTAssertEqual(node.position, position)
        XCTAssertNotNil(
            node.action(forKey: HitEffects.hitPuffAnimationActionKey),
            "a hit puff must run its animation under the documented action key."
        )
    }

    func test_textureForColumn_isDistinctPerColumn_acrossTheWholeSheet() {
        var seen = Set<ObjectIdentifier>()
        for column in 0..<AtlasCellIndex.hitPuff.count {
            let id = ObjectIdentifier(HitEffects.texture(forColumn: column))
            XCTAssertFalse(seen.contains(id), "column \(column) shares a texture with another column.")
            seen.insert(id)
        }
        XCTAssertEqual(seen.count, AtlasCellIndex.hitPuff.count)
    }

    func test_spawnedNodes_shareTheMeasuredHitPuffCellSize() {
        guard let expectedSize = AtlasSheet.hitPuff.sheet.cellSize else {
            XCTFail("AtlasSheet.hitPuff must declare a uniform cellSize.")
            return
        }
        let muzzle = HitEffects.spawnMuzzleFlash(at: .zero)
        let puff = HitEffects.spawnHitPuff(at: .zero)

        XCTAssertEqual(muzzle.size, expectedSize)
        XCTAssertEqual(puff.size, expectedSize)
    }
}
