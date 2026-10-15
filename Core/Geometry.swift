import Foundation

enum Coordinates {
    private static let regions: [[Double]] = [
        [79.446200,49.220400,96.330000,42.889900], [109.687200,54.141500,135.000200,39.374200],
        [73.124600,42.889900,124.143255,29.529700], [82.968400,29.529700,97.035200,26.718600],
        [97.025300,29.529700,124.367395,20.414096], [107.975793,20.414096,111.744104,17.871542]
    ]
    private static let exclusions: [[Double]] = [
        [119.921265,25.398623,122.497559,21.785006], [101.865200,22.284000,106.665000,20.098800],
        [106.452500,21.542200,108.051000,20.487800], [109.032300,55.817500,119.127000,50.325700],
        [127.456800,55.817500,137.022700,49.557400], [131.266200,44.892200,137.022700,42.569200],
        [73.124600,35.398637,77.948114,29.529700]
    ]

    static func inChina(_ p: Coordinate) -> Bool {
        guard p.longitude.isFinite, p.latitude.isFinite else { return false }
        // Same approximate service region as the web client, not an exact border.
        func contains(_ r: [Double]) -> Bool {
            p.longitude >= r[0] && p.longitude <= r[2] && p.latitude >= r[3] && p.latitude <= r[1]
        }
        return regions.contains(where: contains) && !exclusions.contains(where: contains)
    }
    static func gcj(_ p: Coordinate) -> Coordinate {
        guard inChina(p) else { return p }
        let x = p.longitude - 105, y = p.latitude - 35
        var lat = -100 + 2*x + 3*y + 0.2*y*y + 0.1*x*y + 0.2*sqrt(abs(x))
        lat += (20*sin(6*x * .pi) + 20*sin(2*x * .pi))*2/3
        lat += (20*sin(y * .pi) + 40*sin(y/3 * .pi))*2/3
        lat += (160*sin(y/12 * .pi) + 320*sin(y * .pi/30))*2/3
        var lng = 300 + x + 2*y + 0.1*x*x + 0.1*x*y + 0.1*sqrt(abs(x))
        lng += (20*sin(6*x * .pi) + 20*sin(2*x * .pi))*2/3
        lng += (20*sin(x * .pi) + 40*sin(x/3 * .pi))*2/3
        lng += (150*sin(x/12 * .pi) + 300*sin(x/30 * .pi))*2/3
        let rad = p.latitude / 180 * .pi, magic = 1 - 0.00669342162296594323 * pow(sin(rad), 2)
        let root = sqrt(magic)
        lat = lat*180 / ((6378245 * (1-0.00669342162296594323) / (magic*root)) * .pi)
        lng = lng*180 / ((6378245/root) * cos(rad) * .pi)
        return Coordinate(latitude: p.latitude + lat, longitude: p.longitude + lng)
    }
    static func wgs(_ p: Coordinate) -> Coordinate {
        let forward = gcj(p)
        return Coordinate(latitude: 2*p.latitude - forward.latitude, longitude: 2*p.longitude - forward.longitude)
    }
    static func distance(_ a: Coordinate, _ b: Coordinate) -> Double {
        let lat = (b.latitude-a.latitude) * .pi/180, lng = (b.longitude-a.longitude) * .pi/180
        let h = pow(sin(lat/2), 2) + cos(a.latitude * .pi/180)*cos(b.latitude * .pi/180)*pow(sin(lng/2), 2)
        return 6371000 * 2 * asin(sqrt(min(1, max(0, h))))
    }
}
enum RouteGeometry {
    static func curve(_ a: Coordinate, _ b: Coordinate) -> [Coordinate] {
        let dx = b.longitude-a.longitude, dy = b.latitude-a.latitude
        let control = Coordinate(latitude: (a.latitude+b.latitude)/2 + dx*0.12,
                                 longitude: (a.longitude+b.longitude)/2 - dy*0.12)
        return (0...32).map { i in
            let t = Double(i)/32, s = 1-t
            return Coordinate(latitude: s*s*a.latitude+2*s*t*control.latitude+t*t*b.latitude,
                              longitude: s*s*a.longitude+2*s*t*control.longitude+t*t*b.longitude)
        }
    }
    // Only display geometry changes. Keep endpoints, major bends, and the stored route untouched.
    static func smooth(_ path: [Coordinate]) -> [Coordinate] {
        var clean = [Coordinate]()
        for p in path where p.isValid {
            if let last = clean.last, Coordinates.distance(last, p) < 0.25 { continue }
            clean.append(p)
        }
        guard clean.count > 2 else { return clean }
        var result = [clean[0]]
        for i in 0..<(clean.count-1) {
            let a = clean[i], b = clean[i+1]
            result.append(Coordinate(latitude: a.latitude*0.75+b.latitude*0.25, longitude: a.longitude*0.75+b.longitude*0.25))
            result.append(Coordinate(latitude: a.latitude*0.25+b.latitude*0.75, longitude: a.longitude*0.25+b.longitude*0.75))
        }
        result.append(clean.last!); return result
    }
    static func nearestDistance(_ point: (Double, Double), to path: [(Double, Double)]) -> Double {
        guard path.count > 1 else { return .infinity }
        var nearest = Double.infinity
        for i in 1..<path.count {
            let a = path[i-1], b = path[i], dx = b.0-a.0, dy = b.1-a.1
            let length = dx*dx+dy*dy
            let t = length == 0 ? 0 : min(1, max(0, ((point.0-a.0)*dx+(point.1-a.1)*dy)/length))
            nearest = min(nearest, hypot(point.0-a.0-t*dx, point.1-a.1-t*dy))
        }
        return nearest
    }
}
