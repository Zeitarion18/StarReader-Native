import SwiftUI

struct NotesAndBookmarksView: View {
    @Environment(\.readerPalette) private var palette
    @ObservedObject var store: LibraryStore
    @State private var activeTab: RecordTab = .notes
    @State private var searchText = ""
    @State private var selectedNote: AnnotationSheetTarget?
    @State private var categoryFilter = "all"
    @State private var statusFilter = "all"
    @State private var workFilter = "all"
    @State private var volumeFilter = "all"
    @State private var chapterFilter = "all"

    enum RecordTab: String, CaseIterable, Identifiable {
        case notes = "Замечания"
        case bookmarks = "Закладки"
        var id: String { rawValue }
    }

    private var visibleNotes: [ReaderAnnotation] {
        store.annotations.reversed().filter { item in
            let chapter = store.chapter(for: item.bookId)
            let matchesText = searchText.isEmpty ||
                item.quote.localizedCaseInsensitiveContains(searchText) ||
                item.note.localizedCaseInsensitiveContains(searchText) ||
                item.categoryTitle.localizedCaseInsensitiveContains(searchText) ||
                (chapter?.displayTitle.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (chapter?.series.localizedCaseInsensitiveContains(searchText) ?? false)
            return matchesText &&
                (categoryFilter == "all" || item.kind == categoryFilter) &&
                (statusFilter == "all" ||
                    (statusFilter == "review" && item.status == "needs_review") ||
                    (statusFilter == "normal" && item.status != "needs_review")) &&
                (workFilter == "all" || chapter?.series == workFilter) &&
                (volumeFilter == "all" || chapter?.volume == volumeFilter) &&
                (chapterFilter == "all" || item.bookId == chapterFilter)
        }
    }

    private var relevantVolumes: [String] {
        let volumes = store.snapshot.chapters.filter {
            workFilter == "all" || $0.series == workFilter
        }.map(\.volume)
        return Array(Set(volumes)).sorted()
    }

    private var relevantChapters: [LibraryChapter] {
        store.snapshot.chapters.filter {
            (workFilter == "all" || $0.series == workFilter) &&
            (volumeFilter == "all" || $0.volume == volumeFilter)
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
                        .foregroundStyle(palette.text)
                    Text("\(store.annotations.count) замечаний · \(store.bookmarks.count) закладок")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.secondary)
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
                        .foregroundStyle(palette.secondary)
                    TextField("Поиск по записям", text: $searchText)
                        .font(.system(size: 14))
                        .tint(palette.accent)
                        .autocorrectionDisabled()
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(palette.secondary)
                        }
                        .accessibilityLabel("Очистить поиск")
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(palette.surface, in: RoundedRectangle(cornerRadius: 13))

                if activeTab == .notes {
                    noteFilters
                }

                if let pending = store.pendingAnnotationReanchor {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Ожидается повторная привязка", systemImage: "scope")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Открой нужную главу и выдели правильный фрагмент. В меню выделения выбери «Привязать замечание».")
                            .font(.system(size: 12))
                        Text("Исходная цитата: «\(pending.quote)»")
                            .font(.system(size: 12, design: .serif))
                            .lineLimit(2)
                        Button("Отменить повторную привязку") {
                            store.pendingAnnotationReanchorID = nil
                        }
                        .font(.system(size: 12))
                    }
                    .foregroundStyle(.orange)
                    .padding(13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }

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
                                noteRow(item)
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
                                    NavigationLink {
                                        ReaderView(
                                            store: store,
                                            chapter: chapter,
                                            jump: ReaderJump(
                                                bookID: chapter.id,
                                                paragraph: item.paragraph,
                                                offset: item.offset,
                                                recordID: item.id
                                            )
                                        )
                                    } label: {
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
        .background(palette.background.ignoresSafeArea())
        .navigationTitle("Мои записи")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                ReaderBackButton()
            }
        }
        .sheet(item: $selectedNote) { target in
            AnnotationDetailsSheet(store: store, annotationID: target.id)
        }
        .onChange(of: workFilter) { _, _ in
            volumeFilter = "all"
            chapterFilter = "all"
        }
        .onChange(of: volumeFilter) { _, _ in
            chapterFilter = "all"
        }
        .toolbarBackground(palette.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private var noteFilters: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Picker("Категория", selection: $categoryFilter) {
                    Text("Все категории").tag("all")
                    ForEach(AnnotationCategory.allCases) { item in
                        Text(item.label).tag(item.rawValue)
                    }
                }
                Picker("Статус", selection: $statusFilter) {
                    Text("Любой статус").tag("all")
                    Text("Требует проверки").tag("review")
                    Text("Обычные").tag("normal")
                }
            }
            HStack(spacing: 8) {
                Picker("Произведение", selection: $workFilter) {
                    Text("Все произведения").tag("all")
                    ForEach(store.snapshot.works, id: \.self) { work in
                        Text(work).tag(work)
                    }
                }
                Picker("Том", selection: $volumeFilter) {
                    Text("Все тома").tag("all")
                    ForEach(relevantVolumes, id: \.self) { volume in
                        Text(volume).tag(volume)
                    }
                }
            }
            Picker("Глава", selection: $chapterFilter) {
                Text("Все главы").tag("all")
                ForEach(relevantChapters) { chapter in
                    Text(chapter.displayTitle).tag(chapter.id)
                }
            }
        }
        .font(.system(size: 12))
        .tint(palette.accent)
        .padding(10)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 14))
    }

    private func noteRow(_ item: ReaderAnnotation) -> some View {
        VStack(spacing: 8) {
            Button {
                selectedNote = AnnotationSheetTarget(id: item.id)
            } label: {
                annotationCard(item, chapter: store.chapter(for: item.bookId))
            }
            .buttonStyle(.plain)

            if let chapter = store.chapter(for: item.bookId) {
                NavigationLink {
                    ReaderView(
                        store: store,
                        chapter: chapter,
                        jump: ReaderJump(
                            bookID: chapter.id,
                            paragraph: item.paragraph,
                            offset: item.start,
                            recordID: item.id
                        )
                    )
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.turn.down.right")
                        Text(item.status == "needs_review"
                            ? "Открыть главу для новой привязки"
                            : "Перейти к выделенному тексту")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.accent)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
            }
        }
    }

    private func annotationCard(_ item: ReaderAnnotation, chapter: LibraryChapter?) -> some View {
        ReaderSurface {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(displayColor(item))
                        .frame(width: 6, height: 6)
                    Text(item.categoryTitle.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(displayColor(item))
                    Spacer(minLength: 0)
                    if item.status == "needs_review" {
                        Label("Требует проверки", systemImage: "exclamationmark.triangle")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.orange)
                    }
                    if chapter == nil {
                        Label("Нет главы", systemImage: "archivebox")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.orange)
                    } else {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.secondary)
                    }
                }

                Text(chapter?.displayTitle ?? "Глава отсутствует в библиотеке")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if !item.quote.isEmpty {
                    HStack(alignment: .top, spacing: 9) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(displayColor(item).opacity(0.65))
                            .frame(width: 3)
                        Text(item.quote)
                            .font(.system(size: 14, design: .serif))
                            .foregroundStyle(palette.secondary)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }

                if !item.note.isEmpty {
                    Text(item.note)
                        .font(.system(size: 13))
                        .foregroundStyle(palette.text.opacity(0.88))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Text("Абзац \(item.paragraph + 1)")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.secondary.opacity(0.8))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func bookmarkCard(_ item: ReaderBookmark, chapter: LibraryChapter?) -> some View {
        ReaderSurface {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: "bookmark.fill")
                    .foregroundStyle(palette.accent)
                    .font(.system(size: 18))
                    .frame(width: 27)

                VStack(alignment: .leading, spacing: 7) {
                    if item.needsReview {
                        Label("Требует проверки", systemImage: "exclamationmark.triangle")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.orange)
                    }
                    Text(item.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(chapter?.displayTitle ?? "Глава отсутствует в библиотеке")
                        .font(.system(size: 12))
                        .foregroundStyle(chapter == nil ? .orange : palette.secondary)
                        .lineLimit(2)
                    if !item.quote.isEmpty {
                        Text(item.quote)
                            .font(.system(size: 13, design: .serif))
                            .foregroundStyle(palette.secondary)
                            .lineLimit(2)
                    }
                    if !item.note.isEmpty {
                        Text(item.note)
                            .font(.system(size: 12))
                            .foregroundStyle(palette.text)
                            .lineLimit(2)
                    }
                    Text("Абзац \(item.paragraph + 1)")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.secondary)
                }

                Spacer(minLength: 0)
                if chapter != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.secondary)
                }
            }
        }
    }

    private func emptyRecords(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "text.book.closed")
                .font(.system(size: 28, weight: .ultraLight))
                .foregroundStyle(palette.secondary)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(palette.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(38)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 18))
    }

    private func displayColor(_ annotation: ReaderAnnotation) -> Color {
        switch annotation.color {
        case "gold": return .yellow
        case "coral": return .red
        case "blue": return .blue
        case "mint": return .mint
        case "purple": return .purple
        default: return categoryColor(annotation.categoryTitle)
        }
    }

    private func categoryColor(_ category: String) -> Color {
        switch category {
        case "Канон": return .orange
        case "Сюжет": return .red
        case "Стиль": return .blue
        case "Цитата": return .green
        default: return palette.accent
        }
    }
}


private struct AnnotationSheetTarget: Identifiable {
    let id: String
}
