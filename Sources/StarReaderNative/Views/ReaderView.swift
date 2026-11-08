import SwiftUI

private struct ParagraphFramesKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct ReaderView: View {
    @ObservedObject var store: LibraryStore
    let chapter: LibraryChapter
    var jump: ReaderJump? = nil

    @AppStorage("starreader.fontSize") private var fontSize: Double = 17
    @AppStorage("starreader.lineSpacing") private var lineSpacing: Double = 4
    @AppStorage("starreader.paragraphSpacing") private var paragraphSpacing: Double = 13
    @AppStorage("starreader.readingMode") private var readingMode = "pages"

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

    private let pageBackground = ReaderTheme.background

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
                .onChange(of: readingMode) { _, _ in
                    hasRestoredScroll = false
                    hasScrolled = false
                    selectedText = nil
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
                .fill(ReaderTheme.hairline)
                .frame(height: 1)

            informationFooter
        }
        .background(pageBackground.ignoresSafeArea())
        // Keep the navigation bar in the layout even when its contents fade.
        // Hiding the bar itself changes GeometryReader height and repaginates.
        .navigationTitle(controlsVisible ? chapter.displayTitle : "")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                ReaderBackButton()
                    .opacity(controlsVisible ? 1 : 0)
                    .allowsHitTesting(controlsVisible)
                    .accessibilityHidden(!controlsVisible)
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
                .opacity(controlsVisible ? 1 : 0)
                .allowsHitTesting(controlsVisible)
                .accessibilityHidden(!controlsVisible)
                .accessibilityLabel("Добавить закладку")

                Button {
                    showReaderSettings = true
                } label: {
                    Image(systemName: "textformat.size")
                }
                .opacity(controlsVisible ? 1 : 0)
                .allowsHitTesting(controlsVisible)
                .accessibilityHidden(!controlsVisible)
                .accessibilityLabel("Оформление чтения")

                NavigationLink {
                    NotesAndBookmarksView(store: store)
                } label: {
                    Image(systemName: "text.book.closed")
                }
                .opacity(controlsVisible ? 1 : 0)
                .allowsHitTesting(controlsVisible)
                .accessibilityHidden(!controlsVisible)
                .accessibilityLabel("Замечания и закладки")
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
                readingMode: $readingMode
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedAnnotation) { item in
            annotationSheet(item)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
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
            let pageWidth = min(geometry.size.width - 36, 700)
            let pageHeight = geometry.size.height - 20

            HStack(spacing: 0) {
                Spacer(minLength: 0)

                if let plan = nativePlan {
                    NativeSelectablePage(
                        plan: plan,
                        pageIndex: plan.clamp(pageIndex),
                        onTurn: { direction in
                            changePage(by: direction)
                        },
                        onTapCenter: {
                            toggleControls()
                        },
                        onMakeNote: { selection in
                            composingSelection = selection
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
                        .tint(ReaderTheme.accent)
                        .font(.system(size: 13))
                        .foregroundStyle(ReaderTheme.secondary)
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
        let width = min(size.width - 36, 700)
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
            pageWidth: width,
            pageHeight: height,
            fontSize: fontSize,
            lineSpacing: lineSpacing,
            paragraphSpacing: paragraphSpacing
        )
        // Use TextKit for both page measurement and on-screen rendering.
        // Native UITextView selection handles use this exact same layout.
        let native = NativeTextPagePlan(
            source: next,
            pageWidth: width,
            pageHeight: height
        )
        pagination = next
        nativePlan = native
        pageIndex = native.page(for: targetParagraph, offset: targetOffset)
        currentParagraph = min(max(targetParagraph, 0), max(chapter.paragraphs.count - 1, 0))
        currentOffset = max(0, targetOffset)
        lastPageSize = CGSize(width: width, height: height)
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
        withAnimation(.easeInOut(duration: 0.2)) {
            controlsVisible.toggle()
        }
    }

    // MARK: - Optional continuous reading

    private var scrollingReader: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: paragraphSpacing) {
                    Text(chapter.displayTitle)
                        .font(.system(size: 21, weight: .semibold, design: .serif))
                        .foregroundStyle(ReaderTheme.text)
                        .padding(.bottom, 13)
                        .padding(.top, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(chapter.paragraphs) { paragraph in
                        VStack(alignment: .leading, spacing: 6) {
                            highlightedText(paragraph)
                                .font(.system(
                                    size: paragraph.heading ? fontSize + 2 : fontSize,
                                    weight: paragraph.heading ? .semibold : .regular,
                                    design: .serif
                                ))
                                .lineSpacing(lineSpacing)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            let notes = annotations(at: paragraph.index)
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
                .foregroundStyle(ReaderTheme.secondary)
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

        let notes = annotations(at: paragraph.index)
        guard !notes.isEmpty else {
            return Text(paragraph.text).foregroundColor(ReaderTheme.text.opacity(0.93))
        }

        var boundaries = Set([0, length])
        var ranges: [(Int, Int, String)] = []
        for item in notes {
            let lastParagraph = max(item.paragraph, item.endParagraph ?? item.paragraph)
            let start = paragraph.index == item.paragraph ? item.start : 0
            let end = paragraph.index == lastParagraph ? item.end : length
            let lower = min(max(0, start), length)
            let upper = min(max(0, end), length)
            if lower < upper {
                boundaries.insert(lower)
                boundaries.insert(upper)
                ranges.append((lower, upper, item.categoryTitle))
            }
        }

        let cuts = boundaries.sorted()
        var text = Text("")
        if cuts.count >= 2 {
            for index in 0..<(cuts.count - 1) {
                let left = cuts[index], right = cuts[index + 1]
                guard right > left else { continue }
                let part = String(String.UnicodeScalarView(scalars[left..<right]))
                var fragment = Text(part).foregroundColor(ReaderTheme.text.opacity(0.93))
                if let match = ranges.first(where: { $0.0 <= left && $0.1 >= right }) {
                    fragment = Text(part).foregroundColor(noteColor(match.2)).underline()
                }
                text = text + fragment
            }
        }
        return text
    }

    private func annotations(at index: Int) -> [ReaderAnnotation] {
        linkedAnnotations.filter { note in
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
        default: return ReaderTheme.accent
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
                        .foregroundStyle(ReaderTheme.secondary)
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
        .preferredColorScheme(.dark)
    }
}

private struct NotePills: View {
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
                            .foregroundStyle(ReaderTheme.accent)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(ReaderTheme.surfaceHigh, in: Capsule())
                    }
                }
            }
        }
    }
}

private struct ReaderSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var fontSize: Double
    @Binding var lineSpacing: Double
    @Binding var paragraphSpacing: Double
    @Binding var readingMode: String

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
                    .foregroundStyle(ReaderTheme.accent)
                }
            }
            .tint(ReaderTheme.accent)
            .navigationTitle("Чтение и оформление")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
