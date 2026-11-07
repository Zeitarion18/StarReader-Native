import SwiftUI

struct NotesAndBookmarksView: View {
    @ObservedObject var store: LibraryStore
    @State private var activeTab: RecordTab = .notes

    enum RecordTab: String, CaseIterable, Identifiable {
        case notes = "Замечания"
        case bookmarks = "Закладки"
        var id: String { rawValue }
    }

    private let background = Color(red: 0.035, green: 0.045, blue: 0.075)

    var body: some View {
        List {
            Section {
                Picker("Тип записей", selection: $activeTab) {
                    ForEach(RecordTab.allCases) { item in Text(item.rawValue).tag(item) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            }

            if activeTab == .notes {
                if store.annotations.isEmpty {
                    emptyRow("Замечаний пока нет.")
                }
                ForEach(Array(store.annotations.reversed())) { annotation in
                    if let chapter = store.chapter(for: annotation.bookId) {
                        NavigationLink(
                            value: ReaderJump(
                                bookID: chapter.id,
                                paragraph: annotation.paragraph,
                                offset: annotation.start,
                                recordID: annotation.id
                            )
                        ) {
                            annotationContent(annotation, chapter: chapter)
                        }
                    } else {
                        annotationContent(annotation, chapter: nil)
                    }
                }
            } else {
                if store.bookmarks.isEmpty {
                    emptyRow("Закладок пока нет.")
                }
                ForEach(Array(store.bookmarks.reversed())) { bookmark in
                    if let chapter = store.chapter(for: bookmark.bookId) {
                        NavigationLink(
                            value: ReaderJump(
                                bookID: chapter.id,
                                paragraph: bookmark.paragraph,
                                offset: bookmark.offset,
                                recordID: bookmark.id
                            )
                        ) {
                            bookmarkContent(bookmark, chapter: chapter)
                        }
                    } else {
                        bookmarkContent(bookmark, chapter: nil)
                    }
                }
            }

            if store.unlinkedAnnotationCount > 0 || store.unlinkedBookmarkCount > 0 {
                Section {
                    Label {
                        Text("Сохранены записи из удалённых глав: \(store.unlinkedAnnotationCount) замечаний и \(store.unlinkedBookmarkCount) закладок. Оригинальные идентификаторы и текст записей не удалены.")
                            .font(.footnote)
                    } icon: {
                        Image(systemName: "archivebox")
                    }
                    .foregroundStyle(.orange.opacity(0.9))
                } header: {
                    Text("Несвязанные записи")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(background)
        .navigationTitle("Заметки и закладки")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: ReaderJump.self) { jump in
            if let chapter = store.chapter(for: jump.bookID) {
                ReaderView(store: store, chapter: chapter, jump: jump)
            } else {
                ContentUnavailableView("Глава отсутствует", systemImage: "books.vertical")
            }
        }
        .toolbarBackground(background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    @ViewBuilder private func emptyRow(_ message: String) -> some View {
        Text(message)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 24)
    }

    private func annotationContent(_ item: ReaderAnnotation, chapter: LibraryChapter?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(item.categoryTitle)
                    .font(.caption.bold())
                    .foregroundStyle(color(for: item.categoryTitle))
                Spacer(minLength: 6)
                if chapter == nil {
                    Label("Глава отсутствует", systemImage: "archivebox")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            Text(chapter?.displayTitle ?? "Исходная глава недоступна")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            if !item.quote.isEmpty {
                Text("«\(item.quote)»")
                    .font(.system(size: 14, design: .serif))
                    .lineLimit(5)
                    .foregroundStyle(.secondary)
            }
            if !item.note.isEmpty {
                Text(item.note)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }
            Text("Абзац \(item.paragraph + 1)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 7)
    }

    private func bookmarkContent(_ item: ReaderBookmark, chapter: LibraryChapter?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "bookmark.fill")
                    .foregroundStyle(.cyan)
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
            }
            Text(chapter?.displayTitle ?? "Исходная глава недоступна")
                .font(.caption)
                .foregroundStyle(chapter == nil ? .orange : .secondary)
            if !item.note.isEmpty {
                Text(item.note)
                    .font(.subheadline)
            }
            if !item.quote.isEmpty {
                Text(item.quote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Text("Абзац \(item.paragraph + 1)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 7)
    }

    private func color(for category: String) -> Color {
        switch category {
        case "Канон": return .orange
        case "Сюжет": return .red
        case "Стиль": return .blue
        case "Цитата": return .green
        default: return .cyan
        }
    }
}
