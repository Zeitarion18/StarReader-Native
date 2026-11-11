import SwiftUI

/// Smart, reviewable DOCX import. Nothing is written until the user sees and
/// confirms the exact display name, work, volume and document type.
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
    @State private var chapterKind: DocxDocumentKind = .chapter
    @State private var chapterNumber = ""
    @State private var chapterTitle = ""
    @State private var showDuplicateConfirmation = false
    @State private var errorText: String?
    @State private var isSaving = false
    @State private var initialized = false

    private static let newWorkTag = "__starreader_create_work__"
    private static let newVolumeTag = "__starreader_create_volume__"

    private var suggestion: DocxImportSuggestion {
        DocxImportSuggestion.infer(
            from: document.sourceFileName,
            headings: document.paragraphs
                .filter(\.heading)
                .prefix(3)
                .map(\.text)
        )
    }

    private var finalWork: String {
        (workSelection == Self.newWorkTag ? newWork : workSelection)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var finalVolume: String {
        (volumeSelection == Self.newVolumeTag ? newVolume : volumeSelection)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var finalTitle: String {
        chapterKind.libraryTitle(
            chapterNumber: chapterNumber,
            subtitle: chapterTitle
        )
    }

    private var existingVolumes: [LibraryVolume] {
        workSelection == Self.newWorkTag ? [] : store.volumes(for: workSelection)
    }

    private var duplicateCount: Int {
        store.chapters(for: finalWork, volume: finalVolume)
            .filter {
                $0.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    .compare(finalTitle, options: [.caseInsensitive, .diacriticInsensitive])
                    == .orderedSame
            }.count
    }

    private var canSubmit: Bool {
        !isSaving && !finalWork.isEmpty && !finalVolume.isEmpty
            && !finalTitle.isEmpty && !document.paragraphs.isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        fileInfo
                        destinations
                        documentKind
                        chapterFields
                        preview
                        if duplicateCount > 0 {
                            Label(
                                "Такое название уже есть в выбранном томе. " +
                                "Можно добавить отдельный вариант, не заменяя исходный.",
                                systemImage: "exclamationmark.triangle"
                            )
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                            .padding(13)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.10),
                                        in: RoundedRectangle(cornerRadius: 12))
                        }
                        Text("Исходный DOCX будет сохранён. Существующие главы, " +
                             "замечания, закладки и прогресс не изменятся.")
                            .font(.system(size: 12))
                            .foregroundStyle(palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: 680)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.top, 17)
                    .padding(.bottom, 30)
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollIndicators(.hidden)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    footer
                }
            }
            .background(palette.background.ignoresSafeArea())
            .navigationTitle("Добавить главу из Word")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") { dismiss() }
                }
            }
            .tint(palette.accent)
            .onAppear(perform: configureSuggestion)
            .onChange(of: workSelection) { old, next in
                guard initialized, old != next else { return }
                chooseVolume(for: next)
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
                     "Имеющаяся глава и её заметки останутся без изменений.")
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

    private var fileInfo: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("НАЗВАНИЕ ЗАГРУЖАЕМОГО ДОКУМЕНТА")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(palette.secondary)
            HStack(spacing: 9) {
                Image(systemName: "doc.text")
                    .foregroundStyle(palette.accent)
                Text(document.sourceFileName)
                    .font(.system(size: 13))
                    .lineLimit(3)
                    .foregroundStyle(palette.text)
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(palette.hairline, lineWidth: 1)
            }
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                Text(suggestion.confidence
                     ? "Тип и название распознаны по имени файла"
                     : "Предварительное определение — проверь данные")
            }
            .font(.system(size: 12))
            .foregroundStyle(palette.accent)
        }
    }

    private var destinations: some View {
        VStack(alignment: .leading, spacing: 13) {
            VStack(alignment: .leading, spacing: 7) {
                fieldLabel("ПРОИЗВЕДЕНИЕ")
                Picker("Произведение", selection: $workSelection) {
                    ForEach(store.snapshot.works, id: \.self) { work in
                        Text(work).tag(work)
                    }
                    Text("＋ Новое произведение").tag(Self.newWorkTag)
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
                if workSelection == Self.newWorkTag {
                    TextField("Название нового произведения", text: $newWork)
                        .textInputAutocapitalization(.sentences)
                        .fieldStyle(palette: palette)
                }
            }
            VStack(alignment: .leading, spacing: 7) {
                fieldLabel("ТОМ")
                Picker("Том", selection: $volumeSelection) {
                    ForEach(existingVolumes) { volume in
                        Text(volume.title).tag(volume.title)
                    }
                    Text("＋ Новый том").tag(Self.newVolumeTag)
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
                if volumeSelection == Self.newVolumeTag {
                    TextField("Название нового тома", text: $newVolume)
                        .textInputAutocapitalization(.sentences)
                        .fieldStyle(palette: palette)
                }
            }
        }
    }

    private var documentKind: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Что ты загружаешь?")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.text)
            Text("StarReader определяет тип по имени файла. " +
                 "При необходимости его можно изменить.")
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 130), spacing: 8)],
                spacing: 9
            ) {
                ForEach(DocxDocumentKind.allCases) { kind in
                    kindButton(kind)
                }
            }
        }
        .padding(.top, 4)
    }

    private func kindButton(_ kind: DocxDocumentKind) -> some View {
        let isActive = chapterKind == kind
        return Button {
            chapterKind = kind
        } label: {
            HStack(spacing: 7) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 13))
                Text(kind.title)
                    .font(.system(size: 12, weight: isActive ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 1)
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
            }
            .foregroundStyle(isActive ? palette.accent : palette.secondary)
            .padding(.horizontal, 10)
            .frame(height: 55)
            .background(
                isActive ? palette.accent.opacity(0.14) : palette.surface,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isActive ? palette.accent : palette.hairline,
                        lineWidth: isActive ? 1.5 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(kind.title), \(isActive ? "выбрано" : "не выбрано")")
    }

    private var chapterFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            if chapterKind == .chapter {
                fieldLabel("НОМЕР ГЛАВЫ (ЕСЛИ ЕСТЬ)")
                TextField("Например, 3", text: $chapterNumber)
                    .keyboardType(.numbersAndPunctuation)
                    .fieldStyle(palette: palette)
            }
            fieldLabel("НАЗВАНИЕ \(chapterKind == .chapter ? "ГЛАВЫ" : "РАЗДЕЛА") (НЕОБЯЗАТЕЛЬНО)")
            TextField("Название определено автоматически", text: $chapterTitle)
                .textInputAutocapitalization(.sentences)
                .fieldStyle(palette: palette)
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("В БИБЛИОТЕКЕ БУДЕТ ОТОБРАЖАТЬСЯ:")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(palette.secondary)
            Text(finalTitle)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(palette.text)
                .fixedSize(horizontal: false, vertical: true)
            if !finalWork.isEmpty || !finalVolume.isEmpty {
                Text([finalWork, finalVolume].filter { !$0.isEmpty }.joined(separator: "  ·  "))
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.accent.opacity(0.075),
                    in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(palette.accent.opacity(0.45), lineWidth: 1)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Отмена") { dismiss() }
                .buttonStyle(.bordered)
            Button {
                if duplicateCount > 0 {
                    showDuplicateConfirmation = true
                } else {
                    save(allowDuplicate: false)
                }
            } label: {
                Label(
                    isSaving ? "Сохраняем…" : "Сохранить в выбранном томе",
                    systemImage: "checkmark"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSubmit)
        }
        .font(.system(size: 13, weight: .semibold))
        .padding(.horizontal, 17)
        .padding(.vertical, 12)
        .background(palette.surfaceHigh)
        .overlay(alignment: .top) {
            Rectangle().fill(palette.hairline).frame(height: 1)
        }
    }

    private func fieldLabel(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 10, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(palette.secondary)
    }

    private func configureSuggestion() {
        guard !initialized else { return }
        let proposed = suggestion
        chapterKind = proposed.kind
        chapterNumber = proposed.chapterNumber
        chapterTitle = proposed.subtitle
        newVolume = proposed.volume ?? ""

        if let hint = proposed.workHint,
           let work = store.snapshot.works.first(where: {
               $0.compare(hint, options: [.caseInsensitive, .diacriticInsensitive])
                   == .orderedSame
           }) {
            workSelection = work
        } else if let volume = proposed.volume {
            let matchingWorks = store.snapshot.works.filter { work in
                store.volumes(for: work).contains(where: {
                    $0.title.compare(volume, options: [.caseInsensitive, .diacriticInsensitive])
                        == .orderedSame
                })
            }
            if matchingWorks.count == 1 {
                workSelection = matchingWorks[0]
            } else {
                workSelection = store.mostRecentChapter?.series
                    ?? store.snapshot.works.first ?? Self.newWorkTag
            }
        } else {
            workSelection = store.mostRecentChapter?.series
                ?? store.snapshot.works.first ?? Self.newWorkTag
        }
        if workSelection == Self.newWorkTag {
            newWork = proposed.workHint ?? ""
        }
        chooseVolume(for: workSelection)
        initialized = true
    }

    private func chooseVolume(for work: String) {
        let vols = work == Self.newWorkTag ? [] : store.volumes(for: work)
        if let proposed = suggestion.volume {
            if let existing = vols.first(where: {
                $0.title.compare(proposed, options: [.caseInsensitive, .diacriticInsensitive])
                    == .orderedSame
            }) {
                volumeSelection = existing.title
            } else {
                volumeSelection = Self.newVolumeTag
                newVolume = proposed
            }
        } else if let prior = store.mostRecentChapter,
                  prior.series == work,
                  vols.contains(where: { $0.title == prior.volume }) {
            volumeSelection = prior.volume
        } else {
            volumeSelection = vols.first?.title ?? Self.newVolumeTag
        }
    }

    private func save(allowDuplicate: Bool) {
        guard canSubmit else { return }
        isSaving = true
        defer { isSaving = false }
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

private struct DocxImportTextFieldStyle: ViewModifier {
    let palette: ReaderPalette
    func body(content: Content) -> some View {
        content
            .font(.system(size: 14))
            .foregroundStyle(palette.text)
            .padding(13)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(palette.hairline, lineWidth: 1)
            }
    }
}

private extension View {
    func fieldStyle(palette: ReaderPalette) -> some View {
        modifier(DocxImportTextFieldStyle(palette: palette))
    }
}
