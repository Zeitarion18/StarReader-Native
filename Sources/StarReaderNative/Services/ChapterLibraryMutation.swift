import Foundation

/// A pure JSON transform: existing books, IDs, notes, and metadata are never
/// replaced when a new DOCX is appended. Safe to test without SwiftUI.
enum ChapterLibraryMutation {
    struct Paragraph {
        let text: String
        let heading: Bool
    }

    enum Failure: LocalizedError {
        case invalidLibrary
        case emptyDestination
        case emptyChapter
        case duplicateChapter
        case duplicateID

        var errorDescription: String? {
            switch self {
            case .invalidLibrary:
                return "Файл библиотеки имеет неверный формат. Импорт остановлен."
            case .emptyDestination:
                return "Укажи название произведения и тома."
            case .emptyChapter:
                return "Название или содержимое главы пустое."
            case .duplicateChapter:
                return "В этом томе уже есть глава с таким названием."
            case .duplicateID:
                return "Не удалось назначить уникальный номер главы."
            }
        }
    }

    static func append(
        to existingData: Data?,
        series: String,
        volume: String,
        title: String,
        paragraphs: [Paragraph],
        chapterID: String,
        originalFile: String,
        allowDuplicate: Bool
    ) throws -> Data {
        let work = series.trimmingCharacters(in: .whitespacesAndNewlines)
        let bookVolume = volume.trimmingCharacters(in: .whitespacesAndNewlines)
        let chapterTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !work.isEmpty, !bookVolume.isEmpty else {
            throw Failure.emptyDestination
        }
        guard !chapterTitle.isEmpty,
              paragraphs.contains(where: {
                  !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              }) else {
            throw Failure.emptyChapter
        }

        let root: [String: Any]
        if let existingData {
            guard let value = try JSONSerialization.jsonObject(
                with: existingData
            ) as? [String: Any],
            value["schema"] as? Int == 2,
            value["works"] is [String],
            value["volumes"] is [[String: Any]],
            value["books"] is [[String: Any]] else {
                throw Failure.invalidLibrary
            }
            root = value
        } else {
            root = [
                "schema": 2,
                "works": [String](),
                "volumes": [[String: Any]](),
                "books": [[String: Any]](),
                "trash": [Any]()
            ]
        }

        var updated = root
        var works = root["works"] as! [String]
        var volumes = root["volumes"] as! [[String: Any]]
        var books = root["books"] as! [[String: Any]]

        guard !books.contains(where: { $0["id"] as? String == chapterID }) else {
            throw Failure.duplicateID
        }

        let titleExists = books.contains { book in
            guard (book["series"] as? String) == work,
                  (book["volume"] as? String) == bookVolume else { return false }
            let oldTitle = (book["chapter"] as? String).flatMap {
                $0.isEmpty ? nil : $0
            } ?? (book["name"] as? String ?? "")
            return oldTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                .compare(chapterTitle, options: [.caseInsensitive, .diacriticInsensitive])
                == .orderedSame
        }
        if titleExists && !allowDuplicate {
            throw Failure.duplicateChapter
        }

        if !works.contains(work) {
            works.append(work)
        }
        if !volumes.contains(where: {
            ($0["series"] as? String) == work &&
            ($0["title"] as? String) == bookVolume
        }) {
            volumes.append(["series": work, "title": bookVolume])
        }

        let newParagraphs: [[String: Any]] = paragraphs.map {
            ["text": $0.text, "heading": $0.heading]
        }
        books.append([
            "id": chapterID,
            "series": work,
            "volume": bookVolume,
            "name": chapterTitle,
            "chapter": chapterTitle,
            "paragraphs": newParagraphs,
            "originalFile": originalFile
        ])

        updated["works"] = works
        updated["volumes"] = volumes
        updated["books"] = books
        // Retain unknown keys, trash, and other Qt transfer metadata.
        return try JSONSerialization.data(
            withJSONObject: updated,
            options: [.prettyPrinted, .sortedKeys]
        )
    }

    struct BatchChapter {
        let id: String
        let title: String
        let paragraphs: [Paragraph]
    }

    /// All-or-nothing in-memory transform for a complete Word volume.
    /// No existing book or metadata is replaced and the entire source DOCX
    /// can be stored once as one shared originalFile.
    static func appendBatch(
        to existingData: Data?,
        series: String,
        volume: String,
        chapters: [BatchChapter],
        originalFile: String
    ) throws -> Data {
        let work = series.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetVolume = volume.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !work.isEmpty, !targetVolume.isEmpty else {
            throw Failure.emptyDestination
        }
        guard !chapters.isEmpty, chapters.count <= 250 else {
            throw Failure.emptyChapter
        }

        let root: [String: Any]
        if let existingData {
            guard let object = try JSONSerialization.jsonObject(
                with: existingData
            ) as? [String: Any],
            object["schema"] as? Int == 2,
            object["works"] is [String],
            object["volumes"] is [[String: Any]],
            object["books"] is [[String: Any]] else {
                throw Failure.invalidLibrary
            }
            root = object
        } else {
            root = [
                "schema": 2,
                "works": [String](),
                "volumes": [[String: Any]](),
                "books": [[String: Any]](),
                "trash": [Any]()
            ]
        }

        var works = root["works"] as! [String]
        var volumes = root["volumes"] as! [[String: Any]]
        var books = root["books"] as! [[String: Any]]
        var ids = Set(books.compactMap { $0["id"] as? String })

        func titleKey(_ title: String) -> String {
            title.trimmingCharacters(in: .whitespacesAndNewlines).folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "ru_RU")
            )
        }
        var titles = Set(books.compactMap { book -> String? in
            guard book["series"] as? String == work,
                  book["volume"] as? String == targetVolume else { return nil }
            let title = (book["chapter"] as? String).flatMap {
                $0.isEmpty ? nil : $0
            } ?? (book["name"] as? String ?? "")
            return titleKey(title)
        })

        for chapter in chapters {
            let title = chapter.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty,
                  chapter.paragraphs.contains(where: {
                      !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  }) else {
                throw Failure.emptyChapter
            }
            guard !chapter.id.isEmpty, !ids.contains(chapter.id) else {
                throw Failure.duplicateID
            }
            let normalized = titleKey(title)
            guard !titles.contains(normalized) else {
                throw Failure.duplicateChapter
            }
            ids.insert(chapter.id)
            titles.insert(normalized)
            books.append([
                "id": chapter.id,
                "series": work,
                "volume": targetVolume,
                "name": title,
                "chapter": title,
                "paragraphs": chapter.paragraphs.map {
                    ["text": $0.text, "heading": $0.heading]
                },
                "originalFile": originalFile
            ])
        }

        if !works.contains(work) { works.append(work) }
        if !volumes.contains(where: {
            $0["series"] as? String == work && $0["title"] as? String == targetVolume
        }) {
            volumes.append(["series": work, "title": targetVolume])
        }
        var updated = root
        updated["works"] = works
        updated["volumes"] = volumes
        updated["books"] = books
        return try JSONSerialization.data(
            withJSONObject: updated, options: [.prettyPrinted, .sortedKeys]
        )
    }

}
