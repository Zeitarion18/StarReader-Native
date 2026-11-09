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
}
