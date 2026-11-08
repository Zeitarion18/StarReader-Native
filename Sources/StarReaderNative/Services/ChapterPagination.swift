import CoreText
import Foundation
import SwiftUI
import UIKit

struct ChapterPage: Hashable {
    let start: Int
    let length: Int
}

private struct ChapterParagraphSpan {
    let index: Int
    let startUTF16: Int
    let lengthUTF16: Int
    let text: String
}

/// A true typeset layout: each page boundary comes from the number of
/// characters that CoreText can fit into the *current device's page rectangle*.
/// No fixed or guessed number of pages is used.
@MainActor
final class ChapterPagination {
    let chapters: [ChapterPage]
    let attributedText: NSAttributedString
    let framesetter: CTFramesetter
    let pageWidth: CGFloat
    let pageHeight: CGFloat

    private let paragraphs: [ChapterParagraphSpan]
    private let paragraphScalarCounts: [Int]
    private let chapterScalarCount: Int

    var pageCount: Int { chapters.count }

    init(
        chapter: LibraryChapter,
        annotations: [ReaderAnnotation],
        pageWidth: CGFloat,
        pageHeight: CGFloat,
        fontSize: Double,
        lineSpacing: Double,
        paragraphSpacing: Double
    ) {
        self.pageWidth = max(140, pageWidth)
        self.pageHeight = max(150, pageHeight)
        chapterScalarCount = max(1, chapter.totalCharacters)

        let bodyFont = Self.serifFont(size: CGFloat(fontSize), weight: .regular)
        let headingFont = Self.serifFont(size: CGFloat(fontSize + 4), weight: .semibold)
        let bodyStyle = NSMutableParagraphStyle()
        bodyStyle.alignment = .natural
        bodyStyle.lineBreakMode = .byWordWrapping
        bodyStyle.lineSpacing = CGFloat(lineSpacing)
        bodyStyle.paragraphSpacing = CGFloat(paragraphSpacing)

        let titleStyle = NSMutableParagraphStyle()
        titleStyle.alignment = .natural
        titleStyle.lineBreakMode = .byWordWrapping
        titleStyle.lineSpacing = 5
        titleStyle.paragraphSpacing = 21

        let foreground = UIColor(red: 0.94, green: 0.955, blue: 0.985, alpha: 0.96)
        let heading: [NSAttributedString.Key: Any] = [
            .font: headingFont,
            .paragraphStyle: titleStyle,
            .foregroundColor: foreground
        ]
        let body: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .paragraphStyle: bodyStyle,
            .foregroundColor: foreground
        ]

        let rendered = NSMutableAttributedString(
            string: chapter.displayTitle + "\n",
            attributes: heading
        )
        var spans: [ChapterParagraphSpan] = []
        var scalarCounts: [Int] = []

        for paragraph in chapter.paragraphs {
            let start = rendered.length
            let paragraphString = paragraph.text
            let paragraphFont = paragraph.heading
                ? Self.serifFont(size: CGFloat(fontSize + 2), weight: .semibold)
                : bodyFont
            var attributes = body
            attributes[.font] = paragraphFont

            let segment = NSMutableAttributedString(
                string: paragraphString + "\n",
                attributes: attributes
            )

            let related = annotations.filter { item in
                let last = max(item.paragraph, item.endParagraph ?? item.paragraph)
                return item.paragraph <= paragraph.index && paragraph.index <= last
            }
            for note in related {
                let endParagraph = max(note.paragraph, note.endParagraph ?? note.paragraph)
                let scalarCount = paragraphString.unicodeScalars.count
                let lowerScalar = paragraph.index == note.paragraph ? note.start : 0
                let upperScalar = paragraph.index == endParagraph ? note.end : scalarCount
                let lower = max(0, min(scalarCount, lowerScalar))
                let upper = max(0, min(scalarCount, upperScalar))
                guard lower < upper else { continue }

                let utf16Lower = Self.utf16Length(ofPrefix: paragraphString, scalars: lower)
                let utf16Upper = Self.utf16Length(ofPrefix: paragraphString, scalars: upper)
                segment.addAttributes(
                    [
                        .foregroundColor: Self.annotationColor(note.categoryTitle),
                        .underlineStyle: NSUnderlineStyle.single.rawValue
                    ],
                    range: NSRange(location: utf16Lower, length: utf16Upper - utf16Lower)
                )
            }

            rendered.append(segment)
            spans.append(ChapterParagraphSpan(
                index: paragraph.index,
                startUTF16: start,
                lengthUTF16: (paragraphString as NSString).length,
                text: paragraphString
            ))
            scalarCounts.append(paragraphString.unicodeScalars.count)
        }

        paragraphs = spans
        paragraphScalarCounts = scalarCounts
        attributedText = rendered.copy() as! NSAttributedString
        framesetter = CTFramesetterCreateWithAttributedString(attributedText as CFAttributedString)

        let path = CGPath(
            rect: CGRect(origin: .zero, size: CGSize(width: self.pageWidth, height: self.pageHeight)),
            transform: nil
        )
        var pages: [ChapterPage] = []
        var position = 0
        // Prevent infinite loops for corrupt fonts or impossible small frames.
        while position < rendered.length && pages.count < 20_000 {
            let frame = CTFramesetterCreateFrame(
                framesetter,
                CFRange(location: position, length: 0),
                path,
                nil
            )
            let visible = CTFrameGetVisibleStringRange(frame)
            guard visible.length > 0 else { break }
            let safeLength = min(visible.length, rendered.length - position)
            pages.append(ChapterPage(start: position, length: safeLength))
            position += safeLength
        }
        if pages.isEmpty {
            pages = [ChapterPage(start: 0, length: rendered.length)]
        }
        // A smaller font/page height should always fit some text, and a
        // too-small geometry should never quietly produce fictitious pages.
        chapters = pages
    }

    func page(for paragraph: Int, offset: Int) -> Int {
        guard !chapters.isEmpty else { return 0 }
        guard !paragraphs.isEmpty else { return 0 }
        let safeParagraph = min(max(paragraph, 0), paragraphs.count - 1)
        let span = paragraphs[safeParagraph]
        let safeOffset = min(max(offset, 0), span.text.unicodeScalars.count)
        let location = span.startUTF16 + Self.utf16Length(
            ofPrefix: span.text,
            scalars: safeOffset
        )
        // A page contains the range from its start up to the next page start.
        var low = 0, high = chapters.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if chapters[mid].start <= location { low = mid } else { high = mid - 1 }
        }
        return low
    }

    func progress(at page: Int) -> (paragraph: Int, offset: Int, percent: Double) {
        let pageIndex = min(max(0, page), max(0, chapters.count - 1))
        let charIndex = chapters[pageIndex].start
        guard !paragraphs.isEmpty else {
            return (paragraph: 0, offset: 0, percent: 0)
        }

        var spanIndex = 0
        for i in paragraphs.indices {
            if paragraphs[i].startUTF16 <= charIndex {
                spanIndex = i
            } else {
                break
            }
        }
        let span = paragraphs[spanIndex]
        let localUTF16 = max(0, min(span.lengthUTF16, charIndex - span.startUTF16))
        let prefix = (span.text as NSString).substring(to: localUTF16)
        let scalarOffset = prefix.unicodeScalars.count
        let before = paragraphScalarCounts.prefix(spanIndex).reduce(0, +)
        let fraction = min(100, max(
            0, Double(before + scalarOffset) / Double(chapterScalarCount) * 100
        ))
        return (paragraph: span.index, offset: scalarOffset, percent: fraction)
    }

    private static func utf16Length(ofPrefix source: String, scalars: Int) -> Int {
        String(String.UnicodeScalarView(source.unicodeScalars.prefix(scalars))).utf16.count
    }

    private static func serifFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        let descriptor = base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor
        return UIFont(descriptor: descriptor, size: size)
    }

    private static func annotationColor(_ category: String) -> UIColor {
        switch category {
        case "Канон": return UIColor(red: 1.0, green: 0.68, blue: 0.34, alpha: 1)
        case "Сюжет": return UIColor(red: 1.0, green: 0.43, blue: 0.46, alpha: 1)
        case "Стиль": return UIColor(red: 0.43, green: 0.67, blue: 1, alpha: 1)
        case "Цитата": return UIColor(red: 0.40, green: 0.88, blue: 0.57, alpha: 1)
        default: return UIColor(red: 0.36, green: 0.85, blue: 0.91, alpha: 1)
        }
    }
}

/// Renders the same CoreText frame that was used to determine the page break,
/// so text cannot silently flow behind the narrow information bar.
struct CoreTextPage: UIViewRepresentable {
    let pagination: ChapterPagination
    let pageIndex: Int

    func makeUIView(context: Context) -> CoreTextPageCanvas {
        let view = CoreTextPageCanvas()
        view.isOpaque = true
        view.backgroundColor = UIColor(red: 0.035, green: 0.045, blue: 0.075, alpha: 1)
        return view
    }

    func updateUIView(_ view: CoreTextPageCanvas, context: Context) {
        view.pagination = pagination
        view.pageIndex = pageIndex
        view.setNeedsDisplay()
    }
}

final class CoreTextPageCanvas: UIView {
    var pagination: ChapterPagination?
    var pageIndex = 0

    override func draw(_ rect: CGRect) {
        guard let pagination, let context = UIGraphicsGetCurrentContext(),
              pagination.chapters.indices.contains(pageIndex) else { return }

        let page = pagination.chapters[pageIndex]
        let path = CGPath(rect: bounds, transform: nil)
        let frame = CTFramesetterCreateFrame(
            pagination.framesetter,
            CFRange(location: page.start, length: page.length),
            path,
            nil
        )
        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        CTFrameDraw(frame, context)
        context.restoreGState()
    }
}
