import Foundation

@main
enum ReadingStatisticsSmoke {
    static func main() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
            calendar.date(from: DateComponents(
                year: year, month: month, day: day,
                hour: hour, minute: minute, second: second
            ))!
        }
        func approx(_ x: Double, _ y: Double) {
            precondition(abs(x - y) < 0.01, "\(x) != \(y)")
        }

        var stats = ReadingStatistics()
        let first = date(2026, 11, 10, 21, 30)
        stats.recordReading(
            from: first, to: first.addingTimeInterval(25),
            chapterID: "chapterA", calendar: calendar
        )
        approx(stats.days["2026-11-10"]!.seconds, 25)
        approx(stats.secondsByHour["21"]!, 25)
        approx(stats.secondsByChapter["chapterA"]!, 25)
        // A replayed 120s callback is valid, but larger background gaps are
        // ignored rather than counted as active reading.
        stats.recordReading(
            from: first.addingTimeInterval(25),
            to: first.addingTimeInterval(225),
            chapterID: "chapterA", calendar: calendar
        )
        approx(stats.totalSeconds, 25)

        // Split time correctly across a local midnight and a new clock hour.
        let beforeMidnight = date(2026, 11, 10, 23, 59, 40)
        stats.recordReading(
            from: beforeMidnight,
            to: date(2026, 11, 11, 0, 0, 20),
            chapterID: "chapterA", calendar: calendar
        )
        approx(stats.days["2026-11-10"]!.seconds, 45)
        approx(stats.days["2026-11-11"]!.seconds, 20)
        approx(stats.secondsByHour["23"]!, 20)
        approx(stats.secondsByHour["0"]!, 20)
        approx(stats.totalSeconds, 65)

        // Unique text coverage, not page-turn counter.
        stats.visitPage(
            chapterID: "chapterA", revision: "3:250",
            start: 0, end: 100, totalLength: 1000,
            pageCount: 10, at: first, calendar: calendar
        )
        approx(stats.days["2026-11-10"]!.newPages, 1)
        stats.visitPage(
            chapterID: "chapterA", revision: "3:250",
            start: 0, end: 100, totalLength: 1000,
            pageCount: 10, at: first, calendar: calendar
        )
        approx(stats.days["2026-11-10"]!.newPages, 1)
        stats.visitPage(
            chapterID: "chapterA", revision: "3:250",
            start: 80, end: 150, totalLength: 1000,
            pageCount: 10, at: first, calendar: calendar
        )
        approx(stats.days["2026-11-10"]!.newPages, 1.5)
        precondition(stats.coverageByChapter["chapterA"] == [.init(start: 0, end: 150)])

        // Other chapters have their own coverage and reading time.
        stats.visitPage(
            chapterID: "chapterB", revision: "1:25",
            start: 0, end: 50, totalLength: 500,
            pageCount: 5, at: first, calendar: calendar
        )
        approx(stats.days["2026-11-10"]!.newPages, 2)
        stats.visitPage(
            chapterID: "chapterA", revision: "changed",
            start: 0, end: 100, totalLength: 1000,
            pageCount: 10, at: first, calendar: calendar
        )
        precondition(stats.coverageByChapter["chapterA"] == [.init(start: 0, end: 100)])
        approx(stats.totalNewPages, 3)

        // Round-trip exactly as the JSON-backed state file does.
        let serialized = try JSONEncoder().encode(stats)
        let decoded = try JSONDecoder().decode(ReadingStatistics.self, from: serialized)
        precondition(decoded == stats)
        precondition(decoded.schema == 1)
        precondition(decoded.favoriteHour == 21)
        precondition(decoded.activityStreak(asOf: date(2026, 11, 11, 13, 0), calendar: calendar) == 2)
        precondition(decoded.activityStreak(asOf: date(2026, 11, 12, 13, 0), calendar: calendar) == 2)
        approx(
            decoded.seconds(
                from: date(2026, 11, 10, 0, 0),
                through: date(2026, 11, 11, 0, 0),
                calendar: calendar
            ),
            65
        )

        let chapters = [
            LibraryChapter(
                id: "chapterA", name: "Глава 1", series: "Ранобэ",
                volume: "Том 1", chapter: "Глава 1", paragraphs: [],
                originalFile: nil
            ),
            LibraryChapter(
                id: "chapterB", name: "Глава 2", series: "Другое",
                volume: "Том 1", chapter: "Глава 2", paragraphs: [],
                originalFile: nil
            )
        ]
        let popular = decoded.secondsByWork(chapters: chapters)
        precondition(popular.count == 1)
        precondition(popular[0].name == "Ранобэ")
        approx(popular[0].seconds, 65)
        print("PASS: minute buckets, midnight, idle guard, unique text pages, " +
              "overlap merge, old chapter revision, JSON persistence and streak.")
    }
}
