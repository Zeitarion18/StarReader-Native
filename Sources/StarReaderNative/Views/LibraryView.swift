import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @ObservedObject var store: LibraryStore
    @State private var isImporterPresented = false
    @State private var isRecordsPresented = false
    @State private var isConfirmationPresented = false
    @State private var isSuccessPresented = false

    var body: some View {
        NavigationStack {
            Group {
                if store.snapshot.works.isEmpty {
                    emptyLibrary
                } else {
                    libraryList
                }
            }
            .background(Color(red: 0.035, green: 0.045, blue: 0.075))
            .navigationTitle("StarReader")
            .navigationBarTitleDisplayMode(.large)
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
                    .accessibilityLabel("Импорт резервной копии")
                }
            }
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
                    guard let url = urls.first else { return }
                    Task {
                        let hasAccess = url.startAccessingSecurityScopedResource()
                        defer {
                            if hasAccess { url.stopAccessingSecurityScopedResource() }
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
                "Заменить текущую библиотеку?",
                isPresented: $isConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("Импортировать и заменить", role: .destructive) {
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
                    Text("Будут импортированы: \(summary.workCount) произведений, \(summary.volumeCount) томов, \(summary.chapterCount) глав, \(summary.noteCount) замечаний, \(summary.bookmarkCount) закладок и \(summary.originalCount) оригинальных DOCX. Исходный ZIP сохранится в резервной копии.")
                } else {
                    Text("Данные текущей библиотеки будут заменены импортируемой копией.")
                }
            }
            .alert("Импорт завершён", isPresented: $isSuccessPresented) {
                Button("Отлично", role: .cancel) {}
            } message: {
                Text("Библиотека сохранена локально на этом iPhone. Интернет и регистрация не требуются.")
            }
            .alert("Сообщение", isPresented: Binding(
                get: { store.statusMessage != nil },
                set: { if !$0 { store.statusMessage = nil } }
            )) {
                Button("OK", role: .cancel) { store.statusMessage = nil }
            } message: {
                Text(store.statusMessage ?? "")
            }
        }
        .tint(Color(red: 0.30, green: 0.82, blue: 0.92))
    }

    private var emptyLibrary: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color.cyan.opacity(0.10))
                    .frame(width: 112, height: 112)
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(Color(red: 0.35, green: 0.86, blue: 0.95))
                    .shadow(color: .cyan.opacity(0.35), radius: 16)
            }

            VStack(spacing: 8) {
                Text("Твоя библиотека ждёт")
                    .font(.system(size: 23, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Импортируй резервный ZIP из старого StarReader, чтобы перенести произведения, главы и прогресс чтения.")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.58))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .frame(maxWidth: 310)
            }

            Button {
                isImporterPresented = true
            } label: {
                Label("Импортировать библиотеку", systemImage: "square.and.arrow.down")
                    .font(.system(size: 16, weight: .semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(Color(red: 0.12, green: 0.55, blue: 0.68))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .padding(.top, 4)

            Text("Полностью локально · Без аккаунта · Без подписки")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }

    private var libraryList: some View {
        List {
            Section {
                ForEach(store.snapshot.works, id: \.self) { work in
                    NavigationLink(value: work) {
                        HStack(spacing: 14) {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.cyan.opacity(0.25), Color.blue.opacity(0.12)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 48, height: 58)
                                .overlay {
                                    Image(systemName: "book.closed.fill")
                                        .font(.system(size: 19))
                                        .foregroundStyle(Color.cyan.opacity(0.9))
                                }

                            VStack(alignment: .leading, spacing: 5) {
                                Text(work)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white)
                                let count = store.snapshot.chapters.filter { $0.series == work }.count
                                Text("\(store.volumes(for: work).count) томов · \(count) глав")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.48))
                            }
                            Spacer()
                        }
                        .padding(.vertical, 5)
                    }
                }
            } header: {
                Text("Мои произведения")
                    .foregroundStyle(.white.opacity(0.55))
            }

            Section {
                Button {
                    isRecordsPresented = true
                } label: {
                    Label("Замечания (\(store.annotations.count)) и закладки (\(store.bookmarks.count))",
                          systemImage: "text.book.closed")
                        .foregroundStyle(Color.cyan)
                }
                Button {
                    isImporterPresented = true
                } label: {
                    Label("Импортировать другую резервную копию", systemImage: "arrow.down.doc")
                        .foregroundStyle(Color.cyan)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(red: 0.035, green: 0.045, blue: 0.075))
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
                        Label(volume.title, systemImage: "books.vertical")
                            .padding(.vertical, 5)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(red: 0.035, green: 0.045, blue: 0.075))
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
                        VStack(alignment: .leading, spacing: 6) {
                            Text(chapter.displayTitle)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.white)
                            HStack(spacing: 10) {
                                Text("\(chapter.paragraphs.count) абз.")
                                Text("·")
                                Text(store.progress(for: chapter.id).percent.formatted(.number.precision(.fractionLength(0))) + "%")
                            }
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.45))
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(red: 0.035, green: 0.045, blue: 0.075))
        .navigationTitle(volume.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
