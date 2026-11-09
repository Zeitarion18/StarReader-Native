import Foundation
import SwiftUI
import UIKit
import Combine

/// Counts the exact number of TextKit pages that the actual paged reader
/// would produce at a given viewport and typography. Not an estimate based
/// on word or character count. Cached and recalculated on content changes.
@MainActor
final class ReaderPageCounter: ObservableObject {
    @Published private(set) var pageCounts: [String: Int] = [:]
    @Published private(set) var isCalculating = false

    private var calculation: Task<Void, Never>?
    private var currentSignature = ""

    func refresh(
        chapters: [LibraryChapter],
        annotations: [ReaderAnnotation],
        contentWidth: CGFloat,
        pageHeight: CGFloat,
        fontSize: Double,
        lineSpacing: Double,
        paragraphSpacing: Double,
        palette: ReaderPalette
    ) {
        let width = max(140, contentWidth)
        let height = max(150, pageHeight)
        let signature = [
            String(chapters.hashValue),
            String(Int((width * 10).rounded())),
            String(Int((height * 10).rounded())),
            String(fontSize),
            String(lineSpacing),
            String(paragraphSpacing)
        ].joined(separator: "|")
        guard signature != currentSignature else { return }
        currentSignature = signature
        calculation?.cancel()

        // Invalidate results only if the viewport, font or book list changed.
        // Old totals must never appear beside newly imported chapters.
        pageCounts = [:]
        isCalculating = !chapters.isEmpty
        let notesByID = Dictionary(grouping: annotations, by: \.bookId)

        calculation = Task { [weak self] in
            for chapter in chapters {
                if Task.isCancelled { return }
                let layout = ChapterPagination(
                    chapter: chapter,
                    annotations: notesByID[chapter.id] ?? [],
                    pageWidth: width,
                    pageHeight: height,
                    fontSize: fontSize,
                    lineSpacing: lineSpacing,
                    paragraphSpacing: paragraphSpacing,
                    palette: palette
                )
                let plan = NativeTextPagePlan(
                    source: layout,
                    pageWidth: width,
                    pageHeight: height
                )
                if Task.isCancelled { return }
                self?.pageCounts[chapter.id] = plan.pageCount
                // Allow SwiftUI to display progressive results, and let the
                // user navigate without a long block on the main actor.
                try? await Task.sleep(nanoseconds: 8_000_000)
            }
            if !Task.isCancelled {
                self?.isCalculating = false
            }
        }
    }

    func total(for chapters: [LibraryChapter]) -> Int? {
        if chapters.isEmpty { return 0 }
        let known = chapters.compactMap { pageCounts[$0.id] }
        guard known.count == chapters.count else { return nil }
        return known.reduce(0, +)
    }

    func totalText(for chapters: [LibraryChapter], approximate: Bool) -> String {
        guard let pages = total(for: chapters) else {
            return "Считаем страницы…"
        }
        return (approximate ? "≈" : "") + "\(pages) стр."
    }
}
