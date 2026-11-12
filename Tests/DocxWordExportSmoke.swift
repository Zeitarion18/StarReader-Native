import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

@main
enum DocxWordExportSmoke {
    static func main() throws {
        func para(_ index: Int, _ text: String, heading: Bool = false) -> ReaderParagraph {
            ReaderParagraph(index: index, text: text, heading: heading)
        }
        let first = LibraryChapter(
            id: "chapter-1", name: "Original filename",
            series: "Восхождение", volume: "Том 15",
            chapter: "Глава 1. Свет для наших вечеров",
            paragraphs: [
                para(0, "Текст из исправленного редактора: Зейт держит Штандарт."),
                para(1, "Лиара сказала: «Я & ты <3» — \"вместе\". 🌟"),
                para(2, "Строка 1\nСтрока 2\tпосле табуляции"),
                para(3, "Подзаголовок", heading: true),
                para(4, "Конец первой главы.")
            ],
            originalFile: "old-unchanged.docx"
        )
        let second = LibraryChapter(
            id: "chapter-2", name: "Глава 2",
            series: "Восхождение", volume: "Том 15",
            chapter: "Глава 2. Новое начало",
            paragraphs: [
                para(0, "Исправленный второй текст."),
                para(1, "И мир снова стал светлым.")
            ],
            originalFile: "shared-imported-volume.docx"
        )
        let originalFirst = first
        let originalSecond = second
        let fixedDate = Date(timeIntervalSince1970: 1_783_000_000)
        let single = try DocxWordprocessingML.package(
            chapters: [first], created: fixedDate
        )
        let volume = try DocxWordprocessingML.package(
            chapters: [first, second],
            volumeTitle: "Том 15",
            workTitle: "Восхождение",
            created: fixedDate
        )
        precondition(single.count == 7)
        precondition(volume.count == 7)
        let singleXML = String(
            data: single.first { $0.path == "word/document.xml" }!.bytes,
            encoding: .utf8
        )!
        let xml = String(
            data: volume.first { $0.path == "word/document.xml" }!.bytes,
            encoding: .utf8
        )!
        precondition(xml.contains("Зейт держит Штандарт"))
        precondition(!xml.contains("old-unchanged"))
        precondition(!xml.contains("shared-imported-volume"))
        precondition(xml.contains("&amp;"))
        precondition(xml.contains("&lt;3"))
        precondition(xml.contains("&quot;"))
        precondition(xml.contains("<w:tab/>"))
        precondition(xml.contains("<w:br/>"))
        precondition(xml.contains("🌟"))
        precondition(xml.contains("w:pageBreakBefore"))
        precondition(xml.contains("Heading1"))
        precondition(xml.contains("Heading2"))
        precondition(singleXML.contains("Зейт держит Штандарт"))
        precondition(!singleXML.contains("Глава 2. Новое начало"))
        precondition(first == originalFirst && second == originalSecond)

        precondition(DocxWordprocessingML.filename("Глава 1. Свет/Начало") == "Глава 1. Свет_Начало.docx")
        precondition(DocxWordprocessingML.filename("???") == "StarReader.docx")
        precondition(DocxWordprocessingML.filename("Зейт: * Глава") == "Зейт_ _ Глава.docx")
        do {
            _ = try DocxWordprocessingML.package(chapters: [])
            preconditionFailure("Empty chapter list should reject")
        } catch DocxWordprocessingML.Error.noChapters {}
        do {
            let empty = LibraryChapter(
                id: "empty", name: "empty",
                series: "empty", volume: "1", chapter: "No text",
                paragraphs: [], originalFile: nil
            )
            _ = try DocxWordprocessingML.package(chapters: [empty])
            preconditionFailure("Empty text should reject")
        } catch DocxWordprocessingML.Error.emptyDocument {}

        let fm = FileManager.default
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/tmp/starreader-word-test")
        try fm.createDirectory(at: output, withIntermediateDirectories: true)
        for part in volume {
            let file = output.appendingPathComponent(part.path)
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try part.bytes.write(to: file, options: .atomic)
            if part.path.hasSuffix(".xml") || part.path.hasSuffix(".rels") {
                let parser = XMLParser(data: part.bytes)
                parser.shouldResolveExternalEntities = false
                precondition(parser.parse(), "Malformed XML in \(part.path): \(parser.parserError?.localizedDescription ?? "unknown")")
            }
        }
        print("PASS: WordprocessingML package, live edited text, order, escaping, headings, line breaks, Unicode, filename, XML parsing, original immutability.")
    }
}
