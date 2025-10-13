import SwiftUI

enum Theme {
    // Colors
    static let primaryColor = Color.accentColor
    static let secondaryColor = Color.secondary
    static let primaryGradientStart = Color(red: 1.0, green: 0.69, blue: 0.33)
    static let primaryGradientEnd = Color(red: 0.988, green: 0.416, blue: 0.012)
    static let appBackground = Color("AppBackground")
    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
    static let elevatedCardBackground = Color(uiColor: .tertiarySystemGroupedBackground)
    static let highlightedCardBackground = Color(uiColor: .systemFill)

    // Spacing
    static let spacingSmall: CGFloat = 8
    static let spacingMedium: CGFloat = 16
    static let spacingLarge: CGFloat = 24
    static let spacingXLarge: CGFloat = 32

    // Typography helpers
    static func headlineFont() -> Font { .title2.weight(.semibold) }
    static func bodyFont() -> Font { .body }
}
