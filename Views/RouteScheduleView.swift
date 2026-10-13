import SwiftUI

/// Clock components remain local to the itinerary day; no timezone conversion.
struct RouteScheduleEditor: View {
    @ObservedObject var store: AppStore
    let request: RouteScheduleRequest
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var mode: TransportMode = .walking
    @State private var serviceNumber = ""
    @State private var timeEnabled = false
    @State private var time = Date.now
    @State private var duration = ""
    @State private var note = ""
    @State private var error: String?
    @State private var submitting = false
    private var leg: ChainLeg? { request.isTransport ? request.route.leg(at: request.position) : nil }
    private var stop: ChainStop { request.route.stops[request.position] }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    endpoints
                    if request.isTransport {
                        transportModes
                        Divider()
                        HStack(spacing: 16) {
                            Text("线路 / 车次").foregroundStyle(.secondary)
                            TextField("选填", text: $serviceNumber)
                                .multilineTextAlignment(.trailing)
                                .accessibilityIdentifier("schedule-service")
                        }.frame(minHeight: 44)
                    }
                    Divider()
                    VStack(spacing: 16) {
                        HStack(spacing: 12) {
                            Toggle(request.isTransport ? "出发时间" : "游览时间", isOn: $timeEnabled)
                                .labelsHidden().accessibilityLabel(request.isTransport ? "设置出发时间" : "设置游览时间")
                                .accessibilityIdentifier("schedule-time-toggle")
                            Text(request.isTransport ? "出发时间" : "游览时间")
                            Spacer(minLength: 0)
                            if timeEnabled {
                                DatePicker("时间", selection: $time, displayedComponents: .hourAndMinute)
                                    .labelsHidden().environment(\.locale, Locale(identifier: "zh_CN"))
                                    .accessibilityIdentifier("schedule-time")
                            } else { Text("未设置").foregroundStyle(.tertiary) }
                        }
                        HStack(spacing: 8) {
                            Text(request.isTransport ? "预计时长" : "游玩时长")
                            Spacer(minLength: 12)
                            TextField("选填", text: $duration).keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing).frame(width: 72)
                                .accessibilityIdentifier("schedule-duration")
                            Text("分钟").foregroundStyle(.secondary)
                        }.frame(minHeight: 44)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        Text("备注").font(.subheadline).foregroundStyle(.secondary)
                        TextField(request.isTransport ? "站台、集合点或其他提醒" : "入口、预约或其他提醒", text: $note, axis: .vertical)
                            .lineLimit(request.isTransport ? 2...5 : 5...8)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityIdentifier("schedule-note")
                    }
                    Text("按行程当天的当地时间填写")
                        .font(.caption).foregroundStyle(.tertiary)
                    if let error { Text(error).font(.footnote).foregroundStyle(.red).accessibilityIdentifier("schedule-error") }
                    if leg != nil || (!request.isTransport && (!stop.summary.isEmpty || stop.note != nil)) {
                        Button("清除安排", role: .destructive) { save(clear: true) }
                            .font(.subheadline).frame(maxWidth: .infinity, minHeight: 44)
                            .accessibilityIdentifier("schedule-clear")
                    }
                    saveButton
                }.font(.body).padding(.horizontal, 24).padding(.vertical, 16)
                    .frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("schedule-editor-scroll")
            .background(Color(uiColor: .systemBackground))
            .scrollDismissesKeyboard(.interactively)
            .disabled(submitting)
            .navigationTitle(request.isTransport ? "交通安排" : "游览安排")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(uiColor: .systemBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(Color(uiColor: .label))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityLabel("取消").accessibilityIdentifier("schedule-cancel").disabled(submitting)
                }.journeyBareBackground
            }
            .onAppear {
                mode = leg?.mode ?? .walking; serviceNumber = leg?.serviceNumber ?? ""
                let start = request.isTransport ? leg?.startTime : stop.startTime
                let minutes = request.isTransport ? leg?.durationMinutes : stop.durationMinutes
                note = (request.isTransport ? leg?.note : stop.note) ?? ""
                duration = minutes.map(String.init) ?? ""
                timeEnabled = start != nil
                if let start {
                    let parts = start.split(separator: ":").compactMap { Int($0) }
                    if parts.count == 2 { time = Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: .now) ?? .now }
                }
            }
        }
        .interactiveDismissDisabled(submitting)
    }
    private var saveButton: some View {
        JourneyEditorSubmit(title: "保存安排", enabled: !submitting && !store.saving,
            identifier: "schedule-save", background: Color(uiColor: .systemBackground)) { save(clear: false) }
    }
    private var endpoints: some View {
        HStack(spacing: 16) {
            Text(request.fromTitle).frame(maxWidth: .infinity, alignment: .leading)
            if let to = request.toTitle {
                Image(systemName: "arrow.right").font(.subheadline.weight(.regular))
                    .foregroundStyle(.tertiary).accessibilityHidden(true)
                Text(to).frame(maxWidth: .infinity, alignment: .trailing)
            }
        }.font(request.isTransport ? .headline : .title2.weight(.semibold))
            .lineLimit(2).padding(.vertical, 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(request.toTitle.map { "从\(request.fromTitle)到\($0)" } ?? request.fromTitle)
    }
    private var transportModes: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: typeSize.isAccessibilitySize ? 2 : 5), spacing: 8) {
            ForEach(TransportMode.allCases) { option in
                Button { mode = option } label: {
                    VStack(spacing: 9) {
                        Image(systemName: option.symbol).font(.system(size: 22, weight: .regular))
                            .frame(height: 26)
                        Text(option.label).font(.caption)
                    }.frame(maxWidth: .infinity, minHeight: 64)
                        .foregroundStyle(mode == option ? Color(uiColor: .label) : Color(uiColor: .secondaryLabel))
                        .background(mode == option ? Color(uiColor: .quaternarySystemFill) : .clear,
                            in: RoundedRectangle(cornerRadius: 16))
                        .contentShape(RoundedRectangle(cornerRadius: 16))
                }.buttonStyle(.plain).accessibilityLabel(option.label)
                    .accessibilityAddTraits(mode == option ? .isSelected : [])
                    .accessibilityIdentifier("schedule-mode-\(option.rawValue)")
            }
        }.accessibilityIdentifier("schedule-mode")
    }
    private func save(clear: Bool) {
        let cleanedDuration = duration.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clear || cleanedDuration.isEmpty || (Int(cleanedDuration).map { $0 >= 0 } == true) else {
            error = "请填写有效的整数分钟数"; return
        }
        guard clear || (serviceNumber.count <= 120 && note.count <= 4000) else {
            error = "线路 / 车次号最多120字，备注最多4000字"; return
        }
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        let clock = String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
        let null = NSNull()
        var fields: [String: Any] = [
            "startTime": !clear && timeEnabled ? clock as Any : null,
            "durationMinutes": !clear ? Int(cleanedDuration).map { $0 as Any } ?? null : null,
            "note": !clear && !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? note.trimmingCharacters(in: .whitespacesAndNewlines) as Any : null
        ]
        let key: String
        if request.isTransport {
            key = "legs"
            if clear { fields = ["remove": true] }
            else { fields["mode"] = mode.rawValue; fields["serviceNumber"] = serviceNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? null : serviceNumber.trimmingCharacters(in: .whitespacesAndNewlines) as Any }
            fields["fromStopId"] = stop.id; fields["toStopId"] = request.route.stops[request.position + 1].id
        } else { key = "stops"; fields["stopId"] = stop.id }
        submitting = true
        Task {
            if await store.saveRouteSchedule(request, patch: [key: [fields]]) { dismiss() }
            else { error = store.errorMessage ?? "保存失败，请重试" }
            submitting = false
        }
    }
}

struct TransportArtwork: View {
    let mode: TransportMode
    var size: CGFloat = 21
    private var emoji: String? {
        switch mode {
        case .train: "🚞"
        case .subway: "🚉"
        case .driving, .taxi: "🚗"
        case .flight: "✈️"
        case .ferry: "🚢"
        case .cycling: "🚲"
        default: nil
        }
    }
    var body: some View {
        if let emoji { PlaceIconView(emoji: emoji, size: size) }
        else { Image(systemName: mode.symbol).font(.system(size: size * 0.8)).frame(width: size, height: size).accessibilityHidden(true) }
    }
}

struct ItineraryNote: View {
    let text: String
    var allowsExpansion = true
    var collapsedLineLimit = 2
    @State private var expanded = false
    @State private var fullHeight: CGFloat = 0
    @State private var collapsedHeight: CGFloat = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text).font(.footnote).foregroundStyle(.secondary).lineLimit(expanded ? nil : collapsedLineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    Text(text).font(.footnote).fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
                        .hidden().accessibilityHidden(true)
                }
                .background {
                    Text(text).font(.footnote).lineLimit(collapsedLineLimit).fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { collapsedHeight = $0 }
                        .hidden().accessibilityHidden(true)
                }
            if allowsExpansion && fullHeight > collapsedHeight + 1 {
                Button(expanded ? "收起备注" : "展开备注") { expanded.toggle() }
                    .font(.caption).foregroundStyle(.secondary).buttonStyle(.plain)
            }
        }.onChange(of: text) { _, _ in expanded = false }
    }
}

struct RouteTransportRow: View {
    let leg: ChainLeg?
    let distance: String?
    let tint: Color
    let action: () -> Void
    var body: some View {
        Button(action: action) {
        HStack(alignment: .center, spacing: 4) {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                if let leg { TransportArtwork(mode: leg.mode) }
                else { Image(systemName: "arrow.down").foregroundStyle(.secondary) }
                Text([leg?.mode.label ?? "无交通安排", leg?.serviceNumber].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.footnote.weight(.semibold)).foregroundStyle(.primary)
            }
            let metadata = [leg?.startTime.map { $0 + " 出发" }, leg?.durationMinutes.map { "计划 " + RouteScheduleText.duration($0) }, distance]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            if !metadata.isEmpty { Text(metadata).font(.caption).foregroundStyle(.secondary).monospacedDigit() }
            if let note = leg?.note, !note.isEmpty { ItineraryNote(text: note, allowsExpansion: false) }
        }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
        }.padding(12)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel("编辑交通安排")
            .accessibilityIdentifier("transport-edit")
            .accessibilityAction(named: "编辑交通安排", action)
            .padding(.leading, 33).padding(.top, 4).padding(.bottom, 12)
    }
}
