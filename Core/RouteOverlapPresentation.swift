import Foundation

/// Separates opposite-direction planned legs in geographic space once, before SDK rendering.
/// Eight meters per side is deliberately bounded: this is an itinerary diagram, not navigation.
enum RouteOverlapPresentation {
    private struct Point { var x: Double; var y: Double }
    private struct Cell: Hashable { var x: Int; var y: Int }
    private struct Sample { var route: Int; var point: Point; var dx: Double; var dy: Double }
    static func separate(_ input: [DisplayRoute]) throws -> [DisplayRoute] {
        var routes = input
        for i in routes.indices { routes[i].points = routes[i].unseparatedPoints ?? routes[i].points }
        guard let origin = routes.first(where: { $0.isPlanned })?.points.first else { return routes }
        let sy = 111195.0, sx = sy * max(0.01, cos(origin.latitude * .pi / 180))
        func project(_ c: Coordinate) -> Point { Point(x: (c.longitude-origin.longitude)*sx, y: (c.latitude-origin.latitude)*sy) }
        func cell(_ p: Point) -> Cell { Cell(x: Int(floor(p.x/32)), y: Int(floor(p.y/32))) }
        var samples: [[Point]] = Array(repeating: [], count: routes.count)
        var grid: [Cell: [Sample]] = [:]
        for i in routes.indices where routes[i].isPlanned && routes[i].points.count > 1 {
            try Task.checkCancellation()
            let raw = routes[i].points.map(project)
            // Bound work for intercontinental legs; do not approximate those into millions of samples.
            let length = zip(raw, raw.dropFirst()).reduce(0.0) { $0 + hypot($1.1.x-$1.0.x, $1.1.y-$1.0.y) }
            guard length <= 200000 else { continue }
            var points = [raw[0]]
            for (a,b) in zip(raw,raw.dropFirst()) {
                let count = max(1, Int(ceil(hypot(b.x-a.x,b.y-a.y)/16)))
                for j in 1...count { let t = Double(j)/Double(count); points.append(Point(x:a.x+(b.x-a.x)*t,y:a.y+(b.y-a.y)*t)) }
            }
            samples[i] = points
            for (a,b) in zip(points,points.dropFirst()) {
                let length = hypot(b.x-a.x,b.y-a.y)
                guard length > 0.01 else { continue }
                let midpoint = Point(x:(a.x+b.x)/2,y:(a.y+b.y)/2)
                grid[cell(midpoint),default:[]].append(Sample(route:i,point:midpoint,dx:(b.x-a.x)/length,dy:(b.y-a.y)/length))
            }
        }
        for i in routes.indices where samples[i].count > 2 {
            try Task.checkCancellation()
            let points = samples[i]
            var cumulative = [0.0]
            for (a,b) in zip(points,points.dropFirst()) { cumulative.append(cumulative.last! + hypot(b.x-a.x,b.y-a.y)) }
            var offsets = Array(repeating:0.0,count:points.count)
            var normals = Array(repeating:Point(x:0,y:0),count:points.count)
            for j in 1..<(points.count-1) {
                if j.isMultiple(of:256) { try Task.checkCancellation() }
                let p = points[j], a = points[j-1], b = points[j+1]
                let length = hypot(b.x-a.x,b.y-a.y)
                guard length > 0.01 else { continue }
                let dx=(b.x-a.x)/length, dy=(b.y-a.y)/length, key=cell(p)
                normals[j] = Point(x:-dy,y:dx)
                var overlap = false
                for x in -1...1 { for y in -1...1 {
                    for other in grid[Cell(x:key.x+x,y:key.y+y)] ?? [] where other.route != i {
                        guard dx*other.dx+dy*other.dy < -0.94 else { continue }
                        let px=p.x-other.point.x, py=p.y-other.point.y
                        if abs(px*other.dy-py*other.dx) <= 5 && abs(px*other.dx+py*other.dy) <= 12 { overlap = true; break }
                    }
                } }
                if overlap { offsets[j] = 8 * min(1,min(cumulative[j],cumulative.last!-cumulative[j])/40) }
            }
            guard offsets.contains(where: { $0 > 0 }) else { continue }
            // Blend the entrances/exits without moving either saved place.
            let original = offsets
            for j in 1..<(offsets.count-1) { offsets[j]=(original[j-1]+2*original[j]+original[j+1])/4 }
            routes[i].unseparatedPoints = routes[i].points
            routes[i].points = points.indices.map { j in
                Coordinate(latitude:origin.latitude+(points[j].y+normals[j].y*offsets[j])/sy,
                           longitude:origin.longitude+(points[j].x+normals[j].x*offsets[j])/sx)
            }
            routes[i].points[0] = input[i].points.first!
            routes[i].points[routes[i].points.count-1] = input[i].points.last!
        }
        return routes
    }
}
