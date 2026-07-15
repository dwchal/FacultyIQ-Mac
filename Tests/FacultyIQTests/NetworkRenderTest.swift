import SwiftUI
import XCTest
@testable import FacultyIQ

/// Renders a synthetic coauthorship graph to a PNG for visual inspection.
/// Opt-in: RENDER_OUT=/path/to/out.png swift test --filter NetworkRenderTest
final class NetworkRenderTest: XCTestCase {
    @MainActor
    func testRenderNetworkGraph() throws {
        guard let out = ProcessInfo.processInfo.environment["RENDER_OUT"] else {
            throw XCTSkip("Set RENDER_OUT=<path.png> to render")
        }
        let names = ["Sarah Chen", "James Okafor", "Maria Santos", "David Kim",
                     "Emily Watson", "Ahmed Hassan", "Lisa Park", "Tom Alvarez"]
        let ids = names.map { _ in UUID() }
        let edgeSpecs = [(0, 1, 12), (0, 2, 5), (1, 2, 3), (0, 3, 2),
                         (4, 5, 8), (4, 6, 1), (5, 6, 2), (2, 4, 1)]
        let edges = edgeSpecs.map { i, j, w in
            let (a, b) = ids[i].uuidString < ids[j].uuidString ? (ids[i], ids[j]) : (ids[j], ids[i])
            return CoauthorEdge(memberA: a, memberB: b, weight: w)
        }
        var degree: [UUID: Int] = [:]
        for edge in edges {
            degree[edge.memberA, default: 0] += 1
            degree[edge.memberB, default: 0] += 1
        }
        let nodes = zip(ids, names).enumerated().map { i, pair in
            CoauthorNode(memberID: pair.0, name: pair.1,
                         worksCount: 20 + i * 25,
                         degree: degree[pair.0] ?? 0, sharedWorks: 0)
        }
        let connected = nodes.filter { $0.degree > 0 }.map(\.memberID)
        let isolated = nodes.filter { $0.degree == 0 }.map(\.memberID)
        let positions = NetworkLayout.layout(nodeIDs: connected, edges: edges)
            .merging(NetworkLayout.ring(nodeIDs: isolated)) { a, _ in a }

        let graph = NetworkGraphView(
            nodes: nodes,
            edges: edges,
            positions: positions,
            maxWorks: nodes.map(\.worksCount).max() ?? 1,
            selectedID: .constant(ids[0]),
            hoveredID: .constant(nil))
            .frame(width: 640, height: 480)
            .background(Color(nsColor: .windowBackgroundColor))

        let renderer = ImageRenderer(content: graph)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: out))
    }
}
