import Foundation

// Pure Foundation mirrors of the DTOs produced by ZIPFoundation/XMLParser.
// This allows deterministic parser-boundary tests on macOS Swift CLI.
struct ImportedDocxParagraph {
    let text: String
    let heading: Bool
}
struct ImportedDocxChapter {
    let sourceFileName: String
    let suggestedTitle: String
    let paragraphs: [ImportedDocxParagraph]
}

@main
enum VolumeDocxSplitterSmoke {
    static func main() throws {
        func p(_ value: String, heading: Bool = false) -> ImportedDocxParagraph {
            ImportedDocxParagraph(text: value, heading: heading)
        }

        let doc = ImportedDocxChapter(
            sourceFileName: "Том_14.docx",
            suggestedTitle: "Том 14",
            paragraphs: [
                p("Предисловие автора"),
                p("Всё началось неожиданно."),
                p("Пролог. В этот раз я хочу успеть", heading: true),
                p("Зейт открыл глаза."),
                p("Глава 1. Новая жизнь"),
                p("Лиара улыбнулась."),
                p("Глава 2 — Встреча", heading: true),
                p("Штандарт загорелся."),
                p("Эпилог. Счастье быть с тобой", heading: true),
                p("Они взялись за руки.")
            ]
        )
        let detected = VolumeDocxSplitter.detect(in: doc)
        precondition(detected.count == 5, "Expected preface + 4 canonical sections: \(detected)")
        precondition(detected.map(\.startParagraph) == [1,3,5,7,9])
        precondition(detected[0].title == "Вступление")
        precondition(detected[1].title == "Пролог. В этот раз я хочу успеть")
        precondition(detected[2].title == "Глава 1. Новая жизнь")
        precondition(detected[3].title == "Глава 2. Встреча")
        precondition(detected[4].title == "Эпилог. Счастье быть с тобой")

        let sections = try VolumeDocxSplitter.sections(in: doc, drafts: detected)
        precondition(sections.count == 5)
        precondition(sections.map(\.paragraphs.count) == [2,2,2,2,2])
        precondition(sections.flatMap(\.paragraphs).map(\.text) == doc.paragraphs.map(\.text))
        precondition(sections[0].startParagraph == 1 && sections[0].endParagraph == 2)
        precondition(sections[4].startParagraph == 9 && sections[4].endParagraph == 10)

        // Turning off a detected section skips exactly its text, not the
        // following chapter and not the earlier paragraph of the preface.
        var selected = detected
        selected[2].include = false
        let selective = try VolumeDocxSplitter.sections(in: doc, drafts: selected)
        precondition(selective.count == 4)
        precondition(!selective.flatMap(\.paragraphs).map(\.text).contains("Лиара улыбнулась."))
        precondition(selective.last?.paragraphs.last?.text == "Они взялись за руки.")

        // User-edited boundaries reassign only the intended paragraph, while
        // preserving every source paragraph once.
        var edited = detected
        edited[3].startParagraph = 8
        let shifted = try VolumeDocxSplitter.sections(in: doc, drafts: edited)
        precondition(shifted.map(\.paragraphs.count) == [2,2,3,1,2])
        precondition(shifted.flatMap(\.paragraphs).map(\.text) == doc.paragraphs.map(\.text))

        do {
            var colliding = detected
            colliding[2].startParagraph = 3
            _ = try VolumeDocxSplitter.sections(in: doc, drafts: colliding)
            preconditionFailure("Overlapping boundaries must fail")
        } catch VolumeDocxSplitter.Failure.invalidBoundaries {}

        do {
            var none = detected
            for i in none.indices { none[i].include = false }
            _ = try VolumeDocxSplitter.sections(in: doc, drafts: none)
            preconditionFailure("No selected chapters must fail")
        } catch VolumeDocxSplitter.Failure.noSelectedSections {}

        let unrecognized = ImportedDocxChapter(
            sourceFileName: "Старый_том.docx",
            suggestedTitle: "Старый том",
            paragraphs: [
                p("Я не думаю, что слово глава тут означает заголовок."),
                p("Обычный текст."),
                p("Продолжение.")
            ]
        )
        let fallback = VolumeDocxSplitter.detect(in: unrecognized)
        precondition(fallback.count == 1 && fallback[0].title == "Старый том")
        precondition(!fallback[0].confidence)

        // One JSON append for the whole tome. Each new chapter has a unique
        // stable ID; one shared DOCX reference avoids duplicate original files.
        let input: [String: Any] = [
            "schema": 2,
            "works": ["Моё ранобэ"],
            "volumes": [["series": "Моё ранобэ", "title": "Том 14"]],
            "books": [[
                "id": "old-chapter", "series": "Моё ранобэ",
                "volume": "Том 14",
                "name": "Старая глава", "chapter": "Старая глава",
                "originalFile": "original.docx",
                "paragraphs": [["text": "История сохранена", "heading": false]]
            ]],
            "trash": [["id": "deleted"]],
            "unknownRoot": "retain"
        ]
        let inputData = try JSONSerialization.data(withJSONObject: input)
        let newChapters = sections.map { section in
            ChapterLibraryMutation.BatchChapter(
                id: "new-\(section.startParagraph)",
                title: section.title,
                paragraphs: section.paragraphs.map {
                    ChapterLibraryMutation.Paragraph(text: $0.text, heading: $0.heading)
                }
            )
        }
        let result = try ChapterLibraryMutation.appendBatch(
            to: inputData,
            series: "Моё ранобэ",
            volume: "Том 14",
            chapters: newChapters,
            originalFile: "volume-123.docx"
        )
        let json = try JSONSerialization.jsonObject(with: result) as! [String: Any]
        precondition(json["unknownRoot"] as? String == "retain")
        precondition((json["trash"] as! [[String: Any]]).count == 1)
        let books = json["books"] as! [[String: Any]]
        precondition(books.count == 6)
        precondition(books.first?["id"] as? String == "old-chapter")
        precondition(books.first?["originalFile"] as? String == "original.docx")
        let imported = Array(books.dropFirst())
        precondition(imported.allSatisfy { $0["originalFile"] as? String == "volume-123.docx" })
        precondition(Set(imported.compactMap { $0["id"] as? String }).count == 5)
        precondition(imported.map { ($0["chapter"] as? String) ?? "" } == sections.map(\.title))

        do {
            _ = try ChapterLibraryMutation.appendBatch(
                to: inputData,
                series: "Моё ранобэ",
                volume: "Том 14",
                chapters: [
                    ChapterLibraryMutation.BatchChapter(
                        id: "bad",
                        title: "СТАРАЯ ГЛАВА",
                        paragraphs: [ChapterLibraryMutation.Paragraph(text: "Again", heading: false)]
                    )
                ],
                originalFile: "volume-bad.docx"
            )
            preconditionFailure("Existing chapter title cannot be overwritten")
        } catch ChapterLibraryMutation.Failure.duplicateChapter {}

        do {
            _ = try ChapterLibraryMutation.appendBatch(
                to: inputData,
                series: "Моё ранобэ",
                volume: "Том 14",
                chapters: [
                    ChapterLibraryMutation.BatchChapter(
                        id: "same1",
                        title: "Глава 7",
                        paragraphs: [ChapterLibraryMutation.Paragraph(text: "a", heading: false)]
                    ),
                    ChapterLibraryMutation.BatchChapter(
                        id: "same2",
                        title: "глАва 7",
                        paragraphs: [ChapterLibraryMutation.Paragraph(text: "b", heading: false)]
                    )
                ],
                originalFile: "volume-bad.docx"
            )
            preconditionFailure("Duplicated titles within one batch must fail")
        } catch ChapterLibraryMutation.Failure.duplicateChapter {}

        let firstImport = try ChapterLibraryMutation.appendBatch(
            to: nil, series: "Новая история", volume: "Том 1",
            chapters: [ChapterLibraryMutation.BatchChapter(
                id: "first", title: "Пролог",
                paragraphs: [ChapterLibraryMutation.Paragraph(text: "Начало", heading: true)]
            )],
            originalFile: "volume-first.docx"
        )
        let initial = try JSONSerialization.jsonObject(with: firstImport) as! [String: Any]
        precondition((initial["works"] as! [String]) == ["Новая история"])
        precondition((initial["volumes"] as! [[String: Any]]).count == 1)
        precondition((initial["books"] as! [[String: Any]]).count == 1)

        print("PASS: DOCX volume headings, preamble preservation, no lost text, manual boundaries, " +
              "disabled chapters, atomic JSON batch, original sharing and duplicate safety.")
    }
}
