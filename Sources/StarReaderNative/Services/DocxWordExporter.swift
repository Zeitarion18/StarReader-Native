import Foundation
import ZIPFoundation

/// Writes an independent Word file into a temporary directory. Reads ONLY
/// the supplied chapter snapshot; never mutates qt_library.json, the original
/// imported DOCX, reading progress, notes, bookmarks or statistics.
enum DocxWordExporter {
    enum ExportError: LocalizedError {
        case unableToCreateArchive
        case packageIncomplete
        case outputTooLarge

        var errorDescription: String? {
            switch self {
            case .unableToCreateArchive:
                return "Не удалось создать Word-файл. Попробуй экспорт ещё раз."
            case .packageIncomplete:
                return "Готовый DOCX не прошёл проверку целостности."
            case .outputTooLarge:
                return "Получился слишком большой Word-файл для безопасного экспорта."
            }
        }
    }

    static func exportChapter(_ chapter: LibraryChapter) throws -> URL {
        let parts = try DocxWordprocessingML.package(chapters: [chapter])
        return try write(
            parts: parts,
            filename: DocxWordprocessingML.filename(chapter.displayTitle)
        )
    }

    static func exportVolume(
        _ volume: LibraryVolume,
        chapters: [LibraryChapter]
    ) throws -> URL {
        let parts = try DocxWordprocessingML.package(
            chapters: chapters,
            volumeTitle: volume.title,
            workTitle: volume.series
        )
        return try write(
            parts: parts,
            filename: DocxWordprocessingML.filename(volume.title)
        )
    }

    private static func write(
        parts: [DocxWordprocessingML.Part],
        filename: String
    ) throws -> URL {
        let fm = FileManager.default
        let exportRoot = fm.temporaryDirectory.appendingPathComponent(
            "StarReader-Word", isDirectory: true
        )
        // Each export gets its own directory. The share controller receives
        // a real file URL, and separate exports cannot overwrite each other.
        let session = exportRoot.appendingPathComponent(
            UUID().uuidString, isDirectory: true
        )
        let staging = session.appendingPathComponent(
            "staging", isDirectory: true
        )
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        let destination = session.appendingPathComponent(filename)
        do {
            for part in parts {
                let target = staging.appendingPathComponent(part.path)
                try fm.createDirectory(
                    at: target.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try part.bytes.write(to: target, options: .atomic)
            }
            do {
                guard let archive = Archive(url: destination, accessMode: .create) else {
                    throw ExportError.unableToCreateArchive
                }
                for part in parts {
                    try archive.addEntry(
                        with: part.path,
                        relativeTo: staging,
                        compressionMethod: .deflate
                    )
                }
            }
            guard let archive = Archive(url: destination, accessMode: .read) else {
                throw ExportError.packageIncomplete
            }
            for part in parts {
                guard let entry = archive[part.path],
                      entry.type == .file,
                      entry.uncompressedSize == UInt64(part.bytes.count) else {
                    throw ExportError.packageIncomplete
                }
            }
            let size = try destination.resourceValues(forKeys: [.fileSizeKey])
                .fileSize ?? 0
            guard size > 0 && size <= 50 * 1024 * 1024 else {
                throw ExportError.outputTooLarge
            }

            // Verify the generated DOCX with the very same importer that
            // StarReader uses for user-selected Word documents.
            let verified = try SingleDocxImporter.read(from: destination)
            guard !verified.paragraphs.isEmpty else {
                throw ExportError.packageIncomplete
            }
            try? fm.removeItem(at: staging)
            return destination
        } catch {
            try? fm.removeItem(at: session)
            throw error
        }
    }
}
