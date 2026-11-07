import SwiftUI

enum ReaderTheme {
    static let background = Color(red: 0.035, green: 0.045, blue: 0.075)
    static let surface = Color(red: 0.085, green: 0.105, blue: 0.15)
    static let surfaceHigh = Color(red: 0.11, green: 0.14, blue: 0.20)
    static let accent = Color(red: 0.36, green: 0.85, blue: 0.91)
    static let text = Color(red: 0.94, green: 0.96, blue: 1.0)
    static let secondary = Color(red: 0.59, green: 0.65, blue: 0.76)
    static let hairline = Color.white.opacity(0.075)
}

struct BookCover: View {
    let title: String
    var index: Int = 0
    var compact = false

    private var palette: [Color] {
        let palettes: [[Color]] = [
            [Color(red: 0.13, green: 0.27, blue: 0.46), Color(red: 0.07, green: 0.65, blue: 0.76)],
            [Color(red: 0.32, green: 0.18, blue: 0.48), Color(red: 0.54, green: 0.34, blue: 0.72)],
            [Color(red: 0.12, green: 0.37, blue: 0.37), Color(red: 0.16, green: 0.64, blue: 0.59)],
            [Color(red: 0.36, green: 0.23, blue: 0.28), Color(red: 0.71, green: 0.40, blue: 0.32)]
        ]
        return palettes[abs(index % palettes.count)]
    }

    var body: some View {
        ZStack(alignment: .leading) {
            LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing)

            Circle()
                .strokeBorder(Color.white.opacity(0.13), lineWidth: 1)
                .frame(width: compact ? 58 : 85, height: compact ? 58 : 85)
                .offset(x: compact ? 24 : 38, y: compact ? -26 : -36)

            VStack(alignment: .leading, spacing: compact ? 6 : 10) {
                Image(systemName: "sparkle")
                    .font(.system(size: compact ? 15 : 22, weight: .light))
                    .foregroundStyle(Color.white.opacity(0.95))
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.80))
                    .frame(width: compact ? 21 : 32, height: 2)
                Text(title)
                    .font(.system(size: compact ? 8 : 10, weight: .semibold, design: .serif))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.leading)
            }
            .padding(compact ? 9 : 13)
        }
        .frame(width: compact ? 68 : 91, height: compact ? 94 : 128)
        .clipShape(RoundedRectangle(cornerRadius: compact ? 9 : 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: compact ? 9 : 12)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: palette[0].opacity(0.3), radius: 11, y: 5)
        .accessibilityHidden(true)
    }
}

struct ReaderSurface<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(ReaderTheme.surface, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 19)
                    .strokeBorder(ReaderTheme.hairline, lineWidth: 1)
            }
    }
}

struct ReaderBackButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button {
            dismiss()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                Text("Назад")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(ReaderTheme.accent)
        }
        .accessibilityLabel("Назад")
    }
}
