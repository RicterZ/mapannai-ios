import SwiftUI

/// Clock components remain local to the itinerary day; no timezone conversion.
struct RouteScheduleEditor: View {
    @ObservedObject var store: AppStore
    let request: RouteScheduleRequest
    var embedded = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var landscapeEditor = false
    @State private var mode: TransportMode = .walking
    @State private var serviceNumber = ""
    @State private var timeEnabled = false
    @State private var time = Date.now
    @State private var duration = ""
    @State private var note = ""
    @State private var isHighlight = false
    @State private var error: String?
    @State private var submitting = false
    private var leg: ChainLeg? { request.isTransport ? request.route.leg(at: request.position) : nil }
    private var stop: ChainStop { request.route.stops[request.position] }
    var body: some View {
        Group {
            if embedded { editorContent }
            else { NavigationStack { editorContent } }
        }.interactiveDismissDisabled(submitting)
    }
    private var editorContent: some View {
        Group {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    endpoints
                    let layout = landscapeEditor && !typeSize.isAccessibilitySize ? AnyLayout(HStackLayout(alignment: .top, spacing: 48)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 22))
                    layout {
                    VStack(alignment: .leading, spacing: 22) {
                    if request.isTransport {
                        transportModes
                        HStack(spacing: 16) {
                            Text("线路 / 车次")
                            TextField("选填", text: $serviceNumber)
                                .multilineTextAlignment(.trailing)
                                .accessibilityIdentifier("schedule-service")
                        }.frame(minHeight: 44).padding(.top, 12)
                            .overlay(alignment: .bottom) { Divider() }
                    }
                    Toggle(request.isTransport ? "重点行程" : "重点地点", isOn: $isHighlight)
                        .accessibilityIdentifier("schedule-highlight")
                    if !request.isTransport { Divider() }
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            Text(request.isTransport ? "出发时间" : "游览时间")
                            Spacer(minLength: 0)
                            if timeEnabled {
                                DatePicker("时间", selection: $time, displayedComponents: .hourAndMinute)
                                    .labelsHidden().environment(\.locale, Locale(identifier: "zh_CN"))
                                    .accessibilityIdentifier("schedule-time")
                            } else {
                                Button("未设置") { timeEnabled = true }.foregroundStyle(.secondary)
                                    .accessibilityIdentifier("schedule-time-toggle")
                            }
                            Menu {
                                Button(timeEnabled ? "清除时间" : "设置时间") { timeEnabled.toggle() }
                            } label: { Image(systemName: "clock").font(.footnote).foregroundStyle(.primary) }
                                .accessibilityLabel("时间选项")
                        }.frame(minHeight: 58)
                        Divider()
                        HStack(spacing: 8) {
                            Text(request.isTransport ? "预计时长" : "游玩时长")
                            Spacer(minLength: 12)
                            TextField("选填", text: $duration).keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing).frame(width: 72)
                                .accessibilityIdentifier("schedule-duration")
                            Text("分钟").foregroundStyle(.secondary)
                        }.frame(minHeight: 58)
                    }
                    }.frame(maxWidth: .infinity, alignment: .topLeading)
                    VStack(alignment: .leading, spacing: 22) {
                    if !landscapeEditor { Divider() }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("备注").font(.subheadline).foregroundStyle(.secondary)
                        TextField(request.isTransport ? "站台、集合点或其他提醒" : "入口、预约或其他提醒", text: $note, axis: .vertical)
                            .lineLimit(5...8)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityIdentifier("schedule-note")
                    }
                    Text("按行程当天的当地时间填写")
                        .font(.caption).foregroundStyle(.tertiary)
                    if let error { Text(error).font(.footnote).foregroundStyle(.red).accessibilityIdentifier("schedule-error") }
                    if leg != nil || (!request.isTransport && (!stop.summary.isEmpty || stop.note != nil || stop.isHighlight == true)) {
                        Button("清除安排", role: .destructive) { save(clear: true) }
                            .font(.subheadline).frame(maxWidth: .infinity, minHeight: 44)
                            .accessibilityIdentifier("schedule-clear")
                    }
                    }.frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }.font(.subheadline).padding(.horizontal, 24).padding(.vertical, 16)
                    .frame(maxWidth: landscapeEditor && !typeSize.isAccessibilitySize ? 1040 : 560).frame(maxWidth: .infinity)
            }
            .onGeometryChange(for: Bool.self) {
                UIDevice.current.userInterfaceIdiom == .pad && $0.size.width >= 900 && $0.size.width > $0.size.height
            } action: { landscapeEditor = $0 }
            .accessibilityIdentifier("schedule-editor-scroll")
            .background(Color(uiColor: .systemBackground))
            .scrollDismissesKeyboard(.interactively)
            .disabled(submitting)
            .navigationTitle(request.isTransport ? "交通安排" : "游览安排")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden()
            .toolbarBackground(Color(uiColor: .systemBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { goBack() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(Color(uiColor: .label))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityLabel("返回").accessibilityIdentifier("schedule-cancel").disabled(submitting)
                }.journeyBareBackground
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.itineraryDraftOnly ? "完成" : "保存") { save(clear: false) }
                        .buttonStyle(.plain).foregroundStyle(Color(uiColor: .label)).tint(Color(uiColor: .label))
                        .disabled(submitting || store.saving)
                        .accessibilityIdentifier("schedule-save")
                }.journeyBareBackground
            }
            .onAppear {
                mode = leg?.mode ?? .walking; serviceNumber = leg?.serviceNumber ?? ""
                let start = request.isTransport ? leg?.startTime : stop.startTime
                let minutes = request.isTransport ? leg?.durationMinutes : stop.durationMinutes
                note = (request.isTransport ? leg?.note : stop.note) ?? ""
                isHighlight = (request.isTransport ? leg?.isHighlight : stop.isHighlight) == true
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
    private func goBack() {
        dismiss()
    }
    private var endpoints: some View {
        HStack(spacing: 16) {
            Text(request.fromTitle)
            if let to = request.toTitle {
                Image(systemName: "arrow.right").font(.subheadline.weight(.regular))
                    .foregroundStyle(.tertiary).accessibilityHidden(true)
                Text(to)
            }
        }.font(request.isTransport ? .headline : .title2.weight(.semibold))
            .lineLimit(2).frame(maxWidth: .infinity, alignment: request.isTransport ? .center : .leading).padding(.vertical, 8)
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
                            in: RoundedRectangle(cornerRadius: 10))
                        .contentShape(RoundedRectangle(cornerRadius: 10))
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
            "isHighlight": !clear && isHighlight,
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
            if await store.saveRouteSchedule(request, patch: [key: [fields]]) { goBack() }
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
    var editing = true
    let action: () -> Void
    var body: some View {
        Group {
        if editing || leg != nil || distance != nil {
        HStack(alignment: .center, spacing: 4) {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                if let leg { TransportArtwork(mode: leg.mode) }
                else { Image(systemName: "arrow.triangle.branch").foregroundStyle(.secondary) }
                Text([leg?.mode.label ?? (editing ? "安排交通" : "交通"), distance].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.footnote).foregroundStyle(.primary)
                if let leg, let service = leg.serviceNumber, !service.isEmpty {
                    Text(service).font(.caption.weight(.medium)).lineLimit(1)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .foregroundStyle(leg.mode.itineraryColor)
                        .background(leg.mode.itineraryColor.opacity(0.16), in: Capsule())
                        .accessibilityIdentifier("transport-service-tag")
                }
            }
            let metadata = [leg?.startTime.map { $0 + " 出发" }, leg?.durationMinutes.map { "计划 " + RouteScheduleText.duration($0) }]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            if !metadata.isEmpty { Text(metadata).font(.caption).foregroundStyle(.secondary).monospacedDigit() }
            if let note = leg?.note, !note.isEmpty { ItineraryNote(text: note, allowsExpansion: false) }
        }.frame(maxWidth: .infinity, alignment: .leading)
                if editing { Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 28)
                    .contentShape(Rectangle())
                }
        }.padding(12)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        }
            .contentShape(Rectangle())
            .onTapGesture { if editing { action() } }
            .accessibilityLabel(editing ? "编辑交通安排" : "交通安排")
            .accessibilityIdentifier("transport-edit")
            .accessibilityAction(named: "编辑交通安排") { if editing { action() } }
            .padding(.leading, editing ? 0 : 33).padding(.top, editing ? 8 : 4).padding(.bottom, 12)
    }
}

extension TransportMode {
    var itineraryColor: Color {
        switch self {
        case .walking: .green
        case .cycling: .mint
        case .driving: .blue
        case .taxi: .orange
        case .bus: .teal
        case .subway: .indigo
        case .train: .brown
        case .flight: .cyan
        case .ferry: .purple
        case .other: .gray
        }
    }
}
