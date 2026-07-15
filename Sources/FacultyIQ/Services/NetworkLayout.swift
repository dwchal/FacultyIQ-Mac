import Foundation

/// Deterministic Fruchterman–Reingold force layout in the unit square.
/// No randomness: circular initial placement in input order, a fixed iteration
/// count, and linear cooling mean identical input always yields identical output.
enum NetworkLayout {
    struct Point: Hashable {
        var x: Double
        var y: Double
    }

    /// Positions for connected nodes. `nodeIDs` order determines initial
    /// placement, so pass a stably sorted list.
    static func layout(nodeIDs: [UUID],
                       edges: [CoauthorEdge],
                       iterations: Int = 200) -> [UUID: Point] {
        let n = nodeIDs.count
        guard n > 0 else { return [:] }
        guard n > 1 else { return [nodeIDs[0]: Point(x: 0.5, y: 0.5)] }

        let index = Dictionary(uniqueKeysWithValues: nodeIDs.enumerated().map { ($1, $0) })
        var pos = circle(count: n, radius: 0.4)
        var disp = [Point](repeating: Point(x: 0, y: 0), count: n)
        let k = (1.0 / Double(n)).squareRoot()

        for iteration in 0..<iterations {
            for i in 0..<n { disp[i] = Point(x: 0, y: 0) }

            // Repulsion between every pair.
            for i in 0..<n {
                for j in (i + 1)..<n {
                    var dx = pos[i].x - pos[j].x
                    var dy = pos[i].y - pos[j].y
                    var d = (dx * dx + dy * dy).squareRoot()
                    if d < 1e-9 {
                        // Coincident nodes: nudge apart deterministically by index.
                        dx = 1e-6 * Double(i + 1)
                        dy = 1e-6 * Double(j + 1)
                        d = (dx * dx + dy * dy).squareRoot()
                    }
                    let force = k * k / d
                    disp[i].x += dx / d * force
                    disp[i].y += dy / d * force
                    disp[j].x -= dx / d * force
                    disp[j].y -= dy / d * force
                }
            }

            // Attraction along edges, damped by log so heavy pairs don't collapse.
            for edge in edges {
                guard let i = index[edge.memberA], let j = index[edge.memberB] else { continue }
                let dx = pos[i].x - pos[j].x
                let dy = pos[i].y - pos[j].y
                let d = max((dx * dx + dy * dy).squareRoot(), 1e-9)
                let force = d * d / k * log2(1 + Double(edge.weight))
                disp[i].x -= dx / d * force
                disp[i].y -= dy / d * force
                disp[j].x += dx / d * force
                disp[j].y += dy / d * force
            }

            let temperature = 0.1 * (1 - Double(iteration) / Double(iterations))
            for i in 0..<n {
                let d = max((disp[i].x * disp[i].x + disp[i].y * disp[i].y).squareRoot(), 1e-9)
                let step = min(d, temperature)
                pos[i].x = min(max(pos[i].x + disp[i].x / d * step, 0.05), 0.95)
                pos[i].y = min(max(pos[i].y + disp[i].y / d * step, 0.05), 0.95)
            }
        }

        rescale(&pos, into: 0.08...0.92)
        return Dictionary(uniqueKeysWithValues: nodeIDs.enumerated().map { ($1, pos[$0]) })
    }

    /// Static outer-ring placement for isolated nodes (not force-simulated).
    static func ring(nodeIDs: [UUID], radius: Double = 0.42) -> [UUID: Point] {
        let points = circle(count: nodeIDs.count, radius: radius)
        return Dictionary(uniqueKeysWithValues: zip(nodeIDs, points).map { ($0, $1) })
    }

    private static func circle(count: Int, radius: Double) -> [Point] {
        (0..<count).map { i in
            let angle = 2 * Double.pi * Double(i) / Double(count) - .pi / 2
            return Point(x: 0.5 + radius * cos(angle), y: 0.5 + radius * sin(angle))
        }
    }

    /// Stretch the bounding box to fill the given range (leaves room for labels).
    private static func rescale(_ pos: inout [Point], into range: ClosedRange<Double>) {
        guard let minX = pos.map(\.x).min(), let maxX = pos.map(\.x).max(),
              let minY = pos.map(\.y).min(), let maxY = pos.map(\.y).max() else { return }
        let span = range.upperBound - range.lowerBound
        for i in pos.indices {
            pos[i].x = maxX - minX < 1e-9
                ? 0.5
                : range.lowerBound + (pos[i].x - minX) / (maxX - minX) * span
            pos[i].y = maxY - minY < 1e-9
                ? 0.5
                : range.lowerBound + (pos[i].y - minY) / (maxY - minY) * span
        }
    }
}
