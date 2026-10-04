import Foundation
import CoreGraphics

/// Cut a geographic polyline into solid strokes. Phase starts at the route origin,
/// so panning/rotation never shifts the gaps. Clip before enumerating dash intervals.
enum RouteDashGeometry {
    static func segments(_ points: [CGPoint], unitsPerPoint: Double, clip: CGRect) -> [[CGPoint]] {
        guard unitsPerPoint.isFinite, unitsPerPoint > 0, points.count > 1 else { return [] }
        let dash = 8 * unitsPerPoint, period = 14 * unitsPerPoint
        var result: [[CGPoint]] = [], traveled = 0.0
        var previousIndex: Double?
        for (a,b) in zip(points, points.dropFirst()) {
            let dx = b.x-a.x, dy = b.y-a.y, length = hypot(dx,dy)
            guard length.isFinite, length > 0 else { continue }
            defer { traveled += length }
            var lo = 0.0, hi = 1.0
            for (p,q) in [(-dx,a.x-clip.minX),(dx,clip.maxX-a.x),(-dy,a.y-clip.minY),(dy,clip.maxY-a.y)] {
                if abs(p) < 1e-12 { if q < 0 { hi = -1 }; continue }
                if p < 0 { lo = max(lo,q/p) } else { hi = min(hi,q/p) }
            }
            guard hi >= lo else { continue }
            let start = traveled + lo*length, end = traveled + hi*length
            var index = floor(start/period)
            while index*period <= end {
                let from = max(start,index*period), to = min(end,index*period+dash)
                if to > from {
                    let p = CGPoint(x:a.x+dx*(from-traveled)/length,y:a.y+dy*(from-traveled)/length)
                    let q = CGPoint(x:a.x+dx*(to-traveled)/length,y:a.y+dy*(to-traveled)/length)
                    if previousIndex == index, let last = result.last?.last, hypot(last.x-p.x,last.y-p.y) < 0.001 {
                        result[result.count-1].append(q)
                    } else { result.append([p,q]) }
                    previousIndex = index
                }
                index += 1
            }
        }
        return result
    }
}
