import Foundation

@main
enum ChapterEditingSmoke {
    static func main() throws {
        func object(_ data: Data) throws -> [String: Any] {
            try JSONSerialization.jsonObject(with: data) as! [String: Any]
        }
        func data(_ object: [String: Any]) throws -> Data {
            try JSONSerialization.data(withJSONObject: object)
        }

        let oldParagraphs: [ChapterEditing.Paragraph] = [
            .init(text: "Первый безопасный абзац.", heading: false),
            .init(text: "У Зейта был неправильный меч.", heading: false),
            .init(text: "Последний абзац после ошибки.", heading: false)
        ]
        let library: [String: Any] = [
            "schema": 2, "works": ["История"],
            "volumes": [["series": "История", "title": "Том 1"]],
            "books": [[
                "id": "ch1", "series": "История", "volume": "Том 1",
                "name": "Глава 1", "chapter": "Глава 1",
                "originalFile": "original.docx",
                "extraBookField": "keep",
                "paragraphs": oldParagraphs.map {
                    ["text": $0.text, "heading": $0.heading]
                }
            ]],
            "trash": [["id": "older"]],
            "unknownRoot": "remain"
        ]
        let state: [String: Any] = [
            "schema": 1,
            "progress": [
                "ch1": ["bookId": "ch1", "para": 2, "offset": 5, "percent": 88.0],
                "another": ["para": 0]
            ],
            "annotations": [
                ["id": "note-before", "bookId": "ch1", "para": 0,
                 "start": 0, "endPara": 0, "end": 6,
                 "quote": "Первый", "status": "open"],
                ["id": "note-inside", "bookId": "ch1", "para": 1,
                 "start": 14, "endPara": 1, "end": 27,
                 "quote": "неправильный меч", "status": "open"],
                ["id": "note-after", "bookId": "ch1", "para": 2,
                 "start": 0, "endPara": 2, "end": 9,
                 "quote": "Последний", "status": "open"],
                ["id": "unlinked", "bookId": "another", "para": 0,
                 "start": 0, "end": 3, "quote": "abc"]
            ],
            "bookmarks": [
                ["id": "mark-inside", "bookId": "ch1", "para": 1,
                 "offset": 22, "title": "Within"],
                ["id": "mark-after", "bookId": "ch1", "para": 2,
                 "offset": 4, "title": "After"],
                ["id": "unlinked", "bookId": "another", "para": 0,
                 "offset": 0]
            ],
            "settings": ["theme": "night"],
            "unknownState": "preserve"
        ]
        let inputLibrary = try data(library)
        let inputState = try data(state)

        let selection = ReaderTextSelection(
            startUTF16: 0, endUTF16: 0,
            startParagraph: 1, startOffset: 17,
            endParagraph: 1, endOffset: 34,
            quote: "неправильный меч"
        )

        // Use a known exact selection derived from source Unicode scalars.
        let text = oldParagraphs[1].text
        let scalars = Array(text.unicodeScalars)
        let phrase = "неправильный меч"
        let start = (text as NSString).range(of: phrase).location
        let correctSelection = ReaderTextSelection(
            startUTF16: start, endUTF16: start + phrase.utf16.count,
            startParagraph: 1, startOffset: start,
            endParagraph: 1, endOffset: start + phrase.unicodeScalars.count,
            quote: phrase
        )
        _ = selection
        let updated = try ChapterEditing.replacing(
            selection: correctSelection,
            in: LibraryChapter(
                id: "ch1", name: "Глава 1", series: "История",
                volume: "Том 1", chapter: "Глава 1",
                paragraphs: oldParagraphs.enumerated().map {
                    ReaderParagraph(index: $0.offset,
                                    text: $0.element.text,
                                    heading: $0.element.heading)
                },
                originalFile: "original.docx"
            ),
            with: "верный Штандарт"
        )
        precondition(updated.count == 3)
        precondition(updated[1].text.contains("верный Штандарт"))
        precondition(!updated[1].text.contains("неправильный меч"))

        let result = try ChapterEditing.apply(
            libraryData: inputLibrary,
            stateData: inputState,
            chapterID: "ch1",
            expectedTitle: "Глава 1",
            expectedParagraphs: oldParagraphs,
            title: "Глава 1",
            paragraphs: updated
        )
        let changedLibrary = try object(result.libraryData)
        let changedState = try object(result.stateData)
        precondition(changedLibrary["unknownRoot"] as? String == "remain")
        let books = changedLibrary["books"] as! [[String: Any]]
        precondition(books.count == 1)
        precondition(books[0]["id"] as? String == "ch1")
        precondition(books[0]["originalFile"] as? String == "original.docx")
        precondition(books[0]["extraBookField"] as? String == "keep")
        precondition(changedState["unknownState"] as? String == "preserve")
        precondition((changedState["progress"] as! [String: Any])["another"] != nil)

        let notes = changedState["annotations"] as! [[String: Any]]
        let middleNote = notes.first { $0["id"] as? String == "note-inside" }!
        let beforeNote = notes.first { $0["id"] as? String == "note-before" }!
        let afterNote = notes.first { $0["id"] as? String == "note-after" }!
        precondition(middleNote["status"] as? String == "needs_review")
        precondition(middleNote["quote"] as? String == "неправильный меч")
        precondition(middleNote["start"] as? Int == 0 && middleNote["end"] as? Int == 0)
        precondition(beforeNote["status"] as? String == "open")
        precondition(afterNote["status"] as? String == "open")
        precondition(notes.count == 4)
        precondition(result.notesNeedingReview == 1)

        let marks = changedState["bookmarks"] as! [[String: Any]]
        precondition(marks.count == 3)
        precondition(marks.first { $0["id"] as? String == "mark-inside" }!["needsReview"] as? Bool == true)
        precondition(marks.first { $0["id"] as? String == "mark-after" }!["needsReview"] == nil)
        precondition(result.bookmarksNeedingReview == 1)

        let titleOnly = try ChapterEditing.apply(
            libraryData: inputLibrary,
            stateData: inputState,
            chapterID: "ch1",
            expectedTitle: "Глава 1",
            expectedParagraphs: oldParagraphs,
            title: "Глава 1 — Исправлена",
            paragraphs: oldParagraphs
        )
        precondition(titleOnly.notesNeedingReview == 0)
        precondition(titleOnly.bookmarksNeedingReview == 0)

        do {
            _ = try ChapterEditing.apply(
                libraryData: inputLibrary, stateData: inputState,
                chapterID: "ch1", expectedTitle: "Глава 1",
                expectedParagraphs: [],
                title: "Глава 1", paragraphs: updated
            )
            preconditionFailure("Must reject stale chapter")
        } catch ChapterEditing.Failure.staleChapter {}
        do {
            _ = try ChapterEditing.apply(
                libraryData: inputLibrary, stateData: inputState,
                chapterID: "ch1", expectedTitle: "Глава 1",
                expectedParagraphs: oldParagraphs,
                title: "Глава 1", paragraphs: oldParagraphs
            )
            preconditionFailure("Must reject unchanged draft")
        } catch ChapterEditing.Failure.unchanged {}
        print("PASS: selected text, notes/bookmarks remapping, status review, " +
              "all metadata, title-only edits, stale detection, unchanged refusal.")
    }
}
