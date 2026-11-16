import Foundation

@main
enum DocxImportSuggestionSmoke {
    static func main() throws {
        func verify(
            _ file: String,
            volume: String?,
            kind: DocxDocumentKind,
            number: String = "",
            title: String,
            display: String
        ) {
            let value = DocxImportSuggestion.infer(from: file)
            precondition(value.volume == volume, "\(file): volume \(String(describing: value.volume))")
            precondition(value.kind == kind, "\(file): kind \(value.kind)")
            precondition(value.chapterNumber == number, "\(file): number \(value.chapterNumber)")
            precondition(value.subtitle == title, "\(file): title \(value.subtitle)")
            precondition(value.libraryTitle == display, "\(file): result \(value.libraryTitle)")
        }

        // Exact screenshot example.
        verify(
            "Том_14_Пролог_В_этот_раз_я_хочу_успеть (1).docx",
            volume: "Том 14", kind: .prologue,
            title: "В этот раз я хочу успеть",
            display: "Пролог. В этот раз я хочу успеть"
        )
        verify(
            "Том_15_Глава_3_Лицом_к_неизвестному.docx",
            volume: "Том 15", kind: .chapter, number: "3",
            title: "Лицом к неизвестному",
            display: "Глава 3. Лицом к неизвестному"
        )
        verify(
            "Том_14_Эпилог_Счастье_быть_с_тобой.docx",
            volume: "Том 14", kind: .epilogue,
            title: "Счастье быть с тобой",
            display: "Эпилог. Счастье быть с тобой"
        )
        verify(
            "Том 15 Побочная история Особенный день.docx",
            volume: "Том 15", kind: .sideStory,
            title: "Особенный день",
            display: "Побочная история. Особенный день"
        )
        verify(
            "Том_16_Послесловие_Авторские_заметки.docx",
            volume: "Том 16", kind: .afterword,
            title: "Авторские заметки",
            display: "Послесловие. Авторские заметки"
        )
        verify(
            "Том_2_Глава_12_Тест (2).docx",
            volume: "Том 2", kind: .chapter, number: "12",
            title: "Тест",
            display: "Глава 12. Тест"
        )
        verify(
            "Volume 5 Chapter 4 A New Morning.docx",
            volume: "Том 5", kind: .chapter, number: "4",
            title: "A New Morning",
            display: "Глава 4. A New Morning"
        )
        verify(
            "Том 15 Пролог.docx",
            volume: "Том 15", kind: .prologue,
            title: "",
            display: "Пролог"
        )
        let named = DocxImportSuggestion.infer(
            from: "Восхождение звёздного героя штандарта Том_14_Глава_1_Свет_для_наших_вечеров.docx"
        )
        precondition(named.volume == "Том 14")
        precondition(named.workHint == "Восхождение звёздного героя штандарта")
        precondition(named.libraryTitle == "Глава 1. Свет для наших вечеров")

        let unknown = DocxImportSuggestion.infer(from: "Неизвестная_сцена.docx")
        precondition(unknown.volume == nil)
        precondition(unknown.kind == .chapter)
        precondition(unknown.subtitle == "Неизвестная сцена")
        precondition(!unknown.confidence)

        // Explicit manual edits always override filename guesses.
        precondition(
            DocxDocumentKind.epilogue.libraryTitle(chapterNumber: "18", subtitle: "Свет") ==
            "Эпилог. Свет"
        )
        precondition(
            DocxDocumentKind.chapter.libraryTitle(chapterNumber: "17", subtitle: "") ==
            "Глава 17"
        )
        print("PASS: 10 DOCX filename patterns, five document kinds, volume/work inference, " +
              "Windows copy suffix, preview and manual override.")
    }
}
