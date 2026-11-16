import Foundation

/// Historical activity is stored in preview_state.json under "readingStats".
/// It is therefore included in existing ZIP backups without changing their
/// manifest, import schema, or user-visible library data.
struct ReadingStatistics: Codable, Equatable {
    struct Daily: Codable, Equatable {
        var seconds: Double = 0
        var newPages: Double = 0
    }

    struct Coverage: Codable, Equatable {
        var start: Int
        var end: Int
        var length: Int { max(0, end - start) }
    }

    var schema: Int = 1
    var days: [String: Daily] = [:]
    var coverageByChapter: [String: [Coverage]] = [:]
    var revisionByChapter: [String: String] = [:]
    var secondsByChapter: [String: Double] = [:]
    var secondsByHour: [String: Double] = [:]
    var pagesByChapter: [String: Int] = [:]

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 1970,
            components.month ?? 1,
            components.day ?? 1
        )
    }

    static func dayDate(_ key: String, calendar: Calendar = .current) -> Date? {
        let pieces = key.split(separator: "-").compactMap { Int($0) }
        guard pieces.count == 3 else { return nil }
        return calendar.date(from: DateComponents(
            year: pieces[0], month: pieces[1], day: pieces[2]
        ))
    }

    mutating func recordReading(
        from start: Date,
        to end: Date,
        chapterID: String,
        calendar: Calendar = .current
    ) {
        guard start < end, !chapterID.isEmpty else { return }
        // An interruption or clock jump must never count hours in background.
        guard end.timeIntervalSince(start) <= 120 else { return }

        var cursor = start
        while cursor < end {
            let hour = calendar.dateInterval(of: .hour, for: cursor)
            let day = calendar.dateInterval(of: .day, for: cursor)
            let next = min(end, hour?.end ?? end, day?.end ?? end)
            guard next > cursor else { break }
            let seconds = next.timeIntervalSince(cursor)
            let key = Self.dayKey(for: cursor, calendar: calendar)
            var item = days[key] ?? Daily()
            item.seconds += seconds
            days[key] = item
            secondsByChapter[chapterID, default: 0] += seconds
            let clockHour = String(calendar.component(.hour, from: cursor))
            secondsByHour[clockHour, default: 0] += seconds
            cursor = next
        }
    }

    /// Store the actual character interval of the displayed TextKit page.
    /// Reading the same span a second time contributes zero new pages even
    /// after closing/reopening the app. Different fonts/line spacing produce
    /// overlapping intervals that are merged without double-counting.
    ///
    /// newPages are page-equivalents, derived from the fraction of previously
    /// unseen rendered text and the current number of pages in the chapter.
    mutating func visitPage(
        chapterID: String,
        revision: String,
        start: Int,
        end: Int,
        totalLength: Int,
        pageCount: Int,
        at date: Date = Date(),
        calendar: Calendar = .current
    ) {
        guard !chapterID.isEmpty, totalLength > 0,
              pageCount > 0, pageCount <= 50_000,
              start >= 0, end > start, end <= totalLength else { return }

        // Chapter text was replaced or re-imported. Never reuse offsets
        // from an old revision; daily totals already earned remain history.
        if revisionByChapter[chapterID] != revision {
            coverageByChapter[chapterID] = []
            revisionByChapter[chapterID] = revision
        }

        pagesByChapter[chapterID] = pageCount
        let previous = coverageByChapter[chapterID] ?? []
        let previousLength = previous.reduce(0) { $0 + $1.length }
        let ordered = (previous + [Coverage(start: start, end: end)])
            .sorted { $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start }
        var merged: [Coverage] = []
        for item in ordered {
            if let index = merged.indices.last, merged[index].end >= item.start {
                merged[index].end = max(merged[index].end, item.end)
            } else {
                merged.append(item)
            }
        }
        coverageByChapter[chapterID] = merged
        let added = max(0, merged.reduce(0) { $0 + $1.length } - previousLength)
        guard added > 0 else { return }
        let key = Self.dayKey(for: date, calendar: calendar)
        var item = days[key] ?? Daily()
        item.newPages += Double(added) / Double(totalLength) * Double(pageCount)
        days[key] = item
    }

    func seconds(from start: Date, through end: Date, calendar: Calendar = .current) -> Double {
        days.reduce(0) { partial, entry in
            guard let date = Self.dayDate(entry.key, calendar: calendar),
                  date >= calendar.startOfDay(for: start),
                  date <= calendar.startOfDay(for: end) else { return partial }
            return partial + entry.value.seconds
        }
    }

    func pages(from start: Date, through end: Date, calendar: Calendar = .current) -> Double {
        days.reduce(0) { partial, entry in
            guard let date = Self.dayDate(entry.key, calendar: calendar),
                  date >= calendar.startOfDay(for: start),
                  date <= calendar.startOfDay(for: end) else { return partial }
            return partial + entry.value.newPages
        }
    }

    var totalSeconds: Double {
        days.values.reduce(0) { $0 + $1.seconds }
    }

    var totalNewPages: Double {
        days.values.reduce(0) { $0 + $1.newPages }
    }

    func activityStreak(asOf date: Date = Date(), calendar: Calendar = .current) -> Int {
        var cursor = calendar.startOfDay(for: date)
        if !(days[Self.dayKey(for: cursor, calendar: calendar)].map {
            $0.seconds > 0 || $0.newPages > 0
        } ?? false), let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) {
            cursor = yesterday
        }
        var streak = 0
        for _ in 0..<36500 {
            let item = days[Self.dayKey(for: cursor, calendar: calendar)]
            guard let item, item.seconds > 0 || item.newPages > 0 else { break }
            streak += 1
            guard let prior = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prior
        }
        return streak
    }

    var favoriteHour: Int? {
        secondsByHour.max(by: { $0.value < $1.value }).flatMap {
            Int($0.key)
        }
    }

    func secondsByWork(chapters: [LibraryChapter]) -> [(name: String, seconds: Double)] {
        var values: [String: Double] = [:]
        for chapter in chapters {
            let amount = secondsByChapter[chapter.id] ?? 0
            if amount > 0 { values[chapter.series, default: 0] += amount }
        }
        return values.map { (name: $0.key, seconds: $0.value) }
            .sorted { $0.seconds > $1.seconds }
    }
}
