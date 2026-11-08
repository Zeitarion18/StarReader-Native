import Foundation
import SwiftUI
import UIKit

/// Uses the same UIKit text engine for both pagination and visible text.
/// Unlike the older CoreText canvas there is no custom glyph drawing or
/// invisible layer stealing touches from the native iOS selection handles.
@MainActor
final class NativeTextPagePlan {
    let source: ChapterPagination
    let pageWidth: CGFloat
    let pageHeight: CGFloat
    let pageStarts: [CGFloat]
    let pageCharacters: [Int]

    var pageCount: Int { pageStarts.count }

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

        var offsets: [CGFloat] = [0]
        var characters: [Int] = [0]
        var lastStart: CGFloat = 0

        manager.enumerateLineFragments(forGlyphRange: glyphRange) {
            rect, _, _, glyphs, _ in
            // A new page starts at a real TextKit line, never halfway through it.
            if rect.maxY > lastStart + self.pageHeight &&
               rect.minY > lastStart + 1 {
                let nextCharacter = manager.characterIndexForGlyph(at: glyphs.location)
                guard nextCharacter > (characters.last ?? -1) else { return }
                offsets.append(rect.minY)
                characters.append(nextCharacter)
                lastStart = rect.minY
            }
        }
        pageStarts = offsets
        pageCharacters = characters
    }

    func clamp(_ index: Int) -> Int {
        min(max(0, index), max(0, pageCount - 1))
    }

    func page(for paragraph: Int, offset: Int) -> Int {
        let character = source.utf16Location(for: paragraph, offset: offset)
        var low = 0
        var high = pageCharacters.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if pageCharacters[mid] <= character { low = mid } else { high = mid - 1 }
        }
        return low
    }

    func location(at page: Int) -> (paragraph: Int, offset: Int, percent: Double) {
        source.position(atUTF16: pageCharacters[clamp(page)])
    }

    func verticalOffset(for page: Int) -> CGFloat {
        pageStarts[clamp(page)]
    }
}

/// One UITextView holds the complete chapter, but each page exposes exactly
/// one line-aligned viewport. UITextView provides the native selection handles,
/// magnifier, Copy/Select All actions and the system edit menu.
struct NativeSelectablePage: UIViewRepresentable {
    let plan: NativeTextPagePlan
    let pageIndex: Int
    let onTurn: (Int) -> Void
    let onTapCenter: () -> Void
    let onMakeNote: (ReaderTextSelection) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ReaderUITextView {
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: .zero)
        container.lineFragmentPadding = 0
        container.widthTracksTextView = true
        container.heightTracksTextView = false
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)

        let view = ReaderUITextView(frame: .zero, textContainer: container)
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = true
        view.showsVerticalScrollIndicator = false
        view.showsHorizontalScrollIndicator = false
        view.alwaysBounceVertical = false
        view.bounces = false
        view.backgroundColor = UIColor(red: 0.035, green: 0.045, blue: 0.075, alpha: 1)
        view.textColor = UIColor(red: 0.94, green: 0.955, blue: 0.985, alpha: 1)
        view.textContainerInset = .zero
        view.contentInset = .zero
        view.scrollIndicatorInsets = .zero
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
        coordinator.plan = plan

        if view.currentPlan !== plan {
            coordinator.isUpdating = true
            // Never rewrite text on ordinary page turns. Doing so would
            // dismiss Apple's selection handles and often change the layout.
            view.attributedText = plan.source.attributedText
            view.currentPlan = plan
            view.selectedRange = NSRange(location: 0, length: 0)
            coordinator.isUpdating = false
        }

        let targetY = plan.verticalOffset(for: pageIndex)
        if abs(view.contentOffset.y - targetY) > 0.75 {
            coordinator.isUpdating = true
            view.setContentOffset(CGPoint(x: 0, y: targetY), animated: false)
            coordinator.isUpdating = false
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        weak var view: ReaderUITextView?
        var plan: NativeTextPagePlan?
        var onTurn: ((Int) -> Void)?
        var onTapCenter: (() -> Void)?
        var onMakeNote: ((ReaderTextSelection) -> Void)?
        var isUpdating = false

        // Apple's own text selection editing menu, extended by one action.
        func textView(
            _ textView: UITextView,
            editMenuForTextIn range: NSRange,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            guard range.length > 0, let plan,
                  let selected = plan.source.selection(from: range) else {
                return UIMenu(children: suggestedActions)
            }

            let makeNote = UIAction(
                title: "Замечание",
                image: UIImage(systemName: "highlighter")
            ) { [weak self] _ in
                self?.onMakeNote?(selected)
            }
            return UIMenu(children: [makeNote] + suggestedActions)
        }

        @objc func swipe(_ recognizer: UISwipeGestureRecognizer) {
            guard recognizer.state == .ended,
                  let view,
                  view.selectedRange.length == 0 else { return }
            onTurn?(recognizer.direction == .left ? 1 : -1)
        }

        @objc func tap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let view,
                  view.selectedRange.length == 0 else { return }
            let x = recognizer.location(in: view).x
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
            // Do not block UITextView's private native text-selection gestures.
            true
        }

        func scrollViewWillEndDragging(
            _ scrollView: UIScrollView,
            withVelocity velocity: CGPoint,
            targetContentOffset: UnsafeMutablePointer<CGPoint>
        ) {
            guard let plan else { return }
            let current = plan.pageStarts.enumerated().min {
                abs($0.element - targetContentOffset.pointee.y) <
                abs($1.element - targetContentOffset.pointee.y)
            }?.offset ?? 0
            targetContentOffset.pointee.y = plan.verticalOffset(for: current)
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            guard !isUpdating, let plan else { return }
            // Vertical drag is not a page-turn gesture. Recenter to the
            // current page, retaining horizontal native selection gestures.
            let index = plan.pageStarts.enumerated().min {
                abs($0.element - scrollView.contentOffset.y) <
                abs($1.element - scrollView.contentOffset.y)
            }?.offset ?? 0
            if abs(plan.verticalOffset(for: index) - scrollView.contentOffset.y) > 1 {
                scrollView.setContentOffset(
                    CGPoint(x: 0, y: plan.verticalOffset(for: index)),
                    animated: false
                )
            }
        }
    }
}

final class ReaderUITextView: UITextView {
    var currentPlan: NativeTextPagePlan?
}
