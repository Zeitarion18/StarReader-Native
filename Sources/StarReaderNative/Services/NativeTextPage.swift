import Foundation
import SwiftUI
import UIKit
import QuartzCore

/// A TextKit page boundary is a character offset at the START of a whole line.
/// Unlike v0.4.4, a page never scrolls a giant UITextView to a fractional Y
/// coordinate; its UIKit text view owns only that page's exact attributed slice.
@MainActor
final class NativeTextPagePlan {
    let source: ChapterPagination
    let pageWidth: CGFloat
    let pageHeight: CGFloat
    let pageCharacters: [Int]

    var pageCount: Int { pageCharacters.count }

    init(source: ChapterPagination, pageWidth: CGFloat, pageHeight: CGFloat) {
        self.source = source
        self.pageWidth = max(140, pageWidth)
        self.pageHeight = max(150, pageHeight)

        let storage = NSTextStorage(attributedString: source.attributedText)
        let manager = NSLayoutManager()
        let container = NSTextContainer(
            size: CGSize(width: self.pageWidth, height: CGFloat.greatestFiniteMagnitude)
        )
        container.lineFragmentPadding = 0
        container.widthTracksTextView = false
        container.heightTracksTextView = false
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        manager.ensureLayout(for: container)

        let glyphRange = manager.glyphRange(for: container)
        var starts: [Int] = [0]
        var lastStartY: CGFloat = 0

        // Leave a small tolerance for glyph ascenders/descenders at the
        // viewport edge. No line will ever be cut in two by a page boundary.
        // Rendering a page-local attributed slice can slightly change the
        // first line's paragraph geometry. Keep a full line of slack so an
        // actual UITextView never clips the page's last glyph.
        let usableHeight = max(80, self.pageHeight - 34)
        manager.enumerateLineFragments(forGlyphRange: glyphRange) {
            rect, _, _, glyphs, _ in
            if rect.maxY > lastStartY + usableHeight &&
                rect.minY > lastStartY + 1 {
                let character = manager.characterIndexForGlyph(at: glyphs.location)
                guard character > (starts.last ?? -1) else { return }
                starts.append(character)
                lastStartY = rect.minY
            }
        }
        pageCharacters = starts
    }

    func clamp(_ index: Int) -> Int {
        min(max(0, index), max(0, pageCount - 1))
    }

    func page(for paragraph: Int, offset: Int) -> Int {
        let character = source.utf16Location(for: paragraph, offset: offset)
        var low = 0
        var high = pageCharacters.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if pageCharacters[middle] <= character {
                low = middle
            } else {
                high = middle - 1
            }
        }
        return low
    }

    func location(at page: Int) -> (paragraph: Int, offset: Int, percent: Double) {
        source.position(atUTF16: pageCharacters[clamp(page)])
    }

    func range(at page: Int) -> NSRange {
        let index = clamp(page)
        let begin = pageCharacters[index]
        let end = index + 1 < pageCharacters.count
            ? pageCharacters[index + 1]
            : source.attributedText.length
        return NSRange(location: begin, length: max(0, end - begin))
    }

    func attributedPage(at page: Int) -> NSAttributedString {
        source.attributedText.attributedSubstring(from: range(at: page))
    }

    /// Convert source-chapter note ranges to offsets local to this page.
    func noteRanges(at page: Int) -> [NSRange] {
        let bounds = range(at: page)
        let pageEnd = NSMaxRange(bounds)
        return source.highlightRanges.compactMap { note in
            let lower = max(note.location, bounds.location)
            let upper = min(NSMaxRange(note), pageEnd)
            guard upper > lower else { return nil }
            return NSRange(location: lower - bounds.location, length: upper - lower)
        }
    }
}

/// A self-contained, discrete page. UIKit still owns its selection,
/// magnifier and edit menu; swiping/tapping only turns discrete pages.
struct NativeSelectablePage: UIViewRepresentable {
    let plan: NativeTextPagePlan
    let palette: ReaderPalette
    let pageIndex: Int
    let onTurn: (Int) -> Void
    let onTapCenter: () -> Void
    let onMakeNote: (ReaderTextSelection) -> Void
    let onEditSelection: (ReaderTextSelection) -> Void
    let pendingReanchorID: String?
    let onReanchorSelection: (ReaderTextSelection) -> Void
    let onTapAnnotation: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ReaderUITextView {
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        let container = NSTextContainer(
            size: CGSize(width: plan.pageWidth, height: CGFloat.greatestFiniteMagnitude)
        )
        container.lineFragmentPadding = 0
        container.widthTracksTextView = true
        container.heightTracksTextView = false
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)

        let view = ReaderUITextView(frame: .zero, textContainer: container)
        view.isEditable = false
        view.isSelectable = true
        // UIKit must lay out a scrolling UITextView to keep word wrapping
        // correct. v0.4.5 disabled scrolling, and UIKit widened the text
        // container to its intrinsic content size (the screenshot showed
        // horizontally clipped text and most of the page blank).
        //
        // Enable the native text layout, but disable its pan recognizer: only
        // our discrete page-turn gestures are allowed to move between pages.
        view.isScrollEnabled = true
        view.panGestureRecognizer.isEnabled = false
        view.alwaysBounceVertical = false
        view.alwaysBounceHorizontal = false
        view.showsVerticalScrollIndicator = false
        view.showsHorizontalScrollIndicator = false
        view.bounces = false
        view.backgroundColor = palette.uiBackground
        view.textColor = palette.uiText
        // This 10pt gutter on BOTH sides is included in plan.pageWidth.
        // The left gutter houses the orange note marker.
        view.textContainerInset = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        view.contentInset = .zero
        view.scrollIndicatorInsets = .zero
        view.contentInsetAdjustmentBehavior = .never
        view.keyboardDismissMode = .none
        view.dataDetectorTypes = []
        view.textDragInteraction?.isEnabled = false
        view.delegate = context.coordinator
        context.coordinator.view = view

        let left = UISwipeGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.swipe(_:))
        )
        left.direction = .left
        left.cancelsTouchesInView = false
        left.delegate = context.coordinator
        view.addGestureRecognizer(left)

        let right = UISwipeGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.swipe(_:))
        )
        right.direction = .right
        right.cancelsTouchesInView = false
        right.delegate = context.coordinator
        view.addGestureRecognizer(right)

        let tap = UITapGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.tap(_:))
        )
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ view: ReaderUITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onTurn = onTurn
        coordinator.onTapCenter = onTapCenter
        coordinator.onMakeNote = onMakeNote
        coordinator.onEditSelection = onEditSelection
        coordinator.pendingReanchorID = pendingReanchorID
        coordinator.onReanchorSelection = onReanchorSelection
        coordinator.onTapAnnotation = onTapAnnotation
        coordinator.plan = plan
        view.backgroundColor = palette.uiBackground
        view.textColor = palette.uiText
        view.configureNoteColor(palette.uiNoteRail)

        let page = plan.clamp(pageIndex)
        coordinator.chapterStart = plan.range(at: page).location

        if view.currentPlan !== plan || view.currentPage != page {
            // This is the ONLY time the displayed slice is replaced.
            // Ordinary menu interactions never rebuild the selected text.
            view.attributedText = plan.attributedPage(at: page)
            view.currentPlan = plan
            view.currentPage = page
            view.selectedRange = NSRange(location: 0, length: 0)
            view.setContentOffset(.zero, animated: false)
            view.setNoteRanges(plan.noteRanges(at: page))
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        weak var view: ReaderUITextView?
        var plan: NativeTextPagePlan?
        var chapterStart = 0
        var onTurn: ((Int) -> Void)?
        var onTapCenter: (() -> Void)?
        var onMakeNote: ((ReaderTextSelection) -> Void)?
        var onEditSelection: ((ReaderTextSelection) -> Void)?
        var pendingReanchorID: String?
        var onReanchorSelection: ((ReaderTextSelection) -> Void)?
        var onTapAnnotation: ((String) -> Void)?

        func textView(
            _ textView: UITextView,
            editMenuForTextIn range: NSRange,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            guard range.length > 0, let plan else {
                return UIMenu(children: suggestedActions)
            }
            // UIKit reports a page-local UTF-16 range. Notes are stored in
            // immutable chapter-global UTF-16 / Unicode-scalar coordinates.
            let global = NSRange(
                location: chapterStart + range.location,
                length: range.length
            )
            guard let selection = plan.source.selection(from: global) else {
                return UIMenu(children: suggestedActions)
            }
            let makeNote = UIAction(
                title: "Замечание",
                image: UIImage(systemName: "highlighter")
            ) { [weak self] _ in
                self?.onMakeNote?(selection)
            }
            let editText = UIAction(
                title: "Изменить",
                image: UIImage(systemName: "pencil")
            ) { [weak self] _ in
                self?.onEditSelection?(selection)
            }
            var actions: [UIMenuElement] = [editText, makeNote]
            if pendingReanchorID != nil {
                actions.insert(
                    UIAction(
                        title: "Привязать замечание",
                        image: UIImage(systemName: "scope")
                    ) { [weak self] _ in
                        self?.onReanchorSelection?(selection)
                    },
                    at: 0
                )
            }
            return UIMenu(children: actions + suggestedActions)
        }

        @objc func swipe(_ recognizer: UISwipeGestureRecognizer) {
            guard recognizer.state == .ended, let view,
                  view.selectedRange.length == 0 else { return }
            onTurn?(recognizer.direction == .left ? 1 : -1)
        }

        @objc func tap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let view,
                  view.selectedRange.length == 0 else { return }
            let touch = recognizer.location(in: view)
            let local = CGPoint(
                x: touch.x - view.textContainerInset.left + view.contentOffset.x,
                y: touch.y - view.textContainerInset.top + view.contentOffset.y
            )
            let layout = view.layoutManager
            if layout.numberOfGlyphs > 0 {
                let glyph = layout.glyphIndex(
                    for: local, in: view.textContainer
                )
                if glyph < layout.numberOfGlyphs {
                    let glyphRect = layout.boundingRect(
                        forGlyphRange: NSRange(location: glyph, length: 1),
                        in: view.textContainer
                    )
                    if glyphRect.insetBy(dx: -5, dy: -4).contains(local) {
                        let globalOffset = chapterStart + layout.characterIndexForGlyph(at: glyph)
                        if let note = plan?.source.noteHitTargets.first(
                            where: { NSLocationInRange(globalOffset, $0.range) }
                        ) {
                            onTapAnnotation?(note.id)
                            return
                        }
                    }
                }
            }
            let x = touch.x
            if x < view.bounds.width * 0.19 {
                onTurn?(-1)
            } else if x > view.bounds.width * 0.81 {
                onTurn?(1)
            } else {
                onTapCenter?()
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

/// The orange quote rail follows the actual TextKit highlight glyphs,
/// not the entire paragraph. It has no gesture recognizers and cannot
/// interfere with native copy/selection handles.
final class ReaderUITextView: UITextView {
    var currentPlan: NativeTextPagePlan?
    var currentPage = -1

    private let railLayer = CAShapeLayer()
    private var highlightedRanges: [NSRange] = []
    private var noteColor = UIColor(red: 1, green: 0.59, blue: 0.25, alpha: 0.96)

    func configureNoteColor(_ color: UIColor) {
        noteColor = color
        railLayer.strokeColor = color.cgColor
    }

    func setNoteRanges(_ ranges: [NSRange]) {
        highlightedRanges = ranges
        if railLayer.superlayer == nil {
            railLayer.fillColor = nil
            railLayer.strokeColor = noteColor.cgColor
            railLayer.lineWidth = 3
            railLayer.lineCap = .round
            layer.addSublayer(railLayer)
        }
        refreshRails()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // The text container is always the *visible* page width, never the
        // intrinsic width of a long paragraph. Guard against zero-width
        // initial layout and UIKit geometry changes after SwiftUI sizing.
        let width = bounds.width - textContainerInset.left - textContainerInset.right
        if width >= 140 && abs(textContainer.size.width - width) > 0.5 {
            textContainer.size = CGSize(
                width: width,
                height: CGFloat.greatestFiniteMagnitude
            )
        }

        // This UITextView stores ONLY one page; its scroll position must
        // always be zero. The user changes pages through onTurn instead.
        if abs(contentOffset.x) > 0.5 || abs(contentOffset.y) > 0.5 {
            setContentOffset(.zero, animated: false)
        }
        refreshRails()
    }

    private func refreshRails() {
        railLayer.frame = bounds
        let path = UIBezierPath()
        guard bounds.width > 0, bounds.height > 0 else {
            railLayer.path = nil
            return
        }

        layoutManager.ensureLayout(for: textContainer)
        for note in highlightedRanges {
            let textEnd = textStorage.length
            let lower = max(0, min(note.location, textEnd))
            let upper = max(lower, min(NSMaxRange(note), textEnd))
            guard upper > lower else { continue }
            let glyphs = layoutManager.glyphRange(
                forCharacterRange: NSRange(location: lower, length: upper - lower),
                actualCharacterRange: nil
            )
            var top = CGFloat.greatestFiniteMagnitude
            var bottom: CGFloat = 0
            layoutManager.enumerateEnclosingRects(
                forGlyphRange: glyphs,
                withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                in: textContainer
            ) { rect, _ in
                guard rect.height > 0 else { return }
                top = min(top, rect.minY)
                bottom = max(bottom, rect.maxY)
            }
            guard top.isFinite, bottom > top else { continue }
            let start = max(1, top + textContainerInset.top)
            let finish = min(bounds.height - 1, bottom + textContainerInset.top)
            guard finish > start else { continue }
            path.move(to: CGPoint(x: 4, y: start))
            path.addLine(to: CGPoint(x: 4, y: finish))
        }
        railLayer.path = path.cgPath
    }
}
