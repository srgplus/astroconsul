import SwiftUI

/// Someone, drawn the way every social list in the app draws them: their Sun
/// sign in a glass circle, their name, what they did and when, and a
/// "Follow back" on the right while there is someone to follow back.
///
/// Activity, the likes and followers lists and the blocked list all use it,
/// so a person looks the same wherever they turn up.
struct SocialPersonRow<Trailing: View>: View {

    let card: SocialCard
    /// What they did, after their name: "liked Anna", "started following you".
    /// Nil for a list that is only names, like the blocked accounts.
    var action: String?
    /// A word before the time on the second line: the state a like was for,
    /// or a handle.
    var detail: String?
    var date: Date?
    /// A dot at the leading edge, for Activity rows newer than the last visit.
    var isUnread = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .topLeading) {
                SocialAvatar(card: card)

                if isUnread {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 9, height: 9)
                        .offset(x: -3, y: -1)
                        .accessibilityHidden(true)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                sentence
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let second = secondLine {
                    Text(second)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            trailing
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// "Expansive · 5 min. ago", either half alone, or nothing.
    private var secondLine: String? {
        let parts = [detail, date.map { SocialDate.relative($0) }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The name set heavier than the rest, so a column of rows can be read
    /// down its names.
    private var sentence: Text {
        let name = Text(card.displayName).fontWeight(.semibold)
        guard let action else { return name }
        return name + Text(" ") + Text(action).foregroundColor(.white.opacity(0.8))
    }
}

extension SocialPersonRow where Trailing == EmptyView {
    init(card: SocialCard, action: String? = nil, detail: String? = nil, date: Date? = nil, isUnread: Bool = false) {
        self.init(card: card, action: action, detail: detail, date: date, isUnread: isUnread) { EmptyView() }
    }
}

/// A person's Sun sign in a glass circle: the one thing every chart has, and
/// the one thing a stranger reads first.
struct SocialAvatar: View {

    let card: SocialCard
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let sign = card.sunSign {
                Text(AstroGlyph.sign(sign))
                    .font(.system(size: size * 0.48))
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42, weight: .medium))
            }
        }
        .foregroundStyle(.white)
        .frame(width: size, height: size)
        .weatherGlass(in: .circle, tint: 0.28)
        .accessibilityHidden(true)
    }
}

/// "Follow back" while the reader does not follow the person, a quiet
/// "Following" once they do, a spinner while the request is out.
struct FollowBackButton: View {

    let isFollowed: Bool
    let isWorking: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                // Followed wins over working: a row follows back at once and
                // lets the request catch up, so it says "Following" while
                // the request is still out.
                if isFollowed {
                    Label(L("social.following"), systemImage: "checkmark")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.white.opacity(0.7))
                } else if isWorking {
                    ProgressView().controlSize(.small).tint(Theme.spinner)
                        .frame(minWidth: 60)
                } else {
                    Text(L("social.followBack"))
                        .foregroundStyle(.white)
                }
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .padding(.horizontal, 12)
            .frame(height: 30)
        }
        .buttonStyle(.plain)
        .disabled(isFollowed || isWorking)
        .weatherGlass(in: .capsule, tint: isFollowed ? 0.1 : 0.3, interactive: !isFollowed)
    }
}
