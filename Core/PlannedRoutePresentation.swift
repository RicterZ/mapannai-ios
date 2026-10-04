import Foundation

/// Display-only cleanup for one planned leg. Never crosses a saved place boundary.
/// Raw server paths and distances remain in RouteCache.
enum PlannedRoutePresentation {
    static func points(_ input: [Coordinate]) throws -> [Coordinate] {
        guard input.count > 2, let origin = input.first, let destination = input.last else { return input }
        let latitudeScale = 111_195.0
        let longitudeScale = latitudeScale * max(0.01, cos(origin.latitude * .pi / 180))
        func xy(_ point: Coordinate) -> (Double, Double) {
            ((point.longitude - origin.longitude) * longitudeScale, (point.latitude - origin.latitude) * latitudeScale)
        }
        var kept: [Coordinate] = []
        var cumulative: [Double] = []
        for (index, point) in input.enumerated() where point.isValid {
            if index.isMultiple(of: 128) { try Task.checkCancellation() }
            if let last = kept.last, Coordinates.distance(last, point) < 1, index != input.count - 1 { continue }
            // Compare against segments, not sampling vertices: a return can land
            // halfway along a long road segment. Bounds apply only to the excursion.
            if kept.count > 1 {
                let total = (cumulative.last ?? 0) + Coordinates.distance(kept.last!, point)
                let p = xy(point)
                var candidate: (index: Int, join: Coordinate)?
                for previous in stride(from: kept.count - 2, through: 0, by: -1) {
                    if total - cumulative[previous + 1] > 600 { break }
                    let a = xy(kept[previous]), b = xy(kept[previous + 1])
                    let dx = b.0 - a.0, dy = b.1 - a.1
                    let length = dx * dx + dy * dy
                    guard length > 0 else { continue }
                    let t = min(1, max(0, ((p.0-a.0)*dx + (p.1-a.1)*dy)/length))
                    let gap = hypot(p.0-a.0-t*dx, p.1-a.1-t*dy)
                    let traveled = total - cumulative[previous] - t * (cumulative[previous + 1] - cumulative[previous])
                    guard gap <= 20, traveled <= 600, traveled >= max(35, gap * 4) else { continue }
                    guard kept[(previous + 1)...].allSatisfy({ Coordinates.distance($0, point) <= 160 }) else { continue }
                    let join = Coordinate(latitude: kept[previous].latitude + t * (kept[previous + 1].latitude - kept[previous].latitude),
                                          longitude: kept[previous].longitude + t * (kept[previous + 1].longitude - kept[previous].longitude))
                    candidate = (previous, join)
                }
                if let candidate {
                    kept.removeSubrange((candidate.index + 1)..<kept.count)
                    cumulative.removeSubrange((candidate.index + 1)..<cumulative.count)
                    if Coordinates.distance(kept.last!, candidate.join) > 1 {
                        cumulative.append(cumulative.last! + Coordinates.distance(kept.last!, candidate.join))
                        kept.append(candidate.join)
                    }
                }
            }
            cumulative.append((cumulative.last ?? 0) + (kept.last.map { Coordinates.distance($0, point) } ?? 0))
            kept.append(point)
        }
        guard kept.count > 2 else { return [origin, destination] }
        // Iterative Ramer–Douglas–Peucker: 5m maximum deviation from cleaned geometry.
        let projected = kept.map(xy)
        var selected: Set<Int> = [0, kept.count - 1]
        var work = [(0, kept.count - 1)]
        while let (start, end) = work.popLast() {
            try Task.checkCancellation()
            guard end > start + 1 else { continue }
            let a = projected[start], b = projected[end]
            let dx = b.0 - a.0, dy = b.1 - a.1, length = dx * dx + dy * dy
            var maximum = 25.0, furthest: Int?
            for index in (start + 1)..<end {
                let p = projected[index]
                let t = length > 0 ? min(1, max(0, ((p.0-a.0)*dx + (p.1-a.1)*dy)/length)) : 0
                let distance = pow(p.0-a.0-t*dx, 2) + pow(p.1-a.1-t*dy, 2)
                if distance > maximum { maximum = distance; furthest = index }
            }
            if let furthest { selected.insert(furthest); work.append((start, furthest)); work.append((furthest, end)) }
        }
        var result = selected.sorted().map { kept[$0] }
        result[0] = origin; result[result.count - 1] = destination
        return result
    }
}
