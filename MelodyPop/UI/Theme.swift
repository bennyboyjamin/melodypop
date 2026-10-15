import UIKit
import SwiftUI

/// MelodyPop's palette: lavender, mint, peach and cream.
enum Theme {
    static let lavender = Color(hex: 0xB9A5F2)
    static let lavenderSoft = Color(hex: 0xE9E1FF)
    static let lavenderDeep = Color(hex: 0x6E55C8)
    static let mint = Color(hex: 0xA6E8D0)
    static let mintSoft = Color(hex: 0xDDF7EC)
    static let mintDeep = Color(hex: 0x2E9C78)
    static let peach = Color(hex: 0xFFC6A6)
    static let peachSoft = Color(hex: 0xFFE7DA)
    static let peachDeep = Color(hex: 0xE4774A)
    static let cream = Color(hex: 0xFFF8EC)
    static let creamDeep = Color(hex: 0xF5EAD6)
    static let ink = Color(hex: 0x3B2F5E)
    static let inkSoft = Color(hex: 0x7A6F99)
    static let berry = Color(hex: 0xE0607E)

    static func accent(named name: String) -> Color {
        switch name {
        case "mint": return mint
        case "peach": return peach
        default: return lavender
        }
    }

    static func deep(named name: String) -> Color {
        switch name {
        case "mint": return mintDeep
        case "peach": return peachDeep
        default: return lavenderDeep
        }
    }

    static func font(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .rounded).weight(weight)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

struct CardBackground: ViewModifier {
    var color: Color = .white
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(color, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Theme.lavenderDeep.opacity(0.08), radius: 10, y: 4)
    }
}

extension View {
    func card(_ color: Color = .white) -> some View { modifier(CardBackground(color: color)) }

    func screenBackground() -> some View {
        background(Theme.cream.ignoresSafeArea())
    }
}

struct PopButtonStyle: ButtonStyle {
    var color: Color = Theme.lavenderDeep
    var foreground: Color = .white
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(compact ? .subheadline : .headline, weight: .bold))
            .foregroundStyle(foreground)
            .padding(.horizontal, compact ? 14 : 22)
            .padding(.vertical, compact ? 8 : 14)
            .background(color, in: Capsule())
            .shadow(color: color.opacity(0.35), radius: configuration.isPressed ? 2 : 6, y: configuration.isPressed ? 1 : 4)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct StarRow: View {
    var stars: Int
    var size: CGFloat = 16
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                Image(systemName: i < stars ? "star.fill" : "star")
                    .font(.system(size: size, weight: .bold))
                    .foregroundStyle(i < stars ? Theme.peachDeep : Theme.inkSoft.opacity(0.35))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(stars) of 3 stars")
    }
}

/// Pip, MelodyPop's original mascot: a round lavender music-bean with a note-flag sprout.
struct PipMascot: View {
    var size: CGFloat = 80
    var mood: Mood = .happy
    enum Mood { case happy, cheering, thinking }

    var body: some View {
        ZStack {
            // Flag sprout
            Path { p in
                p.move(to: CGPoint(x: size * 0.55, y: size * 0.12))
                p.addLine(to: CGPoint(x: size * 0.55, y: -size * 0.12))
                p.addQuadCurve(to: CGPoint(x: size * 0.78, y: size * 0.02), control: CGPoint(x: size * 0.8, y: -size * 0.12))
            }
            .stroke(Theme.ink, style: StrokeStyle(lineWidth: size * 0.05, lineCap: .round))
            Circle()
                .fill(LinearGradient(colors: [Theme.lavenderSoft, Theme.lavender], startPoint: .top, endPoint: .bottom))
                .overlay(Circle().stroke(Theme.lavenderDeep.opacity(0.4), lineWidth: size * 0.03))
                .frame(width: size, height: size * 0.92)
                .offset(y: size * 0.1)
            // Cheeks
            HStack(spacing: size * 0.42) {
                Circle().fill(Theme.peach).frame(width: size * 0.16)
                Circle().fill(Theme.peach).frame(width: size * 0.16)
            }
            .offset(y: size * 0.22)
            // Eyes
            HStack(spacing: size * 0.24) {
                eye
                eye
            }
            .offset(y: size * 0.08)
            // Mouth
            Path { p in
                let w = size * (mood == .cheering ? 0.24 : 0.16)
                p.move(to: CGPoint(x: -w / 2, y: 0))
                p.addQuadCurve(to: CGPoint(x: w / 2, y: 0), control: CGPoint(x: 0, y: mood == .thinking ? 0 : w * 0.7))
            }
            .stroke(Theme.ink, style: StrokeStyle(lineWidth: size * 0.04, lineCap: .round))
            .frame(width: 0, height: 0)
            .offset(y: size * 0.27)
        }
        .frame(width: size, height: size * 1.1)
        .accessibilityHidden(true)
    }

    private var eye: some View {
        Capsule()
            .fill(Theme.ink)
            .frame(width: size * 0.09, height: size * (mood == .cheering ? 0.06 : 0.13))
    }
}
