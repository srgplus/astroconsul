import SwiftUI
import UIKit

/// The chats' colours, one token per role, each in two values: black in the
/// dark, white in the light, following the Appearance setting like the rest
/// of the app. The dark values are the ones the chats were first drawn with,
/// after the messenger the owner likes; the light ones are the same roles on
/// white, the way that messenger draws its light theme.
enum ChatPalette {

    // MARK: Ground

    /// Under everything: the list, a conversation, the composer's strip.
    static let background = dynamic(dark: grey(0), light: hex(0xFFFFFF))

    // MARK: Bubbles

    /// The reader's bubbles: the blue people read as "mine" in a chat, the
    /// same in both, with white words on it.
    static let mine = Color(red: 0.21, green: 0.47, blue: 0.96)

    /// The other side's bubbles, and the words in them.
    static let theirs = dynamic(dark: UIColor(red: 0.17, green: 0.17, blue: 0.18, alpha: 1), light: hex(0xE9E9EB))
    static let theirsText = dynamic(dark: grey(1), light: hex(0x000000))

    // MARK: Text

    /// Names, titles, what is typed, the glyphs in the header.
    static let text = dynamic(dark: grey(1), light: hex(0x000000))

    /// The line under a title in an empty or failed state, the search glass.
    static let body = dynamic(dark: grey(0.6), light: hex(0x6C6C70))

    /// Dates, handles, "Seen", the last message once it is read.
    static let secondary = dynamic(dark: grey(0.55), light: hex(0x8A8A8E))

    /// The icon over an empty state, "Say hello" in an empty conversation.
    static let hint = dynamic(dark: grey(0.5), light: hex(0x8E8E93))

    /// The chevron at the end of a row.
    static let faint = dynamic(dark: grey(0.4), light: hex(0xC4C4C7))

    // MARK: Surfaces

    /// The capsule with the person's name at the top of a conversation.
    static let capsule = dynamic(dark: grey(0.12), light: hex(0xF2F2F7))
    static let capsuleLine = dynamic(dark: grey(0.24), light: hex(0xD8D8DC))

    /// The field a message is typed in.
    static let composer = dynamic(dark: grey(0.09), light: hex(0xFFFFFF))
    static let composerLine = dynamic(dark: grey(0.2), light: hex(0xD1D1D6))

    /// The send button while there is nothing to send.
    static let sendOff = dynamic(dark: grey(0.2), light: hex(0xE5E5EA))
    static let sendOffGlyph = dynamic(dark: grey(0.45), light: hex(0xAEAEB2))

    /// A face: the circle, its rim, and the sign on it.
    static let avatar = dynamic(dark: grey(0.16), light: hex(0xE9E9EB))
    static let avatarLine = dynamic(dark: UIColor(white: 1, alpha: 0.1), light: UIColor(white: 0, alpha: 0.06))
    static let avatarGlyph = dynamic(dark: grey(1), light: hex(0x3A3A3C))

    /// A row under the finger.
    static let pressed = dynamic(dark: grey(0.11), light: hex(0xE5E5EA))

    /// The hairline between rows.
    static let separator = dynamic(dark: grey(0.2), light: hex(0xC6C6C8))

    /// A card on the ground: a chart to pick in "Which chart is yours?".
    static let card = dynamic(dark: grey(0.1), light: hex(0xF2F2F7))

    /// A header control where there is no Liquid Glass, in the light: the
    /// grey of the system's own search field.
    static let control = dynamic(dark: grey(0.12), light: hex(0xEEEEF0))

    // MARK: Builders

    private static func dynamic(dark: UIColor, light: UIColor) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }

    /// In sRGB, as SwiftUI's `Color(white:)` is, so a dark value here is the
    /// grey the screens had before they had a light theme.
    private static func grey(_ white: CGFloat) -> UIColor {
        UIColor(red: white, green: white, blue: white, alpha: 1)
    }

    private static func hex(_ rgb: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension View {

    /// The header's glass in the chats. In the dark, the app's own dark
    /// glass, as before; in the light, plain Liquid Glass, which reads on
    /// white where the dark tint would sit on it as a grey smudge, and the
    /// system search field's grey where there is no Liquid Glass.
    func chatGlass<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        modifier(ChatGlass(shape: shape, interactive: interactive))
    }

    /// Whatever scrolls up under the bar blurs out gradually, strongest at
    /// the top, rather than stopping at a frosted band with a line under it:
    /// the hard edge is what iOS 26 drew in the chats' sheet on its own.
    @ViewBuilder
    func softTopEdge() -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }
}

private struct ChatGlass<S: Shape>: ViewModifier {

    let shape: S
    let interactive: Bool

    @Environment(\.colorScheme) private var scheme

    @ViewBuilder
    func body(content: Content) -> some View {
        if scheme == .dark {
            content.weatherGlass(in: shape, interactive: interactive)
        } else if #available(iOS 26.0, *) {
            content.glassEffect(interactive ? Glass.regular.interactive() : Glass.regular, in: shape)
        } else {
            content
                .background { shape.fill(ChatPalette.control) }
                .clipShape(shape)
        }
    }
}
