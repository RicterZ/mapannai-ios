import SwiftUI

struct JourneyActionStyle: ButtonStyle {
    var compact = false
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(JourneyActionLabelStyle(compact: compact))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color(uiColor: .label))
            .padding(.horizontal, compact ? 10 : 18).padding(.vertical, 12)
            .frame(minHeight: 48)
            .background(Color(uiColor: configuration.isPressed ? .tertiarySystemFill : .systemBackground), in: Capsule())
            .overlay(Capsule().strokeBorder(Color(uiColor: .separator).opacity(0.15), lineWidth: 0.5))
            .shadow(color: .black.opacity(configuration.isPressed ? 0.02 : 0.05), radius: 5, y: 3)
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.4)
    }
}
private struct JourneyActionLabelStyle: LabelStyle {
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: compact ? 4 : 8) {
            configuration.icon.font(.system(size: compact ? 16 : 20, weight: .regular)).frame(width: compact ? 16 : 20)
            configuration.title.fixedSize(horizontal: true, vertical: false)
        }
    }
}
struct JourneyActionGroup<Content: View>: View {
    var compact = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @ViewBuilder var content: Content
    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 10))
        layout { content }
            .buttonStyle(JourneyActionStyle(compact: compact))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct JourneyPlaceGroupHeading: View {
    let title: String
    let count: Int
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).font(.headline).foregroundStyle(.primary)
            Spacer(minLength: 8)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(count)").font(.body.weight(.semibold)).foregroundStyle(.primary)
                Text("个地点").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8).padding(.bottom, 2)
        .accessibilityElement(children: .combine)
        .listRowBackground(Color(uiColor: .systemBackground))
        .listRowSeparator(.hidden)
    }
}

extension ToolbarContent {
    @ToolbarContentBuilder var journeyBareBackground: some ToolbarContent {
        if #available(iOS 26.0, *) { sharedBackgroundVisibility(.hidden) }
        else { self }
    }
}
