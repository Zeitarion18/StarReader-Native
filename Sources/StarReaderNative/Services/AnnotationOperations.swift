import Foundation

/// Lossless state-file mutations for StarReader annotations.
/// Identifiers, raw quoted text, timestamps, unknown keys and other records
/// are retained unless the user explicitly deletes a selected note.
enum AnnotationOperations {
    enum Action {
        case update(id: String, kind: String, note: String, color: String)
        case remove(id: String)
        case reattach(id: String, chapterID: String, selection: ReaderTextSelection,
                      chapter: LibraryChapter)
    }

    enum Failure: LocalizedError {
        case invalidState, notFound, invalidCategory, invalidColor
        case invalidSelection, mismatchedChapter, requiresReview

        var errorDescription: String? {
            switch self {
            case .invalidState: return "Файл замечаний повреждён. Запись не изменена."
            case .notFound: return "Замечание больше не существует."
            case .invalidCategory: return "Выбрана неизвестная категория."
            case .invalidColor: return "Выбран неизвестный цвет."
            case .invalidSelection: return "Текст выделен неверно. Выдели фрагмент заново."
            case .mismatchedChapter: return "Замечание относится к другой главе."
            case .requiresReview: return "Эта заметка не ожидает повторной привязки."
            }
        }
    }

    private static let kinds: Set<String> = ["canon", "plot", "style", "favorite"]
    private static let colors: Set<String> = ["default", "gold", "coral", "blue", "mint", "purple"]

    static func apply(_ data: Data, action: Action) throws -> Data {
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["schema"] as? Int == 1,
              var notes = root["annotations"] as? [[String: Any]] else {
            throw Failure.invalidState
        }

        let identifier: String
        switch action {
        case .update(let id, _, _, _), .remove(let id), .reattach(let id, _, _, _):
            identifier = id
        }
        guard let index = notes.firstIndex(where: { $0["id"] as? String == identifier }) else {
            throw Failure.notFound
        }

        switch action {
        case .update(_, let kind, let note, let color):
            guard kinds.contains(kind) else { throw Failure.invalidCategory }
            guard colors.contains(color) else { throw Failure.invalidColor }
            notes[index]["kind"] = kind
            notes[index]["note"] = note
            notes[index]["color"] = color
            notes[index]["editedAt"] = ISO8601DateFormatter().string(from: Date())

        case .remove:
            notes.remove(at: index)

        case .reattach(_, let chapterID, let selection, let chapter):
            guard (notes[index]["bookId"] as? String) == chapterID,
                  chapter.id == chapterID else { throw Failure.mismatchedChapter }
            guard notes[index]["status"] as? String == "needs_review" else {
                throw Failure.requiresReview
            }
            guard exactQuote(for: selection, in: chapter) == selection.quote,
                  !selection.quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw Failure.invalidSelection
            }
            notes[index]["para"] = selection.startParagraph
            notes[index]["start"] = selection.startOffset
            notes[index]["endPara"] = selection.endParagraph
            notes[index]["end"] = selection.endOffset
            notes[index]["quote"] = selection.quote
            notes[index]["status"] = "open"
            notes[index].removeValue(forKey: "reviewReason")
            notes[index]["editedAt"] = ISO8601DateFormatter().string(from: Date())
        }
        root["annotations"] = notes
        return try JSONSerialization.data(
            withJSONObject: root, options: [.prettyPrinted, .sortedKeys]
        )
    }

    private static func exactQuote(
        for selection: ReaderTextSelection,
        in chapter: LibraryChapter
    ) -> String? {
        let firstIndex = selection.startParagraph
        let lastIndex = selection.endParagraph
        guard chapter.paragraphs.indices.contains(firstIndex),
              chapter.paragraphs.indices.contains(lastIndex),
              firstIndex <= lastIndex else { return nil }
        let first = Array(chapter.paragraphs[firstIndex].text.unicodeScalars)
        let last = Array(chapter.paragraphs[lastIndex].text.unicodeScalars)
        guard selection.startOffset >= 0, selection.endOffset >= 0,
              selection.startOffset <= first.count,
              selection.endOffset <= last.count,
              (firstIndex < lastIndex || selection.startOffset < selection.endOffset)
        else { return nil }

        func part(_ scalars: ArraySlice<Unicode.Scalar>) -> String {
            String(String.UnicodeScalarView(scalars))
        }

        if firstIndex == lastIndex {
            return part(first[selection.startOffset..<selection.endOffset])
        }
        let middle = chapter.paragraphs[(firstIndex + 1)..<lastIndex].map(\.text)
        return ([part(first[selection.startOffset..<first.count])] +
                middle +
                [part(last[0..<selection.endOffset])]).joined(separator: "\n")
    }
}
