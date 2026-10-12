import SwiftUI

struct JourneyEditorHeading: View {
    let title: String
    @ScaledMetric(relativeTo: .title2) private var size = 22
    var body: some View {
        Text(title).font(.system(size: size, weight: .semibold))
            .foregroundStyle(Color(uiColor: .label)).accessibilityAddTraits(.isHeader)
    }
}
struct JourneyEditorCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}
struct JourneyEditorSubmit: View {
    let title: String
    let enabled: Bool
    let identifier: String
    var background: Color = Color(uiColor: .systemGroupedBackground)
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 18, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 58)
                .foregroundStyle(enabled ? Color(uiColor: .systemBackground) : Color(uiColor: .tertiaryLabel))
                .background(enabled ? Color(uiColor: .label) : Color(uiColor: .quaternarySystemFill), in: Capsule())
                .contentShape(Capsule())
        }.buttonStyle(.plain).disabled(!enabled).accessibilityIdentifier(identifier)
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 12)
            .frame(maxWidth: 560).frame(maxWidth: .infinity)
            .background(background)
    }
}
