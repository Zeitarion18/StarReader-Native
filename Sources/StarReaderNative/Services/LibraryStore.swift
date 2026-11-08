import Foundation
import Combine

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var snapshot = LibrarySnapshot(works: [], volumes: [], chapters: [])
    @Published private(set) var progressByBook: [String: ReaderProgress] = [:]
    @Published private(set) var annotations: [ReaderAnnotation] = []
    @Published private(set) var bookmarks: [ReaderBookmark] = []
    @Published private(set) var pendingSummary: ImportSummary?
    @Published var statusMessage: String?

    private var pendingTransfer: ImportedTransfer?
    private var stateObject: [String: Any] = [:]

    private let rootURL: URL
    private var libraryURL: URL { rootURL.appendingPathComponent("qt_library.json") }
    private var stateURL: URL { rootURL.appendingPathComponent("preview_state.json") }

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        rootURL = base.appendingPathComponent("StarReaderNative", isDirectory: true)
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        loadFromDisk()
    }

    func volumes(for work: String) -> [LibraryVolume] {
        snapshot.volumes(for: work)
    }

    func chapters(for work: String, volume: String) -> [LibraryChapter] {
        snapshot.chapters(for: work, volume: volume)
    }

    func progress(for chapterID: String) -> ReaderProgress {
        progressByBook[chapterID] ?? .zero
    }
    /// Most recent existing chapter. Detached notes and deleted chapters
    /// remain in storage but are never offered as a reading shortcut.
    var mostRecentChapter: LibraryChapter? {
        guard let raw = stateObject["progress"] as? [String: [String: Any]] else {
            return nil
        }
        return snapshot.chapters
            .filter { raw[$0.id] != nil }
            .max { a, b in
                let aDate = raw[a.id]?["updatedAt"] as? String ?? ""
                let bDate = raw[b.id]?["updatedAt"] as? String ?? ""
                if aDate != bDate { return aDate < bDate }
                return (progressByBook[a.id]?.percent ?? 0) <
                    (progressByBook[b.id]?.percent ?? 0)
            }
    }


    func chapter(for id: String) -> LibraryChapter? {
        snapshot.chapters.first(where: { $0.id == id })
    }

    func annotations(for chapterID: String) -> [ReaderAnnotation] {
        annotations.filter { $0.bookId == chapterID }
    }

    func hasBookmark(chapterID: String, paragraph: Int) -> Bool {
        bookmarks.contains { $0.bookId == chapterID && $0.paragraph == paragraph }
    }

    var unlinkedAnnotationCount: Int {
        let ids = Set(snapshot.chapters.map(\.id))
        return annotations.filter { !ids.contains($0.bookId) }.count
    }

    var unlinkedBookmarkCount: Int {
        let ids = Set(snapshot.chapters.map(\.id))
        return bookmarks.filter { !ids.contains($0.bookId) }.count
    }

    func addBookmark(for chapter: LibraryChapter, paragraph: Int, offset: Int = 0) {
        let safeParagraph = min(max(0, paragraph), max(0, chapter.paragraphs.count - 1))
        guard !hasBookmark(chapterID: chapter.id, paragraph: safeParagraph) else {
            statusMessage = "Закладка в этом абзаце уже существует."
            return
        }

        let id = UUID().uuidString
        let newObject: [String: Any] = [
            "id": id,
            "bookId": chapter.id,
            "para": safeParagraph,
            "offset": max(0, offset),
            "title": chapter.displayTitle + " · абз. " + String(safeParagraph + 1),
            "createdAt": ISO8601DateFormatter().string(from: Date())
        ]
        var originals = stateObject["bookmarks"] as? [[String: Any]] ?? []
        originals.append(newObject)
        stateObject["bookmarks"] = originals
        do {
            try saveState()
            loadRecordCollections()
        } catch {
            statusMessage = "Не удалось сохранить закладку: \(error.localizedDescription)"
        }
    }

    /// Adds a note without rewriting or deleting any existing imported records.
    /// This matches the StarReader Qt Transfer shape: para/start/end/endPara
    /// use Unicode-scalar offsets, not the global UTF-16 positions of CoreText.
    @discardableResult
    func addAnnotation(
        for chapter: LibraryChapter,
        selection: ReaderTextSelection,
        kind: String,
        note: String
    ) -> Bool {
        let validKinds: Set<String> = ["canon", "plot", "style", "favorite"]
        guard validKinds.contains(kind),
              !selection.quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              chapter.paragraphs.indices.contains(selection.startParagraph),
              chapter.paragraphs.indices.contains(selection.endParagraph),
              selection.startParagraph <= selection.endParagraph,
              selection.startOffset >= 0,
              selection.endOffset >= 0,
              selection.startOffset <= chapter.paragraphs[selection.startParagraph].text.unicodeScalars.count,
              selection.endOffset <= chapter.paragraphs[selection.endParagraph].text.unicodeScalars.count,
              (selection.startParagraph < selection.endParagraph ||
               selection.startOffset < selection.endOffset) else {
            statusMessage = "Выделение неверно. Выдели текст заново и повтори."
            return false
        }

        let item: [String: Any] = [
            "id": UUID().uuidString,
            "bookId": chapter.id,
            "para": selection.startParagraph,
            "start": selection.startOffset,
            "endPara": selection.endParagraph,
            "end": selection.endOffset,
            "kind": kind,
            "quote": selection.quote,
            "note": note,
            "status": "open",
            "createdAt": ISO8601DateFormatter().string(from: Date())
        ]

        let previous = stateObject["annotations"]
        var entries = stateObject["annotations"] as? [[String: Any]] ?? []
        entries.append(item)
        stateObject["annotations"] = entries

        do {
            try saveState()
            loadRecordCollections()
            return true
        } catch {
            // A failed write must not leave an in-memory item that cannot
            // survive a restart.
            stateObject["annotations"] = previous
            statusMessage = "Не удалось сохранить замечание: \(error.localizedDescription)"
            return false
        }
    }

    func stageImport(from url: URL) async throws {
        let imported = try await Task.detached(priority: .userInitiated) {
            try TransferImporter.read(from: url)
        }.value
        pendingTransfer = imported
        pendingSummary = imported.summary
    }

    func cancelPendingImport() {
        pendingTransfer = nil
        pendingSummary = nil
    }

    func commitPendingImport() throws {
        guard let transfer = pendingTransfer else { return }
        let fm = FileManager.default
        let imports = rootURL.appendingPathComponent("Imports", isDirectory: true)
        try fm.createDirectory(at: imports, withIntermediateDirectories: true)

        let identifier = UUID().uuidString
        let archiveURL = imports.appendingPathComponent("StarReader-" + identifier + ".zip")
        let backupDir = imports.appendingPathComponent("BeforeImport-" + identifier, isDirectory: true)
        let stagingDir = imports.appendingPathComponent("Staging-" + identifier, isDirectory: true)
        try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: stagingDir) }

        // Keep the original archive and a recoverable snapshot of the old data
        // before changing any existing library files.
        try transfer.archiveData.write(to: archiveURL, options: .atomic)
        let originalsURL = rootURL.appendingPathComponent("originals", isDirectory: true)
        let targets: [URL] = [libraryURL, stateURL, originalsURL]
        for target in targets where fm.fileExists(atPath: target.path) {
            try fm.copyItem(at: target, to: backupDir.appendingPathComponent(target.lastPathComponent))
        }

        try transfer.libraryData.write(to: stagingDir.appendingPathComponent("qt_library.json"), options: .atomic)
        try transfer.stateData.write(to: stagingDir.appendingPathComponent("preview_state.json"), options: .atomic)
        let stagedOriginals = stagingDir.appendingPathComponent("originals", isDirectory: true)
        try fm.createDirectory(at: stagedOriginals, withIntermediateDirectories: true)
        for (name, data) in transfer.originals {
            try data.write(to: stagedOriginals.appendingPathComponent(name), options: .atomic)
        }

        do {
            for target in targets {
                let source = stagingDir.appendingPathComponent(target.lastPathComponent)
                if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
                try fm.moveItem(at: source, to: target)
            }
        } catch {
            // Restore each previous file, even if a write failed midway.
            for target in targets {
                let previous = backupDir.appendingPathComponent(target.lastPathComponent)
                if fm.fileExists(atPath: target.path) { try? fm.removeItem(at: target) }
                if fm.fileExists(atPath: previous.path) { try? fm.copyItem(at: previous, to: target) }
            }
            throw error
        }

        pendingTransfer = nil
        pendingSummary = nil
        loadFromDisk()
    }

    func recordProgress(for chapter: LibraryChapter, paragraph: Int, offset: Int = 0) {
        let safeParagraph = min(max(0, paragraph), max(0, chapter.paragraphs.count - 1))
        let currentLength = chapter.paragraphs.indices.contains(safeParagraph)
            ? chapter.paragraphs[safeParagraph].text.unicodeScalars.count : 0
        let safeOffset = min(max(0, offset), currentLength)
        let before = chapter.paragraphs.prefix(safeParagraph).reduce(0) { $0 + $1.text.unicodeScalars.count }
        let total = max(1, chapter.totalCharacters)
        let percent = min(100, max(0, Double(before + min(safeOffset, currentLength)) / Double(total) * 100))
        let progress = ReaderProgress(paragraph: safeParagraph, offset: safeOffset, percent: percent)

        if progressByBook[chapter.id] == progress { return }
        progressByBook[chapter.id] = progress

        var progressObject = stateObject["progress"] as? [String: Any] ?? [:]
        progressObject[chapter.id] = [
            "bookId": chapter.id,
            "para": safeParagraph,
            "offset": safeOffset,
            "percent": (percent * 100).rounded() / 100,
            "updatedAt": ISO8601DateFormatter().string(from: Date())
        ]
        stateObject["progress"] = progressObject

        do {
            try saveState()
        } catch {
            statusMessage = "Не удалось сохранить позицию чтения: \(error.localizedDescription)"
        }
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: libraryURL.path) else {
            snapshot = LibrarySnapshot(works: [], volumes: [], chapters: [])
            progressByBook = [:]
            annotations = []
            bookmarks = []
            stateObject = freshState()
            return
        }

        do {
            let libraryData = try Data(contentsOf: libraryURL)
            snapshot = try LibrarySnapshot.parse(libraryData)

            if FileManager.default.fileExists(atPath: stateURL.path) {
                let stateData = try Data(contentsOf: stateURL)
                stateObject = try JSONSerialization.jsonObject(with: stateData) as? [String: Any] ?? freshState()
            } else {
                stateObject = freshState()
            }

            let rawProgress = stateObject["progress"] as? [String: Any] ?? [:]
            var parsed: [String: ReaderProgress] = [:]
            for (bookID, value) in rawProgress {
                guard let item = value as? [String: Any] else { continue }
                parsed[bookID] = ReaderProgress(
                    paragraph: item["para"] as? Int ?? 0,
                    offset: item["offset"] as? Int ?? 0,
                    percent: item["percent"] as? Double ?? 0
                )
            }
            progressByBook = parsed
            loadRecordCollections()
        } catch {
            statusMessage = "Не удалось открыть локальную библиотеку: \(error.localizedDescription)"
        }
    }

    private func loadRecordCollections() {
        let rawNotes = stateObject["annotations"] as? [[String: Any]] ?? []
        let rawBookmarks = stateObject["bookmarks"] as? [[String: Any]] ?? []
        annotations = rawNotes.compactMap(ReaderAnnotation.parse)
        bookmarks = rawBookmarks.compactMap(ReaderBookmark.parse)
        if rawNotes.count != annotations.count || rawBookmarks.count != bookmarks.count {
            statusMessage = "Некоторые записи повреждены. Исходный JSON сохранён без изменений."
        }
    }

    private func saveState() throws {
        let data = try JSONSerialization.data(withJSONObject: stateObject, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: stateURL, options: .atomic)
    }

    private func freshState() -> [String: Any] {
        [
            "schema": 1,
            "progress": [String: Any](),
            "annotations": [Any](),
            "bookmarks": [Any](),
            "settings": [
                "fontSize": 19,
                "lineHeight": 1.7,
                "theme": "night",
                "mode": "pages",
                "autoResume": true,
                "immersiveReader": false
            ]
        ]
    }
}
