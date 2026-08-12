import CoreGraphics
import Foundation
import UIKit

// MARK: - Measurement

/// Facts read out of an *imported* image. Every value here is measured from
/// pixels at runtime — nothing is derived from a filename. `docs/bootstrap.md`
/// §2 is explicit that sheet dimensions and cell grids must be measured
/// programmatically and never inferred: a sheet called `..._8dir` is not
/// evidence of eight columns, and a `.png` extension is not evidence of an
/// alpha channel.
struct AtlasImageMeasurement: Equatable {
    /// Size in pixels of the 1× rendition, read from the `CGImage`.
    let pixelSize: CGSize

    /// `true` when the decoded image actually carries an alpha channel
    /// (PNG-32). Measured from `CGImage.alphaInfo`, so the "transparent
    /// buildings" assumption in the spec is backed by a real observation.
    let hasAlphaChannel: Bool

    /// Hash of the image's rasterised RGBA bytes. Used only to compare images
    /// against each other *within a single process* (Swift's hash seed is
    /// randomised per run), which is all the distinctness checks need.
    let contentFingerprint: Int

    /// Same hash taken over a horizontally flipped rasterisation, so two
    /// building sprites that are mirror copies of one another can be detected
    /// before code starts treating them as independent variants.
    let mirroredContentFingerprint: Int
}

/// Supplies measurements for an image id. Injected so the contract's rules can
/// be tested against fixtures without shipping art into the test bundle.
protocol AtlasImageMeasuring {
    func measure(imageID: String) -> AtlasImageMeasurement?
}

// MARK: - Declarations

/// One atlas sheet the game references.
///
/// `cellSize` is the only *declared* input; the grid (columns, rows, cell
/// count) is always computed from the measured pixel size, so a sheet that
/// does not divide evenly into whole cells is a contract violation rather
/// than a silent rounding error.
struct AtlasSheetDeclaration: Equatable {
    /// Imageset name in `Assets.xcassets`.
    let imageID: String

    /// Cell size in pixels for this family.
    let cellSize: CGSize

    /// The single owning index list for this family (`docs/bootstrap.md` §2:
    /// "one owning index list per family"). Every index here must exist in the
    /// measured grid.
    let ownedCellIndices: [Int]
}

/// A sheet declaration combined with what its image actually measures.
struct MeasuredAtlasSheet: Equatable {
    let declaration: AtlasSheetDeclaration
    let measurement: AtlasImageMeasurement

    var columns: Int {
        guard declaration.cellSize.width > 0 else { return 0 }
        return Int(measurement.pixelSize.width / declaration.cellSize.width)
    }

    var rows: Int {
        guard declaration.cellSize.height > 0 else { return 0 }
        return Int(measurement.pixelSize.height / declaration.cellSize.height)
    }

    var cellCount: Int { columns * rows }
}

// MARK: - Violations

/// Every way the shipped asset catalog can fail the contract. The v1 rebuild
/// exists because an empty catalog shipped with a green suite; each case here
/// is a condition that must turn a test red.
enum AtlasContractViolation: Equatable, CustomStringConvertible {
    /// Fewer (or more) sheet families declared than the spec requires.
    case sheetManifestIncomplete(declared: Int, required: Int)
    /// A referenced image id does not resolve in `Assets.xcassets`.
    case missingImage(id: String)
    /// Measured pixel size is not a whole multiple of the declared cell size.
    case sheetNotCellAligned(id: String, pixelSize: CGSize, cellSize: CGSize)
    /// An owned cell index falls outside the measured grid.
    case cellIndexOutOfRange(id: String, index: Int, cellCount: Int)
    /// Image decoded without an alpha channel.
    case missingAlphaChannel(id: String)
    /// Two building imagesets are pixel-identical.
    case duplicateBuildingArt(ids: [String])
    /// One building imageset is a horizontal mirror of another.
    case mirroredBuildingArt(ids: [String])

    /// The image ids this violation is about (empty for manifest-level
    /// violations, which are about the declaration list rather than any one
    /// image).
    ///
    /// Lets the acceptance gate be split by subject — "the art that is in the
    /// repository today" versus "the art a named follow-up still owes" —
    /// instead of muting the whole catalog behind one expectation.
    var imageIDs: [String] {
        switch self {
        case .sheetManifestIncomplete:
            return []
        case let .missingImage(id), let .missingAlphaChannel(id):
            return [id]
        case let .sheetNotCellAligned(id, _, _):
            return [id]
        case let .cellIndexOutOfRange(id, _, _):
            return [id]
        case let .duplicateBuildingArt(ids), let .mirroredBuildingArt(ids):
            return ids
        }
    }

    /// `true` when this violation is about any of the given image ids.
    func concerns(anyOf ids: Set<String>) -> Bool {
        imageIDs.contains { ids.contains($0) }
    }

    var description: String {
        switch self {
        case let .sheetManifestIncomplete(declared, required):
            return "Atlas sheet manifest declares \(declared) of \(required) required sheet families."
        case let .missingImage(id):
            return "Referenced image id '\(id)' is missing from Assets.xcassets."
        case let .sheetNotCellAligned(id, pixelSize, cellSize):
            return "Sheet '\(id)' measures \(Int(pixelSize.width))×\(Int(pixelSize.height))px, "
                + "which is not a whole multiple of its \(Int(cellSize.width))×\(Int(cellSize.height))px cell."
        case let .cellIndexOutOfRange(id, index, cellCount):
            return "Sheet '\(id)' owns cell index \(index) but measures only \(cellCount) cells."
        case let .missingAlphaChannel(id):
            return "Image '\(id)' decoded without an alpha channel; the pack is specified as PNG-32."
        case let .duplicateBuildingArt(ids):
            return "Building imagesets \(ids.joined(separator: ", ")) are pixel-identical, "
                + "so they are not independent variants."
        case let .mirroredBuildingArt(ids):
            return "Building imagesets \(ids.joined(separator: ", ")) are horizontal mirrors of each other, "
                + "so they are not independent variants."
        }
    }
}

// MARK: - Contract

/// The pinned contract between the Pixel Grit art pack and the code that draws
/// it: which image ids must exist, how each sheet is celled, and which cell
/// indices each family owns.
struct AtlasContract: Equatable {
    /// Number of atlas sheet families the pack ships (`docs/bootstrap.md` §2).
    /// `tileset_structure.png` and the HTML companion files are not imported
    /// and are deliberately absent from this count.
    let requiredSheetCount: Int

    /// Sheet families whose cell grid is declared. A declaration may only be
    /// added once its cell size has been checked against the measured sheet —
    /// cell sizes are never copied out of filenames.
    let sheets: [AtlasSheetDeclaration]

    /// Atlas sheets that are imported into `Assets.xcassets` but whose cell
    /// grid is not declared in `sheets` yet.
    ///
    /// These ids are still *referenced*, so every rule that does not need a
    /// cell size — the image resolves at all, and it carries a real alpha
    /// channel — is enforced against them today. Without this list an imported
    /// sheet would be invisible to the contract until someone got around to
    /// measuring its cells, which is exactly the "assets present, contract
    /// silent" gap the rebuild exists to close.
    let undeclaredSheetImageIDs: [String]

    /// The 12 whole pre-rendered building sprites. These ids are fixed by the
    /// story (`building_00` … `building_11`).
    let buildingImageIDs: [String]

    init(
        requiredSheetCount: Int,
        sheets: [AtlasSheetDeclaration],
        undeclaredSheetImageIDs: [String] = [],
        buildingImageIDs: [String]
    ) {
        self.requiredSheetCount = requiredSheetCount
        self.sheets = sheets
        self.undeclaredSheetImageIDs = undeclaredSheetImageIDs
        self.buildingImageIDs = buildingImageIDs
    }

    /// Every atlas-sheet id the contract references: the declared families
    /// first, then the imported-but-not-yet-celled ones. Declared ids win, so
    /// an id that appears in both lists is referenced once.
    var atlasSheetImageIDs: [String] {
        let declared = sheets.map(\.imageID)
        return declared + undeclaredSheetImageIDs.filter { !declared.contains($0) }
    }

    /// Every image id the game references. This is the list the acceptance
    /// test walks; if any entry fails to resolve, the suite must go red.
    var referencedImageIDs: [String] {
        atlasSheetImageIDs + buildingImageIDs
    }

    static let buildingCount = 12

    static let requiredBuildingImageIDs: [String] = (0..<AtlasContract.buildingCount)
        .map { String(format: "building_%02d", $0) }

    /// The 10 atlas-sheet imagesets this repository has imported, one per
    /// family, under `Assets.xcassets/Atlas/`.
    ///
    /// This is the single manifest of those ids — tests read it rather than
    /// re-listing the names, so a renamed or dropped imageset cannot leave a
    /// stale copy of the list agreeing with itself somewhere else.
    /// `tileset_structure.png` and the HTML companion files are deliberately
    /// not imported and deliberately absent here.
    static let importedSheetImageIDs: [String] = [
        "sprite_player_walk",
        "sprite_player_weapons",
        "sprite_bullets",
        "sprite_raccoon_walk",
        "sprite_raccoon_attack",
        "tileset_ground",
        "sprite_pickups",
        "sprite_pulse",
        "sprite_hit_puff",
        "sprite_signs",
    ]

    /// The contract as it stands in the repository today.
    ///
    /// The 10 atlas sheets are in the repository, so their ids are referenced
    /// here via `undeclaredSheetImageIDs`: rename or drop one of those
    /// imagesets and `validate(using:)` reports `.missingImage`, and ship one
    /// without an alpha channel and it reports `.missingAlphaChannel`. Both
    /// are measured facts read out of the shipped bytes by
    /// `AssetCatalogImageMeasurer`, and both are asserted unmuted by
    /// `AtlasContractTests`.
    ///
    /// `sheets` stays empty because a declaration additionally needs a *cell
    /// size*, and a cell size may only be written down once it has been
    /// checked against the measured sheet — guessing 32×32 from a sprite
    /// sheet's name is precisely the "filenames as evidence" mistake the spec
    /// forbids, and it would then be rubber-stamped by the cell-alignment rule
    /// it is supposed to be tested by. The gap is not silent:
    /// `validate(using:)` reports `.sheetManifestIncomplete(declared: 0,
    /// required: 10)` until every family is celled.
    static let current = AtlasContract(
        requiredSheetCount: 10,
        sheets: [],
        undeclaredSheetImageIDs: AtlasContract.importedSheetImageIDs,
        buildingImageIDs: AtlasContract.requiredBuildingImageIDs
    )

    /// Measures every declared sheet, for consumers (the central texture
    /// loader) that need the grid rather than the violations.
    func measuredSheets(using measurer: AtlasImageMeasuring) -> [MeasuredAtlasSheet] {
        sheets.compactMap { declaration -> MeasuredAtlasSheet? in
            guard let measurement = measurer.measure(imageID: declaration.imageID) else { return nil }
            return MeasuredAtlasSheet(declaration: declaration, measurement: measurement)
        }
    }

    /// Checks the contract against what is actually in the asset catalog.
    /// Returns every violation found (not just the first) so a single red run
    /// tells you the whole story.
    func validate(using measurer: AtlasImageMeasuring) -> [AtlasContractViolation] {
        var violations: [AtlasContractViolation] = []

        if sheets.count != requiredSheetCount {
            violations.append(
                .sheetManifestIncomplete(declared: sheets.count, required: requiredSheetCount)
            )
        }

        for declaration in sheets {
            guard let measurement = measurer.measure(imageID: declaration.imageID) else {
                violations.append(.missingImage(id: declaration.imageID))
                continue
            }

            if !measurement.hasAlphaChannel {
                violations.append(.missingAlphaChannel(id: declaration.imageID))
            }

            let cellSize = declaration.cellSize
            let pixelSize = measurement.pixelSize
            let dividesEvenly = cellSize.width > 0 && cellSize.height > 0
                && pixelSize.width.truncatingRemainder(dividingBy: cellSize.width) == 0
                && pixelSize.height.truncatingRemainder(dividingBy: cellSize.height) == 0

            guard dividesEvenly else {
                violations.append(
                    .sheetNotCellAligned(
                        id: declaration.imageID,
                        pixelSize: pixelSize,
                        cellSize: cellSize
                    )
                )
                continue
            }

            let measured = MeasuredAtlasSheet(declaration: declaration, measurement: measurement)
            for index in declaration.ownedCellIndices where index < 0 || index >= measured.cellCount {
                violations.append(
                    .cellIndexOutOfRange(
                        id: declaration.imageID,
                        index: index,
                        cellCount: measured.cellCount
                    )
                )
            }
        }

        // Imported sheets without a declared cell grid still have to resolve
        // and still have to carry alpha; only the cell-grid rules are held
        // back until a measured cell size exists for them.
        let declaredSheetIDs = Set(sheets.map(\.imageID))
        for imageID in undeclaredSheetImageIDs where !declaredSheetIDs.contains(imageID) {
            guard let measurement = measurer.measure(imageID: imageID) else {
                violations.append(.missingImage(id: imageID))
                continue
            }
            if !measurement.hasAlphaChannel {
                violations.append(.missingAlphaChannel(id: imageID))
            }
        }

        var buildings: [MeasuredBuilding] = []
        for imageID in buildingImageIDs {
            guard let measurement = measurer.measure(imageID: imageID) else {
                violations.append(.missingImage(id: imageID))
                continue
            }
            if !measurement.hasAlphaChannel {
                violations.append(.missingAlphaChannel(id: imageID))
            }
            buildings.append(MeasuredBuilding(id: imageID, measurement: measurement))
        }

        violations.append(contentsOf: Self.distinctnessViolations(among: buildings))
        return violations
    }

    /// A building imageset paired with what its pixels actually measure.
    private struct MeasuredBuilding {
        let id: String
        let measurement: AtlasImageMeasurement
    }

    /// The 12 buildings must be 12 genuinely different pictures — identical or
    /// mirrored copies would make the world generator's "independent variant"
    /// assumption false.
    private static func distinctnessViolations(
        among buildings: [MeasuredBuilding]
    ) -> [AtlasContractViolation] {
        var violations: [AtlasContractViolation] = []

        let byContent = Dictionary(grouping: buildings, by: { $0.measurement.contentFingerprint })
        var duplicateIDs: Set<String> = []
        for group in byContent.values where group.count > 1 {
            let ids = group.map(\.id).sorted()
            duplicateIDs.formUnion(ids)
            violations.append(.duplicateBuildingArt(ids: ids))
        }

        for outer in buildings.indices {
            for inner in buildings.index(after: outer)..<buildings.endIndex {
                let first = buildings[outer]
                let second = buildings[inner]
                guard !duplicateIDs.contains(first.id) || !duplicateIDs.contains(second.id) else {
                    continue
                }
                if first.measurement.contentFingerprint == second.measurement.mirroredContentFingerprint {
                    violations.append(.mirroredBuildingArt(ids: [first.id, second.id].sorted()))
                }
            }
        }

        return violations.sorted { String(describing: $0) < String(describing: $1) }
    }
}

// MARK: - Asset catalog measurement

/// Measures images by loading them out of `Assets.xcassets` and rasterising
/// them, so the contract is checked against the bytes that actually ship.
struct AssetCatalogImageMeasurer: AtlasImageMeasuring {
    private let bundle: Bundle

    init(bundle: Bundle = .appModule) {
        self.bundle = bundle
    }

    func measure(imageID: String) -> AtlasImageMeasurement? {
        guard let image = UIImage(named: imageID, in: bundle, compatibleWith: nil),
              let cgImage = image.cgImage,
              let content = Self.rasterisedBytes(of: cgImage, mirrored: false),
              let mirrored = Self.rasterisedBytes(of: cgImage, mirrored: true)
        else {
            return nil
        }

        return AtlasImageMeasurement(
            pixelSize: CGSize(width: cgImage.width, height: cgImage.height),
            hasAlphaChannel: Self.hasAlphaChannel(cgImage),
            contentFingerprint: Self.fingerprint(of: content),
            mirroredContentFingerprint: Self.fingerprint(of: mirrored)
        )
    }

    private static func hasAlphaChannel(_ cgImage: CGImage) -> Bool {
        switch cgImage.alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast:
            return true
        case .none, .noneSkipFirst, .noneSkipLast, .alphaOnly:
            return false
        @unknown default:
            return false
        }
    }

    /// Draws the image into a known RGBA8 buffer (nearest-neighbour, no
    /// interpolation, matching the 1×/integer-scale rule) and copies the bytes
    /// out, optionally flipping horizontally first.
    private static func rasterisedBytes(of cgImage: CGImage, mirrored: Bool) -> Data? {
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        let bytesPerRow = width * 4
        let byteCount = bytesPerRow * height
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 8)
        defer { buffer.deallocate() }
        _ = buffer.initializeMemory(as: UInt8.self, repeating: 0, count: byteCount)

        guard let context = CGContext(
            data: buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .none
        if mirrored {
            context.translateBy(x: CGFloat(width), y: 0)
            context.scaleBy(x: -1, y: 1)
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))

        return Data(bytes: buffer, count: byteCount)
    }

    private static func fingerprint(of data: Data) -> Int {
        var hasher = Hasher()
        hasher.combine(data)
        return hasher.finalize()
    }
}

extension Bundle {
    private final class BundleToken {}

    /// The bundle holding the app module's asset catalog — correct both when
    /// the app runs and when the unit-test bundle is hosted inside it.
    static var appModule: Bundle { Bundle(for: BundleToken.self) }
}
