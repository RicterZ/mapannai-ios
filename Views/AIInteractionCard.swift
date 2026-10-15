import SwiftUI

struct AIInteractionCard: View {
    let prompt: AIInteractionPrompt
    @ObservedObject var planner: AIPlannerStore
    let store: AppStore
    let record: AIInteractionRecord
    @State private var declined = false
    @State private var selected: [String] = []
    @State private var range = TripDateRange()
    @State private var start = Date()
    @State private var end = Date()
    @State private var day = 0
    @State private var feedback = ""

    private var input: AIInteractionPrompt.Input { prompt.input }
    private var timezone: TimeZone { TimeZone(identifier: input.timezone ?? "UTC") ?? TimeZone(secondsFromGMT: 0)! }
    private var datetimeSelection: AIInteractionSelection {
        let mode = input.mode ?? "date"
        let formatter = AIInteractionPrompt.formatter(format: mode == "time" ? "HH:mm" : mode.hasPrefix("datetime") ? "yyyy-MM-dd'T'HH:mm" : "yyyy-MM-dd", timezone: input.timezone ?? "UTC")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        func combining(_ day: Date, time: Date) -> Date {
            let parts = calendar.dateComponents([.hour, .minute], from: time)
            return calendar.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0, of: day) ?? day
        }
        let first = mode == "time" ? start : combining(range.start, time: start)
        let last = combining(range.end, time: end)
        return .datetime(start: formatter.string(from: first), end: mode.hasSuffix("_range") ? formatter.string(from: last) : nil)
    }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let expired = prompt.expires <= timeline.date
            let inactive = record.ended || prompt.token.isEmpty
            let disabled = inactive || expired || planner.interactionSubmitting || planner.interactionSubmitted || !prompt.supported
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(input.kind == "ask_choice" ? "选择偏好" : input.kind == "ask_datetime" ? "日期与时间" : "行程草案 · 尚未保存")
                    Spacer()
                    Text(declined ? "都不选，文字说明" : record.selection != nil ? "已选择" : inactive || expired ? "未选择，文字说明" : "请选择")
                        .monospacedDigit()
                }.font(.caption).foregroundStyle(.secondary)
                Text(input.question).font(.headline)
                Group {
                    if !prompt.supported {
                        Text("当前交互暂不支持，请在聊天中补充。").font(.subheadline).foregroundStyle(.secondary)
                    } else if input.kind == "ask_choice" {
                        choices
                    } else if input.kind == "ask_datetime" {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("目的地当地时间 · \(input.timezone ?? "")").font(.caption).foregroundStyle(.secondary)
                            if input.mode != "time" {
                                TripRangeCalendar(range: $range, singleDate: input.mode?.hasSuffix("_range") != true, showsFooter: false) {}
                                Text(input.mode?.hasSuffix("_range") == true ? "先选开始日期，再选结束日期" : "选择日期")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if input.mode == "time" || input.mode?.hasPrefix("datetime") == true {
                                DatePicker(input.mode?.hasSuffix("_range") == true ? "开始时间" : "时间", selection: $start, displayedComponents: .hourAndMinute)
                                if input.mode?.hasSuffix("_range") == true {
                                    DatePicker("结束时间", selection: $end, displayedComponents: .hourAndMinute)
                                }
                            }
                        }.environment(\.timeZone, timezone).environment(\.calendar, Calendar(identifier: .gregorian))
                    } else if input.kind == "preview_itinerary" {
                        preview
                    }
                }.disabled(input.kind == "preview_itinerary" ? false : disabled)
                if planner.interaction?.id == prompt.id, let error = planner.interactionError {
                    Text(error).font(.footnote).foregroundStyle(.red).accessibilityIdentifier("ai-interaction-error")
                }
                if !inactive && !expired && record.selection == nil {
                Divider()
                ViewThatFits(in: .horizontal) {
                    actions(horizontal: true)
                    actions(horizontal: false)
                }.disabled(disabled)
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(Color(uiColor: .separator).opacity(0.7), lineWidth: 1) }
        }.accessibilityIdentifier("ai-interaction-card")
            .onAppear(perform: restore)
            .onChange(of: record.selection.map { if case .none = $0 { return true }; return false } ?? false) { _, value in
                if value { declined = true; selected = [] }
            }
            .onChange(of: planner.interactionSubmitted) { _, submitted in
                if submitted, let record = planner.conversation?.interactions?.first(where: { $0.id == prompt.id }), case .none? = record.selection { declined = true; selected = [] }
            }
    }
    @ViewBuilder private func actions(horizontal: Bool) -> some View {
        let layout = horizontal ? AnyLayout(HStackLayout(spacing: 12)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
        layout {
                    if input.kind == "ask_choice" {
                        Button("都不选，文字说明") { submit(.none) }
                            .buttonStyle(.bordered).tint(.primary)
                            .accessibilityIdentifier("ai-interaction-none")
                    }
                    if input.kind == "preview_itinerary" {
                        Button("想调整") { submit(.preview(action: "revise", feedback: feedback)) }
                            .buttonStyle(.bordered)
                    }
                    if horizontal { Spacer(minLength: 0) }
                    Button(planner.interactionSubmitting ? "提交中…" : input.kind == "preview_itinerary" ? "按这个继续" : "确认选择") {
                        switch input.kind {
                        case "ask_choice": submit(.choices(selected))
                        case "ask_datetime": submit(datetimeSelection)
                        default: submit(.preview(action: "continue", feedback: feedback))
                        }
                    }.buttonStyle(.borderedProminent).tint(.primary)
                        .accessibilityIdentifier("ai-interaction-submit")
        }
    }
    private func restore() {
                var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timezone
                range = TripDateRange(calendar: calendar)
                switch record.selection {
                case .none?: declined = true; selected = []
                case .choices(let ids): selected = ids
                case .datetime(let first, let last):
                    let mode = input.mode ?? "date"
                    let f = AIInteractionPrompt.formatter(format: mode == "time" ? "HH:mm" : mode.hasPrefix("datetime") ? "yyyy-MM-dd'T'HH:mm" : "yyyy-MM-dd", timezone: input.timezone ?? "UTC")
                    start = f.date(from: first) ?? .now; end = f.date(from: last ?? first) ?? start
                    range = TripDateRange(start: start, end: end, calendar: calendar)
                case .preview(_, let value): feedback = value
                case nil: break
                }
    }
    private func submit(_ selection: AIInteractionSelection) { planner.submitInteraction(selection, store: store) }
    private var choices: some View {
        VStack(spacing: 0) {
            ForEach(input.options ?? []) { option in
                Button {
                    if input.multiple == true {
                        if selected.contains(option.id) { selected.removeAll { $0 == option.id } }
                        else if selected.count < (input.maxSelections ?? 1) { selected.append(option.id) }
                    } else { selected = [option.id] }
                } label: {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: selected.contains(option.id) ? "checkmark.circle.fill" : "circle").font(.title3)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(option.label).font(.body)
                            if let description = option.description, !description.isEmpty {
                                Text(description).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }.foregroundStyle(.primary).padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading)

                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityAddTraits(selected.contains(option.id) ? .isSelected : [])
                if option.id != input.options?.last?.id { Divider().padding(.leading, 36) }
            }
            if input.multiple == true { Text("最多选择\(input.maxSelections ?? 1)项").font(.caption).foregroundStyle(.secondary) }
        }
    }
    private var preview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(input.title ?? "行程草案").font(.headline)
            if let days = input.days, !days.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(days.indices, id: \.self) { index in
                            Button(days[index].date) { day = index }
                                .font(.footnote).padding(.horizontal, 10).padding(.vertical, 8)
                                .background(day == index ? Color.primary : Color(uiColor: .tertiarySystemFill), in: Capsule())
                                .foregroundStyle(day == index ? Color(uiColor: .systemBackground) : .primary)
                                .buttonStyle(.plain)
                        }
                    }
                }
                let current = days[min(day, days.count - 1)]
                Text(current.title).font(.subheadline.weight(.medium))
                ForEach(Array(current.places.enumerated()), id: \.offset) { index, place in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)").foregroundStyle(.secondary).monospacedDigit()
                        Text(place)
                    }.font(.subheadline)
                }
            }
            TextField("想调整哪里？（可选）", text: $feedback, axis: .vertical)
                .lineLimit(2...5).padding(12).background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                .disabled(record.ended || prompt.token.isEmpty || planner.interactionSubmitted)
                .onChange(of: feedback) { _, value in if value.count > 2000 { feedback = String(value.prefix(2000)) } }
        }
    }
}
