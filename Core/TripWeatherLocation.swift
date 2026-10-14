import Foundation

/// Selects a dense city-sized neighborhood without linking a long chain of nearby stops.
enum TripWeatherLocation {
    struct Point {
        let id: String
        let coordinate: Coordinate
    }

    static func representative(_ input: [Point], radiusMeters: Double = 30_000) -> Coordinate? {
        guard radiusMeters.isFinite, radiusMeters > 0 else { return nil }
        var seen = Set<String>()
        let points = input.filter { $0.coordinate.isValid }.sorted { $0.id < $1.id }
            .filter { seen.insert($0.id).inserted }
        guard !points.isEmpty else { return nil }
        var best: [Point] = []
        var bestSpread = Double.infinity
        for center in points {
            let group = points.filter { distance(center.coordinate, $0.coordinate) <= radiusMeters }
            let mean = average(group)
            let spread = group.reduce(0.0) { $0 + distance($1.coordinate, mean) } / Double(group.count)
            // Sorted candidates make exact ties deterministic, independent of route order.
            if group.count > best.count || (group.count == best.count && spread < bestSpread - 0.01) {
                best = group
                bestSpread = spread
            }
        }
        return average(best)
    }

    private static func average(_ points: [Point]) -> Coordinate {
        // Preserve exact coordinates/cache identity when the winning group has one stop.
        if points.count == 1 { return points[0].coordinate }
        var x = 0.0, y = 0.0, z = 0.0
        for point in points {
            let lat = point.coordinate.latitude * .pi / 180
            let lon = point.coordinate.longitude * .pi / 180
            x += cos(lat) * cos(lon)
            y += cos(lat) * sin(lon)
            z += sin(lat)
        }
        return Coordinate(latitude: atan2(z, hypot(x, y)) * 180 / .pi,
                          longitude: atan2(y, x) * 180 / .pi)
    }

    private static func distance(_ a: Coordinate, _ b: Coordinate) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLat = lat2 - lat1, dLon = (b.longitude - a.longitude) * .pi / 180
        let h = pow(sin(dLat / 2), 2) + cos(lat1) * cos(lat2) * pow(sin(dLon / 2), 2)
        return 6_371_000 * 2 * asin(sqrt(min(1, max(0, h))))
    }
}
