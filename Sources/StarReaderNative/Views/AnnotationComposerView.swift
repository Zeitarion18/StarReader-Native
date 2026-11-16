import SwiftUI

enum AnnotationCategory: String, CaseIterable, Identifiable {
    case canon = "canon"
    case plot = "plot"
    case style = "style"
    case quote = "favorite"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .canon: return "Канон"
        case .plot: return "Сюжет"
        case .style: return "Стиль"
        case .quote: return "Цитата"
        }
    }

    var color: Color {
        switch self {
        case .canon: return .orange
        case .plot: return .red
        case .style: return .blue
        case .quote: return .green
        }
    }

    var symbol: String {
        switch self {
        case .canon: return "checkmark.seal"
        case .plot: return "text.book.closed"
        case .style: return "paintbrush.pointed"
        case .quote: return "quote.opening"
        }
    }
}

struct AnnotationComposerView: View {
    @Environment(\.readerPalette) private var palette
    let selection: ReaderTextSelection
    let onSave: (String, String) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var category: AnnotationCategory = .canon
    @State private var comment = ""
    @State private var failedToSave = false

    private let columns = [
        GridItem(.flexible(), spacing: 9),
        GridItem(.flexible(), spacing: 9)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 23) {
                    VStack(alignment: .leading, spacing: 10) {
                        sectionCaption("ВЫДЕЛЕННЫЙ ФРАГМЕНТ")

                        ScrollView {
                            Text(selection.quote)
                                .font(.system(size: 15, design: .serif))
                                .foregroundStyle(palette.text)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 155)
                        .padding(15)
                        .background(palette.surface, in: RoundedRectangle(cornerRadius: 14))

                        Text(selection.spansMultipleParagraphs
                             ? "Абзацы \(selection.startParagraph + 1)–\(selection.endParagraph + 1)"
                             : "Абзац \(selection.startParagraph + 1)")
                            .font(.system(size: 12))
                            .foregroundStyle(palette.secondary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        sectionCaption("КАТЕГОРИЯ")

                        LazyVGrid(columns: columns, spacing: 9) {
                            ForEach(AnnotationCategory.allCases) { item in
                                Button {
                                    category = item
                                } label: {
                                    HStack(spacing: 9) {
                                        Image(systemName: item.symbol)
                                            .font(.system(size: 14, weight: .semibold))
                                        Text(item.label)
                                            .font(.system(size: 14, weight: .semibold))
                                        Spacer(minLength: 2)
                                        if category == item {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 11, weight: .bold))
                                        }
                                    }
                                    .foregroundStyle(category == item ? item.color : palette.text)
                                    .padding(.horizontal, 12)
                                    .frame(height: 49)
                                    .background(
                                        category == item ? item.color.opacity(0.12) : palette.surface,
                                        in: RoundedRectangle(cornerRadius: 13)
                                    )
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 13)
                                            .strokeBorder(category == item ? item.color.opacity(0.55) : palette.hairline, lineWidth: 1)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        sectionCaption("ЗАМЕЧАНИЕ")

                        ZStack(alignment: .topLeading) {
                            if comment.isEmpty {
                                Text("Что хочешь отметить в этом фрагменте?")
                                    .font(.system(size: 14))
                                    .foregroundStyle(palette.secondary.opacity(0.75))
                                    .padding(.horizontal, 13)
                                    .padding(.top, 15)
                                    .allowsHitTesting(false)
                            }

                            TextEditor(text: $comment)
                                .font(.system(size: 15))
                                .foregroundStyle(palette.text)
                                .scrollContentBackground(.hidden)
                                .padding(7)
                                .frame(minHeight: 135)
                        }
                        .background(palette.surface, in: RoundedRectangle(cornerRadius: 14))

                        Text("Комментарий необязателен. Выделенный текст и категория сохраняются всегда.")
                            .font(.system(size: 12))
                            .foregroundStyle(palette.secondary)
                    }

                    Button {
                        if onSave(category.rawValue, comment.trimmingCharacters(in: .whitespacesAndNewlines)) {
                            dismiss()
                        } else {
                            failedToSave = true
                        }
                    } label: {
                        Label("Сохранить замечание", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .foregroundStyle(palette.onAccent)
                            .background(palette.accent, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
                .padding(.bottom, 28)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(palette.background.ignoresSafeArea())
            .navigationTitle("Новое замечание")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") { dismiss() }
                }
            }
            .alert("Не удалось сохранить", isPresented: $failedToSave) {
                Button("Понятно", role: .cancel) {}
            } message: {
                Text("Замечание не было добавлено. Проверь доступное место и повтори попытку.")
            }
        }
        .tint(palette.accent)
        .preferredColorScheme(palette.colorScheme)
    }

    private func sectionCaption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .tracking(1.6)
            .foregroundStyle(palette.secondary)
    }
}
