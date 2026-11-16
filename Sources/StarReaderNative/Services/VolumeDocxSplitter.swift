import Foundation

/// Reviewable boundaries for a DOCX that contains many sections. The source
/// paragraph indices always refer to the original, unmodified Word text.
/// A selected section covers [startParagraph, nextStartParagraph) so no
/// paragraph is accidentally lost or duplicated at a split boundary.
struct VolumeSectionDraft: Identifiable, Equatable {
    let id: UUID
    var startParagraph: Int       // 1-based index (editable in the UI)
    var title: String
    var include: Bool
    var confidence: Bool

    init(
        id: UUID = UUID(),
        startParagraph: Int,
        title: String,
        include: Bool = true,
        confidence: Bool = true
    ) {
        self.id = id
        self.startParagraph = startParagraph
        self.title = title
        self.include = include
        self.confidence = confidence
    }
}

enum VolumeDocxSplitter {
    struct Section {
        let title: String
        let paragraphs: [ImportedDocxParagraph]
        let startParagraph: Int
        let endParagraph: Int
    }

    enum Failure: LocalizedError {
        case emptyDocument, noSelectedSections, invalidBoundaries
        case emptyTitle, excessiveSections, emptySection

        var errorDescription: String? {
            switch self {
            case .emptyDocument: return "Документ Word не содержит текста."
            case .noSelectedSections: return "Выбери хотя бы один раздел для импорта."
            case .invalidBoundaries: return "Начала разделов должны быть различны, первый — с абзаца 1. Проверь границы."
            case .emptyTitle: return "У одного из разделов отсутствует название."
            case .excessiveSections: return "Слишком много разделов для одного импорта (не более 250)."
            case .emptySection: return "В выбранном разделе нет содержимого."
            }
        }
    }

    private static let headingPattern = try! NSRegularExpression(
        pattern: #"^\s*(?:(?:глава|chapter)\s*(?:№\s*)?(?:\d{1,4}|[IVXLCDM]{1,8})\b|(?:пролог|prologue|эпилог|epilogue|послесловие|afterword|побочная\s+история|побочка|side[\s\-]*story)\b)(?:\s*[\p{P}\s]\s*.*)?$"#,
        options: [.caseInsensitive]
    )

    static func detect(in document: ImportedDocxChapter) -> [VolumeSectionDraft] {
        let paragraphs = document.paragraphs
        guard !paragraphs.isEmpty else { return [] }
        var result: [VolumeSectionDraft] = []
        for (index, paragraph) in paragraphs.enumerated() {
            let value = paragraph.text.trimmingCharacters(in: .whitespacesAndNewlines)
            // Restrict heuristic matches to short paragraphs. Real Word
            // Heading styles may be longer, but still require heading syntax.
            guard !value.isEmpty, value.count <= 180,
                  paragraph.heading || value.count <= 105 else { continue }
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            guard headingPattern.firstMatch(in: value, range: range) != nil else {
                continue
            }
            let inference = DocxImportSuggestion.infer(from: value + ".docx")
            // The heading's own text is kept inside its section.
            result.append(VolumeSectionDraft(
                startParagraph: index + 1,
                title: inference.libraryTitle,
                confidence: paragraph.heading
            ))
            if result.count > 250 { break }
        }

        // The body before the first heading is never silently discarded.
        if let first = result.first, first.startParagraph != 1 {
            result.insert(
                VolumeSectionDraft(
                    startParagraph: 1,
                    title: "Вступление",
                    confidence: false
                ),
                at: 0
            )
        }
        if result.isEmpty {
            result = [VolumeSectionDraft(
                startParagraph: 1,
                title: document.suggestedTitle,
                confidence: false
            )]
        }
        return result
    }

    /// Validate *all* boundaries, including unselected entries: deselecting
    /// a section skips its text rather than silently merging it elsewhere.
    static func sections(
        in document: ImportedDocxChapter,
        drafts: [VolumeSectionDraft]
    ) throws -> [Section] {
        guard !document.paragraphs.isEmpty else { throw Failure.emptyDocument }
        guard !drafts.isEmpty, drafts.contains(where: \.include) else {
            throw Failure.noSelectedSections
        }
        guard drafts.count <= 250 else { throw Failure.excessiveSections }
        let sorted = drafts.sorted { $0.startParagraph < $1.startParagraph }
        guard sorted.first?.startParagraph == 1,
              sorted.last!.startParagraph <= document.paragraphs.count,
              Set(sorted.map(\.startParagraph)).count == sorted.count else {
            throw Failure.invalidBoundaries
        }

        var selections: [Section] = []
        for (index, draft) in sorted.enumerated() {
            let nextStart = index + 1 < sorted.count
                ? sorted[index + 1].startParagraph
                : document.paragraphs.count + 1
            guard draft.startParagraph >= 1,
                  draft.startParagraph < nextStart,
                  nextStart <= document.paragraphs.count + 1 else {
                throw Failure.invalidBoundaries
            }
            if !draft.include { continue }
            let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { throw Failure.emptyTitle }
            let lower = draft.startParagraph - 1
            let upper = nextStart - 1
            let paragraphs = Array(document.paragraphs[lower..<upper])
            guard !paragraphs.isEmpty else { throw Failure.emptySection }
            selections.append(Section(
                title: title,
                paragraphs: paragraphs,
                startParagraph: draft.startParagraph,
                endParagraph: nextStart - 1
            ))
        }
        return selections
    }

    static func subtitle(from fileName: String) -> String {
        DocxImportSuggestion.infer(from: fileName).volume ?? ""
    }
}
