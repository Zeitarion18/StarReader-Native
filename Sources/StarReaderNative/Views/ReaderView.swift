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

    @State private var currentParagraph = 0
    @State private var didRestorePosition = false

    private let pageBackground = Color(red: 0.035, green: 0.045, blue: 0.075)

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(chapter.displayTitle)
                        .font(.system(size: 27, weight: .semibold, design: .serif))
                        .foregroundStyle(.white)
                        .padding(.bottom, 8)

                    ForEach(chapter.paragraphs) { paragraph in
                        Text(paragraph.text)
                            .font(.system(size: paragraph.heading ? 21 : 19, weight: paragraph.heading ? .semibold : .regular, design: .serif))
                            .foregroundStyle(paragraph.heading ? Color.cyan.opacity(0.95) : Color.white.opacity(0.88))
                            .lineSpacing(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
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
                .padding(.horizontal, 25)
                .padding(.top, 28)
                .padding(.bottom, 48)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .coordinateSpace(name: "readerScroll")
            .background(pageBackground)
            .onPreferenceChange(ParagraphFramesKey.self) { frames in
                guard didRestorePosition, !frames.isEmpty else { return }
                let nearest = frames.min { abs($0.value) < abs($1.value) }?.key ?? 0
                currentParagraph = nearest
                store.recordProgress(for: chapter, paragraph: nearest)
            }
            .onAppear {
                guard !didRestorePosition else { return }
                didRestorePosition = true
                let saved = store.progress(for: chapter.id)
                currentParagraph = min(saved.paragraph, max(0, chapter.paragraphs.count - 1))
                DispatchQueue.main.async {
                    proxy.scrollTo(currentParagraph, anchor: .top)
                    didRestorePosition = true
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                footer
            }
        }
        .background(pageBackground.ignoresSafeArea())
        .navigationTitle(chapter.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(pageBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private var footer: some View {
        HStack {
            Text("\(min(currentParagraph + 1, max(1, chapter.paragraphs.count))) / \(chapter.paragraphs.count) абз.")
            Spacer()
            Text(store.progress(for: chapter.id).percent.formatted(.number.precision(.fractionLength(1))) + "%")
        }
        .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
        .foregroundStyle(.white.opacity(0.55))
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(.white.opacity(0.07)).frame(height: 1)
        }
    }
}
