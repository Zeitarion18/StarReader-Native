import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @ObservedObject var store: LibraryStore

    @State private var isImporterPresented = false
    @State private var isRecordsPresented = false
    @State private var isConfirmationPresented = false
    @State private var isSuccessPresented = false
    @State private var isImporting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    introduction

                    if store.snapshot.chapters.isEmpty {
                        emptyLibrary
                    } else {
                        if let latest = store.mostRecentChapter {
                            continueReading(latest)
                        }
                        worksSection
                    }

                    notesShortcut

                    HStack(spacing: 7) {
                        Image(systemName: "lock.shield")
                        Text("Только на твоём iPhone · Без подписки")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ReaderTheme.secondary.opacity(0.8))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                }
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .background {
                ReaderTheme.background
                    .overlay(alignment: .top) {
                        LinearGradient(
                            colors: [ReaderTheme.accent.opacity(0.065), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 330)
                    }
                    .ignoresSafeArea()
            }
            .navigationTitle("StarReader")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isRecordsPresented = true
                    } label: {
                        Image(systemName: "text.book.closed")
                    }
                    .accessibilityLabel("Заметки и закладки")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isImporterPresented = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .accessibilityLabel("Импортировать резервную копию")
                }
            }
            .toolbarBackground(ReaderTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationDestination(for: String.self) { work in
                WorkDetailView(store: store, work: work)
            }
            .navigationDestination(for: LibraryVolume.self) { volume in
                VolumeDetailView(store: store, volume: volume)
            }
            .navigationDestination(for: LibraryChapter.self) { chapter in
                ReaderView(store: store, chapter: chapter)
            }
            .navigationDestination(isPresented: $isRecordsPresented) {
                NotesAndBookmarksView(store: store)
            }
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [.zip],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first, !isImporting else { return }
                    isImporting = true
                    Task {
                        let access = url.startAccessingSecurityScopedResource()
                        defer {
                            if access { url.stopAccessingSecurityScopedResource() }
                            isImporting = false
                        }
                        do {
                            try await store.stageImport(from: url)
                            isConfirmationPresented = true
                        } catch {
                            store.statusMessage = error.localizedDescription
                        }
                    }
                case .failure(let error):
                    store.statusMessage = error.localizedDescription
                }
            }
            .confirmationDialog(
                "Восстановить библиотеку?",
                isPresented: $isConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("Импортировать") {
                    do {
                        try store.commitPendingImport()
                        isSuccessPresented = true
                    } catch {
                        store.statusMessage = error.localizedDescription
                    }
                }
                Button("Отмена", role: .cancel) {
                    store.cancelPendingImport()
                }
            } message: {
                if let summary = store.pendingSummary {
                    Text("\(summary.workCount) произведений · \(summary.volumeCount) томов · \(summary.chapterCount) глав · \(summary.noteCount) замечаний · \(summary.bookmarkCount) закладок · \(summary.originalCount) DOCX. Несвязанные записи (\(summary.unlinkedNoteCount) замечаний и \(summary.unlinkedBookmarkCount) закладок) тоже будут сохранены. Старые данные останутся в резервной копии.")
                } else {
                    Text("Библиотека будет восстановлена из выбранного ZIP.")
                }
            }
            .alert("Импорт завершён", isPresented: $isSuccessPresented) {
                Button("Отлично", role: .cancel) {}
            } message: {
                Text("Библиотека восстановлена локально. Проверь произведения, заметки, закладки и прогресс чтения.")
            }
            .alert("StarReader", isPresented: Binding(
                get: { store.statusMessage != nil },
                set: { if !$0 { store.statusMessage = nil } }
            )) {
                Button("Понятно", role: .cancel) { store.statusMessage = nil }
            } message: {
                Text(store.statusMessage ?? "")
            }
        }
        .tint(ReaderTheme.accent)
        .preferredColorScheme(.dark)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ЛИЧНАЯ КОЛЛЕКЦИЯ")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(2.4)
                .foregroundStyle(ReaderTheme.accent)

            Text("Библиотека")
                .font(.system(size: 31, weight: .bold, design: .rounded))
                .foregroundStyle(ReaderTheme.text)

            Text("\(store.snapshot.works.count) произведений · \(store.snapshot.chapters.count) глав")
                .font(.system(size: 13))
                .foregroundStyle(ReaderTheme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func continueReading(_ chapter: LibraryChapter) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("Продолжить чтение", count: nil)

            NavigationLink(value: chapter) {
                HStack(alignment: .center, spacing: 15) {
                    BookCover(
                        title: chapter.series,
                        index: store.snapshot.works.firstIndex(of: chapter.series) ?? 0
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Text(chapter.series)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(ReaderTheme.secondary)
                            .lineLimit(2)

                        Text(chapter.displayTitle)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(ReaderTheme.text)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)

                        Spacer(minLength: 0)

                        HStack {
                            Text("Продолжить")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(ReaderTheme.accent)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(ReaderTheme.accent)
                            Spacer()
                            Text("\(Int(store.progress(for: chapter.id).percent.rounded()))%")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(ReaderTheme.text)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 119)

                }
                .padding(15)
                .background(ReaderTheme.surfaceHigh, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 19)
                        .strokeBorder(ReaderTheme.accent.opacity(0.19), lineWidth: 1)
                }
                .overlay(alignment: .bottom) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.08))
                            Capsule()
                                .fill(ReaderTheme.accent)
                                .frame(
                                    width: geometry.size.width * CGFloat(
                                        min(max(store.progress(for: chapter.id).percent, 0), 100) / 100
                                    )
                                )
                        }
                    }
                    .frame(height: 3)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 1)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var worksSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionHeading("Произведения", count: store.snapshot.works.count)

            ForEach(Array(store.snapshot.works.enumerated()), id: \.element) { index, work in
                NavigationLink(value: work) {
                    HStack(alignment: .center, spacing: 14) {
                        BookCover(title: work, index: index, compact: true)

                        VStack(alignment: .leading, spacing: 9) {
                            Text(work)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(ReaderTheme.text)
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)

                            let chapters = store.snapshot.chapters.filter { $0.series == work }.count
                            Text("\(store.volumes(for: work).count) томов · \(chapters) глав")
                                .font(.system(size: 12))
                                .foregroundStyle(ReaderTheme.secondary)
                        }
                        Spacer(minLength: 2)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ReaderTheme.secondary.opacity(0.7))
                    }
                    .padding(13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ReaderTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(ReaderTheme.hairline, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var notesShortcut: some View {
        Button {
            isRecordsPresented = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "bookmark.square")
                    .font(.system(size: 20))
                    .foregroundStyle(ReaderTheme.accent)
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Заметки и закладки")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ReaderTheme.text)
                    Text("\(store.annotations.count) замечаний · \(store.bookmarks.count) закладок")
                        .font(.system(size: 12))
                        .foregroundStyle(ReaderTheme.secondary)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ReaderTheme.secondary)
            }
            .padding(16)
            .background(ReaderTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var emptyLibrary: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical")
                .font(.system(size: 42, weight: .ultraLight))
                .foregroundStyle(ReaderTheme.accent)
                .frame(height: 58)
            Text("Твои истории начнутся здесь")
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(ReaderTheme.text)
                .multilineTextAlignment(.center)
            Text("Перенеси библиотеку из резервного ZIP. Тексты, позиции чтения и заметки останутся с тобой.")
                .font(.system(size: 13))
                .foregroundStyle(ReaderTheme.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                isImporterPresented = true
            } label: {
                Label(isImporting ? "Проверяем ZIP…" : "Импортировать ZIP", systemImage: "square.and.arrow.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ReaderTheme.background)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(ReaderTheme.accent, in: RoundedRectangle(cornerRadius: 13))
            }
            .disabled(isImporting)
            .padding(.top, 5)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(ReaderTheme.surface, in: RoundedRectangle(cornerRadius: 21))
    }

    private func sectionHeading(_ title: String, count: Int?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(ReaderTheme.text)
            Spacer(minLength: 6)
            if let count {
                Text("\(count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ReaderTheme.secondary)
            }
        }
    }
}

private struct WorkDetailView: View {
    @ObservedObject var store: LibraryStore
    let work: String
    @State private var volumeToDelete: LibraryVolume?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .center, spacing: 17) {
                    BookCover(title: work, index: store.snapshot.works.firstIndex(of: work) ?? 0)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ПРОИЗВЕДЕНИЕ")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.5)
                            .foregroundStyle(ReaderTheme.accent)
                        Text(work)
                            .font(.system(size: 20, weight: .bold, design: .serif))
                            .foregroundStyle(ReaderTheme.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Тома")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(ReaderTheme.text)

                    let volumes = store.volumes(for: work)
                    if volumes.isEmpty {
                        missingSection("Тома пока не добавлены")
                    } else {
                        ForEach(Array(volumes.enumerated()), id: \.element.id) { index, volume in
                            HStack(spacing: 8) {
                                NavigationLink(value: volume) {
                                    HStack(spacing: 13) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 13)
                                                .fill(ReaderTheme.accent.opacity(0.10))
                                                .frame(width: 49, height: 53)
                                            Image(systemName: "books.vertical")
                                                .font(.system(size: 20))
                                                .foregroundStyle(ReaderTheme.accent)
                                        }
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(volume.title)
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundStyle(ReaderTheme.text)
                                            Text("\(store.chapters(for: work, volume: volume.title).count) глав")
                                                .font(.system(size: 12))
                                                .foregroundStyle(ReaderTheme.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(ReaderTheme.secondary)
                                    }
                                    .padding(13)
                                    .background(
                                        ReaderTheme.surface,
                                        in: RoundedRectangle(cornerRadius: 17)
                                    )
                                }
                                .buttonStyle(.plain)
                                Menu {
                                    Button(role: .destructive) {
                                        volumeToDelete = volume
                                    } label: {
                                        Label("Удалить том", systemImage: "trash")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(ReaderTheme.secondary)
                                        .frame(width: 42, height: 53)
                                        .background(
                                            ReaderTheme.surface,
                                            in: RoundedRectangle(cornerRadius: 14)
                                        )
                                }
                                .accessibilityLabel("Действия с томом \(volume.title)")
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
            .padding(20)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .background(ReaderTheme.background.ignoresSafeArea())
        .navigationTitle("Произведение")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                ReaderBackButton()
            }
        }
        .toolbarBackground(ReaderTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .alert(
            "Удалить том?",
            isPresented: Binding(
                get: { volumeToDelete != nil },
                set: { if !$0 { volumeToDelete = nil } }
            )
        ) {
            Button("Удалить том", role: .destructive) {
                if let volume = volumeToDelete {
                    do { try store.deleteVolume(volume) }
                    catch { store.statusMessage = error.localizedDescription }
                }
                volumeToDelete = nil
            }
            Button("Отмена", role: .cancel) { volumeToDelete = nil }
        } message: {
            Text("«\(volumeToDelete?.title ?? "")» и все главы тома исчезнут из библиотеки вместе со связанными заметками, закладками и прогрессом. Перед удалением StarReader создаст резервную копию.")
        }
        .alert(
            "StarReader",
            isPresented: Binding(
                get: { store.statusMessage != nil },
                set: { if !$0 { store.statusMessage = nil } }
            )
        ) {
            Button("Понятно", role: .cancel) { store.statusMessage = nil }
        } message: {
            Text(store.statusMessage ?? "")
        }
    }

    private func missingSection(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 14))
            .foregroundStyle(ReaderTheme.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(30)
            .background(ReaderTheme.surface, in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct VolumeDetailView: View {
    @ObservedObject var store: LibraryStore
    let volume: LibraryVolume
    @State private var chapterToDelete: LibraryChapter?

    private var chapters: [LibraryChapter] {
        store.chapters(for: volume.series, volume: volume.title)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(volume.series)
                        .font(.system(size: 12))
                        .foregroundStyle(ReaderTheme.secondary)
                        .lineLimit(2)
                    Text(volume.title)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(ReaderTheme.text)
                    Text("\(chapters.count) глав")
                        .font(.system(size: 13))
                        .foregroundStyle(ReaderTheme.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if chapters.isEmpty {
                    ReaderSurface {
                        Text("Здесь пока нет глав.")
                            .foregroundStyle(ReaderTheme.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    }
                } else {
                    ForEach(Array(chapters.enumerated()), id: \.element.id) { index, chapter in
                        let duplicateNumber = chapters.prefix(index + 1)
                            .filter { $0.displayTitle == chapter.displayTitle }.count
                        let duplicates = chapters.filter { $0.displayTitle == chapter.displayTitle }.count

                        HStack(spacing: 8) {
                            NavigationLink(value: chapter) {
                                HStack(alignment: .center, spacing: 13) {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(ReaderTheme.accent.opacity(0.10))
                                        .frame(width: 42, height: 48)
                                        .overlay {
                                            Text("\(index + 1)")
                                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                                .foregroundStyle(ReaderTheme.accent)
                                        }

                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(chapter.displayTitle)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(ReaderTheme.text)
                                            .fixedSize(horizontal: false, vertical: true)
                                        HStack(spacing: 6) {
                                            if duplicates > 1 {
                                                Text("Вариант \(duplicateNumber)")
                                                Text("·")
                                            }
                                            Text("\(chapter.paragraphs.count) абз.")
                                            Text("·")
                                            Text("\(Int(store.progress(for: chapter.id).percent.rounded()))%")
                                        }
                                        .font(.system(size: 12))
                                        .foregroundStyle(ReaderTheme.secondary)
                                    }
                                    Spacer(minLength: 1)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(ReaderTheme.secondary)
                                }
                                .padding(13)
                                .background(
                                    ReaderTheme.surface,
                                    in: RoundedRectangle(cornerRadius: 17)
                                )
                            }
                            .buttonStyle(.plain)
                            Menu {
                                Button(role: .destructive) {
                                    chapterToDelete = chapter
                                } label: {
                                    Label("Удалить главу", systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(ReaderTheme.secondary)
                                    .frame(width: 42, height: 53)
                                    .background(
                                        ReaderTheme.surface,
                                        in: RoundedRectangle(cornerRadius: 14)
                                    )
                            }
                            .accessibilityLabel("Действия с главой \(chapter.displayTitle)")
                        }
                    }
                }
            }
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
            .padding(20)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .background(ReaderTheme.background.ignoresSafeArea())
        .navigationTitle(volume.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                ReaderBackButton()
            }
        }
        .toolbarBackground(ReaderTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .alert(
            "Удалить главу?",
            isPresented: Binding(
                get: { chapterToDelete != nil },
                set: { if !$0 { chapterToDelete = nil } }
            )
        ) {
            Button("Удалить главу", role: .destructive) {
                if let chapter = chapterToDelete {
                    do { try store.deleteChapter(chapter) }
                    catch { store.statusMessage = error.localizedDescription }
                }
                chapterToDelete = nil
            }
            Button("Отмена", role: .cancel) { chapterToDelete = nil }
        } message: {
            Text("«\(chapterToDelete?.displayTitle ?? "")» будет удалена из библиотеки вместе с её заметками, закладками и прогрессом. Другие главы с таким же названием останутся. Предварительно сохранится резервная копия.")
        }
        .alert(
            "StarReader",
            isPresented: Binding(
                get: { store.statusMessage != nil },
                set: { if !$0 { store.statusMessage = nil } }
            )
        ) {
            Button("Понятно", role: .cancel) { store.statusMessage = nil }
        } message: {
            Text(store.statusMessage ?? "")
        }
    }
}
