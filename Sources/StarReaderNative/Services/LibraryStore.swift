import Foundation
import Combine

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var snapshot = LibrarySnapshot(works: [], volumes: [], chapters: [])
    @Published private(set) var progressByBook: [String: ReaderProgress] = [:]
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

        let fileManager = FileManager.default
        let originalsURL = rootURL.appendingPathComponent("originals", isDirectory: true)
        let importsURL = rootURL.appendingPathComponent("Imports", isDirectory: true)

        try fileManager.createDirectory(at: importsURL, withIntermediateDirectories: true)
        let backupURL = importsURL.appendingPathComponent("StarReader-\(UUID().uuidString).zip")
        try transfer.archiveData.write(to: backupURL, options: .atomic)

        if fileManager.fileExists(atPath: originalsURL.path) {
            try fileManager.removeItem(at: originalsURL)
        }
        try fileManager.createDirectory(at: originalsURL, withIntermediateDirectories: true)

        for (name, data) in transfer.originals {
            try data.write(to: originalsURL.appendingPathComponent(name), options: .atomic)
        }

        try transfer.libraryData.write(to: libraryURL, options: .atomic)
        try transfer.stateData.write(to: stateURL, options: .atomic)

        pendingTransfer = nil
        pendingSummary = nil
        loadFromDisk()
    }

    func recordProgress(for chapter: LibraryChapter, paragraph: Int, offset: Int = 0) {
        let safeParagraph = min(max(0, paragraph), max(0, chapter.paragraphs.count - 1))
        let safeOffset = max(0, offset)
        let before = chapter.paragraphs.prefix(safeParagraph).reduce(0) { $0 + $1.text.count }
        let currentLength = chapter.paragraphs.indices.contains(safeParagraph)
            ? chapter.paragraphs[safeParagraph].text.count : 0
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
            let data = try JSONSerialization.data(withJSONObject: stateObject, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: stateURL, options: .atomic)
        } catch {
            statusMessage = "Не удалось сохранить позицию чтения: \(error.localizedDescription)"
        }
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: libraryURL.path) else {
            snapshot = LibrarySnapshot(works: [], volumes: [], chapters: [])
            progressByBook = [:]
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
        } catch {
            statusMessage = "Не удалось открыть локальную библиотеку: \(error.localizedDescription)"
        }
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
