import Foundation

/// A loss-averse editor for the Qt transfer library format.
/// Chapter IDs remain stable. Annotations intersecting an edit are kept,
/// marked needs_review and detached from text highlighting, never deleted.
enum ChapterEditing {
    struct Paragraph: Equatable {
        let text: String
        let heading: Bool
    }

    struct Result {
        let libraryData: Data
        let stateData: Data
        let notesNeedingReview: Int
        let bookmarksNeedingReview: Int
        let changed: Bool
    }

    enum Failure: LocalizedError {
        case invalidLibrary
        case invalidState
        case chapterMissing
        case staleChapter
        case emptyTitle
        case emptyChapter
        case unchanged
        case invalidSelection

        var errorDescription: String? {
            switch self {
            case .invalidLibrary: return "Файл библиотеки повреждён. Изменения не сохранены."
            case .invalidState: return "Замечания и прогресс повреждены. Изменения не сохранены."
            case .chapterMissing: return "Глава уже отсутствует в библиотеке."
            case .staleChapter: return "Глава изменилась после открытия редактора. Открой редактор заново."
            case .emptyTitle: return "Введи название главы."
            case .emptyChapter: return "Текст главы не может быть полностью пустым."
            case .unchanged: return "Нет изменений для сохранения."
            case .invalidSelection: return "Выделенный фрагмент больше не совпадает с текстом главы."
            }
        }
    }

    static func paragraphs(of chapter: LibraryChapter) -> [Paragraph] {
        chapter.paragraphs.map { Paragraph(text: $0.text, heading: $0.heading) }
    }

    static func wholeChapterDraft(_ paragraphs: [Paragraph]) -> String {
        paragraphs.map(\.text).joined(separator: "\n\n")
    }

    static func paragraphsFromWholeDraft(_ text: String, original: [Paragraph]) -> [Paragraph] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let parts = normalized.components(separatedBy: "\n\n")
        var result: [Paragraph] = []
        for (index, part) in parts.enumerated() {
            guard !part.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            // Retain a heading attribute if a paragraph is unchanged or the
            // same numbered paragraph has merely been corrected in-place.
            let heading = index < original.count ? original[index].heading : false
            result.append(Paragraph(text: part, heading: heading))
        }
        return result
    }

    static func replacing(
        selection: ReaderTextSelection,
        in chapter: LibraryChapter,
        with replacement: String
    ) throws -> [Paragraph] {
        let paragraphs = self.paragraphs(of: chapter)
        guard paragraphs.indices.contains(selection.startParagraph),
              paragraphs.indices.contains(selection.endParagraph),
              selection.startParagraph <= selection.endParagraph else {
            throw Failure.invalidSelection
        }
        let first = Array(paragraphs[selection.startParagraph].text.unicodeScalars)
        let last = Array(paragraphs[selection.endParagraph].text.unicodeScalars)
        guard selection.startOffset >= 0, selection.startOffset <= first.count,
              selection.endOffset >= 0, selection.endOffset <= last.count,
              (selection.startParagraph < selection.endParagraph ||
               selection.startOffset < selection.endOffset) else {
            throw Failure.invalidSelection
        }
        let previousQuote: String
        if selection.startParagraph == selection.endParagraph {
            previousQuote = scalarString(first[selection.startOffset..<selection.endOffset])
        } else {
            let beginning = scalarString(first[selection.startOffset..<first.count])
            let middle = paragraphs[(selection.startParagraph + 1)..<selection.endParagraph]
                .map(\.text)
            let ending = scalarString(last[0..<selection.endOffset])
            previousQuote = ([beginning] + middle + [ending]).joined(separator: "\n")
        }
        guard previousQuote == selection.quote else {
            throw Failure.invalidSelection
        }
        let prefix = scalarString(first[0..<selection.startOffset])
        let suffix = scalarString(last[selection.endOffset..<last.count])
        let normalized = replacement.replacingOccurrences(of: "\r\n", with: "\n")
        let segments = normalized.components(separatedBy: "\n\n")
        var newParagraphs: [Paragraph] = []
        newParagraphs.append(contentsOf: paragraphs.prefix(selection.startParagraph))
        if segments.count <= 1 {
            newParagraphs.append(
                Paragraph(text: prefix + normalized + suffix,
                          heading: paragraphs[selection.startParagraph].heading)
            )
        } else {
            newParagraphs.append(
                Paragraph(text: prefix + segments[0],
                          heading: paragraphs[selection.startParagraph].heading)
            )
            for segment in segments.dropFirst().dropLast() {
                newParagraphs.append(Paragraph(text: segment, heading: false))
            }
            newParagraphs.append(
                Paragraph(text: (segments.last ?? "") + suffix, heading: false)
            )
        }
        if selection.endParagraph + 1 < paragraphs.count {
            newParagraphs.append(contentsOf: paragraphs.dropFirst(selection.endParagraph + 1))
        }
        return newParagraphs
    }

    static func apply(
        libraryData: Data,
        stateData: Data,
        chapterID: String,
        expectedTitle: String,
        expectedParagraphs: [Paragraph],
        title newTitle: String,
        paragraphs newParagraphs: [Paragraph]
    ) throws -> Result {
        guard var library = try JSONSerialization.jsonObject(
            with: libraryData
        ) as? [String: Any],
        library["schema"] as? Int == 2,
        var books = library["books"] as? [[String: Any]],
        let index = books.firstIndex(where: { $0["id"] as? String == chapterID }) else {
            throw Failure.invalidLibrary
        }
        let oldBook = books[index]
        let oldTitle = (oldBook["chapter"] as? String).flatMap {
            $0.isEmpty ? nil : $0
        } ?? (oldBook["name"] as? String ?? "")
        guard let rawParagraphs = oldBook["paragraphs"] as? [[String: Any]],
              rawParagraphs.allSatisfy({ $0["text"] is String }) else {
            throw Failure.invalidLibrary
        }
        let existing = rawParagraphs.map {
            Paragraph(text: $0["text"] as! String, heading: $0["heading"] as? Bool ?? false)
        }
        guard oldTitle == expectedTitle, existing == expectedParagraphs else {
            throw Failure.staleChapter
        }
        let trimmedTitle = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw Failure.emptyTitle }
        guard newParagraphs.contains(where: {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else { throw Failure.emptyChapter }
        guard trimmedTitle != oldTitle || newParagraphs != existing else {
            throw Failure.unchanged
        }
        guard var state = try JSONSerialization.jsonObject(
            with: stateData
        ) as? [String: Any],
        state["schema"] as? Int == 1,
        var rawProgress = state["progress"] as? [String: Any],
        var rawNotes = state["annotations"] as? [[String: Any]],
        var rawBookmarks = state["bookmarks"] as? [[String: Any]] else {
            throw Failure.invalidState
        }

        let before = wholeChapterDraft(existing)
        let after = wholeChapterDraft(newParagraphs)
        let oldScalars = Array(before.unicodeScalars)
        let newScalars = Array(after.unicodeScalars)
        let prefixCount = zip(oldScalars, newScalars).prefix(while: { $0.0 == $0.1 }).count
        var suffixCount = 0
        while suffixCount < min(oldScalars.count, newScalars.count) - prefixCount &&
              oldScalars[oldScalars.count - 1 - suffixCount] ==
              newScalars[newScalars.count - 1 - suffixCount] {
            suffixCount += 1
        }
        let oldChangeEnd = oldScalars.count - suffixCount
        let delta = newScalars.count - oldScalars.count
        let oldOffsets = paragraphStarts(existing)
        let newOffsets = paragraphStarts(newParagraphs)

        // Edited ranges are bounded by the common prefix/suffix. Anchors
        // outside those spans can be mapped exactly even across paragraph
        // additions/deletions, including non-BMP Unicode scalars.
        func remap(_ value: Int, isEnd: Bool = false) -> Int? {
            if oldScalars == newScalars {
                return min(max(0, value), newScalars.count)
            }
            if value < prefixCount || (isEnd && value == prefixCount) {
                return value
            }
            if value > oldChangeEnd || (value == oldChangeEnd && !isEnd) {
                return value + delta
            }
            return nil
        }

        func newPosition(_ absolute: Int) -> (Int, Int) {
            position(at: min(max(0, absolute), newScalars.count),
                     starts: newOffsets, paragraphs: newParagraphs)
        }

        var changedNotes = 0
        for index in rawNotes.indices {
            guard (rawNotes[index]["bookId"] as? String) == chapterID else {
                continue
            }
            if (rawNotes[index]["status"] as? String) == "needs_review" {
                continue
            }
            var note = rawNotes[index]
            let startPara = note["para"] as? Int ?? 0
            let endPara = note["endPara"] as? Int ?? startPara
            let startOffset = note["start"] as? Int ?? 0
            let endOffset = note["end"] as? Int ?? 0
            guard let begin = absolute(startPara, startOffset,
                                       starts: oldOffsets, paragraphs: existing),
                  let finish = absolute(endPara, endOffset,
                                        starts: oldOffsets, paragraphs: existing),
                  begin <= finish,
                  let startMapped = remap(begin),
                  let endMapped = remap(finish, isEnd: true),
                  startMapped < endMapped else {
                changedNotes += 1
                let anchor = newPosition(prefixCount)
                note["para"] = anchor.0
                note["start"] = 0
                note["endPara"] = anchor.0
                note["end"] = 0
                note["status"] = "needs_review"
                note["reviewReason"] = "Текст заметки затронут редактированием главы"
                rawNotes[index] = note
                continue
            }
            let start = newPosition(startMapped)
            let end = newPosition(endMapped)
            note["para"] = start.0
            note["start"] = start.1
            note["endPara"] = end.0
            note["end"] = end.1
            rawNotes[index] = note
        }

        var changedBookmarks = 0
        for index in rawBookmarks.indices {
            guard (rawBookmarks[index]["bookId"] as? String) == chapterID else {
                continue
            }
            var bookmark = rawBookmarks[index]
            let oldPara = bookmark["para"] as? Int ?? 0
            let oldOffset = bookmark["offset"] as? Int ?? 0
            let previous = absolute(oldPara, oldOffset,
                                    starts: oldOffsets, paragraphs: existing)
            if let previous, let mapped = remap(previous) {
                let target = newPosition(mapped)
                bookmark["para"] = target.0
                bookmark["offset"] = target.1
            } else {
                changedBookmarks += 1
                let target = newPosition(prefixCount)
                bookmark["para"] = target.0
                bookmark["offset"] = target.1
                bookmark["needsReview"] = true
            }
            rawBookmarks[index] = bookmark
        }

        if var progress = rawProgress[chapterID] as? [String: Any] {
            let oldPara = progress["para"] as? Int ?? 0
            let oldOffset = progress["offset"] as? Int ?? 0
            let oldAbsolute = absolute(oldPara, oldOffset,
                                       starts: oldOffsets, paragraphs: existing)
            let mapped = oldAbsolute.flatMap { remap($0) } ?? prefixCount
            let target = newPosition(mapped)
            progress["para"] = target.0
            progress["offset"] = target.1
            let total = max(1, newParagraphs.reduce(0) {
                $0 + $1.text.unicodeScalars.count
            })
            let consumed = newParagraphs.prefix(target.0).reduce(0) {
                $0 + $1.text.unicodeScalars.count
            } + target.1
            progress["percent"] = min(100, max(0, Double(consumed) / Double(total) * 100))
            progress["updatedAt"] = ISO8601DateFormatter().string(from: Date())
            rawProgress[chapterID] = progress
        }

        var updatedBook = oldBook
        updatedBook["name"] = trimmedTitle
        updatedBook["chapter"] = trimmedTitle
        updatedBook["paragraphs"] = newParagraphs.map {
            ["text": $0.text, "heading": $0.heading] as [String: Any]
        }
        books[index] = updatedBook
        library["books"] = books
        state["annotations"] = rawNotes
        state["bookmarks"] = rawBookmarks
        state["progress"] = rawProgress

        return Result(
            libraryData: try JSONSerialization.data(
                withJSONObject: library, options: [.prettyPrinted, .sortedKeys]
            ),
            stateData: try JSONSerialization.data(
                withJSONObject: state, options: [.prettyPrinted, .sortedKeys]
            ),
            notesNeedingReview: changedNotes,
            bookmarksNeedingReview: changedBookmarks,
            changed: true
        )
    }

    private static func scalarString<S: Sequence>(_ scalars: S) -> String
        where S.Element == Unicode.Scalar {
        String(String.UnicodeScalarView(scalars))
    }

    private static func paragraphStarts(_ paragraphs: [Paragraph]) -> [Int] {
        var starts: [Int] = []
        var offset = 0
        for paragraph in paragraphs {
            starts.append(offset)
            offset += paragraph.text.unicodeScalars.count + 2
        }
        return starts
    }

    private static func absolute(
        _ paragraph: Int,
        _ offset: Int,
        starts: [Int],
        paragraphs: [Paragraph]
    ) -> Int? {
        guard paragraphs.indices.contains(paragraph),
              offset >= 0,
              offset <= paragraphs[paragraph].text.unicodeScalars.count else {
            return nil
        }
        return starts[paragraph] + offset
    }

    private static func position(
        at absolute: Int,
        starts: [Int],
        paragraphs: [Paragraph]
    ) -> (Int, Int) {
        guard !paragraphs.isEmpty else { return (0, 0) }
        var index = 0
        for i in starts.indices {
            if starts[i] <= absolute { index = i } else { break }
        }
        return (
            index,
            min(max(0, absolute - starts[index]),
                paragraphs[index].text.unicodeScalars.count)
        )
    }
}
