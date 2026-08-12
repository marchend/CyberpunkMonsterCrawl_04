import CoreGraphics
import SpriteKit

/// One layer container plus the `LayerConstants` band its whole subtree must
/// stay inside. `baseZ` is the container's own *cumulative* zPosition (for
/// `uiLayer`, that includes the camera it hangs off), because SpriteKit
/// accumulates `zPosition` down the tree.
private struct LayerBand {
    let name: String
    let root: SKNode
    let baseZ: CGFloat
    let minZ: CGFloat
    let maxZ: CGFloat

    func contains(_ cumulativeZ: CGFloat) -> Bool {
        cumulativeZ >= minZ && cumulativeZ <= maxZ
    }
}

/// Runtime audits for the two structural invariants this feature exists to
/// protect, so that "the UI always wins" is checked for *every* node in the
/// graph rather than only for the three container nodes.
///
/// Both audits are plain functions so tests can drive them with hostile
/// input (a UI child with a large negative `zPosition`, a world child with a
/// large positive one, a node that opts into UIKit touch delivery), and both
/// are wired into `assertSceneInvariants()`, which `GameScene` trips in
/// DEBUG when a screen is mounted, when the scene is presented and on every
/// dispatched touch. A future screen that violates either contract fails
/// loudly at the moment it is added instead of silently reproducing the v1
/// "world paints over UI" / "dead button" bugs with a green suite.
extension GameScene {

    private var auditedBands: [LayerBand] {
        [
            LayerBand(
                name: "worldLayer",
                root: worldLayer,
                baseZ: worldLayer.zPosition,
                minZ: LayerConstants.worldMinZ,
                maxZ: LayerConstants.worldMaxZ
            ),
            LayerBand(
                name: "effectsLayer",
                root: effectsLayer,
                baseZ: effectsLayer.zPosition,
                minZ: LayerConstants.effectsMinZ,
                maxZ: LayerConstants.effectsMaxZ
            ),
            LayerBand(
                name: "uiLayer",
                root: uiLayer,
                baseZ: cameraNode.zPosition + uiLayer.zPosition,
                minZ: LayerConstants.uiMinZ,
                maxZ: LayerConstants.uiMaxZ
            ),
        ]
    }

    // MARK: - Layer-band audit

    /// Every node in the three layer subtrees whose *cumulative* zPosition
    /// escapes its layer's declared band - i.e. every node that could paint
    /// outside the ordering `worldLayer < effectsLayer < uiLayer` promises.
    /// Empty means the invariant holds for the whole graph.
    func nodesEscapingTheirLayerBand() -> [SKNode] {
        var offenders: [SKNode] = []
        for band in auditedBands {
            if !band.contains(band.baseZ) {
                offenders.append(band.root)
            }
            collectBandEscapees(in: band, under: band.root, cumulativeZ: band.baseZ, into: &offenders)
        }
        return offenders
    }

    private func collectBandEscapees(
        in band: LayerBand,
        under node: SKNode,
        cumulativeZ: CGFloat,
        into offenders: inout [SKNode]
    ) {
        for child in node.children {
            let childZ = cumulativeZ + child.zPosition
            if !band.contains(childZ) {
                offenders.append(child)
            }
            collectBandEscapees(in: band, under: child, cumulativeZ: childZ, into: &offenders)
        }
    }

    /// Human-readable form of `nodesEscapingTheirLayerBand()`, used in
    /// assertion messages and test failure output.
    func layerBandViolationReport() -> [String] {
        var report: [String] = []
        for band in auditedBands {
            if !band.contains(band.baseZ) {
                report.append("\(band.name) itself at cumulative z \(band.baseZ), band \(band.minZ)...\(band.maxZ)")
            }
            collectBandViolationDescriptions(in: band, under: band.root, cumulativeZ: band.baseZ, into: &report)
        }
        return report
    }

    private func collectBandViolationDescriptions(
        in band: LayerBand,
        under node: SKNode,
        cumulativeZ: CGFloat,
        into report: inout [String]
    ) {
        for child in node.children {
            let childZ = cumulativeZ + child.zPosition
            if !band.contains(childZ) {
                report.append(
                    "\(describe(child)) under \(band.name) at cumulative z \(childZ), "
                        + "band \(band.minZ)...\(band.maxZ)"
                )
            }
            collectBandViolationDescriptions(in: band, under: child, cumulativeZ: childZ, into: &report)
        }
    }

    // MARK: - Sole-dispatcher audit

    /// Every node that has opted into UIKit touch delivery
    /// (`isUserInteractionEnabled == true`). UIKit hands such a node the
    /// touch *before* `SKScene.touchesBegan(_:with:)` runs, so it bypasses
    /// `routeTouch(at:)` and the UI-first guarantee with it. The contract is
    /// that this list is always empty and the scene dispatches every touch
    /// itself to a `TouchResponder` - see `TouchResponder`.
    func nodesBypassingSceneTouchDispatch() -> [SKNode] {
        var offenders: [SKNode] = []
        for root in [worldLayer, effectsLayer, uiLayer] {
            if root.isUserInteractionEnabled {
                offenders.append(root)
            }
            collectInteractionEnabledNodes(under: root, into: &offenders)
        }
        return offenders
    }

    private func collectInteractionEnabledNodes(under node: SKNode, into offenders: inout [SKNode]) {
        for child in node.children {
            if child.isUserInteractionEnabled {
                offenders.append(child)
            }
            collectInteractionEnabledNodes(under: child, into: &offenders)
        }
    }

    private func describe(_ node: SKNode) -> String {
        node.name.map { "\($0) (\(type(of: node)))" } ?? "\(type(of: node))"
    }

    // MARK: - DEBUG enforcement

    #if DEBUG
    /// Trips in DEBUG the moment either invariant is violated: a node whose
    /// cumulative zPosition escapes its layer band, or a node that steals
    /// touch delivery from the scene.
    func assertSceneInvariants(file: StaticString = #file, line: UInt = #line) {
        assert(
            nodesEscapingTheirLayerBand().isEmpty,
            "Node(s) escaped their layer's zPosition band: "
                + layerBandViolationReport().joined(separator: "; "),
            file: file,
            line: line
        )
        assert(
            nodesBypassingSceneTouchDispatch().isEmpty,
            "Node(s) set isUserInteractionEnabled and would bypass GameScene's UI-first touch "
                + "dispatch: "
                + nodesBypassingSceneTouchDispatch().map { describe($0) }.joined(separator: "; "),
            file: file,
            line: line
        )
    }
    #endif
}
