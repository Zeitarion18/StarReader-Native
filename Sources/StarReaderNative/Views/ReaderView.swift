import SwiftUI

private struct ReaderEditRequest: Identifiable {
    let id = UUID()
    let selection: ReaderTextSelection?
}

private struct ParagraphFramesKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct ReaderView: View {
    @Environment(\.readerPalette) private var palette
    @ObservedObject var store: LibraryStore
    private let initialChapter: LibraryChapter
    let jump: ReaderJump?

    init(store: LibraryStore, chapter: LibraryChapter, jump: ReaderJump? = nil) {
        self.store = store
        self.initialChapter = chapter
        self.jump = jump
    }

    private var chapter: LibraryChapter {
        store.chapter(for: initialChapter.id) ?? initialChapter
    }

    @AppStorage("starreader.fontSize") private var fontSize: Double = 17
    @AppStorage("starreader.lineSpacing") private var lineSpacing: Double = 4
    @AppStorage("starreader.paragraphSpacing") private var paragraphSpacing: Double = 13
    @AppStorage("starreader.readingMode") private var readingMode = "pages"
    @AppStorage("starreader.colorTheme") private var colorThemeID = ReaderColorTheme.dark.rawValue
    @AppStorage("starreader.lastPageContentWidth") private var lastMeasuredWidth: Double = 0
    @AppStorage("starreader.lastPageHeight") private var lastMeasuredHeight: Double = 0

    @State private var pagination: ChapterPagination?
    @State private var nativePlan: NativeTextPagePlan?
    @State private var pageIndex = 0
    @State private var currentParagraph = 0
    @State private var currentOffset = 0
    @State private var lastPageSize = CGSize.zero
    @State private var hasRestored = false
    @State private var hasScrolled = false
    @State private var hasRestoredScroll = false
    @State private var controlsVisible = true
    @State private var showReaderSettings = false
    @State private var selectedAnnotation: ReaderAnnotation?
    @State private var selectedText: ReaderTextSelection?
    @State private var composingSelection: ReaderTextSelection?
    @State private var editorRequest: ReaderEditRequest?
    @State private var lastEditMessage: String?

    private var pageBackground: Color { palette.background }

    private var linkedAnnotations: [ReaderAnnotation] {
        store.annotations(for: chapter.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                Group {
                    if readingMode == "pages" {
                        pageReader(in: geometry.size)
                    } else {
                        scrollingReader
                    }
                }
                .background(pageBackground)
                .onAppear {
                    rebuildPagination(for: geometry.size)
                }
                .onChange(of: geometry.size) { _, newValue in
                    rebuildPagination(for: newValue)
                }
                .onChange(of: fontSize) { _, _ in
                    rebuildPagination(for: geometry.size, force: true)
                }
                .onChange(of: lineSpacing) { _, _ in
                    rebuildPagination(for: geometry.size, force: true)
                }
                .onChange(of: paragraphSpacing) { _, _ in
                    rebuildPagination(for: geometry.size, force: true)
                }
                .onChange(of: colorThemeID) { _, _ in
                    // Restyle all TextKit glyphs without losing the paragraph/offset.
                    rebuildPagination(for: geometry.size, force: true)
                }
                .onChange(of: readingMode) { _, _ in
                    hasRestoredScroll = false
                    hasScrolled = false
                    selectedText = nil
                    rebuildPagination(for: geometry.size, force: true)
                }
                .onChange(of: chapter) { _, _ in
                    // The editor has replaced the JSON, but the reader's
                    // NavigationLink may still hold the original value.
                    // Re-measure using the live chapter with mapped progress.
                    let progress = store.progress(for: chapter.id)
                    currentParagraph = progress.paragraph
                    currentOffset = progress.offset
                    nativePlan = nil
                    pagination = nil
                    hasRestoredScroll = false
                    hasScrolled = false
                    rebuildPagination(for: geometry.size, force: true)
                }
                .onChange(of: store.annotations) { _, _ in
                    // Updated color spans must be reflected in CoreText.
                    // Keep the existing paragraph/offset so this doesn't
                    // move the reader when a new note is saved.
                    rebuildPagination(for: geometry.size, force: true)
                }
            }

            // This is an actual, separate footer, NOT an overlay on the text.
            Rectangle()
                .fill(palette.hairline)
                .frame(height: 1)

            informationFooter
        }
        .background(pageBackground.ignoresSafeArea())
        // Always reserve the navigation-bar height for stable pagination,
        // but REMOVE toolbar items when controls are hidden. Applying
        // .opacity(0) hides only their labels, leaving iOS 26 Liquid Glass
        // button containers visible as empty capsules.
        .navigationTitle(controlsVisible ? chapter.displayTitle : "")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            if controlsVisible {
                ToolbarItem(placement: .topBarLeading) {
                    ReaderBackButton()
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        store.addBookmark(
                            for: chapter,
                            paragraph: currentParagraph,
                            offset: currentOffset
                        )
                    } label: {
                        Image(systemName: store.hasBookmark(
                            chapterID: chapter.id,
                            paragraph: currentParagraph
                        ) ? "bookmark.fill" : "bookmark")
                    }
                    .accessibilityLabel("Добавить закладку")

                    Button {
                        editorRequest = ReaderEditRequest(selection: nil)
                    } label: {
                        Image(systemName: "pencil.line")
                    }
                    .accessibilityLabel("Редактировать главу")

                    Button {
                        showReaderSettings = true
                    } label: {
                        Image(systemName: "textformat.size")
                    }
                    .accessibilityLabel("Оформление чтения")

                    NavigationLink {
                        NotesAndBookmarksView(store: store)
                    } label: {
                        Image(systemName: "text.book.closed")
                    }
                    .accessibilityLabel("Замечания и закладки")
                }
            }
        }
        // Never toggle .hidden for the navigation bar. Its safe-area footprint
        // is a required invariant of pagination and stays reserved at all times.
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(pageBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .sheet(isPresented: $showReaderSettings) {
            ReaderSettingsSheet(
                fontSize: $fontSize,
                lineSpacing: $lineSpacing,
                paragraphSpacing: $paragraphSpacing,
                readingMode: $readingMode,
                colorThemeID: $colorThemeID
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedAnnotation) { item in
            annotationSheet(item)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $editorRequest) { request in
            ChapterEditorSheet(
                store: store,
                chapterID: chapter.id,
                selection: request.selection
            ) { result in
                let noteCount = result.notesNeedingReview
                let bookmarkCount = result.bookmarksNeedingReview
                lastEditMessage = "Глава сохранена. " +
                    "Требуют проверки: (noteCount) замечаний, " +
                    "(bookmarkCount) закладок."
            }
        }
        .alert(
            "Изменения сохранены",
            isPresented: Binding(
                get: { lastEditMessage != nil },
                set: { if !$0 { lastEditMessage = nil } }
            )
        ) {
            Button("Отлично", role: .cancel) { lastEditMessage = nil }
        } message: {
            Text(lastEditMessage ?? "")
        }
        .sheet(item: $composingSelection) { selection in
            AnnotationComposerView(selection: selection) { kind, note in
                let saved = store.addAnnotation(
                    for: chapter,
                    selection: selection,
                    kind: kind,
                    note: note
                )
                if saved { selectedText = nil }
                return saved
            }
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Actual page-based reading

    private func pageReader(in size: CGSize) -> some View {
        GeometryReader { geometry in
            let pageWidth = min(geometry.size.width - 24, 712)
            let pageHeight = geometry.size.height - 20

            HStack(spacing: 0) {
                Spacer(minLength: 0)

                if let plan = nativePlan {
                    NativeSelectablePage(
                        plan: plan,
                        palette: palette,
                        pageIndex: plan.clamp(pageIndex),
                        onTurn: { direction in
                            changePage(by: direction)
                        },
                        onTapCenter: {
                            toggleControls()
                        },
                        onMakeNote: { selection in
                            composingSelection = selection
                        },
                        onEditSelection: { selection in
                            editorRequest = ReaderEditRequest(selection: selection)
                        }
                    )
                    .frame(
                        width: max(140, pageWidth),
                        height: max(150, pageHeight)
                    )
                    .accessibilityLabel(
                        "Страница \(pageIndex + 1) из \(plan.pageCount). Удержи палец на тексте для стандартного выделения iOS."
                    )
                } else {
                    ProgressView("Размечаем страницы…")
                        .tint(palette.accent)
                        .font(.system(size: 13))
                        .foregroundStyle(palette.secondary)
                        .frame(
                            width: max(140, pageWidth),
                            height: max(150, pageHeight)
                        )
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(pageBackground)
    }

    private func rebuildPagination(for size: CGSize, force: Bool = false) {
        let width = min(size.width - 24, 712)
        let contentWidth = width - 20  // 10pt note rail gutters on each side
        let height = size.height - 20
        guard width >= 150, height >= 170 else { return }
        if !force,
           abs(width - lastPageSize.width) < 0.5,
           abs(height - lastPageSize.height) < 0.5,
           pagination != nil { return }

        let saved = store.progress(for: chapter.id)
        let targetParagraph = hasRestored
            ? currentParagraph
            : (jump?.paragraph ?? saved.paragraph)
        let targetOffset = hasRestored
            ? currentOffset
            : (jump?.offset ?? saved.offset)

        let next = ChapterPagination(
            chapter: chapter,
            annotations: linkedAnnotations,
            pageWidth: contentWidth,
            pageHeight: height,
            fontSize: fontSize,
            lineSpacing: lineSpacing,
            paragraphSpacing: paragraphSpacing,
            palette: palette
        )
        // Use TextKit for both page measurement and on-screen rendering.
        // Native UITextView selection handles use this exact same layout.
        let native = NativeTextPagePlan(
            source: next,
            pageWidth: contentWidth,
            pageHeight: height
        )
        pagination = next
        nativePlan = native
        pageIndex = native.page(for: targetParagraph, offset: targetOffset)
        currentParagraph = min(max(targetParagraph, 0), max(chapter.paragraphs.count - 1, 0))
        currentOffset = max(0, targetOffset)
        lastPageSize = CGSize(width: width, height: height)
        // Store the actual TextKit viewport so volume page totals use the
        // same line wrapping and page boundaries as the reading screen.
        if abs(lastMeasuredWidth - Double(contentWidth)) > 0.5 {
            lastMeasuredWidth = Double(contentWidth)
        }
        if abs(lastMeasuredHeight - Double(height)) > 0.5 {
            lastMeasuredHeight = Double(height)
        }
        hasRestored = true
    }

    private func changePage(by delta: Int) {
        guard let nativePlan else { return }
        let next = nativePlan.clamp(pageIndex + delta)
        guard next != pageIndex else { return }
        // Avoid implicit animations stretching UITextView or its text glyphs.
        pageIndex = next
        let location = nativePlan.location(at: next)
        currentParagraph = location.paragraph
        currentOffset = location.offset
        store.recordProgress(
            for: chapter,
            paragraph: location.paragraph,
            offset: location.offset
        )
    }

    private func toggleControls() {
        // Structural removal of iOS Liquid Glass toolbar items should not
        // animate their containers independently from the text viewport.
        controlsVisible.toggle()
    }

    // MARK: - Optional continuous reading

    private var scrollingReader: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: paragraphSpacing) {
                    Text(chapter.displayTitle)
                        .font(.system(size: 21, weight: .semibold, design: .serif))
                        .foregroundStyle(palette.text)
                        .padding(.bottom, 13)
                        .padding(.top, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(chapter.paragraphs) { paragraph in
                        VStack(alignment: .leading, spacing: 6) {
                            let notes = annotations(at: paragraph.index)
                            highlightedText(paragraph)
                                .font(.system(
                                    size: paragraph.heading ? fontSize + 2 : fontSize,
                                    weight: paragraph.heading ? .semibold : .regular,
                                    design: .serif
                                ))
                                .lineSpacing(lineSpacing)
                                .padding(.leading, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .overlay(alignment: .leading) {
                                    if !notes.isEmpty {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(palette.accent)
                                            .frame(width: 3)
                                            .padding(.leading, 2)
                                    }
                                }

                            if !notes.isEmpty {
                                NotePills(notes: notes) { selectedAnnotation = $0 }
                            }
                        }
                        .id(paragraph.index)
                        .background {
                            GeometryReader { frame in
                                Color.clear.preference(
                                    key: ParagraphFramesKey.self,
                                    value: [
                                        paragraph.index: frame.frame(
                                            in: .named("readerScroll")
                                        ).minY
                                    ]
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { toggleControls() }
            }
            .scrollIndicators(.hidden)
            .coordinateSpace(name: "readerScroll")
            .simultaneousGesture(
                DragGesture(minimumDistance: 5).onChanged { _ in
                    if hasRestoredScroll { hasScrolled = true }
                }
            )
            .onPreferenceChange(ParagraphFramesKey.self) { frames in
                guard hasRestoredScroll, hasScrolled, !frames.isEmpty else { return }
                let nearest = frames.min { abs($0.value) < abs($1.value) }?.key ?? 0
                if currentParagraph != nearest {
                    currentParagraph = nearest
                    currentOffset = 0
                    if nativePlan != nil {
                        pageIndex = nativePlan?.page(for: nearest, offset: 0) ?? 0
                    }
                    store.recordProgress(for: chapter, paragraph: nearest)
                }
            }
            .onAppear {
                guard !hasRestoredScroll else { return }
                let location = currentParagraph
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                    proxy.scrollTo(location, anchor: .top)
                    hasRestoredScroll = true
                }
            }
        }
    }

    // MARK: - One-line, always-visible info footer

    private var informationFooter: some View {
        TimelineView(.periodic(from: .now, by: 20)) { context in
            let total = max(1, nativePlan?.pageCount ?? 1)
            let current = min(pageIndex + 1, total)
            let percent = readingMode == "pages"
                ? (nativePlan?.location(at: pageIndex).percent ?? store.progress(for: chapter.id).percent)
                : store.progress(for: chapter.id).percent

            let percentText = String(
                format: "%.2f",
                locale: Locale(identifier: "ru_RU"),
                min(100, max(0, percent))
            )
            let clock = context.date.formatted(date: .omitted, time: .shortened)

            Text("\(current)/\(total) стр.  •  \(percentText)%  •  \(clock)")
                .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(palette.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(
                    "Страница \(current) из \(total), прочитано \(percentText) процентов, время \(clock)"
                )
        }
        .frame(height: 29)
        .frame(maxWidth: .infinity)
        .background(pageBackground)
    }

    // MARK: - Imported notes and highlights in scrolling mode

    private func highlightedText(_ paragraph: ReaderParagraph) -> Text {
        let scalars = Array(paragraph.text.unicodeScalars)
        let length = scalars.count
        guard length > 0 else { return Text(" ") }

        var boundaries = Set([0, length])
        var ranges: [(Int, Int)] = []
        for note in annotations(at: paragraph.index) {
            let last = max(note.paragraph, note.endParagraph ?? note.paragraph)
            let lower = min(max(0, paragraph.index == note.paragraph ? note.start : 0), length)
            let upper = min(max(0, paragraph.index == last ? note.end : length), length)
            guard lower < upper else { continue }
            boundaries.insert(lower)
            boundaries.insert(upper)
            ranges.append((lower, upper))
        }

        let cuts = boundaries.sorted()
        var result = AttributedString()
        for i in 0..<(cuts.count - 1) {
            let lower = cuts[i], upper = cuts[i + 1]
            guard upper > lower else { continue }
            let content = String(String.UnicodeScalarView(scalars[lower..<upper]))
            var fragment = AttributedString(content)
            fragment.foregroundColor = palette.text.opacity(0.93)
            if ranges.contains(where: { $0.0 <= lower && $0.1 >= upper }) {
                fragment.backgroundColor = palette.noteTint
            }
            result.append(fragment)
        }
        return Text(result)
    }

    private func annotations(at index: Int) -> [ReaderAnnotation] {
        linkedAnnotations.filter { note in
            guard note.status != "needs_review" else { return false }
            let end = max(note.paragraph, note.endParagraph ?? note.paragraph)
            return note.paragraph <= index && index <= end
        }
    }

    private func noteColor(_ category: String) -> Color {
        switch category {
        case "Канон": return .orange
        case "Сюжет": return .red
        case "Стиль": return .blue
        case "Цитата": return .green
        default: return palette.accent
        }
    }

    private func annotationSheet(_ item: ReaderAnnotation) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    Text(item.categoryTitle.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(noteColor(item.categoryTitle))
                    if !item.quote.isEmpty {
                        Text("«\(item.quote)»")
                            .font(.system(size: 16, design: .serif))
                            .textSelection(.enabled)
                    }
                    if !item.note.isEmpty {
                        Text(item.note)
                            .font(.system(size: 14))
                            .textSelection(.enabled)
                    }
                    Text("Абзац \(item.paragraph + 1)")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.secondary)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(pageBackground.ignoresSafeArea())
            .navigationTitle("Замечание")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Закрыть") { selectedAnnotation = nil }
                }
            }
        }
        .preferredColorScheme(palette.colorScheme)
    }
}

private struct NotePills: View {
    @Environment(\.readerPalette) private var palette
    let notes: [ReaderAnnotation]
    let onSelect: (ReaderAnnotation) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(notes) { note in
                    Button {
                        onSelect(note)
                    } label: {
                        Label(note.categoryTitle, systemImage: "quote.bubble")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(palette.accent)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(palette.surfaceHigh, in: Capsule())
                    }
                }
            }
        }
    }
}

private struct ReaderSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.readerPalette) private var palette
    @Binding var fontSize: Double
    @Binding var lineSpacing: Double
    @Binding var paragraphSpacing: Double
    @Binding var readingMode: String
    @Binding var colorThemeID: String

    var body: some View {
        NavigationStack {
            Form {
                Section("Режим чтения") {
                    Picker("Режим", selection: $readingMode) {
                        Text("Страницы").tag("pages")
                        Text("Прокрутка").tag("scroll")
                    }
                    .pickerStyle(.segmented)

                    Text("В режиме страниц нажимай по краям экрана для перелистывания, по центру — для меню. Нижняя информационная строка всегда остаётся на месте.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Section {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ], spacing: 10) {
                        ForEach(ReaderColorTheme.allCases) { theme in
                            Button {
                                colorThemeID = theme.rawValue
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("Аа")
                                            .font(.system(size: 22, weight: .medium, design: .serif))
                                            .foregroundStyle(theme.palette.text)
                                        Spacer()
                                        if colorThemeID == theme.rawValue {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(theme.palette.accent)
                                        }
                                    }
                                    Text(theme.title)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(theme.palette.text)
                                    Text(theme.subtitle)
                                        .font(.system(size: 10))
                                        .foregroundStyle(theme.palette.secondary)
                                        .lineLimit(2)
                                        .minimumScaleFactor(0.75)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(height: 95)
                                .padding(12)
                                .background(
                                    theme.palette.background,
                                    in: RoundedRectangle(cornerRadius: 13)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 13)
                                        .strokeBorder(
                                            colorThemeID == theme.rawValue
                                                ? theme.palette.accent
                                                : theme.palette.hairline,
                                            lineWidth: colorThemeID == theme.rawValue ? 2 : 1
                                        )
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Тема \(theme.title)")
                            .accessibilityAddTraits(
                                colorThemeID == theme.rawValue ? [.isSelected] : []
                            )
                        }
                    }
                    .padding(.vertical, 5)
                } header: {
                    Text("Цветовая тема")
                } footer: {
                    Text("«Сумерки» — тёмный фон и приглушённый текст для вечернего чтения. Выбор сохраняется автоматически.")
                }

                Section("Оформление текста") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Размер шрифта")
                            Spacer()
                            Text("\(Int(fontSize))")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $fontSize, in: 14...24, step: 1)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Межстрочный интервал")
                            Spacer()
                            Text("\(Int(lineSpacing))")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $lineSpacing, in: 1...10, step: 1)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Расстояние между абзацами")
                            Spacer()
                            Text("\(Int(paragraphSpacing))")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $paragraphSpacing, in: 8...24, step: 1)
                    }
                }

                Section {
                    Button("Сбросить оформление") {
                        fontSize = 17
                        lineSpacing = 4
                        paragraphSpacing = 13
                    }
                    .foregroundStyle(palette.accent)
                }
            }
            .tint(palette.accent)
            .navigationTitle("Чтение и оформление")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .preferredColorScheme(palette.colorScheme)
    }
}
