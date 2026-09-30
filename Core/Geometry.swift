import Foundation

enum Coordinates {
    static func inChina(_ p: Coordinate) -> Bool {
        (72.004...137.8347).contains(p.longitude) && (0.8293...55.8271).contains(p.latitude)
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
