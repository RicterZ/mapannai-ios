import Foundation
import CoreGraphics

/// Screen-space geometry makes direction cues independent of geographic distance.
struct RouteDirectionPath {
    struct Arrow { let position: CGPoint; let angle: CGFloat; let opacity: Float }
    static let spacing = 100.0
    let points: [CGPoint]
    private let cumulative: [Double]
    let length: Double
    private let indices: [Int]
    init(points: [CGPoint], bounds: CGRect = CGRect(x: -100000, y: -100000, width: 200000, height: 200000)) {
        var kept: [CGPoint] = [], distances: [Double] = [], total = 0.0
        for point in points where point.x.isFinite && point.y.isFinite {
            if let last = kept.last {
                let distance = hypot(point.x - last.x, point.y - last.y)
                guard distance > 0.01 else { continue }
                total += distance
            }
            kept.append(point); distances.append(total)
        }
        self.points = kept; cumulative = distances; length = total
        let count = max(0, Int(min(ceil((total - 50) / Self.spacing), Double(Int.max / 2))))
        let step = Self.spacing
        var visible = Set<Int>()
        if step > 0 {
            let rect = bounds.insetBy(dx: -24, dy: -24)
            for index in 1..<kept.count {
                let a = kept[index - 1], b = kept[index]
                var lower = 0.0, upper = 1.0
                let dx = Double(b.x - a.x), dy = Double(b.y - a.y)
                let clips = [(-dx, Double(a.x - rect.minX)), (dx, Double(rect.maxX - a.x)),
                             (-dy, Double(a.y - rect.minY)), (dy, Double(rect.maxY - a.y))]
                var intersects = true
                for (p, q) in clips {
                    if abs(p) < 0.000001 { if q < 0 { intersects = false; break }; continue }
                    let ratio = q / p
                    if p < 0 { lower = max(lower, ratio) } else { upper = min(upper, ratio) }
                    if lower > upper { intersects = false; break }
                }
                guard intersects else { continue }
                let segment = distances[index] - distances[index - 1]
                let first = max(0, Int(ceil((distances[index - 1] + lower * segment - 12) / step - 0.5)))
                let last = min(count - 1, Int(floor((distances[index - 1] + upper * segment + 12) / step - 0.5)))
                if first <= last { for arrow in first...last { visible.insert(arrow) } }
            }
        }
        indices = visible.sorted()
    }
    func arrows(timestamp: Double, reducedMotion: Bool, bounds: CGRect) -> [Arrow] {
        guard points.count > 1, length >= 28 else { return [] }
        var result: [Arrow] = []
        for index in indices {
            let distance = 50 + Double(index) * Self.spacing
            guard distance >= 12, distance <= length - 12 else { continue }
            var low = 1, high = points.count - 1
            while low < high {
                let middle = (low + high) / 2
                if cumulative[middle] < distance { low = middle + 1 } else { high = middle }
            }
            let a = points[low - 1], b = points[low]
            let fraction = (distance - cumulative[low - 1]) / (cumulative[low] - cumulative[low - 1])
            let point = CGPoint(x: a.x + (b.x - a.x) * fraction, y: a.y + (b.y - a.y) * fraction)
            guard bounds.insetBy(dx: -12, dy: -12).contains(point) else { continue }
            result.append(Arrow(position: point, angle: atan2(b.y - a.y, b.x - a.x), opacity: 1))
        }
        return result
    }
}
