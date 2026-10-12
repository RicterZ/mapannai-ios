import SwiftUI

struct TripNamePlaceholder: View {
    let fontSize: CGFloat
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var places = [TripNameSuggestions.places.randomElement()!]
    @State private var themes = [TripNameSuggestions.themes.randomElement()!]
    @State private var started: TimeInterval?

    private var running: Bool { scenePhase == .active && !reduceMotion && !voiceOver }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: started == nil || !running)) { _ in
            let progress = started.map { TripNameSuggestions.progress(elapsed: ProcessInfo.processInfo.systemUptime - $0) } ?? 0
            Canvas { context, size in
                let font = Font.system(size: fontSize, weight: .medium)
                let sample = context.resolve(Text("澳门").font(font))
                let width = sample.measure(in: CGSize(width: .infinity, height: size.height)).width
                drawReel(places, context: context, x: 0, height: size.height, progress: progress, downward: true)
                drawReel(themes, context: context, x: width, height: size.height, progress: progress, downward: false)
                context.draw(Text("之旅").font(font).foregroundColor(Color(uiColor: .placeholderText)),
                    at: CGPoint(x: width * 2, y: size.height / 2), anchor: .leading)
            }
            .frame(width: fontSize * 6, height: fontSize * 1.25)
            .clipped()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: running) {
            guard running else { return }
            do {
                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(TripNameSuggestions.holdDuration))
                    places = TripNameSuggestions.roll(from: places.last!, words: TripNameSuggestions.places)
                    themes = TripNameSuggestions.roll(from: themes.last!, words: TripNameSuggestions.themes)
                    started = ProcessInfo.processInfo.systemUptime
                    try await Task.sleep(for: .seconds(TripNameSuggestions.rollDuration))
                    places = [places.last!]; themes = [themes.last!]; started = nil
                }
            } catch {
                places = [places.last!]; themes = [themes.last!]; started = nil
            }
        }
    }

    private func drawReel(_ words: [String], context: GraphicsContext, x: CGFloat, height: CGFloat,
                          progress: Double, downward: Bool) {
        let count = words.count - 1
        for index in words.indices {
            let position = downward ? -Double(index) + Double(count) * progress : Double(index) - Double(count) * progress
            let text = Text(words[index]).font(.system(size: fontSize, weight: .medium))
                .foregroundColor(Color(uiColor: .placeholderText))
            context.draw(text, at: CGPoint(x: x, y: height / 2 + CGFloat(position) * height), anchor: .leading)
        }
    }
}
