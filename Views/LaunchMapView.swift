import SwiftUI

struct LaunchMapView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var connected = false
    private let blue = Color(red: 57 / 255, green: 154 / 255, blue: 218 / 255)

    var body: some View {
        ZStack {
            blue.ignoresSafeArea()
            GeometryReader { geometry in
                let scale = geometry.size.width / 1024
                ZStack {
                    Path { path in
                        let points: [CGPoint] = [.init(x: 180, y: 290), .init(x: 395, y: 210),
                            .init(x: 630, y: 290), .init(x: 845, y: 210), .init(x: 845, y: 734),
                            .init(x: 630, y: 814), .init(x: 395, y: 734), .init(x: 180, y: 814)]
                        path.addLines(points.map { CGPoint(x: $0.x * scale, y: $0.y * scale) })
                        path.closeSubpath()
                    }.fill(Color(red: 239 / 255, green: 249 / 255, blue: 1))
                    Path { path in
                        path.addLines([CGPoint(x: 395, y: 210), CGPoint(x: 630, y: 290),
                            CGPoint(x: 630, y: 814), CGPoint(x: 395, y: 734)]
                            .map { CGPoint(x: $0.x * scale, y: $0.y * scale) })
                        path.closeSubpath()
                    }.fill(Color(red: 202 / 255, green: 231 / 255, blue: 249 / 255))
                    Path { path in
                        path.move(to: CGPoint(x: 395 * scale, y: 245 * scale))
                        path.addLine(to: CGPoint(x: 395 * scale, y: 700 * scale))
                        path.move(to: CGPoint(x: 630 * scale, y: 323 * scale))
                        path.addLine(to: CGPoint(x: 630 * scale, y: 780 * scale))
                    }.stroke(blue, lineWidth: 10 * scale)
                    Path { path in
                        path.move(to: CGPoint(x: 280 * scale, y: 620 * scale))
                        path.addQuadCurve(to: CGPoint(x: 741 * scale, y: 430 * scale),
                            control: CGPoint(x: 470 * scale, y: 240 * scale))
                    }.trim(from: 0, to: connected ? 1 : 0)
                        .stroke(blue, style: StrokeStyle(lineWidth: 30 * scale, lineCap: .round))
                    ForEach(0..<2) { index in
                        Circle().fill(blue).frame(width: 94 * scale, height: 94 * scale)
                            .overlay { Circle().fill(.white).frame(width: 40 * scale, height: 40 * scale) }
                            .position(x: (index == 0 ? 280 : 741) * scale,
                                y: (index == 0 ? 620 : 430) * scale)
                    }
                }
            }.frame(width: 240, height: 240)
        }
        .accessibilityLabel("MapAnNai 正在启动")
        .task {
            if reduceMotion { connected = true; return }
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            withAnimation(.easeInOut(duration: 0.65)) { connected = true }
        }
    }
}
