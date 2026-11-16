import Foundation

@main
enum AnnotationOperationsSmoke {
    static func main() throws {
        let state: [String: Any] = [
            "schema": 1,
            "annotations": [
                [
                    "id": "needs-fix", "bookId": "chapter-1",
                    "para": 0, "start": 0, "endPara": 0, "end": 0,
                    "kind": "canon", "quote": "Старая цитата",
                    "note": "Сюжет не сходится",
                    "status": "needs_review", "createdAt": "2026-11-01",
                    "reviewReason": "Правка текста",
                    "unknownNoteKey": "never delete"
                ],
                [
                    "id": "other", "bookId": "chapter-2",
                    "para": 0, "start": 2, "endPara": 0, "end": 6,
                    "kind": "plot", "quote": "other",
                    "note": "Other annotation", "status": "open"
                ]
            ],
            "progress": ["chapter-1": ["para": 0, "percent": 33.0]],
            "bookmarks": [["id": "bookmarked", "bookId": "chapter-1", "para": 1]],
            "settings": ["fontSize": 18],
            "unknownRoot": "must be preserved"
        ]
        func encode(_ value: [String: Any]) throws -> Data {
            try JSONSerialization.data(withJSONObject: value)
        }
        func decode(_ value: Data) throws -> [String: Any] {
            try JSONSerialization.jsonObject(with: value) as! [String: Any]
        }
        func notes(_ value: Data) throws -> [[String: Any]] {
            try decode(value)["annotations"] as! [[String: Any]]
        }
        let initial = try encode(state)

        let edited = try AnnotationOperations.apply(
            initial, action: .update(
                id: "needs-fix", kind: "style",
                note: "Исправить стиль", color: "purple"
            )
        )
        let updatedNotes = try notes(edited)
        precondition(updatedNotes.count == 2)
        precondition(updatedNotes[0]["kind"] as? String == "style")
        precondition(updatedNotes[0]["color"] as? String == "purple")
        precondition(updatedNotes[0]["status"] as? String == "needs_review")
        precondition(updatedNotes[0]["quote"] as? String == "Старая цитата")
        precondition(updatedNotes[0]["unknownNoteKey"] as? String == "never delete")
        precondition(updatedNotes[1]["note"] as? String == "Other annotation")
        let editedRoot = try decode(edited)
        precondition(editedRoot["unknownRoot"] as? String == "must be preserved")

        let chapter = LibraryChapter(
            id: "chapter-1", name: "Глава 1", series: "Ранобэ",
            volume: "Том 1", chapter: "Глава 1",
            paragraphs: [
                ReaderParagraph(index: 0, text: "Зейт держал Штандарт.", heading: false),
                ReaderParagraph(index: 1, text: "Лиара улыбнулась.", heading: false)
            ],
            originalFile: "chapter.docx"
        )
        let phrase = "Штандарт"
        let from = "Зейт держал ".unicodeScalars.count
        let selection = ReaderTextSelection(
            startUTF16: from, endUTF16: from + phrase.utf16.count,
            startParagraph: 0, startOffset: from,
            endParagraph: 0, endOffset: from + phrase.unicodeScalars.count,
            quote: phrase
        )
        let anchored = try AnnotationOperations.apply(
            edited,
            action: .reattach(
                id: "needs-fix", chapterID: "chapter-1",
                selection: selection, chapter: chapter
            )
        )
        let note = try notes(anchored)[0]
        precondition(note["status"] as? String == "open")
        precondition(note["quote"] as? String == "Штандарт")
        precondition(note["para"] as? Int == 0)
        precondition(note["start"] as? Int == from)
        precondition(note["end"] as? Int == from + phrase.unicodeScalars.count)
        precondition(note["reviewReason"] == nil)
        precondition(note["unknownNoteKey"] as? String == "never delete")
        let anchoredRoot = try decode(anchored)
        precondition(anchoredRoot["bookmarks"] as? [[String: Any]] != nil)
        precondition(anchoredRoot["progress"] as? [String: Any] != nil)

        do {
            let stale = ReaderTextSelection(
                startUTF16: 0, endUTF16: 4,
                startParagraph: 0, startOffset: 0,
                endParagraph: 0, endOffset: 4,
                quote: "Ошибка"
            )
            _ = try AnnotationOperations.apply(
                edited,
                action: .reattach(
                    id: "needs-fix", chapterID: "chapter-1",
                    selection: stale, chapter: chapter
                )
            )
            preconditionFailure("Must reject quote mismatches")
        } catch AnnotationOperations.Failure.invalidSelection {}

        do {
            _ = try AnnotationOperations.apply(
                anchored,
                action: .reattach(
                    id: "needs-fix", chapterID: "chapter-1",
                    selection: selection, chapter: chapter
                )
            )
            preconditionFailure("Must reject reattachment of active notes")
        } catch AnnotationOperations.Failure.requiresReview {}

        let removed = try AnnotationOperations.apply(
            anchored, action: .remove(id: "needs-fix")
        )
        let remaining = try notes(removed)
        precondition(remaining.count == 1)
        precondition(remaining[0]["id"] as? String == "other")
        let removedRoot = try decode(removed)
        precondition(removedRoot["unknownRoot"] as? String == "must be preserved")
        precondition(removedRoot["bookmarks"] as? [[String: Any]] != nil)
        print("PASS: edits, six-color validation, no data loss, reviewed reattachment, quote validation, deletion.")
    }
}
