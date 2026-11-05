import Foundation

struct LibraryVolume: Identifiable, Hashable {
    let series: String
    let title: String

    var id: String { "\(series)::\(title)" }
}

struct LibraryChapter: Identifiable, Hashable {
    let id: String
    let name: String
    let series: String
    let volume: String
    let chapter: String
    let paragraphs: [ReaderParagraph]
    let originalFile: String?

    var displayTitle: String {
        chapter.isEmpty ? name : chapter
    }

    var totalCharacters: Int {
        paragraphs.reduce(0) { $0 + $1.text.count }
    }
}

struct ReaderParagraph: Identifiable, Hashable {
    let index: Int
    let text: String
    let heading: Bool

    var id: Int { index }
}

struct ReaderProgress: Equatable {
    let paragraph: Int
    let offset: Int
    let percent: Double

    static let zero = ReaderProgress(paragraph: 0, offset: 0, percent: 0)
}

struct LibrarySnapshot {
    let works: [String]
    let volumes: [LibraryVolume]
    let chapters: [LibraryChapter]

    static func parse(_ data: Data) throws -> LibrarySnapshot {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any],
              (root["schema"] as? Int) == 2,
              let workNames = root["works"] as? [String],
              let rawVolumes = root["volumes"] as? [[String: Any]],
              let rawBooks = root["books"] as? [[String: Any]] else {
            throw LibraryModelError.invalidLibrary
        }

        let volumes = rawVolumes.compactMap { item -> LibraryVolume? in
            guard let series = item["series"] as? String,
                  let title = item["title"] as? String else { return nil }
            return LibraryVolume(series: series, title: title)
        }

        var chapters: [LibraryChapter] = []
        for item in rawBooks {
            guard let id = item["id"] as? String,
                  let series = item["series"] as? String,
                  let volume = item["volume"] as? String,
                  let rawParagraphs = item["paragraphs"] as? [[String: Any]] else {
                continue
            }

            let paragraphs = rawParagraphs.enumerated().compactMap { index, paragraph -> ReaderParagraph? in
                guard let text = paragraph["text"] as? String else { return nil }
                return ReaderParagraph(
                    index: index,
                    text: text,
                    heading: paragraph["heading"] as? Bool ?? false
                )
            }

            chapters.append(
                LibraryChapter(
                    id: id,
                    name: item["name"] as? String ?? "Без названия",
                    series: series,
                    volume: volume,
                    chapter: item["chapter"] as? String ?? "",
                    paragraphs: paragraphs,
                    originalFile: item["originalFile"] as? String
                )
            )
        }

        let allWorks = Set(workNames + chapters.map(\.series))
        return LibrarySnapshot(
            works: allWorks.sorted { $0.localizedStandardCompare($1) == .orderedAscending },
            volumes: volumes,
            chapters: chapters
        )
    }

    func volumes(for work: String) -> [LibraryVolume] {
        var result = volumes.filter { $0.series == work }
        let known = Set(result.map(\.title))
        for chapter in chapters where chapter.series == work && !known.contains(chapter.volume) {
            result.append(LibraryVolume(series: work, title: chapter.volume))
        }
        return result.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func chapters(for work: String, volume: String) -> [LibraryChapter] {
        chapters
            .filter { $0.series == work && $0.volume == volume }
            .sorted { chapterSortKey($0.displayTitle) < chapterSortKey($1.displayTitle) }
    }

    private func chapterSortKey(_ title: String) -> (Int, Int, String) {
        let value = title.lowercased()
        let kind: Int
        if value.hasPrefix("пролог") { kind = 0 }
        else if value.hasPrefix("глава") { kind = 1 }
        else if value.hasPrefix("побоч") { kind = 2 }
        else if value.hasPrefix("эпилог") { kind = 3 }
        else if value.hasPrefix("послеслов") { kind = 4 }
        else { kind = 5 }

        let number = value.split(whereSeparator: { !$0.isNumber }).first.flatMap { Int($0) } ?? Int.max
        return (kind, number, value)
    }
}

enum LibraryModelError: LocalizedError {
    case invalidLibrary

    var errorDescription: String? {
        "Файл qt_library.json не соответствует формату библиотеки StarReader (schema 2)."
    }
}
