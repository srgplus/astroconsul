import SwiftUI

/// A person in the chats. Messengers show a face; this app has no photos, so
/// the face is the one thing every chart has, the Sun sign, white on a quiet
/// grey circle, as Activity draws people: the name beside it tells two
/// people apart, and the colours of the elements made the list look painted.
struct ChatAvatar: View {

    let card: SocialCard
    var size: CGFloat = 52

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(white: 0.16))
                .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 0.5))

            if let sign = card.sunSign {
                Text(AstroGlyph.sign(sign))
                    .font(.system(size: size * 0.72))
                    .foregroundStyle(.white)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
