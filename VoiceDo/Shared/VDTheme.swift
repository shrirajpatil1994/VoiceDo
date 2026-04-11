import SwiftUI

// MARK: - VoiceDo Design Tokens
//
// Palette: creamy-white background, near-black ink, neutral grays.
// No hue-based accent colours anywhere in the app.

extension Color {
    /// Warm cream — app background
    static let vdBackground = Color(red: 0.969, green: 0.957, blue: 0.937)
    /// Pure white — card / surface
    static let vdCard = Color.white
    /// Near-black — primary text, filled buttons
    static let vdInk = Color(white: 0.08)
    /// Medium gray — secondary text
    static let vdMuted = Color(white: 0.52)
    /// Light gray — borders, dividers
    static let vdBorder = Color(white: 0.86)
    /// Very light gray — subtle backgrounds inside cards
    static let vdSubtle = Color(white: 0.94)
}

// MARK: - Shared Modifiers

extension View {
    /// Standard card surface: white, rounded, thin border.
    func vdCard(cornerRadius: CGFloat = 14) -> some View {
        self
            .background(Color.vdCard, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.vdBorder, lineWidth: 0.5)
            )
    }

    /// Full-width filled black button style body.
    func vdPrimaryButton() -> some View {
        self
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.vdInk, in: RoundedRectangle(cornerRadius: 14))
    }

    /// Outlined button style body.
    func vdSecondaryButton() -> some View {
        self
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Color.vdInk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Color.vdCard, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.vdBorder, lineWidth: 1)
            )
    }
}
