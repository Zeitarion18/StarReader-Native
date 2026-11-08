import SwiftUI

@main
struct StarReaderNativeApp: App {
    @StateObject private var library = LibraryStore()
    @AppStorage("starreader.colorTheme") private var themeID = ReaderColorTheme.dark.rawValue

    private var theme: ReaderColorTheme {
        ReaderColorTheme(rawValue: themeID) ?? .dark
    }

    var body: some Scene {
        WindowGroup {
            LibraryView(store: library)
                .environment(\.readerPalette, theme.palette)
                .preferredColorScheme(theme.colorScheme)
                .tint(theme.palette.accent)
                .environment(\.locale, Locale(identifier: "ru_RU"))
        }
    }
}
