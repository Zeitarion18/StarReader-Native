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

    @State private var currentParagraph = 0
    @State private var didRestorePosition = false
    @State private var hasScrolled = false
    @State private var controlsVisible = true
    @State private var showReaderSettings = false
    @State private var selectedAnnotation: ReaderAnnotation?

    private let pageBackground = ReaderTheme.background

    private var linkedAnnotations: [ReaderAnnotation] {
        store.annotations(for: chapter.id)
    }

    var body: some View {
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
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: ParagraphFramesKey.self,
                                    value: [
                                        paragraph.index:
                                            geometry.frame(in: .named("readerScroll")).minY
                                    ]
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 36)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        controlsVisible.toggle()
                    }
                }
            }
            .scrollIndicators(.hidden)
            .coordinateSpace(name: "readerScroll")
            .simultaneousGesture(
                DragGesture(minimumDistance: 5).onChanged { _ in
                    if didRestorePosition { hasScrolled = true }
                }
            )
            .background(pageBackground)
            .onPreferenceChange(ParagraphFramesKey.self) { frames in
                guard didRestorePosition, hasScrolled, !frames.isEmpty else { return }
                let nearest = frames.min { abs($0.value) < abs($1.value) }?.key ?? 0
                if currentParagraph != nearest {
                    currentParagraph = nearest
                    store.recordProgress(for: chapter, paragraph: nearest)
                }
            }
            .onAppear {
                guard !didRestorePosition else { return }
                let saved = store.progress(for: chapter.id)
                let destination = jump?.paragraph ?? saved.paragraph
                currentParagraph = min(max(0, destination), max(0, chapter.paragraphs.count - 1))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    proxy.scrollTo(currentParagraph, anchor: .top)
                    didRestorePosition = true
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                progressFooter
            }
        }
        .background(pageBackground.ignoresSafeArea())
        .navigationTitle("Чтение")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                ReaderBackButton()
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    store.addBookmark(for: chapter, paragraph: currentParagraph)
                } label: {
                    Image(systemName: store.hasBookmark(
                        chapterID: chapter.id,
                        paragraph: currentParagraph
                    ) ? "bookmark.fill" : "bookmark")
                }
                .accessibilityLabel("Добавить закладку")

                Button {
                    showReaderSettings = true
                } label: {
                    Image(systemName: "textformat.size")
                }
                .accessibilityLabel("Настройки чтения")

                NavigationLink {
                    NotesAndBookmarksView(store: store)
                } label: {
                    Image(systemName: "text.book.closed")
                }
                .accessibilityLabel("Замечания и закладки")
            }
        }
        .toolbar(controlsVisible ? .visible : .hidden, for: .navigationBar)
        .toolbarBackground(pageBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .sheet(isPresented: $showReaderSettings) {
            ReaderSettingsSheet(
                fontSize: $fontSize,
                lineSpacing: $lineSpacing,
                paragraphSpacing: $paragraphSpacing
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedAnnotation) { item in
            annotationSheet(item)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    /// Preserve old StarReader's Unicode-scalar highlighting boundaries.
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
        var result = Text("")
        if cuts.count >= 2 {
            for index in 0..<(cuts.count - 1) {
                let start = cuts[index], end = cuts[index + 1]
                guard end > start else { continue }
                let part = String(String.UnicodeScalarView(scalars[start..<end]))
                var fragment = Text(part).foregroundColor(ReaderTheme.text.opacity(0.93))
                if let match = ranges.first(where: { $0.0 <= start && $0.1 >= end }) {
                    fragment = Text(part).foregroundColor(categoryColor(match.2)).underline()
                }
                result = result + fragment
            }
        }
        return result
    }

    private func annotations(at index: Int) -> [ReaderAnnotation] {
        linkedAnnotations.filter { note in
            let end = max(note.paragraph, note.endParagraph ?? note.paragraph)
            return note.paragraph <= index && index <= end
        }
    }

    private func categoryColor(_ category: String) -> Color {
        switch category {
        case "Канон": return .orange
        case "Сюжет": return .red
        case "Стиль": return .blue
        case "Цитата": return .green
        default: return ReaderTheme.accent
        }
    }

    private var progressFooter: some View {
        HStack(spacing: 7) {
            Text("\(min(currentParagraph + 1, max(1, chapter.paragraphs.count)))/\(chapter.paragraphs.count) абз.")
            Spacer(minLength: 5)
            Text(store.progress(for: chapter.id).percent.formatted(
                .number.precision(.fractionLength(2))
            ) + "%")
            Spacer(minLength: 5)
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(context.date.formatted(date: .omitted, time: .shortened))
            }
        }
        .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
        .foregroundStyle(ReaderTheme.secondary)
        .padding(.horizontal, 18)
        .frame(height: controlsVisible ? 37 : 29)
        .background(ReaderTheme.background.opacity(0.97))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(controlsVisible ? 0.07 : 0))
                .frame(height: 1)
        }
    }

    private func annotationSheet(_ item: ReaderAnnotation) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    Text(item.categoryTitle.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(categoryColor(item.categoryTitle))
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
            .background(ReaderTheme.background.ignoresSafeArea())
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

    var body: some View {
        NavigationStack {
            Form {
                Section("Текст") {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Label("Размер шрифта", systemImage: "textformat.size")
                            Spacer()
                            Text("\(Int(fontSize))")
                                .foregroundStyle(ReaderTheme.secondary)
                        }
                        Slider(value: $fontSize, in: 14...24, step: 1)
                            .tint(ReaderTheme.accent)
                    }
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text("Межстрочный интервал")
                            Spacer()
                            Text("\(Int(lineSpacing))")
                                .foregroundStyle(ReaderTheme.secondary)
                        }
                        Slider(value: $lineSpacing, in: 1...10, step: 1)
                            .tint(ReaderTheme.accent)
                    }
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text("Расстояние между абзацами")
                            Spacer()
                            Text("\(Int(paragraphSpacing))")
                                .foregroundStyle(ReaderTheme.secondary)
                        }
                        Slider(value: $paragraphSpacing, in: 8...24, step: 1)
                            .tint(ReaderTheme.accent)
                    }
                }

                Section {
                    Text("Настройки применяются сразу и сохраняются на этом устройстве. Переключение между страницами и прокруткой появится в следующем этапе.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("Сбросить настройки текста") {
                        fontSize = 17
                        lineSpacing = 4
                        paragraphSpacing = 13
                    }
                    .foregroundStyle(ReaderTheme.accent)
                }
            }
            .navigationTitle("Оформление чтения")
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
