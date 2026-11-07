import SwiftUI

struct NotesAndBookmarksView: View {
    @ObservedObject var store: LibraryStore
    @State private var activeTab: RecordTab = .notes
    @State private var searchText = ""

    enum RecordTab: String, CaseIterable, Identifiable {
        case notes = "Замечания"
        case bookmarks = "Закладки"
        var id: String { rawValue }
    }

    private var visibleNotes: [ReaderAnnotation] {
        store.annotations.reversed().filter { item in
            searchText.isEmpty ||
            item.quote.localizedCaseInsensitiveContains(searchText) ||
            item.note.localizedCaseInsensitiveContains(searchText) ||
            item.categoryTitle.localizedCaseInsensitiveContains(searchText) ||
            (store.chapter(for: item.bookId)?.displayTitle.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    private var visibleBookmarks: [ReaderBookmark] {
        store.bookmarks.reversed().filter { item in
            searchText.isEmpty ||
            item.title.localizedCaseInsensitiveContains(searchText) ||
            item.quote.localizedCaseInsensitiveContains(searchText) ||
            item.note.localizedCaseInsensitiveContains(searchText) ||
            (store.chapter(for: item.bookId)?.displayTitle.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Все важные моменты")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(ReaderTheme.text)
                    Text("\(store.annotations.count) замечаний · \(store.bookmarks.count) закладок")
                        .font(.system(size: 13))
                        .foregroundStyle(ReaderTheme.secondary)
                }

                Picker("Раздел", selection: $activeTab) {
                    ForEach(RecordTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundStyle(ReaderTheme.secondary)
                    TextField("Поиск по записям", text: $searchText)
                        .font(.system(size: 14))
                        .tint(ReaderTheme.accent)
                        .autocorrectionDisabled()
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(ReaderTheme.secondary)
                        }
                        .accessibilityLabel("Очистить поиск")
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(ReaderTheme.surface, in: RoundedRectangle(cornerRadius: 13))

                if store.unlinkedAnnotationCount > 0 || store.unlinkedBookmarkCount > 0 {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "archivebox")
                            .font(.system(size: 14))
                            .padding(.top, 1)
                        Text("Записи из удалённых глав сохранены: \(store.unlinkedAnnotationCount) замечаний и \(store.unlinkedBookmarkCount) закладок.")
                            .font(.system(size: 12))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(Color.orange.opacity(0.9))
                    .padding(13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                }

                if activeTab == .notes {
                    if visibleNotes.isEmpty {
                        emptyRecords("Замечаний не найдено")
                    } else {
                        LazyVStack(spacing: 11) {
                            ForEach(visibleNotes) { item in
                                if let chapter = store.chapter(for: item.bookId) {
                                    NavigationLink(
                                        value: ReaderJump(
                                            bookID: chapter.id,
                                            paragraph: item.paragraph,
                                            offset: item.start,
                                            recordID: item.id
                                        )
                                    ) {
                                        annotationCard(item, chapter: chapter)
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    annotationCard(item, chapter: nil)
                                }
                            }
                        }
                    }
                } else {
                    if visibleBookmarks.isEmpty {
                        emptyRecords("Закладок не найдено")
                    } else {
                        LazyVStack(spacing: 11) {
                            ForEach(visibleBookmarks) { item in
                                if let chapter = store.chapter(for: item.bookId) {
                                    NavigationLink(
                                        value: ReaderJump(
                                            bookID: chapter.id,
                                            paragraph: item.paragraph,
                                            offset: item.offset,
                                            recordID: item.id
                                        )
                                    ) {
                                        bookmarkCard(item, chapter: chapter)
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    bookmarkCard(item, chapter: nil)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 690)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 19)
            .padding(.bottom, 38)
        }
        .scrollIndicators(.hidden)
        .background(ReaderTheme.background.ignoresSafeArea())
        .navigationTitle("Мои записи")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                ReaderBackButton()
            }
        }
        .navigationDestination(for: ReaderJump.self) { jump in
            if let chapter = store.chapter(for: jump.bookID) {
                ReaderView(store: store, chapter: chapter, jump: jump)
            } else {
                ContentUnavailableView("Глава отсутствует", systemImage: "archivebox")
            }
        }
        .toolbarBackground(ReaderTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private func annotationCard(_ item: ReaderAnnotation, chapter: LibraryChapter?) -> some View {
        ReaderSurface {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(categoryColor(item.categoryTitle))
                        .frame(width: 6, height: 6)
                    Text(item.categoryTitle.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(categoryColor(item.categoryTitle))
                    Spacer(minLength: 0)
                    if chapter == nil {
                        Label("Нет главы", systemImage: "archivebox")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.orange)
                    } else {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ReaderTheme.secondary)
                    }
                }

                Text(chapter?.displayTitle ?? "Глава отсутствует в библиотеке")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ReaderTheme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if !item.quote.isEmpty {
                    HStack(alignment: .top, spacing: 9) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(categoryColor(item.categoryTitle).opacity(0.65))
                            .frame(width: 3)
                        Text(item.quote)
                            .font(.system(size: 14, design: .serif))
                            .foregroundStyle(ReaderTheme.secondary)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }

                if !item.note.isEmpty {
                    Text(item.note)
                        .font(.system(size: 13))
                        .foregroundStyle(ReaderTheme.text.opacity(0.88))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Text("Абзац \(item.paragraph + 1)")
                    .font(.system(size: 11))
                    .foregroundStyle(ReaderTheme.secondary.opacity(0.8))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func bookmarkCard(_ item: ReaderBookmark, chapter: LibraryChapter?) -> some View {
        ReaderSurface {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: "bookmark.fill")
                    .foregroundStyle(ReaderTheme.accent)
                    .font(.system(size: 18))
                    .frame(width: 27)

                VStack(alignment: .leading, spacing: 7) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ReaderTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(chapter?.displayTitle ?? "Глава отсутствует в библиотеке")
                        .font(.system(size: 12))
                        .foregroundStyle(chapter == nil ? .orange : ReaderTheme.secondary)
                        .lineLimit(2)
                    if !item.quote.isEmpty {
                        Text(item.quote)
                            .font(.system(size: 13, design: .serif))
                            .foregroundStyle(ReaderTheme.secondary)
                            .lineLimit(2)
                    }
                    if !item.note.isEmpty {
                        Text(item.note)
                            .font(.system(size: 12))
                            .foregroundStyle(ReaderTheme.text)
                            .lineLimit(2)
                    }
                    Text("Абзац \(item.paragraph + 1)")
                        .font(.system(size: 11))
                        .foregroundStyle(ReaderTheme.secondary)
                }

                Spacer(minLength: 0)
                if chapter != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11))
                        .foregroundStyle(ReaderTheme.secondary)
                }
            }
        }
    }

    private func emptyRecords(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "text.book.closed")
                .font(.system(size: 28, weight: .ultraLight))
                .foregroundStyle(ReaderTheme.secondary)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(ReaderTheme.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(38)
        .background(ReaderTheme.surface, in: RoundedRectangle(cornerRadius: 18))
    }

    private func categoryColor(_ category: String) -> Color {
        switch category {
        case "Канон": return .orange
        case "Сюжет": return .red
        case "Стиль": return .blue
        case "Цитата": return .green
        default: return ReaderTheme.accent
        }
    }
}
