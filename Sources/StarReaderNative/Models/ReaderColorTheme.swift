import Foundation
import SwiftUI
import UIKit

enum ReaderColorTheme: String, CaseIterable, Identifiable {
    case dark, twilight, light, sepia, oled
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dark: return "Тёмная"
        case .twilight: return "Сумерки"
        case .light: return "Светлая"
        case .sepia: return "Сепия"
        case .oled: return "AMOLED"
        }
    }
    var subtitle: String {
        switch self {
        case .dark: return "Классическая"
        case .twilight: return "Приглушённый текст"
        case .light: return "Дневное чтение"
        case .sepia: return "Тёплая бумага"
        case .oled: return "Чёрный OLED"
        }
    }
    var colorScheme: ColorScheme {
        self == .light || self == .sepia ? .light : .dark
    }
    var palette: ReaderPalette { ReaderPalette(theme: self) }
}

struct ReaderPalette {
    let theme: ReaderColorTheme
    let uiBackground: UIColor
    let uiSurface: UIColor
    let uiSurfaceHigh: UIColor
    let uiAccent: UIColor
    let uiText: UIColor
    let uiSecondary: UIColor
    let uiHairline: UIColor
    let uiOnAccent: UIColor
    let uiNoteTint: UIColor
    let uiNoteRail: UIColor

    init(theme: ReaderColorTheme) {
        self.theme = theme
        switch theme {
        case .dark:
            uiBackground = UIColor(red: 0.035, green: 0.045, blue: 0.075, alpha: 1)
            uiSurface = UIColor(red: 0.085, green: 0.105, blue: 0.15, alpha: 1)
            uiSurfaceHigh = UIColor(red: 0.11, green: 0.14, blue: 0.20, alpha: 1)
            uiAccent = UIColor(red: 0.36, green: 0.85, blue: 0.91, alpha: 1)
            uiText = UIColor(red: 0.94, green: 0.96, blue: 1, alpha: 1)
            uiSecondary = UIColor(red: 0.59, green: 0.65, blue: 0.76, alpha: 1)
            uiHairline = UIColor.white.withAlphaComponent(0.075)
            uiOnAccent = UIColor(red: 0.035, green: 0.045, blue: 0.075, alpha: 1)
            uiNoteTint = UIColor(red: 1, green: 0.59, blue: 0.25, alpha: 0.19)
            uiNoteRail = UIColor(red: 1, green: 0.59, blue: 0.25, alpha: 0.96)
        case .twilight:
            // Soft low-contrast warm gray on charcoal for late-night reading.
            uiBackground = UIColor(red: 0.079, green: 0.082, blue: 0.090, alpha: 1)
            uiSurface = UIColor(red: 0.115, green: 0.120, blue: 0.128, alpha: 1)
            uiSurfaceHigh = UIColor(red: 0.145, green: 0.151, blue: 0.162, alpha: 1)
            uiAccent = UIColor(red: 0.68, green: 0.62, blue: 0.52, alpha: 1)
            uiText = UIColor(red: 0.68, green: 0.66, blue: 0.62, alpha: 1)
            uiSecondary = UIColor(red: 0.53, green: 0.52, blue: 0.49, alpha: 1)
            uiHairline = UIColor.white.withAlphaComponent(0.07)
            uiOnAccent = UIColor(red: 0.079, green: 0.082, blue: 0.090, alpha: 1)
            uiNoteTint = UIColor(red: 0.82, green: 0.57, blue: 0.36, alpha: 0.17)
            uiNoteRail = UIColor(red: 0.81, green: 0.54, blue: 0.32, alpha: 0.85)
        case .light:
            uiBackground = UIColor(red: 0.973, green: 0.975, blue: 0.978, alpha: 1)
            uiSurface = UIColor.white
            uiSurfaceHigh = UIColor(red: 0.931, green: 0.944, blue: 0.949, alpha: 1)
            uiAccent = UIColor(red: 0.075, green: 0.47, blue: 0.57, alpha: 1)
            uiText = UIColor(red: 0.13, green: 0.17, blue: 0.22, alpha: 1)
            uiSecondary = UIColor(red: 0.38, green: 0.43, blue: 0.47, alpha: 1)
            uiHairline = UIColor.black.withAlphaComponent(0.10)
            uiOnAccent = UIColor.white
            uiNoteTint = UIColor(red: 1.0, green: 0.65, blue: 0.22, alpha: 0.27)
            uiNoteRail = UIColor(red: 0.82, green: 0.39, blue: 0.08, alpha: 1)
        case .sepia:
            uiBackground = UIColor(red: 0.955, green: 0.917, blue: 0.843, alpha: 1)
            uiSurface = UIColor(red: 0.982, green: 0.949, blue: 0.879, alpha: 1)
            uiSurfaceHigh = UIColor(red: 0.905, green: 0.844, blue: 0.742, alpha: 1)
            uiAccent = UIColor(red: 0.52, green: 0.31, blue: 0.18, alpha: 1)
            uiText = UIColor(red: 0.30, green: 0.23, blue: 0.17, alpha: 1)
            uiSecondary = UIColor(red: 0.46, green: 0.37, blue: 0.28, alpha: 1)
            uiHairline = UIColor.black.withAlphaComponent(0.13)
            uiOnAccent = UIColor.white
            uiNoteTint = UIColor(red: 0.93, green: 0.53, blue: 0.18, alpha: 0.22)
            uiNoteRail = UIColor(red: 0.70, green: 0.34, blue: 0.14, alpha: 1)
        case .oled:
            uiBackground = UIColor.black
            uiSurface = UIColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)
            uiSurfaceHigh = UIColor(red: 0.12, green: 0.12, blue: 0.13, alpha: 1)
            uiAccent = UIColor(red: 0.53, green: 0.82, blue: 0.85, alpha: 1)
            uiText = UIColor(red: 0.80, green: 0.83, blue: 0.85, alpha: 1)
            uiSecondary = UIColor(red: 0.56, green: 0.58, blue: 0.61, alpha: 1)
            uiHairline = UIColor.white.withAlphaComponent(0.12)
            uiOnAccent = UIColor.black
            uiNoteTint = UIColor(red: 1, green: 0.59, blue: 0.25, alpha: 0.20)
            uiNoteRail = UIColor(red: 1, green: 0.59, blue: 0.25, alpha: 0.95)
        }
    }
    var background: Color { Color(uiColor: uiBackground) }
    var surface: Color { Color(uiColor: uiSurface) }
    var surfaceHigh: Color { Color(uiColor: uiSurfaceHigh) }
    var accent: Color { Color(uiColor: uiAccent) }
    var text: Color { Color(uiColor: uiText) }
    var secondary: Color { Color(uiColor: uiSecondary) }
    var hairline: Color { Color(uiColor: uiHairline) }
    var onAccent: Color { Color(uiColor: uiOnAccent) }
    var noteTint: Color { Color(uiColor: uiNoteTint) }
    var noteRail: Color { Color(uiColor: uiNoteRail) }
    var colorScheme: ColorScheme { theme.colorScheme }
}

private struct ReaderPaletteKey: EnvironmentKey {
    static let defaultValue = ReaderColorTheme.dark.palette
}
extension EnvironmentValues {
    var readerPalette: ReaderPalette {
        get { self[ReaderPaletteKey.self] }
        set { self[ReaderPaletteKey.self] = newValue }
    }
}
