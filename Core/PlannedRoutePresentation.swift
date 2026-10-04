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
            // Only remove a short local excursion returning within 12m. Bound both
            // traveled length and spatial extent, so large detours/bridges survive.
            if kept.count > 2 {
                let total = (cumulative.last ?? 0) + Coordinates.distance(kept.last!, point)
                var candidate: Int?
                for previous in stride(from: kept.count - 2, through: 0, by: -1) {
                    let traveled = total - cumulative[previous]
                    if traveled > 240 { break }
                    let gap = Coordinates.distance(kept[previous], point)
                    guard gap <= 12, traveled >= max(35, gap * 4) else { continue }
                    if kept[previous...].allSatisfy({ Coordinates.distance($0, point) <= 65 }) { candidate = previous }
                }
                if let candidate {
                    kept.removeSubrange((candidate + 1)..<kept.count)
                    cumulative.removeSubrange((candidate + 1)..<cumulative.count)
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
