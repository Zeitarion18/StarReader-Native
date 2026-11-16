import SwiftUI

/// The editing sheet is separate from the reader so its TextEditor can
/// expand and use the native iOS keyboard without changing page geometry.
struct ChapterEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.readerPalette) private var palette
    @ObservedObject var store: LibraryStore

    let chapterID: String
    let selection: ReaderTextSelection?
    let onSaved: (ChapterEditing.Result) -> Void

    @State private var openedChapter: LibraryChapter?
    @State private var title = ""
    @State private var draft = ""
    @State private var originalDraft = ""
    @State private var originalTitle = ""
    @State private var isSaveConfirmationPresented = false
    @State private var notesNeedingReview = 0
    @State private var bookmarksNeedingReview = 0
    @State private var errorText: String?

    private var isQuickEdit: Bool { selection != nil }
    private var isDirty: Bool {
        title != originalTitle || draft != originalDraft
    }

    private var newParagraphs: [ChapterEditing.Paragraph]? {
        guard let chapter = openedChapter else { return nil }
        if let selection {
            return try? ChapterEditing.replacing(
                selection: selection,
                in: chapter,
                with: draft
            )
        }
        return ChapterEditing.paragraphsFromWholeDraft(
            draft, original: ChapterEditing.paragraphs(of: chapter)
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let chapter = openedChapter {
                        Text(chapter.series + "  •  " + chapter.volume)
                            .font(.system(size: 12))
                            .foregroundStyle(palette.secondary)

                        if !isQuickEdit {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Название главы")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(palette.secondary)
                                TextField("Название главы", text: $title)
                                    .textInputAutocapitalization(.sentences)
                                    .padding(13)
                                    .background(
                                        palette.surface,
                                        in: RoundedRectangle(cornerRadius: 12)
                                    )
                            }
                        } else {
                            Text(chapter.displayTitle)
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(palette.text)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(isQuickEdit
                                    ? "Изменить выделенный фрагмент"
                                    : "Текст главы")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(palette.text)
                                Spacer()
                                Text("\(draft.unicodeScalars.count) симв.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(palette.secondary)
                            }

                            TextEditor(text: $draft)
                                .font(.system(
                                    size: 16, weight: .regular, design: .serif
                                ))
                                .foregroundStyle(palette.text)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: isQuickEdit ? 185 : 440)
                                .padding(8)
                                .background(
                                    palette.surface,
                                    in: RoundedRectangle(cornerRadius: 13)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 13)
                                        .strokeBorder(palette.hairline)
                                }
                        }

                        if !isQuickEdit {
                            Label(
                                "Абзацы разделяются пустой строкой. " +
                                "Один перенос внутри абзаца сохраняется.",
                                systemImage: "text.alignleft"
                            )
                            .font(.system(size: 12))
                            .foregroundStyle(palette.secondary)
                        }
                        Label(
                            "Перед сохранением создаётся локальная копия " +
                            "главы и замечаний. Исходный DOCX не изменяется.",
                            systemImage: "shield.lefthalf.filled"
                        )
                        .font(.system(size: 12))
                        .foregroundStyle(palette.secondary)

                        HStack(spacing: 12) {
                            Button {
                                draft = originalDraft
                                title = originalTitle
                            } label: {
                                Label("Отменить правки", systemImage: "arrow.uturn.backward")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                            }
                            .disabled(!isDirty)
                            .buttonStyle(.bordered)

                            Button {
                                prepareSave()
                            } label: {
                                Label("Сохранить", systemImage: "checkmark")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                            }
                            .disabled(!isDirty || newParagraphs == nil)
                            .buttonStyle(.borderedProminent)
                        }
                        .tint(palette.accent)
                    } else {
                        ProgressView("Открываем редактор…")
                    }
                }
                .frame(maxWidth: 760)
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollContentBackground(.hidden)
            .background(palette.background.ignoresSafeArea())
            .navigationTitle(isQuickEdit ? "Исправить фрагмент" : "Редактор главы")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Закрыть") {
                        if isDirty {
                            showDiscardWarning = true
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Сохранить") { prepareSave() }
                        .disabled(!isDirty || newParagraphs == nil)
                }
            }
            .onAppear(perform: populate)
            .confirmationDialog(
                "Сохранить изменения главы?",
                isPresented: $isSaveConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("Сохранить главу") { commitSave() }
                Button("Вернуться к редактированию", role: .cancel) {}
            } message: {
                Text("Заметки, требующие проверки: \(notesNeedingReview). " +
                     "Закладки, требующие проверки: \(bookmarksNeedingReview). " +
                     "Все записи сохранятся, а перед заменой текста " +
                     "будет создана резервная копия.")
            }
            .confirmationDialog(
                "Закрыть без сохранения?",
                isPresented: $showDiscardWarning,
                titleVisibility: .visible
            ) {
                Button("Не сохранять", role: .destructive) { dismiss() }
                Button("Продолжить редактирование", role: .cancel) {}
            } message: {
                Text("Несохранённые правки будут потеряны.")
            }
            .alert(
                "Редактор StarReader",
                isPresented: Binding(
                    get: { errorText != nil },
                    set: { if !$0 { errorText = nil } }
                )
            ) {
                Button("Понятно", role: .cancel) { errorText = nil }
            } message: {
                Text(errorText ?? "")
            }
        }
        .preferredColorScheme(palette.colorScheme)
    }

    @State private var showDiscardWarning = false

    private func populate() {
        guard let chapter = store.chapter(for: chapterID) else {
            errorText = "Не удалось найти главу в библиотеке."
            return
        }
        openedChapter = chapter
        originalTitle = chapter.displayTitle
        title = originalTitle
        originalDraft = selection?.quote
            ?? ChapterEditing.wholeChapterDraft(
                ChapterEditing.paragraphs(of: chapter)
            )
        draft = originalDraft
    }

    private func prepareSave() {
        guard let chapter = openedChapter,
              let paragraphs = newParagraphs else { return }
        do {
            let plan = try store.previewChapterEdits(
                for: chapter, title: title, paragraphs: paragraphs
            )
            notesNeedingReview = plan.notesNeedingReview
            bookmarksNeedingReview = plan.bookmarksNeedingReview
            isSaveConfirmationPresented = true
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func commitSave() {
        guard let chapter = openedChapter,
              let paragraphs = newParagraphs else { return }
        do {
            let result = try store.saveChapterEdits(
                for: chapter, title: title, paragraphs: paragraphs
            )
            onSaved(result)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
