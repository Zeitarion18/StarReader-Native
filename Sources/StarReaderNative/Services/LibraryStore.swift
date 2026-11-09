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

    // MARK: - Advanced annotations (v0.5.2)

    /// Transient UI intent only. Never persisted as a new annotation or
    /// written into the chapter, so leaving the reader cannot corrupt notes.
    @Published var pendingAnnotationReanchorID: String?

    var pendingAnnotationReanchor: ReaderAnnotation? {
        guard let id = pendingAnnotationReanchorID else { return nil }
        return annotations.first(where: { $0.id == id && $0.status == "needs_review" })
    }

    @discardableResult
    func updateAnnotation(id: String, kind: String, note: String, color: String) -> Bool {
        changeAnnotation(.update(id: id, kind: kind, note: note, color: color))
    }

    @discardableResult
    func deleteAnnotation(id: String) -> Bool {
        changeAnnotation(.remove(id: id))
    }

    @discardableResult
    func reattachAnnotation(
        id: String, chapter: LibraryChapter, selection: ReaderTextSelection
    ) -> Bool {
        let success = changeAnnotation(
            .reattach(id: id, chapterID: chapter.id,
                      selection: selection, chapter: chapter)
        )
        if success { pendingAnnotationReanchorID = nil }
        return success
    }

    private func changeAnnotation(_ action: AnnotationOperations.Action) -> Bool {
        do {
            let previous = try JSONSerialization.data(
                withJSONObject: stateObject, options: [.prettyPrinted, .sortedKeys]
            )
            let updated = try AnnotationOperations.apply(previous, action: action)
            let backup = rootURL
                .appendingPathComponent("Notes", isDirectory: true)
                .appendingPathComponent(
                    "BeforeNote-" + UUID().uuidString, isDirectory: true
                )
            try FileManager.default.createDirectory(
                at: backup, withIntermediateDirectories: true
            )
            try previous.write(
                to: backup.appendingPathComponent("preview_state.json"),
                options: .atomic
            )
            // Update memory only after an atomic disk write succeeds.
            try updated.write(to: stateURL, options: .atomic)
            guard let parsed = try JSONSerialization.jsonObject(
                with: updated
            ) as? [String: Any] else {
                throw AnnotationOperations.Failure.invalidState
            }
            stateObject = parsed
            loadRecordCollections()
            return true
        } catch {
            statusMessage = "Замечание не изменено: " + error.localizedDescription
            return false
        }
    }

    // MARK: - On-device backup and export

    /// Build the ZIP outside the main actor so large libraries do not stall
    /// SwiftUI rendering. The exporter independently checks its own ZIP using
    /// the same restore pipeline as Import ZIP.
    func exportBackup() async throws -> URL {
        let directory = rootURL
        return try await Task.detached(priority: .userInitiated) {
            try LibraryBackupExporter.export(from: directory)
        }.value
    }

    // MARK: - Individual DOCX chapter imports

    /// Add only one document, preserving every existing chapter, note,
    /// bookmark and reading position in the JSON library.
    @discardableResult
    func importDocxChapter(
        _ document: ImportedDocxChapter,
        work: String,
        volume: String,
        title: String,
        allowDuplicate: Bool = false
    ) throws -> LibraryChapter {
        let fm = FileManager.default
        let oldLibraryData: Data? = fm.fileExists(atPath: libraryURL.path)
            ? try Data(contentsOf: libraryURL)
            : nil

        let chapterID = UUID().uuidString
        // Generated file names are safe even when the original filename
        // contains slashes, unusual Unicode, or is identical to another DOCX.
        let originalFile = "native-" + chapterID + ".docx"
        let newLibraryData = try ChapterLibraryMutation.append(
            to: oldLibraryData,
            series: work,
            volume: volume,
            title: title,
            paragraphs: document.paragraphs.map {
                ChapterLibraryMutation.Paragraph(
                    text: $0.text, heading: $0.heading
                )
            },
            chapterID: chapterID,
            originalFile: originalFile,
            allowDuplicate: allowDuplicate
        )

        // Fail before touching any files if JSON content isn't readable by
        // the actual StarReader model.
        let parsed = try LibrarySnapshot.parse(newLibraryData)
        guard let newChapter = parsed.chapters.first(where: { $0.id == chapterID }) else {
            throw ChapterLibraryMutation.Failure.invalidLibrary
        }

        let backupDirectory = rootURL
            .appendingPathComponent("Imports", isDirectory: true)
            .appendingPathComponent("BeforeDocx-" + chapterID, isDirectory: true)
        let originalsDirectory = rootURL
            .appendingPathComponent("originals", isDirectory: true)
        try fm.createDirectory(
            at: backupDirectory, withIntermediateDirectories: true
        )
        try fm.createDirectory(
            at: originalsDirectory, withIntermediateDirectories: true
        )

        // The previous library and state are kept as a local recoverable
        // snapshot. State never changes during a single-chapter import.
        if let oldLibraryData {
            try oldLibraryData.write(
                to: backupDirectory.appendingPathComponent("qt_library.json"),
                options: .atomic
            )
        }
        if fm.fileExists(atPath: stateURL.path) {
            try fm.copyItem(
                at: stateURL,
                to: backupDirectory.appendingPathComponent("preview_state.json")
            )
        }

        let originalURL = originalsDirectory.appendingPathComponent(originalFile)
        do {
            try document.originalData.write(to: originalURL, options: .atomic)
            try newLibraryData.write(to: libraryURL, options: .atomic)
        } catch {
            let saveError = error
            // Roll back the library JSON if the second write fails. Even if
            // rollback fails, the pristine backup remains on disk.
            do {
                if let oldLibraryData {
                    try oldLibraryData.write(to: libraryURL, options: .atomic)
                } else if fm.fileExists(atPath: libraryURL.path) {
                    try fm.removeItem(at: libraryURL)
                }
            } catch {
                throw NSError(
                    domain: "StarReader.DocxImport",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey:
                        "Не удалось сохранить DOCX и откатить библиотеку. " +
                        "Исходная копия есть в папке BeforeDocx. " +
                        "Перед следующим импортом восстанови библиотеку."]
                )
            }
            try? fm.removeItem(at: originalURL)
            throw saveError
        }

        loadFromDisk()
        return newChapter
    }

    // MARK: - Safe chapter editing

    func previewChapterEdits(
        for chapter: LibraryChapter,
        title: String,
        paragraphs: [ChapterEditing.Paragraph]
    ) throws -> ChapterEditing.Result {
        let fm = FileManager.default
        let source = try Data(contentsOf: libraryURL)
        let state = fm.fileExists(atPath: stateURL.path)
            ? try Data(contentsOf: stateURL)
            : try JSONSerialization.data(withJSONObject: freshState())
        return try ChapterEditing.apply(
            libraryData: source,
            stateData: state,
            chapterID: chapter.id,
            expectedTitle: chapter.displayTitle,
            expectedParagraphs: ChapterEditing.paragraphs(of: chapter),
            title: title,
            paragraphs: paragraphs
        )
    }

    @discardableResult
    func saveChapterEdits(
        for chapter: LibraryChapter,
        title: String,
        paragraphs: [ChapterEditing.Paragraph]
    ) throws -> ChapterEditing.Result {
        let fm = FileManager.default
        let oldLibrary = try Data(contentsOf: libraryURL)
        let oldState: Data? = fm.fileExists(atPath: stateURL.path)
            ? try Data(contentsOf: stateURL) : nil
        let state = try oldState ?? JSONSerialization.data(
            withJSONObject: freshState()
        )
        // Calculate all remappings before touching anything on disk.
        let result = try ChapterEditing.apply(
            libraryData: oldLibrary,
            stateData: state,
            chapterID: chapter.id,
            expectedTitle: chapter.displayTitle,
            expectedParagraphs: ChapterEditing.paragraphs(of: chapter),
            title: title,
            paragraphs: paragraphs
        )
        _ = try LibrarySnapshot.parse(result.libraryData)

        let backup = rootURL
            .appendingPathComponent("Edits", isDirectory: true)
            .appendingPathComponent(
                "BeforeEdit-" + UUID().uuidString, isDirectory: true
            )
        try fm.createDirectory(at: backup, withIntermediateDirectories: true)
        // Keep the exact prior state and library so annotated passages can
        // always be recovered. Imported original DOCX never changes.
        try oldLibrary.write(
            to: backup.appendingPathComponent("qt_library.json"),
            options: .atomic
        )
        if let oldState {
            try oldState.write(
                to: backup.appendingPathComponent("preview_state.json"),
                options: .atomic
            )
        }

        do {
            try result.libraryData.write(to: libraryURL, options: .atomic)
            try result.stateData.write(to: stateURL, options: .atomic)
        } catch {
            let saveError = error
            do {
                try oldLibrary.write(to: libraryURL, options: .atomic)
                if let oldState {
                    try oldState.write(to: stateURL, options: .atomic)
                } else if fm.fileExists(atPath: stateURL.path) {
                    try fm.removeItem(at: stateURL)
                }
            } catch {
                throw NSError(
                    domain: "StarReader.ChapterEditing", code: 2,
                    userInfo: [NSLocalizedDescriptionKey:
                        "Не удалось сохранить правки и откатить библиотеку. " +
                        "Исходные данные есть в резервной папке BeforeEdit. " +
                        "Не вноси новые изменения до восстановления."]
                )
            }
            throw saveError
        }

        loadFromDisk()
        return result
    }

    // MARK: - Confirmed library deletion (always backup first)

    func deleteChapter(_ chapter: LibraryChapter) throws {
        try delete(.chapter(id: chapter.id))
    }

    func deleteVolume(_ volume: LibraryVolume) throws {
        try delete(.volume(series: volume.series, title: volume.title))
    }

    private func delete(_ target: LibraryDeletion.Target) throws {
        let fm = FileManager.default
        let oldLibrary = try Data(contentsOf: libraryURL)
        let hadState = fm.fileExists(atPath: stateURL.path)
        let oldState: Data? = hadState ? try Data(contentsOf: stateURL) : nil
        let currentState: Data = try oldState ?? JSONSerialization.data(
            withJSONObject: freshState()
        )

        // Validate and calculate both new JSON documents before touching
        // live data. If any field is corrupt the deletion is refused.
        let result = try LibraryDeletion.remove(
            target,
            from: oldLibrary,
            stateData: currentState
        )
        _ = try LibrarySnapshot.parse(result.libraryData)

        let backups = rootURL.appendingPathComponent("Deletes", isDirectory: true)
        let backup = backups.appendingPathComponent(
            "BeforeDelete-" + UUID().uuidString, isDirectory: true
        )
        try fm.createDirectory(at: backup, withIntermediateDirectories: true)
        // The complete previous JSON (including notes, bookmarks, progress)
        // is preserved until the user chooses to clear old backups manually.
        try oldLibrary.write(
            to: backup.appendingPathComponent("qt_library.json"),
            options: .atomic
        )
        if let oldState {
            try oldState.write(
                to: backup.appendingPathComponent("preview_state.json"),
                options: .atomic
            )
        }

        do {
            try result.libraryData.write(to: libraryURL, options: .atomic)
            try result.stateData.write(to: stateURL, options: .atomic)
        } catch {
            let primaryError = error
            // A two-file save can fail between writes. Attempt to restore the
            // exact old pair instead of exposing a mismatched library/state.
            do {
                try oldLibrary.write(to: libraryURL, options: .atomic)
                if let oldState {
                    try oldState.write(to: stateURL, options: .atomic)
                } else if fm.fileExists(atPath: stateURL.path) {
                    try fm.removeItem(at: stateURL)
                }
            } catch {
                throw NSError(
                    domain: "StarReader.LibraryDelete", code: 2,
                    userInfo: [NSLocalizedDescriptionKey:
                        "Сохранение не удалось, автоматический откат тоже. " +
                        "Исходные файлы остались в локальной копии BeforeDelete. " +
                        "Не импортируй новые данные до восстановления."]
                )
            }
            throw primaryError
        }

        loadFromDisk()
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
