import Foundation

/// Port of Web src/lib/map/route-geometry.ts smoothRoutePath.
/// Display only, per saved-place leg; raw navigation paths/distances stay intact.
/// Opposite-direction layout remains a separate RouteOverlapPresentation pass.
enum PlannedRoutePresentation {
    static func points(_ input: [Coordinate]) throws -> [Coordinate] {
        try Task.checkCancellation()
        let path = input.filter(\.isValid)
        guard path.count >= 3 else { return path }
        let origin = path[0]
        let sy = 111000.0, sx = sy * max(0.01, cos(origin.latitude * .pi / 180))
        func x(_ p: Coordinate) -> Double { (p.longitude - origin.longitude) * sx }
        func y(_ p: Coordinate) -> Double { (p.latitude - origin.latitude) * sy }
        func distance(_ a: Coordinate, _ b: Coordinate) -> Double { hypot(x(a)-x(b), y(a)-y(b)) }
        func error(_ p: Coordinate, _ a: Coordinate, _ b: Coordinate) -> Double {
            let dx = x(b)-x(a), dy = y(b)-y(a), length = dx*dx + dy*dy
            let px = x(p)-x(a), py = y(p)-y(a)
            let t = length > 0 ? max(0, min(1, (px*dx + py*dy)/length)) : 0
            return hypot(px-t*dx, py-t*dy)
        }
        func lerp(_ a: Coordinate, _ b: Coordinate, _ t: Double) -> Coordinate {
            Coordinate(latitude: a.latitude + (b.latitude-a.latitude)*t,
                       longitude: a.longitude + (b.longitude-a.longitude)*t)
        }
        var deduplicated = [origin]
        for i in 1..<(path.count-1) {
            if i.isMultiple(of: 128) { try Task.checkCancellation() }
            if distance(deduplicated.last!, path[i]) >= 0.3 { deduplicated.append(path[i]) }
        }
        deduplicated.append(path.last!)

        // Arrival/departure excursions that revisit the waypoint's entrance.
        func trimEnd(_ values: [Coordinate]) throws -> [Coordinate] {
            let endpoint = values.last!
            var arc = 0.0, extent = 0.0, chosen = values.count-1
            for i in stride(from: values.count-2, through: 0, by: -1) {
                if i.isMultiple(of: 128) { try Task.checkCancellation() }
                arc += distance(values[i], values[i+1])
                extent = max(extent, distance(values[i], endpoint))
                if arc > 500 || extent > 180 { break }
                let chord = distance(values[i], endpoint)
                if chord <= 65 && arc-chord >= 30 && arc >= max(1, chord)*1.6 { chosen = i }
            }
            return chosen < values.count-1 ? Array(values[...chosen]) + [endpoint] : values
        }
        let endTrimmed = try trimEnd(deduplicated)
        let endpointCleaned = Array(try trimEnd(Array(endTrimmed.reversed())).reversed())
        var localPoints = [endpointCleaned[0]], start = 0
        while start < endpointCleaned.count-1 {
            try Task.checkCancellation()
            var chosen = start+1, arc = 0.0, extent = 0.0
            let nearWaypoint = min(distance(endpointCleaned[start], origin), distance(endpointCleaned[start], path.last!)) <= 300
            for end in (start+1)..<endpointCleaned.count {
                if end.isMultiple(of: 128) { try Task.checkCancellation() }
                arc += distance(endpointCleaned[end-1], endpointCleaned[end])
                extent = max(extent, distance(endpointCleaned[start], endpointCleaned[end]))
                if arc > 500 || extent > 180 { break }
                let chord = distance(endpointCleaned[start], endpointCleaned[end])
                let smallLoop = extent <= 60 && arc <= 300 && chord <= 20 && arc-chord >= 50
                if end >= start+3 && (nearWaypoint || smallLoop) && chord <= 50 && arc-chord >= (smallLoop ? 50 : 100) && arc >= max(1, chord)*3.5 { chosen = end }
            }
            localPoints.append(endpointCleaned[chosen]); start = chosen
        }

        // Short bends in a 30m corridor; preserve major turns and detours.
        var cleaned = [localPoints[0]]
        start = 0
        while start < localPoints.count-1 {
            try Task.checkCancellation()
            var chosen = start+1, arc = 0.0
            for end in (start+1)..<min(localPoints.count, start+129) {
                arc += distance(localPoints[end-1], localPoints[end])
                if arc > 300 { break }
                let chord = distance(localPoints[start], localPoints[end])
                if end < start+2 || arc-chord < 8 || chord < arc*0.5 { continue }
                var maximum = 0.0
                for i in (start+1)..<end { maximum = max(maximum, error(localPoints[i], localPoints[start], localPoints[end])) }
                if maximum <= 30 { chosen = end }
            }
            cleaned.append(localPoints[chosen]); start = chosen
        }
        var keep: Set<Int> = [0, cleaned.count-1], stack = [(0, cleaned.count-1)]
        while let (start, end) = stack.popLast() {
            try Task.checkCancellation()
            guard end > start+1 else { continue }
            var furthest: Int?, maxError = 6.0
            for i in (start+1)..<end {
                let deviation = error(cleaned[i], cleaned[start], cleaned[end])
                if deviation > maxError { maxError = deviation; furthest = i }
            }
            if let furthest { keep.insert(furthest); stack.append((start, furthest)); stack.append((furthest, end)) }
        }
        var simplified = cleaned.indices.filter { keep.contains($0) }.map { cleaned[$0] }
        var i = 1
        while i < simplified.count-1 {
            try Task.checkCancellation()
            let a = simplified[i-1], b = simplified[i], c = simplified[i+1]
            let ab = distance(a,b), bc = distance(b,c)
            let product = ab*bc
            let cosine = ((x(b)-x(a))*(x(c)-x(b)) + (y(b)-y(a))*(y(c)-y(b))) / (product > 0 ? product : 1)
            if cosine < -0.85 && min(ab,bc) <= 80 && error(b,a,c) <= 60 {
                simplified.remove(at:i); i = max(1,i-1)
            } else { i += 1 }
        }
        // Web's bounded corner rounding, not whole-path Chaikin subdivision.
        var result = [simplified[0]]
        for i in 1..<(simplified.count-1) {
            if i.isMultiple(of: 128) { try Task.checkCancellation() }
            let previous = simplified[i-1], point = simplified[i], next = simplified[i+1]
            let incoming = distance(previous,point), outgoing = distance(point,next)
            if incoming == 0 || outgoing == 0 { result.append(point); continue }
            let radius = min(45, incoming*0.45, outgoing*0.45)
            let entry = lerp(point,previous,radius/incoming), exit = lerp(point,next,radius/outgoing)
            result.append(entry)
            for step in 1...10 {
                let t = Double(step)/10
                result.append(lerp(lerp(entry,point,t),lerp(point,exit,t),t))
            }
        }
        result.append(simplified.last!)
        return result
    }
}
