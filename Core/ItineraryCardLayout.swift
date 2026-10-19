import Foundation

struct ItineraryLayoutAnchor: Codable, Sendable {
    var id: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}
struct ItineraryLayoutPlacement: Codable, Sendable {
    var id: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var left: Double
    var top: Double
    var end: ItineraryLayoutPoint
}
struct ItineraryLayoutPoint: Codable, Sendable {
    var x: Double
    var y: Double
}
struct ItineraryLayoutBounds: Codable, Sendable {
    var left: Double
    var top: Double
    var right: Double
    var bottom: Double
}

/// Native leader-label solver following the Web itinerary layout: fixed leader directions × length bands,
/// unary costs for route clearance and open space, pairwise costs forbidding overlap, deterministic annealing,
/// hysteresis toward previous placements, then a repair pass that lets every label move into free slots.
actor ItineraryCardLayout {
    private typealias Point = ItineraryLayoutPoint
    private typealias Rect = ItineraryLayoutBounds
    private struct Candidate {
        var left: Double, top: Double, end: Point, angle: Double, length: Double, unary: Double
        var u: Double, v: Double, side: Double, polar: Double
    }
    private enum Shape { case linear, radial }

    private static let directions: [Double] = [-150, -120, -60, -30, 30, 60, 120, 150, 0, 180]
    private static let lengths: [Double] = [80, 104, 136, 176, 232, 300]
    private static let cardGap = 10.0, anchorPad = 14.0, clearanceLimit = 24.0, hard = 100_000.0, freeStep = 12.0

    func layout(anchors: [ItineraryLayoutAnchor], bounds: ItineraryLayoutBounds,
                paths: [[ItineraryLayoutPoint]], previous: [ItineraryLayoutPlacement]) throws -> [ItineraryLayoutPlacement] {
        try Task.checkCancellation()
        let result = try Self.solve(anchors: anchors, bounds: bounds, paths: paths, previous: previous)
        try Task.checkCancellation()
        return result
    }

    static func leaderEnd(left: Double, top: Double, width: Double, height: Double, anchor: ItineraryLayoutPoint) -> ItineraryLayoutPoint {
        let cx = left + width / 2, cy = top + height / 2, dx = anchor.x - cx, dy = anchor.y - cy
        let scale = 1 / max(abs(dx) / (width / 2), abs(dy) / (height / 2), 1)
        return Point(x: cx + dx * scale, y: cy + dy * scale)
    }

    // MARK: Geometry

    private static func wrap(_ a: Double) -> Double { atan2(sin(a), cos(a)) }
    private static func degDiff(_ a: Double, _ b: Double) -> Double { abs(wrap(a - b)) * 180 / .pi }
    private static func cross(_ a: Point, _ b: Point, _ c: Point) -> Double { (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x) }
    private static func segmentsCross(_ a: Point, _ b: Point, _ c: Point, _ d: Point) -> Bool {
        cross(a, b, c) * cross(a, b, d) < 0 && cross(c, d, a) * cross(c, d, b) < 0
    }
    private static func rect(_ left: Double, _ top: Double, _ width: Double, _ height: Double, pad: Double = 0) -> Rect {
        Rect(left: left - pad, top: top - pad, right: left + width + pad, bottom: top + height + pad)
    }
    private static func overlaps(_ a: Rect, _ b: Rect) -> Bool { a.left < b.right && a.right > b.left && a.top < b.bottom && a.bottom > b.top }
    private static func contains(_ r: Rect, _ p: Point) -> Bool { p.x > r.left && p.x < r.right && p.y > r.top && p.y < r.bottom }
    private static func rectPointDistance(_ r: Rect, _ p: Point) -> Double {
        hypot(max(r.left - p.x, 0, p.x - r.right), max(r.top - p.y, 0, p.y - r.bottom))
    }
    private static func segmentHitsRect(_ a: Point, _ b: Point, _ r: Rect) -> Bool {
        var low = 0.0, high = 1.0
        for (start, delta, minV, maxV) in [(a.x, b.x - a.x, r.left, r.right), (a.y, b.y - a.y, r.top, r.bottom)] {
            if delta == 0 { if start < minV || start > maxV { return false }; continue }
            let enter = (minV - start) / delta, exit = (maxV - start) / delta
            low = max(low, min(enter, exit)); high = min(high, max(enter, exit))
            if low > high { return false }
        }
        return true
    }
    private static func pointSegmentDistance(_ p: Point, _ a: Point, _ b: Point) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y, len = dx * dx + dy * dy
        let t = len > 0 ? max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len)) : 0
        return hypot(p.x - a.x - t * dx, p.y - a.y - t * dy)
    }
    private static func rectSegmentDistance(_ r: Rect, _ a: Point, _ b: Point) -> Double {
        if segmentHitsRect(a, b, r) { return 0 }
        let corners = [Point(x: r.left, y: r.top), Point(x: r.right, y: r.top), Point(x: r.right, y: r.bottom), Point(x: r.left, y: r.bottom)]
        return ([rectPointDistance(r, a), rectPointDistance(r, b)] + corners.map { pointSegmentDistance($0, a, b) }).min() ?? 0
    }

    /// Uniform grid over screen-space route segments so candidate checks stay local.
    private struct SegmentIndex {
        private var cells: [Int64: [Int]] = [:]
        private(set) var segments: [(Point, Point)] = []
        private let size = 64.0
        init(paths: [[Point]], view: Rect) {
            for path in paths {
                var last: Point?
                for point in path where point.x.isFinite && point.y.isFinite {
                    if let l = last, hypot(point.x - l.x, point.y - l.y) < 4 { continue }
                    if let l = last, max(l.x, point.x) >= view.left, min(l.x, point.x) <= view.right,
                       max(l.y, point.y) >= view.top, min(l.y, point.y) <= view.bottom { add((l, point)) }
                    last = point
                }
            }
        }
        private static func key(_ x: Int, _ y: Int) -> Int64 { Int64(x) << 32 | Int64(UInt32(bitPattern: Int32(y))) }
        private mutating func add(_ segment: (Point, Point)) {
            let index = segments.count; segments.append(segment)
            let (a, b) = segment
            for cx in Int(floor(min(a.x, b.x) / size))...Int(floor(max(a.x, b.x) / size)) {
                for cy in Int(floor(min(a.y, b.y) / size))...Int(floor(max(a.y, b.y) / size)) { cells[Self.key(cx, cy), default: []].append(index) }
            }
        }
        func query(_ r: Rect) -> [(Point, Point)] {
            var found = Set<Int>(), ordered: [Int] = []
            for cx in Int(floor(r.left / size))...Int(floor(r.right / size)) {
                for cy in Int(floor(r.top / size))...Int(floor(r.bottom / size)) {
                    for i in cells[Self.key(cx, cy)] ?? [] where found.insert(i).inserted { ordered.append(i) }
                }
            }
            return ordered.map { segments[$0] }
        }
    }

    /// Open space around an anchor at itinerary scale: away from nearby route mass and other anchors.
    private static func freeDirection(_ anchor: Point, _ index: SegmentIndex, _ anchors: [Point], _ center: Point) -> (angle: Double, strength: Double) {
        var fx = 0.0, fy = 0.0, mass = 0.0
        func push(_ p: Point, _ weight: Double) {
            let dx = anchor.x - p.x, dy = anchor.y - p.y, d = hypot(dx, dy)
            if d < 2 || d > 320 { return }
            let w = weight / (40 + d)
            fx += dx / d * w; fy += dy / d * w; mass += w
        }
        for (a, b) in index.query(Rect(left: anchor.x - 320, top: anchor.y - 320, right: anchor.x + 320, bottom: anchor.y + 320)) {
            push(Point(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), hypot(b.x - a.x, b.y - a.y))
        }
        for p in anchors { push(p, 60) }
        let strength = mass > 0 ? hypot(fx, fy) / mass : 0
        if strength > 0.12 { return (atan2(fy, fx), min(1, strength * 1.6)) }
        let dx = anchor.x - center.x, dy = anchor.y - center.y
        return hypot(dx, dy) > 24 ? (atan2(dy, dx), 0.4) : (-.pi / 6, 0.2)
    }

    /// Elongated itineraries get two bands parallel to the principal axis; round ones and loops get an outer ring.
    private static func routeShape(_ paths: [[Point]], _ anchors: [Point]) -> (kind: Shape, center: Point, axis: Point, normal: Point) {
        var points = anchors
        for path in paths {
            let step = max(1, path.count / 40)
            for p in stride(from: 0, to: path.count, by: step).map({ path[$0] }) where p.x.isFinite && p.y.isFinite { points.append(p) }
        }
        let n = Double(points.count)
        let center = Point(x: points.reduce(0) { $0 + $1.x } / n, y: points.reduce(0) { $0 + $1.y } / n)
        var xx = 0.0, yy = 0.0, xy = 0.0
        for p in points { let dx = p.x - center.x, dy = p.y - center.y; xx += dx * dx; yy += dy * dy; xy += dx * dy }
        let theta = 0.5 * atan2(2 * xy, xx - yy)
        let mean = (xx + yy) / 2, spread = hypot((xx - yy) / 2, xy)
        let ratio = mean + spread > 0 ? (mean - spread) / (mean + spread) : 1
        let axis = Point(x: cos(theta), y: sin(theta))
        return (ratio > 0.4 ? .radial : .linear, center, axis, Point(x: -axis.y, y: axis.x))
    }

    private static func cardAt(_ anchor: ItineraryLayoutAnchor, _ angle: Double, _ length: Double) -> (left: Double, top: Double, end: Point) {
        let c = cos(angle), s = sin(angle)
        let edge = 1 / max(abs(c) / (anchor.width / 2), abs(s) / (anchor.height / 2))
        let cx = anchor.x + c * (length + edge), cy = anchor.y + s * (length + edge)
        return (cx - anchor.width / 2, cy - anchor.height / 2, Point(x: anchor.x + c * length, y: anchor.y + s * length))
    }

    /// Deterministic PRNG seeded from the anchor IDs so identical inputs produce identical layouts.
    private struct Seeded {
        var h: UInt32 = 2_166_136_261
        init(_ text: String) { for unit in text.utf16 { h = (h ^ UInt32(unit)) &* 16_777_619 } }
        mutating func next() -> Double {
            h = (h ^ (h >> 15)) &* (h | 1)
            h ^= h &+ ((h ^ (h >> 7)) &* (h | 61))
            return Double(h ^ (h >> 14)) / 4_294_967_296
        }
    }

    // MARK: Solver

    private static func solve(anchors: [ItineraryLayoutAnchor], bounds: Rect, paths: [[Point]], previous: [ItineraryLayoutPlacement]) throws -> [ItineraryLayoutPlacement] {
        let visible = anchors.filter { $0.x.isFinite && $0.y.isFinite && $0.width > 0 && $0.height > 0
            && $0.x >= bounds.left - 100 && $0.x <= bounds.right + 100 && $0.y >= bounds.top - 100 && $0.y <= bounds.bottom + 100 }
        guard !visible.isEmpty, let minWidth = visible.map(\.width).min(), let minHeight = visible.map(\.height).min(),
              bounds.right - bounds.left >= minWidth, bounds.bottom - bounds.top >= minHeight else { return [] }
        let points = visible.map { Point(x: $0.x, y: $0.y) }
        let index = SegmentIndex(paths: paths, view: Rect(left: bounds.left - 400, top: bounds.top - 400, right: bounds.right + 400, bottom: bounds.bottom + 400))
        let center = Point(x: points.reduce(0) { $0 + $1.x } / Double(points.count), y: points.reduce(0) { $0 + $1.y } / Double(points.count))
        var prior: [String: (angle: Double, length: Double)] = [:]
        for p in previous {
            let end = leaderEnd(left: p.left, top: p.top, width: p.width, height: p.height, anchor: Point(x: p.x, y: p.y))
            prior[p.id] = (atan2(end.y - p.y, end.x - p.x), hypot(end.x - p.x, end.y - p.y))
        }
        func inside(_ r: Rect) -> Bool { r.left >= bounds.left && r.top >= bounds.top && r.right <= bounds.right && r.bottom <= bounds.bottom }
        func coversAnchor(_ r: Rect) -> Bool { points.contains { contains(r, $0) } }
        let near = { (p: Point) in p.x >= bounds.left - 400 && p.x <= bounds.right + 400 && p.y >= bounds.top - 400 && p.y <= bounds.bottom + 400 }
        let shape = routeShape(paths.map { $0.filter(near) }.filter { !$0.isEmpty }, points)
        func dot(_ p: Point, _ d: Point) -> Double { p.x * d.x + p.y * d.y }
        let normalAngle = atan2(shape.normal.y, shape.normal.x)
        var angles = directions.map { $0 * .pi / 180 }
        if shape.kind == .linear { angles += [0, Double.pi].flatMap { base in [-0.45, 0, 0.45].map { wrap(normalAngle + base + $0) } } }
        angles = angles.enumerated().filter { i, a in angles.firstIndex { degDiff(a, $0) < 8 } == i }.map(\.1)
        let axisRank = visible.indices.sorted { dot(points[$0], shape.axis) < dot(points[$1], shape.axis) }
        func candidate(_ anchor: ItineraryLayoutAnchor, _ left: Double, _ top: Double, _ end: Point, _ angle: Double, _ length: Double, _ unary: Double) -> Candidate {
            let card = Point(x: left + anchor.width / 2, y: top + anchor.height / 2)
            let rel = Point(x: card.x - shape.center.x, y: card.y - shape.center.y)
            let side = dot(Point(x: card.x - anchor.x, y: card.y - anchor.y), shape.normal)
            return Candidate(left: left, top: top, end: end, angle: angle, length: length, unary: unary,
                             u: dot(rel, shape.axis), v: dot(rel, shape.normal), side: side > 0 ? 1 : side < 0 ? -1 : 1, polar: atan2(rel.y, rel.x))
        }
        func clearance(_ r: Rect, _ anchor: ItineraryLayoutAnchor) -> Double {
            var value = clearanceLimit
            for (a, b) in index.query(rect(r.left, r.top, anchor.width, anchor.height, pad: clearanceLimit)) { value = min(value, rectSegmentDistance(r, a, b)) }
            return value
        }

        var options: [[Candidate]] = visible.enumerated().map { anchorIndex, anchor in
            let anchorPoint = points[anchorIndex]
            let free = freeDirection(anchorPoint, index, points, center)
            let preferred: Double
            if shape.kind == .linear {
                let localSide = cos(free.angle - normalAngle) * free.strength
                let offset = dot(Point(x: anchor.x - shape.center.x, y: anchor.y - shape.center.y), shape.normal)
                let side = abs(localSide) > 0.15 ? (localSide > 0 ? 1.0 : -1) : abs(offset) > 20 ? (offset > 0 ? 1 : -1) : (axisRank.firstIndex(of: anchorIndex)! % 2 == 1 ? 1 : -1)
                preferred = side > 0 ? normalAngle : wrap(normalAngle + .pi)
            } else {
                let dx = anchor.x - shape.center.x, dy = anchor.y - shape.center.y
                preferred = hypot(dx, dy) > 24 ? atan2(dy, dx) : free.angle
            }
            var list: [Candidate] = []
            for (li, length) in lengths.enumerated() {
                for angle in angles {
                    let deg = (angle * 180 / .pi).rounded()
                    let (left, top, end) = cardAt(anchor, angle, length)
                    let r = rect(left, top, anchor.width, anchor.height)
                    guard inside(r), !coversAnchor(rect(left, top, anchor.width, anchor.height, pad: anchorPad)) else { continue }
                    var unary = (length - lengths[0]) * 2.4 + (li >= 3 ? 300 : 0) + (li >= 4 ? 500 : 0)
                    unary += degDiff(angle, preferred) * 2 + degDiff(angle, free.angle) * free.strength
                    if shape.kind == .radial, deg == 0 || abs(deg) == 180 { unary += 50 }
                    let clear = clearance(r, anchor)
                    unary += clear == 0 ? 1600 : (clearanceLimit - clear) * 18
                    let box = Rect(left: min(anchor.x, end.x), top: min(anchor.y, end.y), right: max(anchor.x, end.x), bottom: max(anchor.y, end.y))
                    for (a, b) in index.query(box) where pointSegmentDistance(anchorPoint, a, b) > anchorPad && segmentsCross(anchorPoint, end, a, b) { unary += 140 }
                    list.append(candidate(anchor, left, top, end, angle, length, unary))
                }
            }
            // Keep the previous offset as an explicit candidate; it only moves when it becomes clearly worse.
            if let before = prior[anchor.id] {
                let (left, top, end) = cardAt(anchor, before.angle, before.length)
                let r = rect(left, top, anchor.width, anchor.height)
                if inside(r), rectPointDistance(r, anchorPoint) >= lengths[0] - 1, !coversAnchor(rect(left, top, anchor.width, anchor.height, pad: anchorPad)) {
                    list.append(candidate(anchor, left, top, end, before.angle, before.length, (clearance(r, anchor) == 0 ? 1600 : 0) - 1500))
                }
            }
            return list.sorted { $0.unary < $1.unary }
        }
        try Task.checkCancellation()

        let maxWidth = visible.map(\.width).max() ?? 0
        let reach = lengths[lengths.count - 1] + maxWidth * 1.2
        var neighbors: [Set<Int>] = visible.indices.map { i in
            Set(visible.indices.filter { $0 != i && hypot(points[i].x - points[$0].x, points[i].y - points[$0].y) < reach * 2 })
        }
        func pair(_ i: Int, _ p: Candidate, _ j: Int, _ q: Candidate) -> Double {
            let a = visible[i], b = visible[j], pa = points[i], pb = points[j]
            let pr = rect(p.left, p.top, a.width, a.height), qr = rect(q.left, q.top, b.width, b.height)
            if overlaps(rect(p.left, p.top, a.width, a.height, pad: cardGap), qr) { return hard }
            var cost = segmentsCross(pa, p.end, pb, q.end) ? 900.0 : 0
            if segmentHitsRect(pa, p.end, rect(q.left, q.top, b.width, b.height, pad: 4)) { cost += 3000 }
            if segmentHitsRect(pb, q.end, rect(p.left, p.top, a.width, a.height, pad: 4)) { cost += 3000 }
            let distance = hypot(pa.x - pb.x, pa.y - pb.y)
            if distance < 220 { cost += min(60, degDiff(p.angle, q.angle) * 0.5) * (1 - distance / 220) }
            if shape.kind == .linear {
                if p.side == q.side, abs(p.u - q.u) < reach * 1.5 {
                    if (dot(pa, shape.axis) - dot(pb, shape.axis)) * (p.u - q.u) < 0 { cost += 700 }
                    let dv = abs(p.v - q.v)
                    if dv < 6 { cost -= 50 } else if dv < 28 { cost += 20 }
                }
            } else {
                let turn = wrap(atan2(pa.y - shape.center.y, pa.x - shape.center.x) - atan2(pb.y - shape.center.y, pb.x - shape.center.x))
                if distance < reach, abs(turn) > 0.05, turn * wrap(p.polar - q.polar) < 0 { cost += 600 }
                if abs(pr.top - qr.top) < 240, abs(pr.left - qr.left) < reach {
                    let dl = min(abs(pr.left - qr.left), abs(pr.right - qr.right))
                    if dl < 4 { cost -= 40 } else if dl < 24 { cost += 24 }
                }
            }
            return cost
        }

        var choice = Array(repeating: -1, count: visible.count)
        func local(_ i: Int, _ c: Int) -> Double {
            guard c >= 0 else { return hard * 10 }
            var cost = options[i][c].unary
            for j in neighbors[i] where choice[j] >= 0 { cost += pair(i, options[i][c], j, options[j][choice[j]]) }
            return cost
        }
        func best(_ i: Int, from start: Int = 0, margin: Double = 0) -> Int {
            var best = choice[i], bestCost = choice[i] >= 0 ? local(i, choice[i]) : .infinity
            for c in start..<options[i].count { let cost = local(i, c); if cost < bestCost - margin { best = c; bestCost = cost } }
            return best
        }
        // Greedy start from the most constrained anchors, then anneal.
        let crowd = visible.indices.map { i in neighbors[i].filter { hypot(points[i].x - points[$0].x, points[i].y - points[$0].y) < 260 }.count }
        let order = visible.indices.sorted { i, j in
            crowd[i] != crowd[j] ? crowd[i] > crowd[j] : options[i].count != options[j].count ? options[i].count < options[j].count : visible[i].id < visible[j].id
        }
        for i in order { choice[i] = best(i) }
        var random = Seeded(visible.map(\.id).joined(separator: "|"))
        let annealSteps = min(24_000, visible.count * 900)
        func anneal(heat: Double) throws {
            for step in 0..<annealSteps {
                if step % 2000 == 0 { try Task.checkCancellation() }
                let temperature = heat * pow(0.002, Double(step) / Double(annealSteps))
                let i = min(visible.count - 1, Int(random.next() * Double(visible.count)))
                guard !options[i].isEmpty else { continue }
                let next = min(options[i].count - 1, Int(random.next() * Double(options[i].count)))
                guard next != choice[i] else { continue }
                let current = local(i, choice[i]), old = choice[i]
                choice[i] = next
                let delta = local(i, next) - current
                if delta > 0, random.next() >= exp(-delta / temperature) { choice[i] = old }
            }
        }
        func descend() { for _ in 0..<3 { for i in order { choice[i] = best(i, margin: 0.01) } } }
        try anneal(heat: 400)
        descend()

        // Labels are never hidden. A blocked label can only be freed if its neighbours may move too, so once conflicts
        // remain every label gets viewport free slots and the search reruns.
        func grid(_ minV: Double, _ maxV: Double) -> [Double] {
            guard maxV >= minV else { return [] }
            return Array(stride(from: minV, to: maxV, by: freeStep)) + [maxV]
        }
        var freed = Set<Int>()
        func addFree(_ i: Int) {
            guard freed.insert(i).inserted else { return }
            let anchor = visible[i]
            for top in grid(bounds.top, bounds.bottom - anchor.height) {
                for left in grid(bounds.left, bounds.right - anchor.width) {
                    let r = rect(left, top, anchor.width, anchor.height)
                    if rectPointDistance(r, points[i]) < lengths[0] || coversAnchor(rect(left, top, anchor.width, anchor.height, pad: anchorPad)) { continue }
                    let end = leaderEnd(left: left, top: top, width: anchor.width, height: anchor.height, anchor: points[i])
                    let length = hypot(end.x - anchor.x, end.y - anchor.y)
                    options[i].append(candidate(anchor, left, top, end, atan2(end.y - anchor.y, end.x - anchor.x), length, 2000 + length * 2))
                }
            }
            // Distant free slots can reach labels outside the neighbour radius.
            for j in visible.indices where j != i { neighbors[i].insert(j); neighbors[j].insert(i) }
        }
        for round in 0..<3 {
            try Task.checkCancellation()
            let blocked = order.filter { choice[$0] < 0 || local($0, choice[$0]) >= hard }
            if blocked.isEmpty { break }
            if round == 0 { blocked.forEach(addFree) } else { visible.indices.forEach(addFree) }
            for i in blocked { choice[i] = best(i) }
            if round > 0 { try anneal(heat: 2000) }
            descend()
        }

        return visible.indices.compactMap { i in
            guard choice[i] >= 0 else { return nil }
            let anchor = visible[i], c = options[i][choice[i]]
            let left = c.left.rounded(), top = c.top.rounded()
            return ItineraryLayoutPlacement(id: anchor.id, x: anchor.x, y: anchor.y, width: anchor.width, height: anchor.height, left: left, top: top,
                                            end: leaderEnd(left: left, top: top, width: anchor.width, height: anchor.height, anchor: Point(x: anchor.x, y: anchor.y)))
        }
    }
}
