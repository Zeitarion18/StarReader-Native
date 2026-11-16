import SwiftUI
import Charts

struct ReadingStatisticsView: View {
    @Environment(\.readerPalette) private var palette
    @ObservedObject var store: LibraryStore

    @State private var graphPeriod = 7
    @State private var graphMode = 0
    @State private var calendarMonthOffset = 0
    @State private var selectedDay: String?

    private let calendar = Calendar.current
    private var currentDay: Date { calendar.startOfDay(for: Date()) }
    private var weekStart: Date {
        calendar.date(byAdding: .day, value: -6, to: currentDay) ?? currentDay
    }
    private var monthStart: Date {
        calendar.dateInterval(of: .month, for: currentDay)?.start ?? currentDay
    }

    private var stats: ReadingStatistics { store.readingStats }

    private struct GraphPoint: Identifiable {
        let date: Date
        let minutes: Double
        let pages: Double
        var id: Date { date }
    }

    private var graphPoints: [GraphPoint] {
        (0..<graphPeriod).compactMap { index -> GraphPoint? in
            guard let day = calendar.date(
                byAdding: .day, value: index - (graphPeriod - 1), to: currentDay
            ) else { return nil }
            let entry = stats.days[ReadingStatistics.dayKey(for: day)] ?? .init()
            return GraphPoint(
                date: day,
                minutes: entry.seconds / 60,
                pages: entry.newPages
            )
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 21) {
                introduction
                timeSummary
                pageSummary
                graphSection
                calendarSection
                readingProgressSection
                habitsSection
                Text("Учёт начался с версии 0.5.3. Ранее прочитанные страницы и время чтения задним числом не восстанавливаются. Данные сохраняются на устройстве и в ZIP-резервных копиях.")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 15)
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 18)
            .padding(.top, 20)
        }
        .scrollIndicators(.hidden)
        .background(palette.background.ignoresSafeArea())
        .navigationTitle("Статистика")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(palette.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .tint(palette.accent)
        .preferredColorScheme(palette.colorScheme)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("МОЯ АКТИВНОСТЬ", systemImage: "books.vertical")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.6)
                .foregroundStyle(palette.accent)
            Text("Статистика чтения")
                .font(.system(size: 29, weight: .bold, design: .rounded))
                .foregroundStyle(palette.text)
            Text("Твои главы, страницы и время — без подписки и облака")
                .font(.system(size: 13))
                .foregroundStyle(palette.secondary)
        }
    }

    private var timeSummary: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionTitle("Время чтения", icon: "clock")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                summaryCard("Сегодня", value: readableTime(stats.seconds(
                    from: currentDay, through: currentDay
                )), subtitle: "Активное чтение", symbol: "sun.max")
                summaryCard("За 7 дней", value: readableTime(stats.seconds(
                    from: weekStart, through: currentDay
                )), subtitle: "Эта неделя", symbol: "calendar")
                summaryCard("За месяц", value: readableTime(stats.seconds(
                    from: monthStart, through: currentDay
                )), subtitle: "Текущий месяц", symbol: "calendar.badge.clock")
                summaryCard("Всего", value: readableTime(stats.totalSeconds),
                            subtitle: "С начала учёта", symbol: "infinity")
            }
        }
    }

    private var pageSummary: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionTitle("Новые прочитанные страницы", icon: "book.pages")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                summaryCard("Сегодня", value: readablePages(stats.pages(
                    from: currentDay, through: currentDay
                )), subtitle: "Без повторного счёта", symbol: "book")
                summaryCard("За 7 дней", value: readablePages(stats.pages(
                    from: weekStart, through: currentDay
                )), subtitle: "Новые страницы", symbol: "books.vertical")
                summaryCard("За месяц", value: readablePages(stats.pages(
                    from: monthStart, through: currentDay
                )), subtitle: "Новые страницы", symbol: "calendar")
                summaryCard("Всего", value: readablePages(stats.totalNewPages),
                            subtitle: "За всё время", symbol: "checkmark.seal")
            }
        }
    }

    private var graphSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Динамика чтения", icon: "chart.bar")
            Picker("Период", selection: $graphPeriod) {
                Text("7 дней").tag(7)
                Text("30 дней").tag(30)
            }
            .pickerStyle(.segmented)
            Picker("Показатель", selection: $graphMode) {
                Text("Минуты").tag(0)
                Text("Новые страницы").tag(1)
            }
            .pickerStyle(.segmented)
            Chart(graphPoints) { item in
                BarMark(
                    x: .value("Дата", item.date, unit: .day),
                    y: .value(
                        graphMode == 0 ? "Минуты" : "Страницы",
                        graphMode == 0 ? item.minutes : item.pages
                    )
                )
                .foregroundStyle(palette.accent.gradient)
                .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: graphPeriod == 7 ? 1 : 5)) {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 195)
            .padding(.top, 5)
        }
        .padding(16)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 18))
    }

    private var calendarStart: Date {
        let reference = calendar.date(
            byAdding: .month, value: calendarMonthOffset, to: currentDay
        ) ?? currentDay
        return calendar.dateInterval(of: .month, for: reference)?.start ?? reference
    }

    private var calendarLength: Int {
        calendar.range(of: .day, in: .month, for: calendarStart)?.count ?? 30
    }

    private var firstWeekdayOffset: Int {
        // Russian layout: Monday is the first weekday.
        (calendar.component(.weekday, from: calendarStart) + 5) % 7
    }

    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionTitle("Календарь активности", icon: "calendar")
            HStack {
                Button {
                    calendarMonthOffset -= 1
                    selectedDay = nil
                } label: {
                    Image(systemName: "chevron.left").frame(width: 36, height: 36)
                }
                Spacer()
                Text(calendarStart.formatted(
                    .dateTime.month(.wide).year().locale(Locale(identifier: "ru_RU"))
                ).capitalized)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.text)
                Spacer()
                Button {
                    calendarMonthOffset += 1
                    selectedDay = nil
                } label: {
                    Image(systemName: "chevron.right").frame(width: 36, height: 36)
                }
                .disabled(calendarMonthOffset >= 0)
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.accent)

            let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)
            LazyVGrid(columns: columns, spacing: 7) {
                ForEach(["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"], id: \.self) { weekday in
                    Text(weekday)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.secondary)
                        .frame(maxWidth: .infinity)
                }
                ForEach(0..<firstWeekdayOffset, id: \.self) { _ in
                    Color.clear.frame(height: 35)
                }
                ForEach(1...calendarLength, id: \.self) { number in
                    if let date = calendar.date(byAdding: .day, value: number - 1, to: calendarStart) {
                        dayButton(date, number: number)
                    }
                }
            }

            if let selectedDay,
               let date = ReadingStatistics.dayDate(selectedDay) {
                let day = stats.days[selectedDay] ?? .init()
                Text("\(date.formatted(.dateTime.day().month(.wide))): \(readableTime(day.seconds)) · \(readablePages(day.newPages)) стр.")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
            } else {
                Text("Нажми на дату, чтобы посмотреть время и страницы.")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
            }
        }
        .padding(16)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 18))
    }

    private func dayButton(_ date: Date, number: Int) -> some View {
        let key = ReadingStatistics.dayKey(for: date)
        let day = stats.days[key] ?? .init()
        let isActive = day.seconds > 0 || day.newPages > 0
        let isSelected = selectedDay == key
        return Button {
            selectedDay = key
        } label: {
            Text("\(number)")
                .font(.system(size: 12, weight: isActive ? .bold : .regular))
                .foregroundStyle(isActive ? palette.onAccent : palette.text)
                .frame(maxWidth: .infinity)
                .frame(height: 35)
                .background(
                    isActive ? palette.accent : palette.surfaceHigh,
                    in: RoundedRectangle(cornerRadius: 9)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(
                            isSelected ? palette.text : .clear,
                            lineWidth: isSelected ? 1.5 : 0
                        )
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("День \(number), \(isActive ? "есть чтение" : "без чтения")")
    }

    private var readingProgressSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionTitle("Прогресс библиотеки", icon: "books.vertical.fill")
            if store.snapshot.chapters.isEmpty {
                Text("Импортируй первую главу, чтобы появился прогресс.")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.secondary)
            } else {
                ForEach(store.snapshot.works, id: \.self) { work in
                    let chapters = store.snapshot.chapters.filter { $0.series == work }
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text(work)
                                .font(.system(size: 14, weight: .semibold))
                                .lineLimit(2)
                            Spacer()
                            Text("\(Int(progress(for: chapters).rounded()))%")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(palette.accent)
                        }
                        progressRail(progress(for: chapters))
                        ForEach(store.volumes(for: work)) { volume in
                            let items = store.chapters(for: work, volume: volume.title)
                            HStack(spacing: 9) {
                                Text(volume.title)
                                    .font(.system(size: 12))
                                    .foregroundStyle(palette.secondary)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(Int(progress(for: items).rounded()))%")
                                    .font(.system(size: 11))
                                    .foregroundStyle(palette.secondary)
                                    .frame(width: 40, alignment: .trailing)
                            }
                            progressRail(progress(for: items), height: 4)
                        }
                    }
                    .padding(14)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: 15))
                }
            }
        }
    }

    private var habitsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Привычки чтения", icon: "flame")
            HStack(spacing: 10) {
                summaryCard("Серия дней", value: "\(stats.activityStreak())",
                            subtitle: "Дней подряд", symbol: "flame.fill")
                summaryCard("Любимое время",
                            value: stats.favoriteHour.map {
                                String(format: "%02d:00", $0)
                            } ?? "—",
                            subtitle: "Час наибольшей активности", symbol: "clock")
            }
            let favorites = Array(stats.secondsByWork(chapters: store.snapshot.chapters).prefix(5))
            if !favorites.isEmpty {
                VStack(alignment: .leading, spacing: 11) {
                    Text("Самые читаемые произведения")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.text)
                    ForEach(favorites.indices, id: \.self) { index in
                        let work = favorites[index]
                        HStack(spacing: 8) {
                            Text("\(index + 1). \(work.name)")
                                .font(.system(size: 13))
                                .foregroundStyle(palette.text)
                                .lineLimit(2)
                            Spacer()
                            Text(readableTime(work.seconds))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(palette.accent)
                        }
                    }
                }
                .padding(15)
                .background(palette.surface, in: RoundedRectangle(cornerRadius: 15))
            }
        }
    }

    private func progress(for chapters: [LibraryChapter]) -> Double {
        guard !chapters.isEmpty else { return 0 }
        var weighted = 0.0
        var total = 0.0
        for chapter in chapters {
            let weight = Double(max(1, stats.pagesByChapter[chapter.id] ?? 1))
            total += weight
            weighted += weight * min(100, max(0, store.progress(for: chapter.id).percent))
        }
        return total > 0 ? weighted / total : 0
    }

    private func progressRail(_ percentage: Double, height: CGFloat = 7) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.surfaceHigh)
                Capsule()
                    .fill(palette.accent)
                    .frame(
                        width: max(0, geo.size.width * CGFloat(min(max(percentage, 0), 100) / 100))
                    )
            }
        }
        .frame(height: height)
    }

    private func summaryCard(
        _ title: String, value: String,
        subtitle: String, symbol: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.secondary)
                Spacer(minLength: 3)
                Image(systemName: symbol)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.accent)
            }
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(palette.text)
                .minimumScaleFactor(0.72)
                .lineLimit(1)
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(palette.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 15))
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(palette.text)
    }

    private func readableTime(_ value: Double) -> String {
        let minutes = Int((max(0, value) / 60).rounded())
        if minutes == 0 { return "0 мин" }
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return "\(minutes) мин" }
        return remainder == 0 ? "\(hours) ч" : "\(hours) ч \(remainder) мин"
    }

    private func readablePages(_ value: Double) -> String {
        "\(Int(max(0, value).rounded()))"
    }
}
