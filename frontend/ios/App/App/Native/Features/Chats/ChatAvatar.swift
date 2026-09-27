import SwiftUI

/// A person in the chats. Messengers show a face; this app has no photos, so
/// the face is the one thing every chart has, the Sun sign, on a quiet grey
/// circle (white on charcoal in the dark, charcoal on pale grey in the
/// light), as Activity draws people: the name beside it tells two people
/// apart, and the colours of the elements made the list look painted.
struct ChatAvatar: View {

    let card: SocialCard
    var size: CGFloat = 52

    var body: some View {
        ZStack {
            Circle()
                .fill(ChatPalette.avatar)
                .overlay(Circle().stroke(ChatPalette.avatarLine, lineWidth: 0.5))

            if let sign = card.sunSign {
                Text(AstroGlyph.sign(sign))
                    .font(.system(size: size * 0.72))
                    .foregroundStyle(ChatPalette.avatarGlyph)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(ChatPalette.avatarGlyph.opacity(0.9))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
