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
    let highlightRanges: [NSRange]
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
        paragraphSpacing: Double,
        palette: ReaderPalette
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

        let foreground = palette.uiText
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
        var noteHighlights: [NSRange] = []

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
                guard item.status != "needs_review" else { return false }
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
                let localRange = NSRange(
                    location: utf16Lower,
                    length: utf16Upper - utf16Lower
                )
                // Telegram-like highlight: readable white glyphs over a
                // translucent orange tint. No underlines or font changes.
                segment.addAttribute(
                    .backgroundColor,
                    value: palette.uiNoteTint,
                    range: localRange
                )
                noteHighlights.append(NSRange(
                    location: start + localRange.location,
                    length: localRange.length
                ))
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
        highlightRanges = noteHighlights
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

    /// Resolve a selected CoreText range to exact chapter paragraphs and
    /// Unicode-scalar offsets. Imported notes and new notes share this format.
    func selection(from range: NSRange) -> ReaderTextSelection? {
        guard range.location != NSNotFound, range.length > 0,
              let first = paragraphs.first, let last = paragraphs.last else { return nil }
        let lower = max(range.location, first.startUTF16)
        let upper = min(NSMaxRange(range), last.startUTF16 + last.lengthUTF16)
        guard lower < upper else { return nil }

        var pieces: [(index: Int, start: Int, end: Int, quote: String)] = []
        for span in paragraphs {
            let pStart = span.startUTF16
            let pEnd = pStart + span.lengthUTF16
            if pStart >= upper { break }
            if pEnd <= lower { continue }
            let localStart = max(lower, pStart) - pStart
            let localEnd = min(upper, pEnd) - pStart
            guard localStart < localEnd else { continue }

            let scalarStart = Self.scalarOffset(
                in: span.text, atUTF16: localStart, roundUp: false
            )
            let scalarEnd = Self.scalarOffset(
                in: span.text, atUTF16: localEnd, roundUp: true
            )
            guard scalarStart < scalarEnd else { continue }
            let scalars = Array(span.text.unicodeScalars)
            let selected = String(String.UnicodeScalarView(
                scalars[scalarStart..<scalarEnd]
            ))
            pieces.append((span.index, scalarStart, scalarEnd, selected))
        }

        guard let begin = pieces.first, let finish = pieces.last else {
            return nil
        }
        // Any original paragraph boundary is represented by a line break.
        // Neither chapter titles nor unrelated text can enter the quote.
        let quote = pieces.map { $0.quote }.joined(separator: "\n")
        guard !quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let globalStart = paragraphs[begin.index].startUTF16
            + Self.utf16Length(ofPrefix: paragraphs[begin.index].text, scalars: begin.start)
        let globalEnd = paragraphs[finish.index].startUTF16
            + Self.utf16Length(ofPrefix: paragraphs[finish.index].text, scalars: finish.end)

        return ReaderTextSelection(
            startUTF16: globalStart,
            endUTF16: globalEnd,
            startParagraph: begin.index,
            startOffset: begin.start,
            endParagraph: finish.index,
            endOffset: finish.end,
            quote: quote
        )
    }

    /// Return the word at the touch point, so a short long press highlights
    /// a useful fragment even before the finger begins dragging.
    func wordRange(around location: Int) -> NSRange? {
        let nsText = attributedText.string as NSString
        guard nsText.length > 0 else { return nil }
        let position = min(max(0, location), nsText.length - 1)
        let separators = Set(" \t\r\n.,!?;:—–()[]{}«»\"'".utf16)
        var lower = position
        var upper = position

        if separators.contains(nsText.character(at: upper)) {
            if upper + 1 < nsText.length &&
               !separators.contains(nsText.character(at: upper + 1)) {
                upper += 1
                lower += 1
            } else {
                return nil
            }
        }
        while lower > 0 && !separators.contains(nsText.character(at: lower - 1)) {
            lower -= 1
        }
        while upper < nsText.length &&
              !separators.contains(nsText.character(at: upper)) {
            upper += 1
        }
        guard upper > lower else { return nil }
        let range = NSRange(location: lower, length: upper - lower)
        return selection(from: range) == nil ? nil : range
    }

    /// Converts a finger position into a CoreText string index using the
    /// same frame and line origins that were used to render the page.
    func stringIndex(at point: CGPoint, onPage pageIndex: Int) -> Int? {
        guard chapters.indices.contains(pageIndex) else { return nil }
        let page = chapters[pageIndex]
        let path = CGPath(
            rect: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight),
            transform: nil
        )
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: page.start, length: page.length),
            path,
            nil
        )
        let lines = CTFrameGetLines(frame) as! [CTLine]
        guard !lines.isEmpty else { return nil }

        var origins = Array(repeating: CGPoint.zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        let coreY = pageHeight - point.y
        let nearest = lines.indices.min { left, right in
            abs(origins[left].y - coreY) < abs(origins[right].y - coreY)
        } ?? 0

        let line = lines[nearest]
        let lineRange = CTLineGetStringRange(line)
        let localX = point.x - origins[nearest].x
        let lineWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let result: Int
        if localX <= 0 {
            result = lineRange.location
        } else if localX >= lineWidth {
            result = lineRange.location + lineRange.length
        } else {
            let index = CTLineGetStringIndexForPosition(
                line, CGPoint(x: localX, y: 0)
            )
            result = index == kCFNotFound
                ? lineRange.location + lineRange.length
                : index
        }
        return min(max(page.start, result), page.start + page.length)
    }

    private static func scalarOffset(
        in text: String, atUTF16 location: Int, roundUp: Bool
    ) -> Int {
        let target = min(max(0, location), text.utf16.count)
        var cursor = 0
        var count = 0
        for scalar in text.unicodeScalars {
            if cursor >= target { break }
            let next = cursor + (scalar.value > 0xFFFF ? 2 : 1)
            if next > target {
                return roundUp ? count + 1 : count
            }
            count += 1
            cursor = next
        }
        return count
    }

    /// Shared stable source offsets for TextKit pagination and JSON progress.
    func utf16Location(for paragraph: Int, offset: Int) -> Int {
        guard !paragraphs.isEmpty else { return 0 }
        let index = min(max(0, paragraph), paragraphs.count - 1)
        let span = paragraphs[index]
        let safeOffset = min(max(0, offset), span.text.unicodeScalars.count)
        return span.startUTF16 + Self.utf16Length(
            ofPrefix: span.text, scalars: safeOffset
        )
    }

    func position(atUTF16 location: Int) -> (
        paragraph: Int, offset: Int, percent: Double
    ) {
        guard !paragraphs.isEmpty else {
            return (paragraph: 0, offset: 0, percent: 0)
        }

        let position = max(0, location)
        var spanIndex = 0
        for i in paragraphs.indices {
            if paragraphs[i].startUTF16 <= position {
                spanIndex = i
            } else { break }
        }
        let span = paragraphs[spanIndex]
        let localUTF16 = max(
            0, min(span.lengthUTF16, position - span.startUTF16)
        )
        let scalarOffset = Self.scalarOffset(
            in: span.text, atUTF16: localUTF16, roundUp: false
        )
        let preceding = paragraphScalarCounts.prefix(spanIndex).reduce(0, +)
        let percent = min(
            100,
            max(0, Double(preceding + scalarOffset) /
                Double(chapterScalarCount) * 100)
        )
        return (span.index, scalarOffset, percent)
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

/// A native CoreText page surface with precise long-press selection.
/// Tap/swipe handling lives on the same UIView as the glyph drawing, so touch
/// coordinates never drift relative to the rendered page.
struct CoreTextPage: UIViewRepresentable {
    let pagination: ChapterPagination
    let pageIndex: Int
    let selection: ReaderTextSelection?
    let onTap: (ReaderTapZone) -> Void
    let onSwipe: (Int) -> Void
    let onSelection: (NSRange, Bool) -> Void

    func makeUIView(context: Context) -> CoreTextPageCanvas {
        let view = CoreTextPageCanvas()
        view.isOpaque = true
        view.backgroundColor = UIColor(red: 0.035, green: 0.045, blue: 0.075, alpha: 1)
        return view
    }

    func updateUIView(_ view: CoreTextPageCanvas, context: Context) {
        view.pagination = pagination
        view.pageIndex = pageIndex
        view.selectedRange = selection.map {
            NSRange(location: $0.startUTF16, length: $0.lengthUTF16)
        }
        view.onTap = onTap
        view.onSwipe = onSwipe
        view.onSelection = onSelection
        view.setNeedsDisplay()
    }
}

enum ReaderTapZone {
    case left, center, right
}

final class CoreTextPageCanvas: UIView {
    var pagination: ChapterPagination?
    var pageIndex = 0
    var selectedRange: NSRange?
    var onTap: ((ReaderTapZone) -> Void)?
    var onSwipe: ((Int) -> Void)?
    var onSelection: ((NSRange, Bool) -> Void)?

    private var initialWordRange: NSRange?
    private var currentDragRange: NSRange?

    override init(frame: CGRect) {
        super.init(frame: frame)
        installGestures()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        installGestures()
    }

    private func installGestures() {
        isUserInteractionEnabled = true

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        addGestureRecognizer(tap)

        let swipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(swiped(_:)))
        swipeLeft.direction = .left
        addGestureRecognizer(swipeLeft)

        let swipeRight = UISwipeGestureRecognizer(target: self, action: #selector(swiped(_:)))
        swipeRight.direction = .right
        addGestureRecognizer(swipeRight)

        let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
        hold.minimumPressDuration = 0.32
        hold.allowableMovement = 14
        addGestureRecognizer(hold)
        tap.require(toFail: hold)
    }

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        let x = recognizer.location(in: self).x
        let zone: ReaderTapZone
        if x < bounds.width * 0.20 {
            zone = .left
        } else if x > bounds.width * 0.80 {
            zone = .right
        } else {
            zone = .center
        }
        onTap?(zone)
    }

    @objc private func swiped(_ recognizer: UISwipeGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        // Left swipe turns to the next page; right swipe goes back.
        onSwipe?(recognizer.direction == .left ? 1 : -1)
    }

    @objc private func held(_ recognizer: UILongPressGestureRecognizer) {
        guard let pagination,
              let index = pagination.stringIndex(
                at: recognizer.location(in: self),
                onPage: pageIndex
              ) else { return }

        switch recognizer.state {
        case .began:
            guard let word = pagination.wordRange(around: index) else {
                initialWordRange = nil
                return
            }
            initialWordRange = word
            currentDragRange = word
            UISelectionFeedbackGenerator().selectionChanged()
            onSelection?(word, false)

        case .changed:
            guard let initial = initialWordRange else { return }
            let start: Int
            let end: Int
            if index < initial.location {
                start = index
                end = NSMaxRange(initial)
            } else {
                start = initial.location
                end = max(index, NSMaxRange(initial))
            }
            guard start < end else { return }
            let range = NSRange(location: start, length: end - start)
            currentDragRange = range
            onSelection?(range, false)

        case .ended:
            if let range = currentDragRange {
                onSelection?(range, true)
            }
            initialWordRange = nil
            currentDragRange = nil

        case .cancelled, .failed:
            initialWordRange = nil
            currentDragRange = nil

        default:
            break
        }
    }

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

        if let selectedRange, selectedRange.length > 0 {
            drawHighlight(in: frame, selectedRange: selectedRange, context: context)
        }
        CTFrameDraw(frame, context)
        context.restoreGState()
    }

    private func drawHighlight(
        in frame: CTFrame,
        selectedRange: NSRange,
        context: CGContext
    ) {
        let lines = CTFrameGetLines(frame) as! [CTLine]
        guard !lines.isEmpty else { return }

        var origins = Array(repeating: CGPoint.zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        let selectionEnd = NSMaxRange(selectedRange)

        context.setFillColor(
            UIColor(red: 0.30, green: 0.82, blue: 0.92, alpha: 0.30).cgColor
        )
        for i in lines.indices {
            let line = lines[i]
            let lineRange = CTLineGetStringRange(line)
            let from = max(lineRange.location, selectedRange.location)
            let to = min(lineRange.location + lineRange.length, selectionEnd)
            guard from < to else { continue }

            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            _ = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
            let beginX = CTLineGetOffsetForStringIndex(line, from, nil)
            let endX = CTLineGetOffsetForStringIndex(line, to, nil)
            let left = origins[i].x + min(beginX, endX)
            let width = max(2, abs(endX - beginX))
            context.fill(
                CGRect(
                    x: left,
                    y: origins[i].y - descent - 2,
                    width: width,
                    height: ascent + descent + 4
                )
            )
        }
    }
}
