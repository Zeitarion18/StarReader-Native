import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct LibraryView: View {
    @Environment(\.readerPalette) private var palette
    @ObservedObject var store: LibraryStore
    @StateObject private var pageCounter = ReaderPageCounter()
    @AppStorage("starreader.fontSize") private var fontSize: Double = 17
    @AppStorage("starreader.lineSpacing") private var lineSpacing: Double = 4
    @AppStorage("starreader.paragraphSpacing") private var paragraphSpacing: Double = 13
    @AppStorage("starreader.lastPageContentWidth") private var measuredContentWidth: Double = 0
    @AppStorage("starreader.lastPageHeight") private var measuredPageHeight: Double = 0

    @State private var isExporting = false
    @State private var backupToShare: StarReaderBackupFile?
    @State private var isImporterPresented = false
    @State private var isDocxPickerPresented = false
    @State private var isReadingDocx = false
    @State private var pendingDocx: ImportedDocxChapter?
    @State private var isVolumePickerPresented = false
    @State private var isReadingVolumeDocx = false
    @State private var pendingVolumeDocx: ImportedDocxChapter?
    @State private var isRecordsPresented = false
    @State private var isStatisticsPresented = false
    @State private var isConfirmationPresented = false
    @State private var isSuccessPresented = false
    @State private var isImporting = false

    var body: some View {
        NavigationStack {
            confirmationNavigation
        }
        .tint(palette.accent)
        .preferredColorScheme(palette.colorScheme)
    }

    private var libraryScroll: some View {
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

                    volumeImportShortcut
                    notesShortcut
                    statisticsShortcut
                    backupShortcut

                    HStack(spacing: 7) {
                        Image(systemName: "lock.shield")
                        Text("Только на твоём iPhone · Без подписки")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.secondary.opacity(0.8))
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
                palette.background
                    .overlay(alignment: .top) {
                        LinearGradient(
                            colors: [palette.accent.opacity(0.065), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 330)
                    }
                    .ignoresSafeArea()
            }
    }

    private var baseNavigation: some View {
        libraryScroll
            .navigationTitle("StarReader")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        isRecordsPresented = true
                    } label: {
                        Image(systemName: "text.book.closed")
                    }
                    .accessibilityLabel("Заметки и закладки")

                    Button {
                        isStatisticsPresented = true
                    } label: {
                        Image(systemName: "chart.bar.xaxis")
                    }
                    .accessibilityLabel("Статистика чтения")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        exportBackup()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(isExporting)
                    .accessibilityLabel("Экспортировать резервную копию ZIP")

                    Button {
                        isVolumePickerPresented = true
                    } label: {
                        Image(systemName: "books.vertical.fill")
                    }
                    .disabled(isReadingVolumeDocx || isReadingDocx)
                    .accessibilityLabel("Импортировать целый том DOCX")

                    Button {
                        isDocxPickerPresented = true
                    } label: {
                        Image(systemName: "doc.badge.plus")
                    }
                    .disabled(isReadingDocx || isReadingVolumeDocx)
                    .accessibilityLabel("Добавить главу из DOCX")

                    Button {
                        isImporterPresented = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .accessibilityLabel("Импортировать резервную копию ZIP")
                }
            }
            .toolbarBackground(palette.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationDestination(for: String.self) { work in
                WorkDetailView(store: store, pageCounter: pageCounter, approximate: measuredContentWidth <= 0 || measuredPageHeight <= 0, work: work)
            }
            .navigationDestination(for: LibraryVolume.self) { volume in
                VolumeDetailView(store: store, pageCounter: pageCounter, approximate: measuredContentWidth <= 0 || measuredPageHeight <= 0, volume: volume)
            }
            .navigationDestination(for: LibraryChapter.self) { chapter in
                ReaderView(store: store, chapter: chapter)
            }
            .navigationDestination(isPresented: $isRecordsPresented) {
                NotesAndBookmarksView(store: store)
            }
            .navigationDestination(isPresented: $isStatisticsPresented) {
                ReadingStatisticsView(store: store)
            }
    }

    private var observedNavigation: some View {
        baseNavigation
            .onAppear { refreshPageTotals() }
            .onChange(of: store.snapshot.chapters) { _, _ in refreshPageTotals() }
            .onChange(of: fontSize) { _, _ in refreshPageTotals() }
            .onChange(of: lineSpacing) { _, _ in refreshPageTotals() }
            .onChange(of: paragraphSpacing) { _, _ in refreshPageTotals() }
            .onChange(of: measuredContentWidth) { _, _ in refreshPageTotals() }
            .onChange(of: measuredPageHeight) { _, _ in refreshPageTotals() }
            .sheet(item: $backupToShare) { file in
                StarReaderBackupShareSheet(url: file.url)
            }
    }

    private var zipImportNavigation: some View {
        observedNavigation
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
    }

    private var docxImportNavigation: some View {
        zipImportNavigation
            .fileImporter(
                isPresented: $isDocxPickerPresented,
                allowedContentTypes: [
                    UTType(filenameExtension: "docx")
                        ?? UTType(importedAs: "org.openxmlformats.wordprocessingml.document")
                ],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first, !isReadingDocx else { return }
                    isReadingDocx = true
                    Task {
                        let accessed = url.startAccessingSecurityScopedResource()
                        defer {
                            if accessed { url.stopAccessingSecurityScopedResource() }
                            isReadingDocx = false
                        }
                        do {
                            let imported = try await Task.detached(
                                priority: .userInitiated
                            ) {
                                try SingleDocxImporter.read(from: url)
                            }.value
                            pendingDocx = imported
                        } catch {
                            store.statusMessage = error.localizedDescription
                        }
                    }
                case .failure(let error):
                    store.statusMessage = error.localizedDescription
                }
            }
            .sheet(item: $pendingDocx) { document in
                DocxChapterImportSheet(store: store, document: document) { chapter in
                    pendingDocx = nil
                    store.statusMessage = "Глава «\(chapter.displayTitle)» добавлена в том «\(chapter.volume)»."
                }
            }
    }

    private var volumeImportNavigation: some View {
        docxImportNavigation
            .fileImporter(
                isPresented: $isVolumePickerPresented,
                allowedContentTypes: [
                    UTType(filenameExtension: "docx")
                        ?? UTType(importedAs: "org.openxmlformats.wordprocessingml.document")
                ],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first,
                          !isReadingVolumeDocx, !isReadingDocx else { return }
                    isReadingVolumeDocx = true
                    Task {
                        let access = url.startAccessingSecurityScopedResource()
                        defer {
                            if access { url.stopAccessingSecurityScopedResource() }
                            isReadingVolumeDocx = false
                        }
                        do {
                            let parsed = try await Task.detached(
                                priority: .userInitiated
                            ) {
                                try SingleDocxImporter.read(from: url)
                            }.value
                            pendingVolumeDocx = parsed
                        } catch {
                            store.statusMessage = error.localizedDescription
                        }
                    }
                case .failure(let error):
                    store.statusMessage = error.localizedDescription
                }
            }
            .sheet(item: $pendingVolumeDocx) { document in
                VolumeDocxImportSheet(store: store, document: document) { count, tome in
                    pendingVolumeDocx = nil
                    store.statusMessage = "Импортировано \(count) разделов в «\(tome)»."
                }
            }
    }

    private var confirmationNavigation: some View {
        volumeImportNavigation
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

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ЛИЧНАЯ КОЛЛЕКЦИЯ")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(2.4)
                .foregroundStyle(palette.accent)

            Text("Библиотека")
                .font(.system(size: 31, weight: .bold, design: .rounded))
                .foregroundStyle(palette.text)

            Text("\(store.snapshot.works.count) произведений · \(store.snapshot.chapters.count) глав")
                .font(.system(size: 13))
                .foregroundStyle(palette.secondary)
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
                            .foregroundStyle(palette.secondary)
                            .lineLimit(2)

                        Text(chapter.displayTitle)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(palette.text)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)

                        Spacer(minLength: 0)

                        HStack {
                            Text("Продолжить")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(palette.accent)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(palette.accent)
                            Spacer()
                            Text("\(Int(store.progress(for: chapter.id).percent.rounded()))%")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(palette.text)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 119)

                }
                .padding(15)
                .background(palette.surfaceHigh, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 19)
                        .strokeBorder(palette.accent.opacity(0.19), lineWidth: 1)
                }
                .overlay(alignment: .bottom) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.08))
                            Capsule()
                                .fill(palette.accent)
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
                                .foregroundStyle(palette.text)
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)

                            let workChapters = store.snapshot.chapters.filter { $0.series == work }
                            Text("\(store.volumes(for: work).count) томов · \(workChapters.count) глав")
                                .font(.system(size: 12))
                                .foregroundStyle(palette.secondary)
                            Text(pageCounter.totalText(
                                for: workChapters,
                                approximate: measuredContentWidth <= 0 || measuredPageHeight <= 0
                            ))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(palette.accent)
                                .font(.system(size: 12))
                                .foregroundStyle(palette.secondary)
                        }
                        Spacer(minLength: 2)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.secondary.opacity(0.7))
                    }
                    .padding(13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(palette.hairline, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var volumeImportShortcut: some View {
        Button {
            isVolumePickerPresented = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(palette.accent)
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text(isReadingVolumeDocx ? "Читаем Word…" : "Импортировать целый том")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.text)
                    Text("Разделить DOCX на главы, пролог и эпилог")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.secondary)
                }
                Spacer(minLength: 5)
                if isReadingVolumeDocx {
                    ProgressView().tint(palette.accent)
                } else {
                    Image(systemName: "square.and.arrow.down")
                        .foregroundStyle(palette.secondary)
                }
            }
            .padding(16)
            .background(
                palette.surface, in: RoundedRectangle(cornerRadius: 18)
            )
        }
        .buttonStyle(.plain)
        .disabled(isReadingVolumeDocx || isReadingDocx)
    }

    private var backupShortcut: some View {
        Button {
            exportBackup()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "externaldrive.badge.timemachine")
                    .font(.system(size: 20))
                    .foregroundStyle(palette.accent)
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text(isExporting ? "Создаём ZIP…" : "Резервная копия библиотеки")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.text)
                    Text("Экспорт глав, записей, прогресса и статистики")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.secondary)
                }
                Spacer(minLength: 4)
                if isExporting {
                    ProgressView().tint(palette.accent)
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(palette.secondary)
                }
            }
            .padding(16)
            .background(
                palette.surface,
                in: RoundedRectangle(cornerRadius: 18)
            )
        }
        .buttonStyle(.plain)
        .disabled(isExporting)
    }

    private func exportBackup() {
        guard !isExporting else { return }
        isExporting = true
        Task {
            defer { isExporting = false }
            do {
                let url = try await store.exportBackup()
                backupToShare = StarReaderBackupFile(url: url)
            } catch {
                store.statusMessage = "Резервная копия не создана: " +
                    error.localizedDescription
            }
        }
    }

    private func refreshPageTotals() {
        // Once ReaderView has been opened, use its real TextKit viewport.
        // Before that, explicitly mark the totals as approximate.
        let fallbackWidth = max(140, min(UIScreen.main.bounds.width - 44, 692))
        let fallbackHeight = max(150, UIScreen.main.bounds.height - 200)
        pageCounter.refresh(
            chapters: store.snapshot.chapters,
            annotations: store.annotations,
            contentWidth: measuredContentWidth > 0
                ? CGFloat(measuredContentWidth) : fallbackWidth,
            pageHeight: measuredPageHeight > 0
                ? CGFloat(measuredPageHeight) : fallbackHeight,
            fontSize: fontSize,
            lineSpacing: lineSpacing,
            paragraphSpacing: paragraphSpacing,
            palette: palette
        )
    }

    private var statisticsShortcut: some View {
        Button {
            isStatisticsPresented = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 20))
                    .foregroundStyle(palette.accent)
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Статистика чтения")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.text)
                    let today = Calendar.current.startOfDay(for: Date())
                    let seconds = store.readingStats.seconds(
                        from: today, through: today
                    )
                    Text("Сегодня: \(Int((seconds / 60).rounded())) мин · \(Int(store.readingStats.pages(from: today, through: today).rounded())) новых стр.")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.secondary)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.secondary)
            }
            .padding(16)
            .background(
                palette.surface,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    private var notesShortcut: some View {
        Button {
            isRecordsPresented = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "bookmark.square")
                    .font(.system(size: 20))
                    .foregroundStyle(palette.accent)
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Заметки и закладки")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.text)
                    Text("\(store.annotations.count) замечаний · \(store.bookmarks.count) закладок")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.secondary)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.secondary)
            }
            .padding(16)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var emptyLibrary: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical")
                .font(.system(size: 42, weight: .ultraLight))
                .foregroundStyle(palette.accent)
                .frame(height: 58)
            Text("Твои истории начнутся здесь")
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(palette.text)
                .multilineTextAlignment(.center)
            Text("Перенеси библиотеку из резервного ZIP. Тексты, позиции чтения и заметки останутся с тобой.")
                .font(.system(size: 13))
                .foregroundStyle(palette.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                isImporterPresented = true
            } label: {
                Label(isImporting ? "Проверяем ZIP…" : "Импортировать ZIP", systemImage: "square.and.arrow.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(palette.accent, in: RoundedRectangle(cornerRadius: 13))
            }
            .disabled(isImporting)
            .padding(.top, 5)

            Button {
                isDocxPickerPresented = true
            } label: {
                Label("Добавить главу DOCX", systemImage: "doc.badge.plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.accent)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(
                        palette.surfaceHigh,
                        in: RoundedRectangle(cornerRadius: 13)
                    )
            }
            .disabled(isReadingDocx)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 21))
    }

    private func sectionHeading(_ title: String, count: Int?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(palette.text)
            Spacer(minLength: 6)
            if let count {
                Text("\(count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.secondary)
            }
        }
    }
}

private struct WorkDetailView: View {
    @Environment(\.readerPalette) private var palette
    @ObservedObject var store: LibraryStore
    @ObservedObject var pageCounter: ReaderPageCounter
    let approximate: Bool
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
                            .foregroundStyle(palette.accent)
                        Text(work)
                            .font(.system(size: 20, weight: .bold, design: .serif))
                            .foregroundStyle(palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(pageCounter.totalText(
                            for: store.snapshot.chapters.filter { $0.series == work },
                            approximate: approximate
                        ))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(palette.accent)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Тома")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(palette.text)

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
                                                .fill(palette.accent.opacity(0.10))
                                                .frame(width: 49, height: 53)
                                            Image(systemName: "books.vertical")
                                                .font(.system(size: 20))
                                                .foregroundStyle(palette.accent)
                                        }
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(volume.title)
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundStyle(palette.text)
                                            Text("\(store.chapters(for: work, volume: volume.title).count) глав")
                                                .font(.system(size: 12))
                                                .foregroundStyle(palette.secondary)
                                            Text(pageCounter.totalText(
                                                for: store.chapters(for: work, volume: volume.title),
                                                approximate: approximate
                                            ))
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundStyle(palette.accent)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(palette.secondary)
                                    }
                                    .padding(13)
                                    .background(
                                        palette.surface,
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
                                        .foregroundStyle(palette.secondary)
                                        .frame(width: 42, height: 53)
                                        .background(
                                            palette.surface,
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
        .background(palette.background.ignoresSafeArea())
        .navigationTitle("Произведение")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                ReaderBackButton()
            }
        }
        .toolbarBackground(palette.background, for: .navigationBar)
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
            .foregroundStyle(palette.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(30)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct VolumeDetailView: View {
    @Environment(\.readerPalette) private var palette
    @ObservedObject var store: LibraryStore
    @ObservedObject var pageCounter: ReaderPageCounter
    let approximate: Bool
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
                        .foregroundStyle(palette.secondary)
                        .lineLimit(2)
                    Text(volume.title)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(palette.text)
                    Text("\(chapters.count) глав")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.secondary)
                    Text("Всего: " + pageCounter.totalText(for: chapters, approximate: approximate))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.accent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if chapters.isEmpty {
                    ReaderSurface {
                        Text("Здесь пока нет глав.")
                            .foregroundStyle(palette.secondary)
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
                                        .fill(palette.accent.opacity(0.10))
                                        .frame(width: 42, height: 48)
                                        .overlay {
                                            Text("\(index + 1)")
                                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                                .foregroundStyle(palette.accent)
                                        }

                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(chapter.displayTitle)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(palette.text)
                                            .fixedSize(horizontal: false, vertical: true)
                                        HStack(spacing: 6) {
                                            if duplicates > 1 {
                                                Text("Вариант \(duplicateNumber)")
                                                Text("·")
                                            }
                                            Text("\(chapter.paragraphs.count) абз.")
                                            Text("·")
                                            Text("\(Int(store.progress(for: chapter.id).percent.rounded()))%")
                                        Text("·")
                                        Text(pageCounter.totalText(for: [chapter], approximate: approximate))
                                        }
                                        .font(.system(size: 12))
                                        .foregroundStyle(palette.secondary)
                                    }
                                    Spacer(minLength: 1)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(palette.secondary)
                                }
                                .padding(13)
                                .background(
                                    palette.surface,
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
                                    .foregroundStyle(palette.secondary)
                                    .frame(width: 42, height: 53)
                                    .background(
                                        palette.surface,
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
        .background(palette.background.ignoresSafeArea())
        .navigationTitle(volume.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                ReaderBackButton()
            }
        }
        .toolbarBackground(palette.background, for: .navigationBar)
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


private struct StarReaderBackupFile: Identifiable {
    let id = UUID()
    let url: URL
}

private struct StarReaderBackupShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ controller: UIActivityViewController,
        context: Context
    ) {}
}
