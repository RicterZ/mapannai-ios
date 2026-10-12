import SwiftUI

enum TripEditorLayout {
    static let placeholderSize: CGFloat = 19
    static let leadingWidth: CGFloat = 60
    static let iconWidth: CGFloat = 32
    static let fieldSpacing: CGFloat = 12
}

struct TripCreationView: View {
    @ObservedObject var store: AppStore
    var trip: Trip? = nil
    var initial: TripSaveDraft? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title2) private var headingSize = 22
    @ScaledMetric(relativeTo: .body) private var inputSize = 20
    @ScaledMetric(relativeTo: .body) private var compactInputSize = 17
    @FocusState private var nameFocused: Bool
    @State private var name = ""
    @State private var emoji = "✈️"
    @State private var destinations: [TripDestination] = []
    @State private var range = TripDateRange()
    @State private var calendarVisible = false
    @State private var iconPickerVisible = false
    @State private var error: String?
    @State private var initialized = false
    @State private var submitted = false

    // Matches the Web sidebar's predefined trip icons, in the same order.
    private static let tripIcons = [
        "✈️", "🚞", "🚢", "🚗", "🏍️",
        "🏕️", "🏖️", "🗻", "🏯", "🎒",
        "🇨🇳", "🇯🇵", "🇰🇷", "🇸🇬", "🇹🇭",
        "🇺🇸", "🇫🇷", "🇬🇧", "🇮🇹", "🇩🇪",
        "🍜", "🍣", "🍲", "🍛", "🍖",
        "🚲", "🚐", "⛵", "🚠", "🎈",
        "🏜️", "🌋", "🏝️", "🌌", "🌸",
        "🏰", "🗼", "🕌", "⛩️", "🗽",
        "🎿", "🤿", "🏄", "🥾", "♨️",
        "🎭", "🎨", "🎡", "🎪", "🎶",
        "🐼", "🐘", "🐋", "🦒", "🐧",
        "☕", "🍷", "🍺", "🥐", "🍕"
    ]

    private var compact: Bool { nameFocused || calendarVisible }
    private var minimumDays: Int { trip?.minimumEditableDayCount ?? 1 }
    private var canCreate: Bool {
        (trip != nil || (!destinations.isEmpty && destinations.count <= 20 && destinations.allSatisfy(\.isValid))) && range.dayCount >= minimumDays && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && range.isValid && !store.saving && !submitted
    }
    private var pageColor: Color { Color(uiColor: .systemBackground) }

    var body: some View {
        GeometryReader { geometry in
            content.frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .background(pageColor.ignoresSafeArea())
    }

    private var content: some View {
        VStack(spacing: 0) {
            navigation
            ScrollView {
                VStack(alignment: .leading, spacing: compact ? 18 : 28) {
                    if trip == nil {
                    TripDestinationPicker(settings: store.settings, demo: store.demo, selection: $destinations,
                        compact: compact, onSearchFocus: { nameFocused = false; calendarVisible = false })
                        .frame(height: calendarVisible ? 0 : nil).clipped()
                        .accessibilityHidden(calendarVisible)
                    }
                    identity
                    dates
                    if let error { Text(error).font(.footnote).foregroundStyle(.red).accessibilityIdentifier("trip-create-error") }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 24)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(pageColor.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(action: create) {
                Text(trip == nil ? "创建旅途" : "保存旅途").font(.system(size: 18, weight: .semibold))
                    .padding(.vertical, 18).frame(maxWidth: .infinity)
                    .foregroundStyle(canCreate ? Color(uiColor: .systemBackground) : Color(uiColor: .tertiaryLabel))
                    .background(canCreate ? Color(uiColor: .label) : Color(uiColor: .quaternarySystemFill), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain).disabled(!canCreate)
            .accessibilityIdentifier("trip-create-submit")
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, nameFocused ? 12 : 22)
            .frame(maxWidth: 560).frame(maxWidth: .infinity)
            .background(pageColor)
        }
        .onAppear {
            guard !initialized else { return }
            initialized = true
            if let initial {
                name = initial.name; emoji = initial.emoji; destinations = initial.destinations
                range = TripDateRange(savedStart: initial.start, savedEnd: initial.end)
            } else if let trip {
                name = trip.name; emoji = trip.emoji ?? "✈️"; destinations = trip.selectedDestinations
                range = TripDateRange(savedStart: .fromDay(trip.startDate), savedEnd: .fromDay(trip.endDate))
            }
        }
        .onChange(of: nameFocused) { _, focused in
            if focused { calendarVisible = false }
        }
    }

    private var navigation: some View {
        HStack {
            Button { nameFocused = false; dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 22, weight: .regular))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("取消")
                .accessibilityIdentifier("trip-create-cancel").disabled(submitted)
            Spacer(minLength: 0)
            Text(trip == nil ? "新的旅途" : "编辑旅途").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
        }
        .padding(.horizontal, 12).frame(height: 64)
        .frame(maxWidth: 576).frame(maxWidth: .infinity)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !compact { heading("旅途名称") }
            HStack(spacing: TripEditorLayout.fieldSpacing) {
                Button {
                    nameFocused = false
                    iconPickerVisible = true
                } label: {
                    HStack(spacing: 5) {
                        PlaceIconView(emoji: emoji, size: calendarVisible ? 26 : 32)
                            .frame(width: TripEditorLayout.iconWidth)
                        Image(systemName: "chevron.down").font(.system(size: 10)).foregroundStyle(.tertiary)
                    }.frame(width: TripEditorLayout.leadingWidth, height: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("旅行图标：\(emoji)")
                    .accessibilityIdentifier("trip-icon-picker")
                    .popover(isPresented: $iconPickerVisible, arrowEdge: .top) {
                        ScrollView {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 5), spacing: 4) {
                                ForEach(Self.tripIcons, id: \.self) { symbol in
                                    Button {
                                        emoji = symbol
                                        iconPickerVisible = false
                                    } label: {
                                        PlaceIconView(emoji: symbol, size: 30)
                                            .frame(maxWidth: .infinity, minHeight: 44)
                                            .background(emoji == symbol ? Color(uiColor: .quaternarySystemFill) : .clear,
                                                        in: RoundedRectangle(cornerRadius: 12))
                                            .contentShape(Rectangle())
                                    }.buttonStyle(.plain).accessibilityLabel(symbol)
                                        .accessibilityAddTraits(emoji == symbol ? .isSelected : [])
                                        .accessibilityIdentifier("trip-icon-option-\(symbol)")
                                }
                            }.padding(12)
                        }.frame(width: 276, height: 312)
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("trip-icon-panel")
                            .presentationBackground(Color(uiColor: .systemBackground))
                            .presentationCompactAdaptation(.popover)
                    }
                TextField("旅途名称", text: $name, prompt: Text(nameFocused ? "输入旅途名称" : "")
                    .font(.system(size: TripEditorLayout.placeholderSize, weight: .medium)))
                    .font(.system(size: calendarVisible ? compactInputSize : inputSize, weight: .medium))
                    .focused($nameFocused).submitLabel(.done).onSubmit { nameFocused = false }
                    .overlay(alignment: .leading) {
                        if name.isEmpty && !nameFocused {
                            GeometryReader { geometry in
                                let size = TripEditorLayout.placeholderSize
                                if geometry.size.width >= size * 6 {
                                    TripNamePlaceholder(fontSize: size)
                                        .frame(height: geometry.size.height)
                                } else {
                                    Text("输入旅途名称").foregroundStyle(Color(uiColor: .placeholderText))
                                        .font(.system(size: size, weight: .medium))
                                        .lineLimit(1).minimumScaleFactor(0.75)
                                        .frame(height: geometry.size.height)
                                }
                            }.allowsHitTesting(false).accessibilityHidden(true)
                        }
                    }
                    .accessibilityLabel("旅途名称")
                    .accessibilityIdentifier("trip-name-field")
            }
            .padding(.vertical, 8)
            Divider()
        }
    }

    private var dates: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !nameFocused { heading("旅行日期") }
            VStack(spacing: 0) {
                Button {
                    nameFocused = false
                    range.choosingEnd = false
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { calendarVisible.toggle() }
                } label: {
                    HStack(spacing: TripEditorLayout.fieldSpacing) {
                        Image(systemName: "calendar").font(.system(size: 23, weight: .regular))
                            .frame(width: TripEditorLayout.iconWidth)
                            .frame(width: TripEditorLayout.leadingWidth, alignment: .leading)
                        Text(rangeLabel).font(.system(size: inputSize - 1, weight: .semibold)).multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right").font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.tertiary).rotationEffect(.degrees(calendarVisible ? 90 : 0))
                    }.padding(.vertical, 20)
                        .frame(maxWidth: .infinity).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("旅行日期")
                    .accessibilityValue(rangeLabel).accessibilityIdentifier("trip-date-range")
                if calendarVisible {
                    TripRangeCalendar(range: $range) {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { calendarVisible = false }
                    }
                }
            }
            .overlay(alignment: .bottom) { Divider() }
            Text("\(range.start.formatted(.dateTime.year().locale(Locale(identifier: "zh_CN")))) · 共 \(range.dayCount) 天")
                .font(.footnote).foregroundStyle(.secondary).padding(.top, -6)
                .accessibilityIdentifier("trip-date-summary")
            if let trip, range.dayCount < minimumDays {
                Text("至少保留原有 \(trip.minimumEditableDayCount) 天，可整体改期或延长旅途。")
                    .font(.footnote).foregroundStyle(.red).accessibilityIdentifier("trip-minimum-days-error")
            } else if trip != nil {
                Text("已有行程按顺序保留；延长部分为空白日。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if !range.isValid {
                Text("一次最多创建 367 天，请缩短日期范围。")
                    .font(.footnote).foregroundStyle(.red).accessibilityIdentifier("trip-range-error")
            }
        }
    }
    private func heading(_ title: String) -> some View {
        Text(title).font(.system(size: headingSize, weight: .semibold)).tracking(-0.6).accessibilityAddTraits(.isHeader)
    }
    private var rangeLabel: String {
        let crossYear = range.calendar.component(.year, from: range.start) != range.calendar.component(.year, from: range.end)
        let style: Date.FormatStyle = crossYear ? .dateTime.year().month().day() : .dateTime.month().day()
        return "\(range.start.formatted(style.locale(Locale(identifier: "zh_CN")))) — \(range.end.formatted(style.locale(Locale(identifier: "zh_CN"))))"
    }
    private func create() {
        guard canCreate else { return }
        let value = TripSaveDraft(id: initial?.id ?? UUID(), trip: trip,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines), start: range.apiStart, end: range.apiEnd, emoji: emoji, destinations: destinations)
        if store.saveTripInBackground(value) {
            submitted = true; nameFocused = false; dismiss()
        } else { error = store.errorMessage }
    }
}

private struct TripRangeCalendar: View {
    @Binding var range: TripDateRange
    let onDone: () -> Void
    @State private var month: Date = .now
    private var calendar: Calendar { range.calendar }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private var days: [Date?] {
        guard let start = calendar.dateInterval(of: .month, for: month)?.start,
              let count = calendar.range(of: .day, in: .month, for: month)?.count else { return [] }
        let offset = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: offset) + (0..<count).map { calendar.date(byAdding: .day, value: $0, to: start) }
    }
    private var weekdays: [String] {
        var localized = calendar
        localized.locale = Locale(identifier: "zh_CN")
        let names = localized.veryShortStandaloneWeekdaySymbols
        let index = calendar.firstWeekday - 1
        return Array(names[index...] + names[..<index])
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(month.formatted(.dateTime.year().month(.wide).locale(Locale(identifier: "zh_CN")))).font(.headline)
                Spacer()
                monthButton(-1, title: "上个月", symbol: "chevron.left")
                monthButton(1, title: "下个月", symbol: "chevron.right")
            }
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(Array(weekdays.enumerated()), id: \.offset) { _, name in
                    Text(name).font(.caption).foregroundStyle(.tertiary).frame(maxWidth: .infinity, minHeight: 28)
                }
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if let day { dayButton(day) }
                    else { Color.clear.frame(height: 44).accessibilityHidden(true) }
                }
            }
            HStack(alignment: .center) {
                Text(range.choosingEnd ? "再选结束日期；同一天也可。" : "选择出发日期，再选择结束日期。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button("完成", action: onDone).font(.subheadline.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44).buttonStyle(.plain)
                    .accessibilityIdentifier("trip-range-done")
            }
        }.padding(.horizontal, 14).padding(.bottom, 12)
            .onAppear { month = calendar.dateInterval(of: .month, for: range.start)?.start ?? range.start }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("trip-range-calendar")
    }
    private func monthButton(_ direction: Int, title: String, symbol: String) -> some View {
        Button { if let next = calendar.date(byAdding: .month, value: direction, to: month) { month = next } } label: {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).frame(width: 44, height: 44)
        }.buttonStyle(.plain).accessibilityLabel(title)
            .accessibilityIdentifier(direction < 0 ? "trip-month-previous" : "trip-month-next")
    }
    private func dayButton(_ day: Date) -> some View {
        let endpoint = calendar.isDate(day, inSameDayAs: range.start) || calendar.isDate(day, inSameDayAs: range.end)
        let between = day > range.start && day < range.end
        return Button { range.select(day) } label: {
            Text("\(calendar.component(.day, from: day))").font(.body)
                .foregroundStyle(endpoint ? Color(uiColor: .systemBackground) : Color(uiColor: .label))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background {
                    ZStack {
                        HStack(spacing: 0) {
                            Rectangle().fill(between || (day == range.end && range.start < range.end)
                                ? Color(uiColor: .quaternarySystemFill) : .clear)
                            Rectangle().fill(between || (day == range.start && range.start < range.end)
                                ? Color(uiColor: .quaternarySystemFill) : .clear)
                        }.frame(height: 38)
                        if endpoint { Circle().fill(Color(uiColor: .label)).frame(width: 38, height: 38) }
                    }
                }
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel(day.formatted(.dateTime.year().month().day().weekday()))
            .accessibilityValue(endpoint ? "日期范围端点" : between ? "已选范围内" : "")
            .accessibilityAddTraits(endpoint || between ? [.isSelected] : [])
            .accessibilityIdentifier("trip-range-day-\(TripDateRange.apiDate(day, calendar: calendar).dayString)")
    }
}
