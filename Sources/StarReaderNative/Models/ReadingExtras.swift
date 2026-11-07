import Foundation

/// Imported notes and bookmarks keep their original IDs and book IDs.
/// Records linked to removed chapters remain visible instead of being discarded.
struct ReaderAnnotation: Identifiable, Hashable {
    let id: String
    let bookId: String
    let paragraph: Int
    let start: Int
    let end: Int
    let endParagraph: Int?
    let kind: String
    let quote: String
    let note: String
    let status: String
    let createdAt: String

    var categoryTitle: String {
        switch kind.lowercased() {
        case "canon", "канон": return "Канон"
        case "plot", "сюжет": return "Сюжет"
        case "style", "стиль": return "Стиль"
        case "favorite", "цитата": return "Цитата"
        default: return kind.isEmpty ? "Замечание" : kind
        }
    }

    static func parse(_ value: [String: Any]) -> ReaderAnnotation? {
        guard let id = value["id"] as? String, !id.isEmpty,
              let bookId = value["bookId"] as? String, !bookId.isEmpty,
              let paragraph = value["para"] as? Int else { return nil }
        return ReaderAnnotation(
            id: id, bookId: bookId, paragraph: max(0, paragraph),
            start: max(0, value["start"] as? Int ?? 0),
            end: max(0, value["end"] as? Int ?? 0),
            endParagraph: value["endPara"] as? Int,
            kind: value["kind"] as? String ?? "",
            quote: value["quote"] as? String ?? "",
            note: value["note"] as? String ?? "",
            status: value["status"] as? String ?? "open",
            createdAt: value["createdAt"] as? String ?? ""
        )
    }
}

struct ReaderBookmark: Identifiable, Hashable {
    let id: String
    let bookId: String
    let paragraph: Int
    let offset: Int
    let title: String
    let quote: String
    let note: String
    let createdAt: String

    static func parse(_ value: [String: Any]) -> ReaderBookmark? {
        guard let id = value["id"] as? String, !id.isEmpty,
              let bookId = value["bookId"] as? String, !bookId.isEmpty,
              let paragraph = value["para"] as? Int else { return nil }
        return ReaderBookmark(
            id: id, bookId: bookId, paragraph: max(0, paragraph),
            offset: max(0, value["offset"] as? Int ?? 0),
            title: value["title"] as? String ?? "Закладка",
            quote: value["quote"] as? String ?? "",
            note: value["note"] as? String ?? "",
            createdAt: value["createdAt"] as? String ?? ""
        )
    }
}

struct ReaderJump: Hashable {
    let bookID: String
    let paragraph: Int
    let offset: Int
    let recordID: String
}
