import Foundation

enum DocxDocumentKind: String, CaseIterable, Identifiable {
    case chapter, prologue, epilogue, sideStory, afterword

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chapter: return "Глава"
        case .prologue: return "Пролог"
        case .epilogue: return "Эпилог"
        case .sideStory: return "Побочная история"
        case .afterword: return "Послесловие"
        }
    }

    var symbol: String {
        switch self {
        case .chapter: return "book.closed"
        case .prologue: return "sparkle"
        case .epilogue: return "star.fill"
        case .sideStory: return "circle.grid.cross"
        case .afterword: return "list.bullet.rectangle"
        }
    }

    func libraryTitle(chapterNumber: String, subtitle: String) -> String {
        let trimmed = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if self == .chapter {
            let number = chapterNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            let base = number.isEmpty ? "Глава" : "Глава \(number)"
            return trimmed.isEmpty ? base : "\(base). \(trimmed)"
        }
        return trimmed.isEmpty ? title : "\(title). \(trimmed)"
    }
}

struct DocxImportSuggestion {
    let volume: String?
    let workHint: String?
    let kind: DocxDocumentKind
    let chapterNumber: String
    let subtitle: String
    let confidence: Bool

    var libraryTitle: String {
        kind.libraryTitle(chapterNumber: chapterNumber, subtitle: subtitle)
    }

    /// Parse the Word filename, not DOCX content metadata. Never infer
    /// a specific work from merely "Том 14" if several works exist.
    static func infer(from fileName: String, headings: [String] = []) -> Self {
        var name = (fileName as NSString).lastPathComponent
        if name.lowercased().hasSuffix(".docx") {
            name = String(name.dropLast(5))
        }
        name = name.replacingOccurrences(of: "_", with: " ")
        name = name.replacingOccurrences(of: #"[\s]+"#, with: " ",
                                         options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Common Windows duplicate-file suffixes must not leak into
        // the title (e.g. "Пролог (1).docx" -> "Пролог").
        for _ in 0..<3 {
            let cleaned = name.replacingOccurrences(
                of: #"(?i)\s*(?:\(\d{1,3}\)|копия(?:\s*\d{1,3})?|copy(?:\s*\d{1,3})?)\s*$"#,
                with: "",
                options: .regularExpression
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned == name { break }
            name = cleaned
        }

        var volume: String?
        var workHint: String?
        if let match = match(
            #"(?:^|[\s\-—])(?:том|volume|vol\.?)\s*([0-9]{1,3}|[IVXLCDM]{1,8})(?=$|[\s.,:;—\-])"#,
            in: name
        ), let number = group(1, match: match, in: name) {
            let numeric = number.uppercased()
            volume = "Том \(numeric)"
            let prefix = (name as NSString).substring(to: match.range.location)
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            if !prefix.isEmpty {
                workHint = prefix
            }
            let position = NSMaxRange(match.range)
            name = (name as NSString).substring(from: position)
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        }

        let patterns: [(DocxDocumentKind, String)] = [
            (.prologue, #"^(?:пролог|prologue)\b"#),
            (.epilogue, #"^(?:эпилог|epilogue)\b"#),
            (.sideStory, #"^(?:побочная\s+история|побочка|side[\s\-]*story)\b"#),
            (.afterword, #"^(?:послесловие|afterword)\b"#),
            (.chapter, #"^(?:глава|chapter)\s*([0-9]{1,4}|[IVXLCDM]{1,8})?\b"#)
        ]
        for (kind, pattern) in patterns {
            guard let result = match(pattern, in: name) else { continue }
            let number = kind == .chapter
                ? (group(1, match: result, in: name) ?? "") : ""
            let remainder = (name as NSString).substring(from: NSMaxRange(result.range))
            return Self(
                volume: volume,
                workHint: workHint,
                kind: kind,
                chapterNumber: number,
                subtitle: cleanSubtitle(remainder),
                confidence: true
            )
        }

        // The first Word heading is a secondary hint only if filename
        // doesn't identify the type; we keep the filename as subtitle.
        for heading in headings.prefix(3) {
            let inferred = inferHeading(heading)
            if let inferred {
                return Self(
                    volume: volume,
                    workHint: workHint,
                    kind: inferred.kind,
                    chapterNumber: inferred.chapterNumber,
                    subtitle: name.isEmpty || name == heading
                        ? inferred.subtitle : cleanSubtitle(name),
                    confidence: false
                )
            }
        }

        return Self(
            volume: volume,
            workHint: workHint,
            kind: .chapter,
            chapterNumber: "",
            subtitle: cleanSubtitle(name),
            confidence: false
        )
    }

    private static func inferHeading(_ heading: String) -> (
        kind: DocxDocumentKind, chapterNumber: String, subtitle: String
    )? {
        let clean = heading.trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns: [(DocxDocumentKind, String)] = [
            (.prologue, #"^(?:пролог|prologue)\b"#),
            (.epilogue, #"^(?:эпилог|epilogue)\b"#),
            (.sideStory, #"^(?:побочная\s+история|побочка)\b"#),
            (.afterword, #"^(?:послесловие)\b"#),
            (.chapter, #"^(?:глава|chapter)\s*([0-9]{1,4}|[IVXLCDM]{1,8})?\b"#)
        ]
        for (kind, pattern) in patterns {
            guard let result = match(pattern, in: clean) else { continue }
            let number = kind == .chapter
                ? (group(1, match: result, in: clean) ?? "") : ""
            return (kind, number,
                    cleanSubtitle((clean as NSString).substring(from: NSMaxRange(result.range))))
        }
        return nil
    }

    private static func cleanSubtitle(_ value: String) -> String {
        value.replacingOccurrences(of: #"^[\s\p{P}]+|[\s\p{P}]+$"#,
                                   with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func match(_ pattern: String, in string: String) -> NSTextCheckingResult? {
        guard let expression = try? NSRegularExpression(
            pattern: pattern, options: [.caseInsensitive]
        ) else { return nil }
        return expression.firstMatch(
            in: string, range: NSRange(location: 0, length: (string as NSString).length)
        )
    }

    private static func group(
        _ index: Int,
        match: NSTextCheckingResult,
        in text: String
    ) -> String? {
        guard index < match.numberOfRanges else { return nil }
        let range = match.range(at: index)
        guard range.location != NSNotFound else { return nil }
        return (text as NSString).substring(with: range)
    }
}
