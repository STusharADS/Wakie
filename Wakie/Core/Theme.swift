//
//  Theme.swift
//  Wakie
//
//  Colors, fonts and decorative shapes shared across the app.
//

import SwiftUI
import UIKit

// MARK: - Colors

nonisolated extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

nonisolated extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(uiColor: UIColor(hex: hex, alpha: opacity))
    }

    /// A color that resolves differently in day (light) and night (dark) mode.
    static func dynamic(day: UInt32, night: UInt32, dayOpacity: CGFloat = 1, nightOpacity: CGFloat = 1) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: night, alpha: nightOpacity)
                : UIColor(hex: day, alpha: dayOpacity)
        })
    }
}

nonisolated enum Theme {
    // Backgrounds
    // TESTING: night background uses the Day/Night toggle's night-sky colour (#001120).
    // To revert, restore night: 0x17123A (top) and night: 0x261E58 (bottom).
    static let backgroundTop = Color.dynamic(day: 0xEDE4FF, night: 0x001120)
    static let backgroundBottom = Color.dynamic(day: 0xF8F4FF, night: 0x001120)

    // Surfaces
    static let card = Color.dynamic(day: 0xFFFFFF, night: 0x2E2766, dayOpacity: 0.82, nightOpacity: 0.92)
    static let cardStroke = Color.dynamic(day: 0xFFFFFF, night: 0x4B4296, dayOpacity: 0.9, nightOpacity: 0.6)
    /// Inner panels; translucent white at night so they sit softly on Liquid Glass.
    static let inset = Color.dynamic(day: 0xF1ECFF, night: 0xFFFFFF, nightOpacity: 0.08)
    static let lavenderPill = Color.dynamic(day: 0xDCCFFF, night: 0xFFFFFF, nightOpacity: 0.14)

    // Text
    static let ink = Color.dynamic(day: 0x1E1A3C, night: 0xFFFFFF)
    static let inkSecondary = Color.dynamic(day: 0x5C5684, night: 0xBEB7E8)

    // Accents
    static let purple = Color(hex: 0x8B6CF6)
    static let purpleDeep = Color(hex: 0x6A4BE0)
    static let lavender = Color(hex: 0xC6B3FF)
    static let yellow = Color(hex: 0xFFD43B)
    static let yellowDeep = Color(hex: 0xF5B700)
    static let peach = Color(hex: 0xFFB59A)
    static let timeBox = Color(hex: 0x27223F)
    static let danger = Color(hex: 0xF5564A)
    static let dangerLight = Color(hex: 0xFF7A63)
    static let shadow = Color.dynamic(day: 0x7B5CE0, night: 0x000000, dayOpacity: 0.16, nightOpacity: 0.4)

    // Night "alarm ringing" palette
    static let ringTop = Color(hex: 0x3A2A86)
    static let ringBottom = Color(hex: 0x6E50C8)
}

// MARK: - Fonts

extension Font {
    /// The chunky rounded display font used throughout the design.
    static func wakie(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

// MARK: - Backgrounds

/// Soft lavender gradient with blobs rising from the bottom edge.
struct AppBackground: View {
    var showsBlobs = true
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [Theme.backgroundTop, Theme.backgroundBottom], startPoint: .top, endPoint: .bottom)
            if colorScheme == .dark {
                StarField()
                    .transition(.opacity)
            }
            if showsBlobs {
                BottomBlobs()
                    .frame(height: 220)
            }
        }
        .ignoresSafeArea()
    }
}

/// Twinkling night sky shown behind every screen in dark mode.
struct StarField: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Star {
        let x, y, radius, brightness, speed, phase: Double
        let isSparkle: Bool
    }

    /// Fixed pseudo-random layout so stars don't jump around between launches.
    private static let stars: [Star] = {
        var seed: UInt64 = 0x5EED_CAFE
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 33) / Double(1 << 31)
        }
        return (0..<90).compactMap { index -> Star? in
            let sparkle = index % 9 == 0
            let x = next()
            // Denser toward the top of the screen, thinning out near the hills.
            let y = pow(next(), 1.4) * 0.85
            // Leave the title area (top-left, where every tab's heading sits) clear,
            // and keep the bigger sparkles out of the top of the screen entirely.
            if y < 0.16 && x < 0.75 { return nil }
            if sparkle && y < 0.3 { return nil }
            return Star(
                x: x,
                y: y,
                radius: sparkle ? 4 + next() * 3 : 0.8 + next() * 2.2,
                brightness: 0.45 + next() * 0.55,
                speed: 0.6 + next() * 1.6,
                phase: next() * .pi * 2,
                isSparkle: sparkle
            )
        }
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12, paused: reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            Canvas { canvas, size in
                for star in Self.stars {
                    let twinkle = reduceMotion ? 1 : 0.55 + 0.45 * sin(time * star.speed + star.phase)
                    let center = CGPoint(x: star.x * size.width, y: star.y * size.height)
                    let r = star.radius
                    let path = star.isSparkle
                        ? Self.sparkle(center: center, radius: r)
                        : Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
                    canvas.fill(path, with: .color(.white.opacity(star.brightness * twinkle)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// A four-pointed twinkle shape.
    private static func sparkle(center c: CGPoint, radius r: Double) -> Path {
        var p = Path()
        let inner = r * 0.28
        p.move(to: CGPoint(x: c.x, y: c.y - r))
        p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + inner, y: c.y - inner))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x + inner, y: c.y + inner))
        p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - inner, y: c.y + inner))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x - inner, y: c.y - inner))
        p.closeSubpath()
        return p
    }
}

/// The wavy purple / yellow hills at the bottom of every screen.
struct BottomBlobs: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                Ellipse()
                    .fill(LinearGradient(colors: [Theme.lavender.opacity(0.75), Theme.purple.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                    .frame(width: w * 0.95, height: h * 0.9)
                    .position(x: w * 0.1, y: h * 0.95)
                Ellipse()
                    .fill(LinearGradient(colors: [Theme.yellow.opacity(0.55), Theme.peach.opacity(0.35)], startPoint: .top, endPoint: .bottom))
                    .frame(width: w * 0.8, height: h * 0.7)
                    .position(x: w * 0.62, y: h * 1.02)
                Ellipse()
                    .fill(LinearGradient(colors: [Theme.lavender.opacity(0.8), Theme.purple.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                    .frame(width: w * 0.75, height: h * 0.95)
                    .position(x: w * 1.02, y: h * 0.9)
            }
            .blur(radius: 2)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Decorations

/// Three short "sparkle" strokes, as drawn next to the titles in the design.
struct SparkleLines: View {
    var color: Color = Theme.yellow
    var size: CGFloat = 26

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(color)
                    .frame(width: size * 0.13, height: size * 0.42)
                    .offset(y: -size * 0.42)
                    .rotationEffect(.degrees(Double(i) * 38 - 10))
            }
        }
        .frame(width: size, height: size)
    }
}

/// A painted brush-stroke banner used behind mission titles.
struct BrushBanner: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        // Ragged edges are expressed as fractions so the shape scales cleanly.
        let top: [(CGFloat, CGFloat)] = [(0.02, 0.10), (0.18, 0.02), (0.35, 0.08), (0.52, 0.0), (0.70, 0.06), (0.86, 0.0), (0.97, 0.08)]
        let bottom: [(CGFloat, CGFloat)] = [(0.98, 0.92), (0.82, 1.0), (0.64, 0.93), (0.46, 1.0), (0.28, 0.94), (0.12, 1.0), (0.01, 0.9)]
        p.move(to: CGPoint(x: top[0].0 * w, y: top[0].1 * h))
        for point in top.dropFirst() {
            p.addLine(to: CGPoint(x: point.0 * w, y: point.1 * h))
        }
        // Right edge flick
        p.addQuadCurve(to: CGPoint(x: bottom[0].0 * w, y: bottom[0].1 * h), control: CGPoint(x: 1.03 * w, y: 0.5 * h))
        for point in bottom.dropFirst() {
            p.addLine(to: CGPoint(x: point.0 * w, y: point.1 * h))
        }
        // Left edge flick
        p.addQuadCurve(to: CGPoint(x: top[0].0 * w, y: top[0].1 * h), control: CGPoint(x: -0.03 * w, y: 0.5 * h))
        p.closeSubpath()
        return p
    }
}

/// Title text sitting on a brush banner (e.g. "Shaky-Shaky").
struct BannerTitle: View {
    let text: String
    var color: Color = Theme.yellow
    var size: CGFloat = 30

    var body: some View {
        Text(text)
            .font(.wakie(size, .black))
            .foregroundStyle(Color(hex: 0x1E1A3C))
            .padding(.horizontal, 22)
            .padding(.vertical, 8)
            .background(BrushBanner().fill(color))
            .rotationEffect(.degrees(-2))
    }
}

// MARK: - Card style

struct CardBackground: ViewModifier {
    var radius: CGFloat = 28

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(Theme.cardStroke, lineWidth: 1.5)
                    )
                    .shadow(color: Theme.shadow, radius: 14, y: 8)
            )
    }
}

/// Fully transparent card. The background shows straight through; a light-catching rim
/// (bright top-left, fading round the sides) gives it the look of a clear glass pane.
struct ClearGlassCard: ViewModifier {
    let radius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        // White highlights on the night sky; soft dark ones on the light background.
        let edge: Color = colorScheme == .dark ? .white : .black
        content
            .contentShape(shape)
            .overlay(
                shape.strokeBorder(
                    LinearGradient(stops: [
                        .init(color: edge.opacity(colorScheme == .dark ? 0.6 : 0.28), location: 0),
                        .init(color: edge.opacity(0.06), location: 0.45),
                        .init(color: edge.opacity(colorScheme == .dark ? 0.3 : 0.14), location: 1),
                    ], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1.2
                )
                .allowsHitTesting(false)
            )
    }
}

extension View {
    func wakieCard(radius: CGFloat = 28) -> some View {
        modifier(CardBackground(radius: radius))
    }

    /// A completely clear glass card: no fill, tint or frosting, just a fine edge highlight.
    func liquidGlassCard(radius: CGFloat = 28) -> some View {
        modifier(ClearGlassCard(radius: radius))
    }
}

/// Round icon button (back chevron, plus, etc.) with a soft white fill.
struct CircleIconButton: View {
    let systemName: String
    var fill: Color = Theme.card
    var foreground: Color = Theme.ink
    var size: CGFloat = 44
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
                .background(Circle().fill(fill).shadow(color: Theme.shadow, radius: 8, y: 4))
        }
        .buttonStyle(.plain)
    }
}

/// Slight press-down effect for custom tappable cards.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
            // A light tap as the finger goes down.
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { _, pressed in pressed }
    }
}
