import Foundation
import CryptoKit
import ZIPFoundation

/// Creates a genuine StarReader Qt Transfer-compatible ZIP.
/// The export is validated with the *existing import parser* before it is
/// offered through the iOS share sheet.
enum LibraryBackupExporter {
    enum ExportError: LocalizedError {
        case invalidLibrary
        case missingOriginal(String)
        case oversized
        case unableToCreateArchive

        var errorDescription: String? {
            switch self {
            case .invalidLibrary:
                return "Библиотека повреждена. Резервная копия не создана."
            case .missingOriginal(let file):
                return "Для главы отсутствует исходный DOCX «\(file)». Экспорт остановлен, чтобы не создать неполную копию."
            case .oversized:
                return "Библиотека превышает лимит резервного ZIP (350 МБ)."
            case .unableToCreateArchive:
                return "Не удалось создать ZIP-архив резервной копии."
            }
        }
    }

    static func export(from root: URL) throws -> URL {
        let fm = FileManager.default
        let libraryURL = root.appendingPathComponent("qt_library.json")
        let stateURL = root.appendingPathComponent("preview_state.json")
        let originals = root.appendingPathComponent("originals", isDirectory: true)

        let libraryData: Data = try fm.fileExists(atPath: libraryURL.path)
            ? Data(contentsOf: libraryURL)
            : JSONSerialization.data(withJSONObject: [
                "schema": 2, "works": [String](),
                "volumes": [[String: Any]](), "books": [[String: Any]](),
                "trash": [Any]()
            ])
        let stateData: Data = try fm.fileExists(atPath: stateURL.path)
            ? Data(contentsOf: stateURL)
            : JSONSerialization.data(withJSONObject: [
                "schema": 1, "progress": [String: Any](),
                "annotations": [[String: Any]](), "bookmarks": [[String: Any]](),
                "settings": ["theme": "night", "mode": "pages"]
            ])

        guard let rootJSON = try JSONSerialization.jsonObject(
            with: libraryData
        ) as? [String: Any],
        rootJSON["schema"] as? Int == 2,
        rootJSON["works"] is [String],
        rootJSON["volumes"] is [[String: Any]],
        rootJSON["trash"] is [Any],
        let books = rootJSON["books"] as? [[String: Any]] else {
            throw ExportError.invalidLibrary
        }
        // Ensure current transfer schema and all ID/paragraph invariants.
        let model = try LibrarySnapshot.parse(libraryData)
        guard model.chapters.count == books.count else {
            throw ExportError.invalidLibrary
        }

        let required = try Set(books.compactMap { book -> String? in
            guard let file = book["originalFile"] as? String else { return nil }
            guard TransferImporter.isSafeOriginalName(file) else {
                throw ExportError.invalidLibrary
            }
            return file
        })
        for name in required {
            let url = originals.appendingPathComponent(name)
            guard fm.fileExists(atPath: url.path) else {
                throw ExportError.missingOriginal(name)
            }
        }

        let scratch = fm.temporaryDirectory.appendingPathComponent(
            "StarReaderExport-" + UUID().uuidString, isDirectory: true
        )
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: scratch) }

        var listed: [[String: Any]] = []
        var totalSize = 0
        func stage(_ data: Data, as path: String) throws {
            guard data.count <= 120 * 1024 * 1024 else {
                throw ExportError.oversized
            }
            totalSize += data.count
            guard totalSize <= 500 * 1024 * 1024 else {
                throw ExportError.oversized
            }
            let destination = scratch.appendingPathComponent(path)
            try fm.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: destination, options: .atomic)
            listed.append([
                "path": path,
                "size": data.count,
                "sha256": SHA256.hash(data: data)
                    .map { String(format: "%02x", $0) }.joined()
            ])
        }
        try stage(libraryData, as: "data/qt_library.json")
        try stage(stateData, as: "data/preview_state.json")
        for file in required.sorted() {
            try stage(
                Data(contentsOf: originals.appendingPathComponent(file)),
                as: "originals/" + file
            )
        }

        let manifest: [String: Any] = [
            "format": "starreader-qt-library-transfer",
            "schema": 1,
            "createdAt": ISO8601DateFormatter().string(from: Date()),
            "files": listed
        ]
        let manifestData = try JSONSerialization.data(
            withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]
        )
        try manifestData.write(
            to: scratch.appendingPathComponent("starreader-library-manifest.json"),
            options: .atomic
        )

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let archiveURL = fm.temporaryDirectory.appendingPathComponent(
            "StarReader-Backup-" + timestamp + "-" +
            String(UUID().uuidString.prefix(8)) + ".zip"
        )
        do {
            // Close the writer before re-opening the ZIP for verification.
            do {
                guard let archive = Archive(
                    url: archiveURL, accessMode: .create
                ) else {
                    throw ExportError.unableToCreateArchive
                }
                let paths = ["starreader-library-manifest.json"] +
                    listed.compactMap { $0["path"] as? String }
                guard paths.count <= 1_600 else {
                    throw ExportError.oversized
                }
                for file in paths {
                    // No compression avoids false ZIP-bomb detection during
                    // restore and works well for already-compressed DOCX.
                    try archive.addEntry(
                        with: file,
                        relativeTo: scratch,
                        compressionMethod: .none
                    )
                }
            }
            let size = try archiveURL.resourceValues(
                forKeys: [.fileSizeKey]
            ).fileSize ?? 0
            guard size <= 350 * 1024 * 1024 else {
                throw ExportError.oversized
            }

            // Export must pass the exact iPhone importer, including checksum
            // and state validation; an incomplete ZIP will never be shared.
            let verified = try TransferImporter.read(from: archiveURL)
            guard verified.libraryData == libraryData,
                  verified.stateData == stateData else {
                throw ExportError.invalidLibrary
            }
            return archiveURL
        } catch {
            try? fm.removeItem(at: archiveURL)
            throw error
        }
    }
}
