import SwiftUI

/// A separate confirmation screen for a selected DOCX. It never overwrites
/// existing chapters, even when the title matches a chapter already in a tom.
struct DocxChapterImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.readerPalette) private var palette
    @ObservedObject var store: LibraryStore

    let document: ImportedDocxChapter
    let onImported: (LibraryChapter) -> Void

    @State private var workSelection = "__starreader_create_work__"
    @State private var volumeSelection = "__starreader_create_volume__"
    @State private var newWork = ""
    @State private var newVolume = ""
    @State private var chapterTitle = ""
    @State private var showDuplicateConfirmation = false
    @State private var errorText: String?

    private static let newWorkTag = "__starreader_create_work__"
    private static let newVolumeTag = "__starreader_create_volume__"

    private var finalWork: String {
        (workSelection == Self.newWorkTag ? newWork : workSelection)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var finalVolume: String {
        (volumeSelection == Self.newVolumeTag ? newVolume : volumeSelection)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var finalTitle: String {
        chapterTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var existingVolumes: [LibraryVolume] {
        workSelection == Self.newWorkTag
            ? []
            : store.volumes(for: workSelection)
    }

    private var duplicateCount: Int {
        store.chapters(for: finalWork, volume: finalVolume)
            .filter {
                $0.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    .compare(finalTitle, options: [.caseInsensitive, .diacriticInsensitive])
                    == .orderedSame
            }
            .count
    }

    private var canSubmit: Bool {
        !finalWork.isEmpty && !finalVolume.isEmpty && !finalTitle.isEmpty
            && !document.paragraphs.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Выбранный файл") {
                    Label(document.sourceFileName, systemImage: "doc.text")
                        .font(.system(size: 14, weight: .medium))
                    HStack {
                        Label("\(document.paragraphs.count) абз.", systemImage: "text.alignleft")
                        Spacer()
                        Text("\(document.characterCount) символов")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)

                    Text(document.paragraphs.prefix(2).map(\.text).joined(separator: " "))
                        .font(.system(size: 13, design: .serif))
                        .foregroundStyle(palette.secondary)
                        .lineLimit(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Section("Произведение") {
                    Picker("Куда добавить", selection: $workSelection) {
                        Text("Новое произведение").tag(Self.newWorkTag)
                        ForEach(store.snapshot.works, id: \.self) { work in
                            Text(work).tag(work)
                        }
                    }
                    if workSelection == Self.newWorkTag {
                        TextField("Название нового произведения", text: $newWork)
                            .textInputAutocapitalization(.sentences)
                    }
                }

                Section("Том") {
                    Picker("Выбери том", selection: $volumeSelection) {
                        Text("Новый том").tag(Self.newVolumeTag)
                        ForEach(existingVolumes) { volume in
                            Text(volume.title).tag(volume.title)
                        }
                    }
                    if volumeSelection == Self.newVolumeTag {
                        TextField("Название нового тома", text: $newVolume)
                            .textInputAutocapitalization(.sentences)
                    }
                }

                Section("Название главы") {
                    TextField("Например, Глава 2. Новое утро", text: $chapterTitle)
                        .textInputAutocapitalization(.sentences)

                    if duplicateCount > 0 {
                        Label(
                            "В этом томе уже \(duplicateCount) глав с таким названием. " +
                            "Исходные главы не будут заменены.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                    }
                }

                Section {
                    Button {
                        if duplicateCount > 0 {
                            showDuplicateConfirmation = true
                        } else {
                            save(allowDuplicate: false)
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Label("Добавить главу", systemImage: "plus.circle.fill")
                                .font(.system(size: 16, weight: .semibold))
                            Spacer()
                        }
                        .padding(.vertical, 5)
                    }
                    .disabled(!canSubmit)
                } footer: {
                    Text("Импорт добавит главу, не изменяя существующие заметки, закладки и прогресс чтения. Оригинальный DOCX сохранится локально.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(palette.background.ignoresSafeArea())
            .navigationTitle("Импорт DOCX")
            .navigationBarTitleDisplayMode(.inline)
            .tint(palette.accent)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") { dismiss() }
                }
            }
            .onAppear {
                chapterTitle = document.suggestedTitle
                if let first = store.snapshot.works.first {
                    workSelection = first
                    volumeSelection = store.volumes(for: first).first?.title
                        ?? Self.newVolumeTag
                }
            }
            .onChange(of: workSelection) { _, next in
                volumeSelection = next == Self.newWorkTag
                    ? Self.newVolumeTag
                    : (store.volumes(for: next).first?.title ?? Self.newVolumeTag)
            }
            .confirmationDialog(
                "Глава уже существует",
                isPresented: $showDuplicateConfirmation,
                titleVisibility: .visible
            ) {
                Button("Добавить отдельным вариантом") {
                    save(allowDuplicate: true)
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("«\(finalTitle)» уже есть в томе «\(finalVolume)». " +
                     "Существующий текст и его заметки останутся без изменений.")
            }
            .alert(
                "Импорт не завершён",
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

    private func save(allowDuplicate: Bool) {
        guard canSubmit else { return }
        do {
            let chapter = try store.importDocxChapter(
                document,
                work: finalWork,
                volume: finalVolume,
                title: finalTitle,
                allowDuplicate: allowDuplicate
            )
            onImported(chapter)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
