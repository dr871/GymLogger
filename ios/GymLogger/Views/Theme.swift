import SwiftUI

// Dark, high contrast, big targets — designed for a phone held one-handed in
// bad gym lighting with damp fingers.
enum Palette {
    static let bg = Color(hex: 0x101216)
    static let surface = Color(hex: 0x191C22)
    static let surface2 = Color(hex: 0x21252E)
    static let line = Color(hex: 0x2C313C)
    static let text = Color(hex: 0xEEF1F6)
    static let muted = Color(hex: 0x8D95A5)
    static let ghost = Color(hex: 0x5D6675)
    static let accent = Color(hex: 0x4ADE80)
    static let accentInk = Color(hex: 0x06240F)
    static let warn = Color(hex: 0xFBBF24)
    static let danger = Color(hex: 0xF87171)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

enum Metrics {
    /// Nothing tappable goes below this.
    static let tap: CGFloat = 52
    static let radius: CGFloat = 14
}

struct CardBackground: ViewModifier {
    var dimmed = false
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                    .stroke(Palette.line, lineWidth: 1)
            )
            .opacity(dimmed ? 0.62 : 1)
    }
}

extension View {
    func card(dimmed: Bool = false) -> some View { modifier(CardBackground(dimmed: dimmed)) }
}

/// Pill button used for secondary actions.
struct ChipStyle: ButtonStyle {
    var tint: Color = Palette.text
    var filled = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: filled ? .semibold : .regular))
            .foregroundColor(filled ? Palette.accentInk : tint)
            .padding(.horizontal, 15)
            .frame(minHeight: 46)
            .background(filled ? Palette.accent : Palette.surface2)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(filled ? Color.clear : Palette.line, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Full-width action button.
struct BigButtonStyle: ButtonStyle {
    var primary = false
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, alignment: primary ? .leading : .center)
            .padding(primary ? 20 : 14)
            .frame(minHeight: primary ? 84 : Metrics.tap)
            .background(primary ? Palette.accent : Palette.surface)
            .foregroundColor(primary ? Palette.accentInk : (destructive ? Palette.danger : Palette.text))
            .clipShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                    .stroke(primary ? Color.clear : Palette.line, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
