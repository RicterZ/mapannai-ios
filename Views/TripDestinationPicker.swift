import SwiftUI
import UIKit

struct TripDestinationPicker: View {
    @ObservedObject var settings: Settings
    let demo: Bool
    @Binding var selection: [TripDestination]
    let compact: Bool
    let onSearchFocus: () -> Void
    @State private var focused = false
    @State private var query = ""
    @State private var results: [TripDestination] = []
    @State private var loading = false
    @State private var error: String?
    @State private var retry = 0
    @State private var searchFieldSize = CGSize.zero
    @ScaledMetric(relativeTo: .title2) private var headingSize = 22

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !compact || selection.isEmpty {
                Text("目的地").font(.system(size: headingSize, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: 12) {
                if compact && !focused && !selection.isEmpty {
                    HStack {
                        Text(selection.map(\.name).joined(separator: " · "))
                            .font(.subheadline.weight(.medium)).lineLimit(2)
                        Spacer(minLength: 8)
                        Text("\(selection.count)处").font(.caption).foregroundStyle(.secondary)
                    }.frame(minHeight: 32)
                } else {
                    ForEach(Array(selection.enumerated()), id: \.element.coordinateKey) { index, value in
                        HStack(spacing: 12) {
                            Text(String(format: "%02d", index + 1)).font(.caption.monospacedDigit())
                                .foregroundStyle(.tertiary)
                            Text(value.name).font(.body.weight(.medium)).frame(maxWidth: .infinity, alignment: .leading)
                            Button { selection.removeAll { $0.coordinateKey == value.coordinateKey } } label: {
                                Image(systemName: "xmark").font(.system(size: 12, weight: .medium))
                                    .frame(width: 44, height: 44).contentShape(Rectangle())
                            }.buttonStyle(.plain).foregroundStyle(.secondary)
                                .accessibilityLabel("移除目的地 \(value.name)")
                                .accessibilityIdentifier("trip-destination-remove-\(index)")
                        }
                        Divider()
                    }
                    HStack(spacing: TripEditorLayout.fieldSpacing) {
                        Image(systemName: "magnifyingglass").font(.system(size: 22)).accessibilityHidden(true)
                            .frame(width: TripEditorLayout.iconWidth)
                            .frame(width: TripEditorLayout.leadingWidth, alignment: .leading)
                        DestinationSearchField(placeholder: selection.isEmpty ? "搜索城市或省份" : "添加另一处目的地",
                            text: $query, focused: Binding(get: { focused }, set: { focused = $0 }),
                            enabled: selection.count < 20)
                            .accessibilityIdentifier("trip-destination-search")
                            .disabled(selection.count >= 20)
                            .frame(minHeight: 44)
                            .onGeometryChange(for: CGSize.self) { $0.size } action: { searchFieldSize = $0 }
                            .overlay(alignment: .topLeading) {
                                if focused && (!results.isEmpty || error != nil) {
                                    resultMenu
                                        .frame(width: searchFieldSize.width + 24)
                                        .offset(x: -24, y: searchFieldSize.height + 6)
                                }
                            }
                            .zIndex(1)
                        if loading { ProgressView().accessibilityLabel("搜索中") }
                    }.frame(minHeight: 44)
                    .zIndex(1)
                }
            }
            .padding(.vertical, compact ? 12 : 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: focused) { _, value in if value { onSearchFocus() } }
        .onChange(of: query) { _, value in if value.count > 200 { query = String(value.prefix(200)) } }
        .onChange(of: [settings.baseURL, settings.token]) { _, _ in
            selection = []; results = []; error = nil
        }
        .task(id: [query, settings.baseURL, settings.token, String(retry)]) {
            await search()
        }
    }

    private var resultMenu: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let error {
                    HStack(alignment: .top, spacing: 12) {
                        Text(error).font(.footnote).foregroundStyle(.secondary)
                            .accessibilityIdentifier("trip-destination-error")
                        Spacer(minLength: 0)
                        Button("重试") { retry += 1 }.font(.footnote)
                    }.padding(14)
                }
                ForEach(Array(results.enumerated()), id: \.offset) { index, result in
                    Button {
                        guard selection.count < 20, !selection.contains(where: { $0.coordinateKey == result.coordinateKey }) else { return }
                        selection.append(result); results = []; query = ""; error = nil; loading = false; focused = false
                    } label: {
                        HStack(spacing: 12) {
                            Text(result.name).font(.system(size: 19, weight: .medium))
                                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                            if selection.contains(where: { $0.coordinateKey == result.coordinateKey }) {
                                Image(systemName: "checkmark").font(.subheadline)
                            }
                        }.foregroundStyle(.primary).padding(.horizontal, 14)
                            .padding(.vertical, 12).frame(minHeight: 52).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .disabled(selection.count >= 20 || selection.contains { $0.coordinateKey == result.coordinateKey })
                        .accessibilityIdentifier("trip-destination-result-\(index)")
                    if index < results.count - 1 { Divider().padding(.horizontal, 14) }
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: error != nil ? 80 : min(224, CGFloat(results.count) * 53))
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Color(uiColor: .separator).opacity(0.35), lineWidth: 0.5) }
        .shadow(color: .black.opacity(0.07), radius: 8, y: 3)
        .accessibilityIdentifier("trip-destination-menu")
    }

    @MainActor private func search() async {
        results = []; error = nil; loading = false
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        loading = true
        let client = APIClient(baseURL: settings.baseURL, token: settings.token)
        do {
            try await Task.sleep(for: .milliseconds(400))
            let values: [TripDestination]
            if demo {
                // Read-only fixture; never searches or writes the configured production service.
                values = [TripDestination(name: "日本京都府京都市", latitude: 35.0116, longitude: 135.7681),
                          TripDestination(name: "日本东京都", latitude: 35.6762, longitude: 139.6503),
                          TripDestination(name: "重庆市", latitude: 29.563, longitude: 106.5516)]
                    .filter { $0.name.contains(text) }
            } else { values = try await client.searchDestinations(text) }
            try Task.checkCancellation()
            results = values; loading = false
            if values.isEmpty { error = "未找到省市，请尝试完整名称" }
        } catch {
            guard !Task.isCancelled else { return }
            loading = false; self.error = error.localizedDescription
        }
    }
}

// Search is debounced while typing; Return must not dismiss or submit the field.
private struct DestinationSearchField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    @Binding var focused: Bool
    let enabled: Bool
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.font = .systemFont(ofSize: TripEditorLayout.placeholderSize, weight: .medium)
        field.returnKeyType = .search
        field.autocorrectionType = .no
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.accessibilityIdentifier = "trip-destination-search"
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        return field
    }
    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        field.placeholder = placeholder
        field.isEnabled = enabled
        if field.text != text, field.markedTextRange == nil { field.text = text }
        if !focused, field.isFirstResponder { field.resignFirstResponder() }
    }
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: DestinationSearchField
        init(_ parent: DestinationSearchField) { self.parent = parent }
        @objc func changed(_ field: UITextField) { parent.text = field.text ?? "" }
        func textFieldDidBeginEditing(_ textField: UITextField) { parent.focused = true }
        func textFieldDidEndEditing(_ textField: UITextField) { parent.focused = false }
        func textFieldShouldReturn(_ textField: UITextField) -> Bool { false }
    }
}
