import SwiftUI

/// One shared editing surface used from the reader and the records list.
/// Saves by original annotation ID, so the source quote and all anchors
/// remain unchanged unless the user explicitly reattaches a reviewed note.
struct AnnotationDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.readerPalette) private var palette
    @ObservedObject var store: LibraryStore

    let annotationID: String

    @State private var kind = "canon"
    @State private var comment = ""
    @State private var tint = "default"
    @State private var confirmDeletion = false
    @State private var errorMessage: String?

    private var current: ReaderAnnotation? {
        store.annotations.first(where: { $0.id == annotationID })
    }

    private struct ColorOption: Identifiable {
        let id: String
        let title: String
        let value: Color
    }

    private let colors: [ColorOption] = [
        ColorOption(id: "default", title: "По теме", value: .orange),
        ColorOption(id: "gold", title: "Золотой", value: .yellow),
        ColorOption(id: "coral", title: "Коралловый", value: .red),
        ColorOption(id: "blue", title: "Голубой", value: .blue),
        ColorOption(id: "mint", title: "Мятный", value: .mint),
        ColorOption(id: "purple", title: "Лиловый", value: .purple)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let item = current {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("ВЫДЕЛЕННЫЙ ТЕКСТ")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(palette.secondary)
                            Text(item.quote)
                                .font(.system(size: 15, design: .serif))
                                .foregroundStyle(palette.text)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(15)
                                .background(palette.surface, in: RoundedRectangle(cornerRadius: 13))
                        }

                        if item.status == "needs_review" {
                            VStack(alignment: .leading, spacing: 9) {
                                Label("Требует проверки", systemImage: "exclamationmark.triangle.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Глава была изменена, и этот фрагмент больше не привязан к тексту. Исходная цитата сохранена.")
                                    .font(.system(size: 13))
                                if let chapter = store.chapter(for: item.bookId) {
                                    Button {
                                        store.pendingAnnotationReanchorID = item.id
                                        dismiss()
                                    } label: {
                                        Label("Выбрать новое место в главе", systemImage: "scope")
                                            .font(.system(size: 14, weight: .semibold))
                                    }
                                    Text("Открой главу «\(chapter.displayTitle)», выдели правильный фрагмент и выбери «Привязать замечание».")
                                        .font(.system(size: 12))
                                } else {
                                    Text("Глава отсутствует в библиотеке. Привязать замечание пока нельзя.")
                                        .font(.system(size: 12))
                                }
                            }
                            .foregroundStyle(.orange)
                            .padding(13)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 13))
                        }

                        VStack(alignment: .leading, spacing: 9) {
                            Text("КАТЕГОРИЯ")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(palette.secondary)
                            Picker("Категория", selection: $kind) {
                                ForEach(AnnotationCategory.allCases) { category in
                                    Text(category.label).tag(category.rawValue)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        VStack(alignment: .leading, spacing: 9) {
                            Text("ЦВЕТ ПОДСВЕТКИ")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(palette.secondary)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                                ForEach(colors) { color in
                                    Button {
                                        tint = color.id
                                    } label: {
                                        VStack(spacing: 6) {
                                            Circle()
                                                .fill(color.value)
                                                .frame(width: 23, height: 23)
                                                .overlay {
                                                    Circle().strokeBorder(palette.text.opacity(0.25), lineWidth: 1)
                                                }
                                            Text(color.title)
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundStyle(palette.text)
                                            if tint == color.id {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(palette.accent)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, minHeight: 79)
                                        .background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 12)
                                                .strokeBorder(
                                                    tint == color.id ? palette.accent : palette.hairline,
                                                    lineWidth: tint == color.id ? 1.5 : 0.5
                                                )
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("КОММЕНТАРИЙ")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(palette.secondary)
                            TextEditor(text: $comment)
                                .scrollContentBackground(.hidden)
                                .font(.system(size: 15))
                                .foregroundStyle(palette.text)
                                .frame(minHeight: 145)
                                .padding(9)
                                .background(palette.surface, in: RoundedRectangle(cornerRadius: 13))
                        }

                        Button {
                            if store.updateAnnotation(
                                id: annotationID, kind: kind,
                                note: comment.trimmingCharacters(in: .whitespacesAndNewlines),
                                color: tint
                            ) {
                                dismiss()
                            } else {
                                errorMessage = store.statusMessage ?? "Изменения не сохранены."
                            }
                        } label: {
                            Label("Сохранить изменения", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(maxWidth: .infinity, minHeight: 49)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(palette.accent)

                        Button(role: .destructive) {
                            confirmDeletion = true
                        } label: {
                            Label("Удалить замечание", systemImage: "trash")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .foregroundStyle(.red)
                    } else {
                        ContentUnavailableView("Замечание отсутствует", systemImage: "archivebox")
                    }
                }
                .padding(20)
                .frame(maxWidth: 690)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(palette.background.ignoresSafeArea())
            .navigationTitle("Замечание")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
            .onAppear {
                guard let item = current else { return }
                kind = AnnotationCategory.allCases.first(where: { $0.rawValue == item.kind })?.rawValue ?? "canon"
                comment = item.note
                tint = colors.contains(where: { $0.id == item.color }) ? item.color : "default"
            }
            .confirmationDialog(
                "Удалить это замечание?",
                isPresented: $confirmDeletion,
                titleVisibility: .visible
            ) {
                Button("Удалить навсегда", role: .destructive) {
                    if store.deleteAnnotation(id: annotationID) {
                        dismiss()
                    } else {
                        errorMessage = store.statusMessage ?? "Не удалось удалить замечание."
                    }
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Исходная глава и другие замечания останутся без изменений. Перед удалением будет создана локальная копия записей.")
            }
            .alert(
                "Ошибка",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("Понятно", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .tint(palette.accent)
        .preferredColorScheme(palette.colorScheme)
    }
}
