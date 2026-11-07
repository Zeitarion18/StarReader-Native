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

    @State private var currentParagraph = 0
    @State private var didRestorePosition = false
    @State private var hasScrolled = false
    @State private var selectedAnnotation: ReaderAnnotation?

    private let pageBackground = Color(red: 0.035, green: 0.045, blue: 0.075)

    private var linkedAnnotations: [ReaderAnnotation] {
        store.annotations(for: chapter.id)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(chapter.displayTitle)
                        .font(.system(size: 27, weight: .semibold, design: .serif))
                        .foregroundStyle(.white)
                        .padding(.bottom, 8)

                    ForEach(chapter.paragraphs) { paragraph in
                        VStack(alignment: .leading, spacing: 8) {
                            highlightedText(paragraph)
                                .font(.system(
                                    size: paragraph.heading ? 21 : 19,
                                    weight: paragraph.heading ? .semibold : .regular,
                                    design: .serif
                                ))
                                .lineSpacing(8)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            let notes = annotations(at: paragraph.index)
                            if !notes.isEmpty {
                                FlowNoteMarkers(notes: notes) { selectedAnnotation = $0 }
                            }
                        }
                        .id(paragraph.index)
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: ParagraphFramesKey.self,
                                    value: [paragraph.index: geometry.frame(in: .named("readerScroll")).minY]
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 23)
                .padding(.top, 26)
                .padding(.bottom, 46)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
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
                    // Only an actual user scroll changes the imported progress.
                    // Simply opening the chapter must not erase its stored offset.
                    store.recordProgress(for: chapter, paragraph: nearest)
                }
            }
            .onAppear {
                guard !didRestorePosition else { return }
                let saved = store.progress(for: chapter.id)
                let desired = jump?.paragraph ?? saved.paragraph
                currentParagraph = min(max(0, desired), max(0, chapter.paragraphs.count - 1))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    proxy.scrollTo(currentParagraph, anchor: .top)
                    didRestorePosition = true
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        }
        .background(pageBackground.ignoresSafeArea())
        .navigationTitle(chapter.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(pageBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    store.addBookmark(for: chapter, paragraph: currentParagraph)
                } label: {
                    Image(systemName: store.hasBookmark(chapterID: chapter.id, paragraph: currentParagraph)
                          ? "bookmark.fill" : "bookmark")
                }
                .accessibilityLabel("Добавить закладку")
                NavigationLink {
                    NotesAndBookmarksView(store: store)
                } label: {
                    Image(systemName: "text.book.closed")
                }
                .accessibilityLabel("Замечания и закладки")
            }
        }
        .sheet(item: $selectedAnnotation) { item in
            annotationSheet(item)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    /// The old app stores offsets as JS Unicode code points, not Swift grapheme clusters.
    /// Preserve those boundaries while coloring the exact imported note ranges.
    private func highlightedText(_ paragraph: ReaderParagraph) -> Text {
        let scalars = Array(paragraph.text.unicodeScalars)
        let length = scalars.count
        guard length > 0 else { return Text(" ") }

        let notes = annotations(at: paragraph.index)
        guard !notes.isEmpty else {
            return Text(paragraph.text).foregroundColor(.white.opacity(0.88))
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
                var fragment = Text(part).foregroundColor(.white.opacity(0.88))
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

    private func noteColor(_ kind: String) -> Color {
        switch kind {
        case "Канон": return .orange
        case "Сюжет": return .red
        case "Стиль": return .blue
        case "Цитата": return .green
        default: return .cyan
        }
    }

    private func annotationSheet(_ item: ReaderAnnotation) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(item.categoryTitle)
                        .font(.headline)
                        .foregroundStyle(noteColor(item.categoryTitle))
                    if !item.quote.isEmpty {
                        Text("«\(item.quote)»")
                            .font(.system(size: 17, design: .serif))
                            .textSelection(.enabled)
                    }
                    if !item.note.isEmpty {
                        Text(item.note).font(.body).textSelection(.enabled)
                    }
                    Text("Абзац \(item.paragraph + 1)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
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

    private var footer: some View {
        HStack(spacing: 8) {
            Text("\(min(currentParagraph + 1, max(1, chapter.paragraphs.count)))/\(chapter.paragraphs.count) абз.")
            Text("•")
            Text(store.progress(for: chapter.id).percent.formatted(
                .number.precision(.fractionLength(2))
            ) + "%")
            Text("•")
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(context.date.formatted(date: .omitted, time: .shortened))
            }
        }
        .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
        .foregroundStyle(.white.opacity(0.7))
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(.ultraThinMaterial)
    }
}

/// A compact native footnote link appears beneath paragraphs with imported notes.
private struct FlowNoteMarkers: View {
    let notes: [ReaderAnnotation]
    let onSelect: (ReaderAnnotation) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(notes) { note in
                    Button {
                        onSelect(note)
                    } label: {
                        Label(note.categoryTitle, systemImage: "text.bubble")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .foregroundStyle(.cyan)
                            .background(Color.cyan.opacity(0.10), in: Capsule())
                    }
                }
            }
        }
        .accessibilityLabel("Замечания к абзацу")
    }
}
