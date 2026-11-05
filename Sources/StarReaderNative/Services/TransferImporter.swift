import Foundation
import CryptoKit
import ZIPFoundation

struct ImportSummary: Sendable {
    let workCount: Int
    let volumeCount: Int
    let chapterCount: Int
    let noteCount: Int
    let bookmarkCount: Int
    let originalCount: Int
}

struct ImportedTransfer: Sendable {
    let libraryData: Data
    let stateData: Data
    let originals: [String: Data]
    let archiveData: Data
    let summary: ImportSummary
}

enum TransferImportError: LocalizedError {
    case archiveTooLarge
    case unreadableArchive
    case tooManyEntries
    case unsupportedEntry(String)
    case unsafeArchive(String)
    case fileTooLarge(String)
    case archiveExpansionTooLarge
    case missingFile(String)
    case invalidManifest
    case checksumMismatch(String)
    case invalidLibrary(String)
    case invalidState
    case missingOriginal(String)

    var errorDescription: String? {
        switch self {
        case .archiveTooLarge:
            return "ZIP превышает допустимый размер 350 МБ."
        case .unreadableArchive:
            return "Не удалось открыть ZIP-архив."
        case .tooManyEntries:
            return "В архиве слишком много файлов."
        case .unsupportedEntry(let path):
            return "В архиве найден неподдерживаемый элемент: \(path)"
        case .unsafeArchive(let path):
            return "В архиве найден небезопасный или посторонний путь: \(path)"
        case .fileTooLarge(let path):
            return "Файл внутри архива слишком большой: \(path)"
        case .archiveExpansionTooLarge:
            return "Распакованный архив превышает допустимый объём 500 МБ."
        case .missingFile(let path):
            return "В архиве отсутствует обязательный файл: \(path)"
        case .invalidManifest:
            return "Манифест StarReader отсутствует или имеет неизвестный формат."
        case .checksumMismatch(let path):
            return "Не совпала контрольная сумма файла: \(path). Импорт отменён."
        case .invalidLibrary(let reason):
            return "Библиотека повреждена: \(reason)"
        case .invalidState:
            return "Файл состояния чтения имеет неверный формат."
        case .missingOriginal(let name):
            return "В архиве отсутствует оригинальный DOCX: \(name)"
        }
    }
}

enum TransferImporter {
    private static let manifestName = "starreader-library-manifest.json"
    private static let libraryName = "data/qt_library.json"
    private static let stateName = "data/preview_state.json"
    private static let maxArchiveSize = 350 * 1024 * 1024
    private static let maxFileSize = 120 * 1024 * 1024
    private static let maxTotalSize = 500 * 1024 * 1024
    private static let maxEntries = 1_600

    static func read(from url: URL) throws -> ImportedTransfer {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let fileSize = values.fileSize, fileSize <= maxArchiveSize else {
            throw TransferImportError.archiveTooLarge
        }
        guard let archive = Archive(url: url, accessMode: .read) else {
            throw TransferImportError.unreadableArchive
        }

        let entries = Array(archive)
        guard entries.count <= maxEntries else {
            throw TransferImportError.tooManyEntries
        }

        var extracted: [String: Data] = [:]
        var totalSize = 0

        for entry in entries {
            guard entry.type == .file else {
                throw TransferImportError.unsupportedEntry(entry.path)
            }
            guard isAllowedPath(entry.path) else {
                throw TransferImportError.unsafeArchive(entry.path)
            }
            guard entry.uncompressedSize <= UInt64(maxFileSize) else {
                throw TransferImportError.fileTooLarge(entry.path)
            }

            let unpacked = Int(entry.uncompressedSize)
            let packed = Int(entry.compressedSize)
            if unpacked > 1_024 * 1_024, packed > 0, unpacked / packed > 250 {
                throw TransferImportError.fileTooLarge(entry.path)
            }

            totalSize += unpacked
            guard totalSize <= maxTotalSize else {
                throw TransferImportError.archiveExpansionTooLarge
            }

            var data = Data()
            _ = try archive.extract(entry) { chunk in
                data.append(chunk)
            }
            extracted[entry.path] = data
        }

        guard let manifestData = extracted[manifestName],
              let manifest = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
              manifest["format"] as? String == "starreader-qt-library-transfer",
              manifest["schema"] as? Int == 1,
              let manifestFiles = manifest["files"] as? [[String: Any]] else {
            throw TransferImportError.invalidManifest
        }

        var expectedPaths: Set<String> = [manifestName]
        var verifiedFiles: [String: Data] = [:]

        for item in manifestFiles {
            guard let path = item["path"] as? String,
                  let expectedSize = item["size"] as? Int,
                  let expectedHash = item["sha256"] as? String,
                  isAllowedDataPath(path),
                  !expectedPaths.contains(path) else {
                throw TransferImportError.invalidManifest
            }

            expectedPaths.insert(path)
            guard let data = extracted[path] else {
                throw TransferImportError.missingFile(path)
            }
            guard data.count == expectedSize, sha256(data) == expectedHash.lowercased() else {
                throw TransferImportError.checksumMismatch(path)
            }
            verifiedFiles[path] = data
        }

        guard Set(extracted.keys) == expectedPaths else {
            let unexpected = Set(extracted.keys).subtracting(expectedPaths).sorted().first ?? "unknown"
            throw TransferImportError.unsafeArchive(unexpected)
        }

        guard let libraryData = verifiedFiles[libraryName],
              let stateData = verifiedFiles[stateName] else {
            throw TransferImportError.missingFile(libraryName + " / " + stateName)
        }

        let libraryRoot = try JSONSerialization.jsonObject(with: libraryData) as? [String: Any]
        guard let library = libraryRoot,
              library["schema"] as? Int == 2,
              let works = library["works"] as? [String],
              let volumes = library["volumes"] as? [[String: Any]],
              let books = library["books"] as? [[String: Any]],
              let trash = library["trash"] as? [Any] else {
            throw TransferImportError.invalidLibrary("ожидаются schema 2 и массивы works, volumes, books, trash")
        }

        var bookIDs = Set<String>()
        var requiredOriginals = Set<String>()
        for book in books {
            guard let id = book["id"] as? String, !id.isEmpty,
                  bookIDs.insert(id).inserted,
                  let paragraphs = book["paragraphs"] as? [[String: Any]],
                  paragraphs.allSatisfy({ $0["text"] is String }) else {
                throw TransferImportError.invalidLibrary("найдена глава без ID, с повторным ID или повреждёнными абзацами")
            }
            if let original = book["originalFile"] as? String {
                guard isSafeOriginalName(original) else {
                    throw TransferImportError.invalidLibrary("недопустимое имя оригинального DOCX")
                }
                requiredOriginals.insert(original)
            }
        }

        guard let state = try JSONSerialization.jsonObject(with: stateData) as? [String: Any],
              state["schema"] as? Int == 1,
              state["progress"] is [String: Any],
              state["settings"] is [String: Any],
              state["annotations"] is [Any],
              state["bookmarks"] is [Any] else {
            throw TransferImportError.invalidState
        }

        var originals: [String: Data] = [:]
        for (path, data) in verifiedFiles where path.hasPrefix("originals/") {
            let name = String(path.dropFirst("originals/".count))
            originals[name] = data
        }
        for name in requiredOriginals where originals[name] == nil {
            throw TransferImportError.missingOriginal(name)
        }

        return ImportedTransfer(
            libraryData: libraryData,
            stateData: stateData,
            originals: originals,
            archiveData: try Data(contentsOf: url, options: .mappedIfSafe),
            summary: ImportSummary(
                workCount: works.count,
                volumeCount: volumes.count,
                chapterCount: books.count,
                noteCount: (state["annotations"] as? [Any])?.count ?? 0,
                bookmarkCount: (state["bookmarks"] as? [Any])?.count ?? 0,
                originalCount: originals.count
            )
        )
    }

    static func isSafeOriginalName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 180,
              name.lowercased().hasSuffix(".docx"),
              !name.contains(".."),
              !name.contains("/"),
              !name.contains("\\"),
              !name.hasSuffix(" ") else { return false }
        return name.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
    }

    private static func isAllowedPath(_ path: String) -> Bool {
        path == manifestName || isAllowedDataPath(path)
    }

    private static func isAllowedDataPath(_ path: String) -> Bool {
        if path == libraryName || path == stateName { return true }
        guard path.hasPrefix("originals/") else { return false }
        return isSafeOriginalName(String(path.dropFirst("originals/".count)))
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
