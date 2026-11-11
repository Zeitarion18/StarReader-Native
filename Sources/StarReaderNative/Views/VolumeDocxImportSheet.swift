import SwiftUI

/// Preview and edit the boundaries discovered inside one complete Word tome.
/// The original Word document is not changed. Unselected sections are skipped
/// explicitly and existing chapters are never overwritten.
struct VolumeDocxImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.readerPalette) private var palette
    @ObservedObject var store: LibraryStore

    let document: ImportedDocxChapter
    let onImported: (Int, String) -> Void

    @State private var sections: [VolumeSectionDraft] = []
    @State private var workSelection = "__create_work__"
    @State private var volumeSelection = "__create_volume__"
    @State private var newWork = ""
    @State private var newVolume = ""
    @State private var newBoundaryParagraph = 2
    @State private var showSaveConfirmation = false
    @State private var isSaving = false
    @State private var initialized = false
    @State private var errorText: String?

    private static let newWorkTag = "__create_work__"
    private static let newVolumeTag = "__create_volume__"

    private var proposed: DocxImportSuggestion {
        DocxImportSuggestion.infer(from: document.sourceFileName)
    }

    private var finalWork: String {
        (workSelection == Self.newWorkTag ? newWork : workSelection)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var finalVolume: String {
        (volumeSelection == Self.newVolumeTag ? newVolume : volumeSelection)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var volumes: [LibraryVolume] {
        workSelection == Self.newWorkTag ? [] : store.volumes(for: workSelection)
    }

    private var selectedSections: [VolumeDocxSplitter.Section] {
        (try? VolumeDocxSplitter.sections(
            in: document, drafts: sections
        )) ?? []
    }

    private var splitError: String? {
        do {
            _ = try VolumeDocxSplitter.sections(in: document, drafts: sections)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private var duplicateTitles: [String] {
        let existing = store.chapters(for: finalWork, volume: finalVolume)
        var names = Set(existing.map { normalized($0.displayTitle) })
        var duplicates: [String] = []
        for section in selectedSections {
            let key = normalized(section.title)
            if names.contains(key) {
                duplicates.append(section.title)
            }
            names.insert(key)
        }
        return duplicates
    }

    private var canImport: Bool {
        !isSaving && !finalWork.isEmpty && !finalVolume.isEmpty &&
        splitError == nil && duplicateTitles.isEmpty &&
        !selectedSections.isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        documentCard
                        destinationControls
                        detectionSummary
                        boundaryControls
                        sectionCards
                        if let splitError {
                            notice(splitError, icon: "exclamationmark.triangle")
                        }
                        if !duplicateTitles.isEmpty {
                            notice(
                                "Такие главы уже существуют или повторяются в списке: " +
                                duplicateTitles.joined(separator: ", ") +
                                ". Измени названия или отключи их импорт.",
                                icon: "doc.on.doc"
                            )
                        }
                        Text("Текст и порядок абзацев сохраняются. Старые главы, заметки, " +
                             "закладки и прогресс останутся без изменений. " +
                             "Перед импортом создаётся локальная резервная копия.")
                            .font(.system(size: 12))
                            .foregroundStyle(palette.secondary)
                    }
                    .frame(maxWidth: 700)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 19)
                    .padding(.top, 17)
                    .padding(.bottom, 25)
                }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    bottomBar
                }
            }
            .background(palette.background.ignoresSafeArea())
            .navigationTitle("Импорт целого тома")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") { dismiss() }
                }
            }
            .tint(palette.accent)
            .onAppear(perform: initialize)
            .onChange(of: workSelection) { old, next in
                guard initialized && old != next else { return }
                chooseVolume(for: next)
            }
            .confirmationDialog(
                "Добавить \(selectedSections.count) разделов?",
                isPresented: $showSaveConfirmation,
                titleVisibility: .visible
            ) {
                Button("Импортировать весь выбранный текст") {
                    save()
                }
                Button("Проверить ещё раз", role: .cancel) {}
            } message: {
                Text("Произведение: «\(finalWork)», том: «\(finalVolume)». " +
                     "Импорт будет выполнен одним сохранением, с резервной копией. " +
                     "Отключённые разделы добавлены не будут.")
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

    private var documentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("WORD-ФАЙЛ ЦЕЛОГО ТОМА", systemImage: "doc.richtext")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(palette.accent)
            Text(document.sourceFileName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.text)
                .textSelection(.enabled)
            Text("\(document.paragraphs.count) абзацев · " +
                 "\(document.characterCount) символов")
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private var destinationControls: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Куда добавить главы?")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.text)
            Picker("Произведение", selection: $workSelection) {
                ForEach(store.snapshot.works, id: \.self) { work in
                    Text(work).tag(work)
                }
                Text("＋ Новое произведение").tag(Self.newWorkTag)
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
            if workSelection == Self.newWorkTag {
                TextField("Название произведения", text: $newWork)
                    .textInputAutocapitalization(.sentences)
                    .padding(12)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
            }
            Picker("Том", selection: $volumeSelection) {
                ForEach(volumes) { volume in
                    Text(volume.title).tag(volume.title)
                }
                Text("＋ Новый том").tag(Self.newVolumeTag)
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
            if volumeSelection == Self.newVolumeTag {
                TextField("Название тома", text: $newVolume)
                    .textInputAutocapitalization(.sentences)
                    .padding(12)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var detectionSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Найденные разделы")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(palette.text)
                Spacer()
                Text("\(selectedSections.count) из \(sections.count)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.accent)
            }
            Text("Проверь названия и начало каждой главы перед сохранением. " +
                 "Если раздел не найден, его границу можно добавить вручную.")
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if sections.count <= 1 {
                notice(
                    "Автоматически обнаружен только один раздел. " +
                    "Если внутри файла несколько глав, добавь их границы вручную.",
                    icon: "exclamationmark.triangle"
                )
            }
        }
    }

    private var boundaryControls: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Добавить границу вручную")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.text)
            HStack(spacing: 10) {
                TextField("Начало с абзаца №", value: $newBoundaryParagraph,
                          format: .number)
                    .keyboardType(.numberPad)
                    .padding(12)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
                Button {
                    addBoundary()
                } label: {
                    Label("Добавить", systemImage: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .disabled(sections.count >= 250 || document.paragraphs.count < 2)
            }
            Text("Номера абзацев начинаются с 1. Можно изменить номер начала " +
                 "любой главы, кроме первой, или удалить лишнюю границу.")
                .font(.system(size: 11))
                .foregroundStyle(palette.secondary)
        }
        .padding(14)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 15))
    }

    private var sectionCards: some View {
        VStack(spacing: 11) {
            ForEach($sections) { $section in
                sectionCard($section)
            }
        }
    }

    private func sectionCard(
        _ section: Binding<VolumeSectionDraft>
    ) -> some View {
        let id = section.wrappedValue.id
        let position = section.wrappedValue.startParagraph
        let isFirst = sections.first?.id == id
        let range = sectionRange(for: id)
        let count = range?.count ?? 0
        let chars = range.map { span in
            document.paragraphs[span].reduce(0) {
                $0 + $1.text.unicodeScalars.count
            }
        } ?? 0
        let snippet = range.flatMap { span in
            document.paragraphs[span].first?.text
        } ?? ""

        return VStack(alignment: .leading, spacing: 11) {
            Toggle(isOn: section.include) {
                HStack(spacing: 7) {
                    Image(systemName: "book.pages")
                        .foregroundStyle(palette.accent)
                    Text("Раздел с абзаца \(position)")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(palette.text)
            }
            .tint(palette.accent)

            TextField("Название главы или пролога", text: section.title)
                .font(.system(size: 14, weight: .medium))
                .textInputAutocapitalization(.sentences)
                .padding(12)
                .background(palette.surfaceHigh, in: RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 10) {
                if isFirst {
                    Label("Первый абзац: 1", systemImage: "lock")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.secondary)
                } else {
                    Text("Начало №")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.secondary)
                    TextField("Абзац", value: section.startParagraph, format: .number)
                        .keyboardType(.numberPad)
                        .font(.system(size: 12))
                        .frame(width: 73)
                        .padding(8)
                        .background(palette.surfaceHigh,
                                    in: RoundedRectangle(cornerRadius: 9))
                    Spacer()
                    Button(role: .destructive) {
                        sections.removeAll { $0.id == id }
                    } label: {
                        Label("Убрать границу", systemImage: "trash")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.orange)
                }
            }

            Text("\(count) абз. · \(chars) символов")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.accent)
            Text(snippet)
                .font(.system(size: 12, design: .serif))
                .foregroundStyle(palette.secondary)
                .lineLimit(3)

            if !section.wrappedValue.confidence {
                Label("Границу желательно проверить", systemImage: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 15))
        .overlay {
            RoundedRectangle(cornerRadius: 15)
                .strokeBorder(palette.hairline, lineWidth: 1)
        }
        .opacity(section.wrappedValue.include ? 1 : 0.6)
    }

    private func sectionRange(for id: UUID) -> Range<Int>? {
        let sorted = sections.sorted { $0.startParagraph < $1.startParagraph }
        guard let index = sorted.firstIndex(where: { $0.id == id }) else { return nil }
        let start = sorted[index].startParagraph - 1
        let end = index + 1 < sorted.count
            ? sorted[index + 1].startParagraph - 1
            : document.paragraphs.count
        guard start >= 0, start < end, end <= document.paragraphs.count else {
            return nil
        }
        return start..<end
    }

    private var bottomBar: some View {
        VStack(spacing: 9) {
            HStack {
                Text("Будет импортировано:")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
                Spacer()
                Text("\(selectedSections.count) разделов")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.text)
            }
            HStack(spacing: 10) {
                Button("Отмена") { dismiss() }
                    .buttonStyle(.bordered)
                Button {
                    showSaveConfirmation = true
                } label: {
                    Label(isSaving ? "Сохраняем…" : "Добавить в том",
                          systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canImport)
            }
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 12)
        .background(palette.surfaceHigh)
        .overlay(alignment: .top) {
            Rectangle().fill(palette.hairline).frame(height: 1)
        }
    }

    private func notice(_ message: String, icon: String) -> some View {
        Label(message, systemImage: icon)
            .font(.system(size: 12))
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.075),
                        in: RoundedRectangle(cornerRadius: 12))
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "ru_RU")
        )
    }

    private func initialize() {
        guard !initialized else { return }
        sections = VolumeDocxSplitter.detect(in: document)
        newBoundaryParagraph = min(2, max(1, document.paragraphs.count))
        newVolume = proposed.volume ?? ""
        if let workHint = proposed.workHint,
           let exact = store.snapshot.works.first(where: {
               normalized($0) == normalized(workHint)
           }) {
            workSelection = exact
        } else if let name = proposed.volume {
            let matched = store.snapshot.works.filter { work in
                store.volumes(for: work).contains {
                    normalized($0.title) == normalized(name)
                }
            }
            if matched.count == 1 {
                workSelection = matched[0]
            } else {
                workSelection = store.mostRecentChapter?.series
                    ?? store.snapshot.works.first ?? Self.newWorkTag
            }
        } else {
            workSelection = store.mostRecentChapter?.series
                ?? store.snapshot.works.first ?? Self.newWorkTag
        }
        if workSelection == Self.newWorkTag { newWork = proposed.workHint ?? "" }
        chooseVolume(for: workSelection)
        initialized = true
    }

    private func chooseVolume(for work: String) {
        let options = work == Self.newWorkTag ? [] : store.volumes(for: work)
        if let candidate = proposed.volume {
            if let exact = options.first(where: {
                normalized($0.title) == normalized(candidate)
            }) {
                volumeSelection = exact.title
            } else {
                volumeSelection = Self.newVolumeTag
                newVolume = candidate
            }
        } else if let recent = store.mostRecentChapter,
                  recent.series == work,
                  options.contains(where: { $0.title == recent.volume }) {
            volumeSelection = recent.volume
        } else {
            volumeSelection = options.first?.title ?? Self.newVolumeTag
        }
    }

    private func addBoundary() {
        guard sections.count < 250,
              newBoundaryParagraph > 1,
              newBoundaryParagraph <= document.paragraphs.count,
              !sections.contains(where: {
                  $0.startParagraph == newBoundaryParagraph
              }) else {
            errorText = "Укажи новый номер абзаца от 2 до \(document.paragraphs.count)."
            return
        }
        let firstText = document.paragraphs[newBoundaryParagraph - 1].text
        let name = DocxImportSuggestion.infer(
            from: firstText + ".docx"
        )
        sections.append(VolumeSectionDraft(
            startParagraph: newBoundaryParagraph,
            title: name.confidence ? name.libraryTitle : "Новый раздел",
            confidence: false
        ))
        sections.sort { $0.startParagraph < $1.startParagraph }
    }

    private func save() {
        guard canImport else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let selected = try VolumeDocxSplitter.sections(
                in: document, drafts: sections
            )
            let count = try store.importDocxVolume(
                document, work: finalWork, volume: finalVolume,
                sections: selected
            )
            onImported(count, finalVolume)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
