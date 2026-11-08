import Foundation

/// A deletion changes the actual Qt-transfer JSON library, not just the
/// in-memory SwiftUI snapshot. All unrelated and unknown JSON fields survive.
enum LibraryDeletion {
    enum Target {
        case chapter(id: String)
        case volume(series: String, title: String)
    }

    struct Result {
        let libraryData: Data
        let stateData: Data
        let deletedIDs: Set<String>
        let deletedChapters: Int
    }

    enum Failure: LocalizedError {
        case invalidLibrary
        case invalidState
        case notFound

        var errorDescription: String? {
            switch self {
            case .invalidLibrary:
                return "Невозможно изменить повреждённый файл библиотеки."
            case .invalidState:
                return "Невозможно безопасно изменить повреждённые заметки или прогресс."
            case .notFound:
                return "Эта глава или том уже отсутствует в библиотеке."
            }
        }
    }

    static func remove(
        _ target: Target,
        from libraryData: Data,
        stateData: Data
    ) throws -> Result {
        guard var library = try JSONSerialization.jsonObject(
            with: libraryData
        ) as? [String: Any],
        library["schema"] as? Int == 2,
        let books = library["books"] as? [[String: Any]],
        let volumes = library["volumes"] as? [[String: Any]] else {
            throw Failure.invalidLibrary
        }

        guard var state = try JSONSerialization.jsonObject(
            with: stateData
        ) as? [String: Any],
        state["schema"] as? Int == 1,
        var progress = state["progress"] as? [String: Any],
        let annotations = state["annotations"] as? [[String: Any]],
        let bookmarks = state["bookmarks"] as? [[String: Any]] else {
            throw Failure.invalidState
        }

        let removed: Set<String>
        var newVolumes = volumes
        switch target {
        case .chapter(let id):
            guard books.contains(where: { ($0["id"] as? String) == id }) else {
                throw Failure.notFound
            }
            removed = [id]

        case .volume(let series, let title):
            let matches = books.filter {
                ($0["series"] as? String) == series &&
                ($0["volume"] as? String) == title
            }
            let exists = volumes.contains {
                ($0["series"] as? String) == series &&
                ($0["title"] as? String) == title
            }
            guard exists || !matches.isEmpty else {
                throw Failure.notFound
            }
            // IDs are the exact identity of chapters, even if two prologues
            // have an identical display title.
            removed = Set(matches.compactMap { $0["id"] as? String })
            newVolumes.removeAll {
                ($0["series"] as? String) == series &&
                ($0["title"] as? String) == title
            }
        }

        let remainingBooks = books.filter {
            guard let id = $0["id"] as? String else { return true }
            return !removed.contains(id)
        }

        for id in removed {
            progress.removeValue(forKey: id)
        }

        // Only records for intentionally deleted chapters are removed.
        // Existing unrelated orphaned records remain unchanged.
        let remainingAnnotations = annotations.filter {
            guard let id = $0["bookId"] as? String else { return true }
            return !removed.contains(id)
        }
        let remainingBookmarks = bookmarks.filter {
            guard let id = $0["bookId"] as? String else { return true }
            return !removed.contains(id)
        }

        library["books"] = remainingBooks
        library["volumes"] = newVolumes
        state["progress"] = progress
        state["annotations"] = remainingAnnotations
        state["bookmarks"] = remainingBookmarks

        // Do not touch 'works', 'trash', saved original DOCX names, settings
        // or unknown fields. The pre-deletion backup is the recovery source.
        return Result(
            libraryData: try JSONSerialization.data(
                withJSONObject: library, options: [.prettyPrinted, .sortedKeys]
            ),
            stateData: try JSONSerialization.data(
                withJSONObject: state, options: [.prettyPrinted, .sortedKeys]
            ),
            deletedIDs: removed,
            deletedChapters: books.count - remainingBooks.count
        )
    }
}
