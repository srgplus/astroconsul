import SwiftUI

/// A person in the chats. Messengers show a face; this app has no photos, so
/// the face is the one thing every chart has, the Sun sign, on a circle in
/// the colour of its element: fire red, earth green, air gold, water blue.
/// Two people side by side in the list read apart at a glance, the way two
/// photos would.
struct ChatAvatar: View {

    let card: SocialCard
    var size: CGFloat = 52

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))

            if let sign = card.sunSign {
                Text(AstroGlyph.sign(sign))
                    .font(.system(size: size * 0.46))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private enum Element {
        case fire
        case earth
        case air
        case water
    }

    private var colors: [Color] {
        switch Self.element(of: card.sunSign) {
        case .fire:
            return [Color(hex: 0xFF7A59), Color(hex: 0xE0413A)]
        case .earth:
            return [Color(hex: 0x5BC98C), Color(hex: 0x2F8F5B)]
        case .air:
            return [Color(hex: 0xF5C451), Color(hex: 0xD28B1E)]
        case .water:
            return [Color(hex: 0x5AA9F7), Color(hex: 0x2F6FD6)]
        case nil:
            return [Color(white: 0.3), Color(white: 0.2)]
        }
    }

    private static func element(of sign: String?) -> Element? {
        switch sign?.capitalized {
        case "Aries", "Leo", "Sagittarius": return .fire
        case "Taurus", "Virgo", "Capricorn": return .earth
        case "Gemini", "Libra", "Aquarius": return .air
        case "Cancer", "Scorpio", "Pisces": return .water
        default: return nil
        }
    }
}
