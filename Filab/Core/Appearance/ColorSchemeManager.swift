import SwiftUI
import Combine

// MARK: - Color Scheme Manager

@MainActor
final class ColorSchemeManager: ObservableObject {
    static let shared = ColorSchemeManager()

    @AppStorage("isDarkMode") var isDarkMode: Bool = true {
        didSet {
            updateColorScheme()
        }
    }

    @Published var colorScheme: ColorScheme = .dark

    init() {
        updateColorScheme()
    }

    private func updateColorScheme() {
        colorScheme = isDarkMode ? .dark : .light
    }
}

// MARK: - App Theme Modifier

struct AppThemeModifier: ViewModifier {
    @ObservedObject var manager = ColorSchemeManager.shared

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(manager.colorScheme)
    }
}

extension View {
    func appTheme() -> some View {
        self.modifier(AppThemeModifier())
    }
}
