import SwiftUI
import UniformTypeIdentifiers

private enum StarStyle {
    static let background = Color(red: 0.027, green: 0.037, blue: 0.075)
    static let surface = Color(red: 0.075, green: 0.094, blue: 0.145)
    static let surfaceRaised = Color(red: 0.100, green: 0.125, blue: 0.185)
    static let accent = Color(red: 0.30, green: 0.82, blue: 0.91)
    static let muted = Color(red: 0.60, green: 0.66, blue: 0.76)
    static let outline = Color.white.opacity(0.065)
}

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
                VStack(alignment: .leading, spacing: 22) {
                    topBanner

                    if store.snapshot.works.isEmpty {
                        emptyLibrary
                    } else {
                        libraryContent
                    }

                    bottomActions
                }
                .frame(maxWidth: 650)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 35)
            }
            .scrollIndicators(.hidden)
            .background {
                StarStyle.background
                    .overlay(alignment: .top) {
                        LinearGradient(
                            colors: [Color.cyan.opacity(0.075), .clear],
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
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .accessibilityLabel("Замечания и закладки")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isImporterPresented = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .accessibilityLabel("Импортировать библиотеку")
                }
            }
            .toolbarBackground(StarStyle.background, for: .navigationBar)
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
                        let hasAccess = url.startAccessingSecurityScopedResource()
                        defer {
                            if hasAccess { url.stopAccessingSecurityScopedResource() }
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
                "Подтвердить перенос библиотеки",
                isPresented: $isConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("Импортировать библиотеку") {
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
                    Text("Будут импортированы: \(summary.workCount) произведений, \(summary.volumeCount) томов, \(summary.chapterCount) глав, \(summary.noteCount) замечаний, \(summary.bookmarkCount) закладок и \(summary.originalCount) оригинальных DOCX. Записи из отсутствующих глав: \(summary.unlinkedNoteCount) замечаний и \(summary.unlinkedBookmarkCount) закладок — они также сохранятся. Исходный ZIP будет сохранён как резервная копия.")
                } else {
                    Text("Будет восстановлена библиотека из ZIP.")
                }
            }
            .alert("Библиотека восстановлена", isPresented: $isSuccessPresented) {
                Button("Открыть", role: .cancel) {}
            } message: {
                Text("Проверь количество глав, замечаний и закладок. Копию исходного ZIP сохрани в приложении «Файлы».")
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
        .tint(StarStyle.accent)
        .preferredColorScheme(.dark)
    }

    private var topBanner: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(StarStyle.surfaceRaised)
                    .frame(width: 58, height: 58)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(StarStyle.outline, lineWidth: 1)
                    }
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 25, weight: .light))
                    .foregroundStyle(StarStyle.accent)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Твоя личная библиотека")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Чтение, которое всегда с тобой")
                    .font(.system(size: 12))
                    .foregroundStyle(StarStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyLibrary: some View {
        VStack(spacing: 19) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [StarStyle.accent.opacity(0.22), StarStyle.accent.opacity(0.04)],
                            center: .center,
                            startRadius: 5,
                            endRadius: 90
                        )
                    )
                    .frame(width: 138, height: 138)
                Circle()
                    .strokeBorder(StarStyle.accent.opacity(0.17), lineWidth: 1)
                    .frame(width: 112, height: 112)
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 48, weight: .ultraLight))
                    .foregroundStyle(StarStyle.accent)
                    .shadow(color: StarStyle.accent.opacity(0.4), radius: 16)
            }

            VStack(spacing: 8) {
                Text("Здесь начнётся история")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Перенеси произведения из старой читалки. Главы, заметки и закладки останутся с тобой.")
                    .font(.system(size: 14))
                    .foregroundStyle(StarStyle.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            importButton

            Label("Локально и без подписки", systemImage: "lock.shield")
                .font(.system(size: 12))
                .foregroundStyle(StarStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 29)
        .background(StarStyle.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(StarStyle.outline, lineWidth: 1)
        }
    }

    private var importButton: some View {
        Button {
            isImporterPresented = true
        } label: {
            HStack(spacing: 10) {
                if isImporting {
                    ProgressView().tint(StarStyle.background)
                } else {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 18, weight: .semibold))
                }
                Text(isImporting ? "Проверяем ZIP…" : "Импортировать библиотеку")
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(StarStyle.background)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 12)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.42, green: 0.91, blue: 0.96), StarStyle.accent],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(isImporting)
        .accessibilityLabel("Импортировать библиотеку из ZIP")
    }

    private var libraryContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Мои произведения")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                Text("\(store.snapshot.works.count)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(StarStyle.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(StarStyle.accent.opacity(0.10), in: Capsule())
            }

            ForEach(store.snapshot.works, id: \.self) { work in
                NavigationLink(value: work) {
                    HStack(spacing: 14) {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(StarStyle.accent.opacity(0.14))
                            .frame(width: 52, height: 65)
                            .overlay {
                                Image(systemName: "book.closed.fill")
                                    .font(.system(size: 22, weight: .light))
                                    .foregroundStyle(StarStyle.accent)
                            }
                        VStack(alignment: .leading, spacing: 5) {
                            Text(work)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(store.volumes(for: work).count) томов · \(store.snapshot.chapters.filter { $0.series == work }.count) глав")
                                .font(.system(size: 12))
                                .foregroundStyle(StarStyle.muted)
                        }
                        Spacer(minLength: 3)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(StarStyle.muted)
                    }
                    .padding(14)
                    .background(StarStyle.surface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 17).strokeBorder(StarStyle.outline, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var bottomActions: some View {
        VStack(spacing: 11) {
            if !store.snapshot.works.isEmpty {
                importButton
            }

            Button {
                isRecordsPresented = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "text.book.closed")
                        .foregroundStyle(StarStyle.accent)
                    Text("Замечания и закладки")
                        .foregroundStyle(.white.opacity(0.90))
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text("\(store.annotations.count + store.bookmarks.count)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(StarStyle.muted)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(StarStyle.muted)
                }
                .padding(16)
                .background(StarStyle.surface, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)

            Text("StarReader Native · Preview 0.3.1")
                .font(.system(size: 11))
                .foregroundStyle(StarStyle.muted.opacity(0.6))
                .padding(.top, 6)
        }
    }
}

private struct WorkDetailView: View {
    @ObservedObject var store: LibraryStore
    let work: String

    var body: some View {
        List {
            let volumes = store.volumes(for: work)
            if volumes.isEmpty {
                ContentUnavailableView("Томов пока нет", systemImage: "books.vertical")
            } else {
                ForEach(volumes) { volume in
                    NavigationLink(value: volume) {
                        HStack(spacing: 11) {
                            Image(systemName: "books.vertical.fill")
                                .foregroundStyle(StarStyle.accent)
                            Text(volume.title)
                                .font(.system(size: 16, weight: .medium))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 9)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(StarStyle.background)
        .navigationTitle(work)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct VolumeDetailView: View {
    @ObservedObject var store: LibraryStore
    let volume: LibraryVolume

    var body: some View {
        List {
            let chapters = store.chapters(for: volume.series, volume: volume.title)
            if chapters.isEmpty {
                ContentUnavailableView("В этом томе пока нет глав", systemImage: "text.book.closed")
            } else {
                ForEach(chapters) { chapter in
                    NavigationLink(value: chapter) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(chapter.displayTitle)
                                .font(.system(size: 15, weight: .medium))
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 9) {
                                Text("\(chapter.paragraphs.count) абзацев")
                                Text("·")
                                Text(store.progress(for: chapter.id).percent.formatted(.number.precision(.fractionLength(0))) + "%")
                            }
                            .font(.system(size: 12))
                            .foregroundStyle(StarStyle.muted)
                        }
                        .padding(.vertical, 7)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(StarStyle.background)
        .navigationTitle(volume.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
