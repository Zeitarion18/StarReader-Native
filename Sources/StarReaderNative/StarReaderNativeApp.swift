import SwiftUI

@main
struct StarReaderNativeApp: App {
    @StateObject private var library = LibraryStore()

    var body: some Scene {
        WindowGroup {
            LibraryView(store: library)
                .preferredColorScheme(.dark)
                .environment(\.locale, Locale(identifier: "ru_RU"))
        }
    }
}
