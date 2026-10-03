import SwiftUI

/// Clock components remain local to the itinerary day; no timezone conversion.
struct RouteScheduleEditor: View {
    @ObservedObject var store: AppStore
    let request: RouteScheduleRequest
    @Environment(\.dismiss) private var dismiss
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
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(request.fromTitle).font(.body)
                        if let to = request.toTitle {
                            Label(to, systemImage: "arrow.down").font(.body).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 4)
                }
                if request.isTransport {
                    Section("交通") {
                        Picker(selection: $mode) {
                            ForEach(TransportMode.allCases) { mode in Label(mode.label, systemImage: mode.symbol).tag(mode) }
                        } label: { Text("交通方式") }
                        .accessibilityIdentifier("schedule-mode")
                        HStack {
                            Text("线路 / 车次号")
                            Spacer()
                            TextField("未设置", text: $serviceNumber)
                                .multilineTextAlignment(.trailing)
                                .accessibilityIdentifier("schedule-service")
                        }
                    }
                }
                Section {
                    Toggle(request.isTransport ? "出发时间" : "游览时间", isOn: $timeEnabled)
                        .accessibilityIdentifier("schedule-time-toggle")
                    if timeEnabled {
                        DatePicker("时间", selection: $time, displayedComponents: .hourAndMinute)
                            .environment(\.locale, Locale(identifier: "zh_CN"))
                            .accessibilityIdentifier("schedule-time")
                    }
                    HStack {
                        Text(request.isTransport ? "交通时长" : "游玩时长")
                        Spacer()
                        TextField("未设置", text: $duration).keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing).frame(width: 90)
                            .accessibilityIdentifier("schedule-duration")
                        Text("分钟").foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("时间按行程当天的当地时间填写，时长为计划安排。")
                }
                Section("备注") {
                    TextField("入口、站台或预约事项", text: $note, axis: .vertical)
                        .lineLimit(3...6).accessibilityIdentifier("schedule-note")
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                if leg != nil || (!request.isTransport && (!stop.summary.isEmpty || stop.note != nil)) {
                    Section {
                        Button("清除安排", role: .destructive) { save(clear: true) }
                            .accessibilityIdentifier("schedule-clear")
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .disabled(submitting)
            .navigationTitle(request.isTransport ? "交通安排" : "游览安排")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("取消").disabled(submitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save(clear: false) } label: { Image(systemName: "checkmark") }
                        .accessibilityLabel("保存").accessibilityIdentifier("schedule-save")
                        .disabled(submitting || store.saving)
                }
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

struct RouteTransportRow: View {
    let leg: ChainLeg?
    let distance: String?
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: leg?.mode.symbol ?? "arrow.down").frame(width: 18)
                    Text(leg?.mode.label ?? "无交通安排")
                    if let service = leg?.serviceNumber { Text(service).foregroundStyle(.primary).lineLimit(1) }
                    Spacer(minLength: 4)
                    if let summary = leg?.summary, !summary.isEmpty {
                        Text(summary).font(.caption).monospacedDigit().fixedSize()
                    } else {
                        Image(systemName: "chevron.right").font(.caption2)
                    }
                }
                if let distance { Text(distance).monospacedDigit().padding(.leading, 26) }
                if let note = leg?.note { Text(note).lineLimit(2).padding(.leading, 26) }
            }
            .font(.footnote).foregroundStyle(.secondary)
            .padding(.horizontal, 10).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).accessibilityLabel("编辑交通安排")
            .padding(.leading, 28).padding(.vertical, 5)
    }
}
