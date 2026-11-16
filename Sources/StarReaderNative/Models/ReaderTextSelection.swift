import Foundation

/// A selected range in the CoreText chapter stream. Global positions use
/// UTF-16 boundaries; paragraph offsets use Unicode scalar counts to match
/// the existing StarReader ZIP backup format.
struct ReaderTextSelection: Identifiable, Equatable {
    let startUTF16: Int
    let endUTF16: Int
    let startParagraph: Int
    let startOffset: Int
    let endParagraph: Int
    let endOffset: Int
    let quote: String

    var id: String { "\(startUTF16):\(endUTF16)" }
    var lengthUTF16: Int { endUTF16 - startUTF16 }
    var spansMultipleParagraphs: Bool { startParagraph != endParagraph }
}
