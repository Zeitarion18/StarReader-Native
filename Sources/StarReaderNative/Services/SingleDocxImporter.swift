import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import ZIPFoundation

struct ImportedDocxChapter: Identifiable, Sendable {
    let id: UUID
    let sourceFileName: String
    let suggestedTitle: String
    let paragraphs: [ImportedDocxParagraph]
    let originalData: Data

    var characterCount: Int {
        paragraphs.reduce(0) { $0 + $1.text.unicodeScalars.count }
    }
}

struct ImportedDocxParagraph: Sendable {
    let text: String
    let heading: Bool
}

enum SingleDocxImportError: LocalizedError {
    case invalidExtension
    case tooLarge
    case invalidArchive
    case missingDocument
    case invalidXML
    case emptyDocument
    case tooManyParagraphs

    var errorDescription: String? {
        switch self {
        case .invalidExtension:
            return "Выбери файл Word с расширением .docx."
        case .tooLarge:
            return "DOCX слишком большой для безопасного импорта (до 40 МБ)."
        case .invalidArchive:
            return "Не удалось открыть DOCX: неверная структура архива."
        case .missingDocument:
            return "В DOCX отсутствует основной текст word/document.xml."
        case .invalidXML:
            return "Не удалось разобрать текст документа Word."
        case .emptyDocument:
            return "В документе нет текстовых абзацев для чтения."
        case .tooManyParagraphs:
            return "В документе слишком много абзацев для безопасного импорта."
        }
    }
}

/// Reads the WordprocessingML body, retaining paragraphs and logical headings.
/// Embedded images, drawings, comments and Word styling aren't rendered.
enum SingleDocxImporter {
    private static let maxDocxBytes = 40 * 1024 * 1024
    private static let maxXMLBytes: UInt64 = 55 * 1024 * 1024

    static func read(from url: URL) throws -> ImportedDocxChapter {
        guard url.pathExtension.lowercased() == "docx" else {
            throw SingleDocxImportError.invalidExtension
        }
        let attr = try url.resourceValues(forKeys: [.fileSizeKey])
        if let size = attr.fileSize, size > maxDocxBytes {
            throw SingleDocxImportError.tooLarge
        }
        let data = try Data(contentsOf: url)
        guard data.count > 0, data.count <= maxDocxBytes else {
            throw SingleDocxImportError.tooLarge
        }

        let archive: Archive
        do {
            archive = try Archive(data: data, accessMode: .read)
        } catch {
            throw SingleDocxImportError.invalidArchive
        }
        guard let document = archive["word/document.xml"],
              document.type == .file else {
            throw SingleDocxImportError.missingDocument
        }
        guard document.uncompressedSize <= maxXMLBytes else {
            throw SingleDocxImportError.tooLarge
        }

        var xmlData = Data()
        do {
            _ = try archive.extract(document) { chunk in
                xmlData.append(chunk)
                if xmlData.count > Int(maxXMLBytes) {
                    throw SingleDocxImportError.tooLarge
                }
            }
        } catch let error as SingleDocxImportError {
            throw error
        } catch {
            throw SingleDocxImportError.invalidArchive
        }

        let collector = WordParagraphCollector()
        let parser = XMLParser(data: xmlData)
        parser.shouldResolveExternalEntities = false
        parser.delegate = collector
        guard parser.parse() else {
            if collector.exceededLimit {
                throw SingleDocxImportError.tooManyParagraphs
            }
            throw SingleDocxImportError.invalidXML
        }
        let paragraphs = collector.paragraphs
        guard !paragraphs.isEmpty else {
            throw SingleDocxImportError.emptyDocument
        }
        let name = url.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ImportedDocxChapter(
            id: UUID(),
            sourceFileName: url.lastPathComponent,
            suggestedTitle: name.isEmpty ? "Новая глава" : String(name.prefix(180)),
            paragraphs: paragraphs,
            originalData: data
        )
    }
}

private final class WordParagraphCollector: NSObject, XMLParserDelegate {
    private(set) var paragraphs: [ImportedDocxParagraph] = []
    private(set) var exceededLimit = false

    private var insideBody = false
    private var insideParagraph = false
    private var insideText = false
    private var currentText = ""
    private var currentIsHeading = false
    private var totalCharacters = 0

    private static let maxParagraphs = 35_000
    private static let maxCharacters = 8_000_000

    private func localName(_ value: String) -> String {
        String(value.split(separator: ":").last ?? Substring(value))
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = localName(elementName)
        if name == "body" {
            insideBody = true
        } else if name == "p" && insideBody && !insideParagraph {
            insideParagraph = true
            currentText = ""
            currentIsHeading = false
        } else if insideParagraph {
            switch name {
            case "pStyle":
                let style = attributeDict["w:val"] ?? attributeDict["val"] ?? ""
                currentIsHeading = style.localizedCaseInsensitiveContains("Heading")
                    || style.localizedCaseInsensitiveContains("Заголовок")
                    || style.localizedCaseInsensitiveContains("Title")
            case "t":
                // w:t text is processed by SAX in its original run order.
                insideText = true
            case "tab":
                currentText.append("    ")
            case "br", "cr":
                currentText.append("\n")
            default:
                break
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideParagraph && insideText {
            currentText.append(string)
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = localName(elementName)
        if name == "t" { insideText = false }
        if name == "p" && insideParagraph {
            let text = currentText
                .replacingOccurrences(of: "\r", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                totalCharacters += text.unicodeScalars.count
                paragraphs.append(
                    ImportedDocxParagraph(text: text, heading: currentIsHeading)
                )
            }
            insideParagraph = false
            currentText = ""
            if paragraphs.count > Self.maxParagraphs ||
                totalCharacters > Self.maxCharacters {
                exceededLimit = true
                parser.abortParsing()
            }
        }
        if name == "body" {
            insideBody = false
        }
    }
}
