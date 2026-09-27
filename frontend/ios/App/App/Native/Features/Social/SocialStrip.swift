import SwiftUI

/// The social line under a page's reading.
///
/// On someone else's chart it is a heart to like it, with its count, and
/// "Follows you" when its owner follows one of yours. On your own it is what
/// came back to this chart: how many like it and how many follow it, each
/// opening the people it counts. Activity, which is the whole account's, is
/// the bell in the page's corner rather than a pill here.
struct SocialStrip: View {

    let profile: ProfileSummary
    let isOwn: Bool
    var onOpenPeople: ((PeopleSheet.Tab) -> Void)?

    @ObservedObject private var social = SocialStore.shared
    @ObservedObject private var strings = L10n.shared
    @State private var likeError: String?
    @State private var likeTaps = 0

    private var like: SocialStore.Like { social.like(for: profile) }

    var body: some View {
        WeatherGlassGroup(spacing: 8) {
            HStack(spacing: 8) {
                if isOwn {
                    pill(
                        icon: "heart.fill",
                        text: "\(like.count)",
                        label: L(count: like.count, "social.likesCount")
                    ) { onOpenPeople?(.likes) }

                    pill(
                        icon: "person.2.fill",
                        text: "\(profile.followersCount ?? 0)",
                        label: L(count: profile.followersCount ?? 0, "social.followersCount")
                    ) { onOpenPeople?(.followers) }
                } else {
                    likePill

                    if profile.followsYou == true {
                        Text(L("social.followsYou"))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 12)
                            .frame(height: Self.height)
                            .weatherGlass(in: .capsule, tint: 0.1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .sensoryFeedback(.impact(weight: .light), trigger: likeTaps)
        .alert(
            L("social.likeFailed"),
            isPresented: Binding(
                get: { likeError != nil },
                set: { if !$0 { likeError = nil } }
            )
        ) {
            Button(L("common.ok"), role: .cancel) { likeError = nil }
        } message: {
            Text(likeError ?? "")
        }
    }

    private static let height: CGFloat = 34

    /// The heart on someone else's chart: filled and red once liked.
    private var likePill: some View {
        HStack(spacing: 6) {
            Image(systemName: like.isLiked ? "heart.fill" : "heart")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(like.isLiked ? Theme.challenge : .white)
                .contentTransition(.symbolEffect(.replace))
            Text("\(like.count)")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 14)
        .frame(height: Self.height)
        .weatherGlass(in: .capsule, tint: 0.2, interactive: true)
        .contentShape(Capsule())
        // A tap gesture rather than a Button, for the reason the reading's
        // stamp uses one: inside the pager's scroll view a plain Button
        // never fires.
        .onTapGesture {
            likeTaps += 1
            Task {
                if let error = await social.toggleLike(profile) {
                    likeError = error.localizedDescription
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: like)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L(like.isLiked ? "social.unlike" : "social.like"))
        .accessibilityValue(L(count: like.count, "social.likesCount"))
        .accessibilityAddTraits(.isButton)
    }

    private func pill(icon: String, text: String, label: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
            Text(text)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(height: Self.height)
        .weatherGlass(in: .capsule, tint: 0.2, interactive: true)
        .contentShape(Capsule())
        .onTapGesture(perform: action)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
    }
}

/// The bell in the top-left corner of every page, opposite the •••: the way
/// into Activity, with the number of likes and follows since it was last
/// opened riding on it in red.
struct ActivityBell: View {

    var action: () -> Void

    @ObservedObject private var social = SocialStore.shared
    @ObservedObject private var strings = L10n.shared

    /// The •••'s own size, so the two corners read as a pair.
    private static let size: CGFloat = 36

    var body: some View {
        // The plain bell either way: the count on its corner already says
        // there is something new, and the badged glyph said it twice.
        Image(systemName: "bell.fill")
            .foregroundStyle(.white)
            .font(.system(size: 15, weight: .semibold))
            .frame(width: Self.size, height: Self.size)
            .contentShape(Circle())
            .weatherGlass(in: .circle, interactive: true)
            .overlay(alignment: .topTrailing) {
                if social.unreadActivity > 0 {
                    Text("\(min(social.unreadActivity, 99))")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Capsule().fill(Theme.challenge))
                        .offset(x: 6, y: -5)
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityHidden(true)
                }
            }
            // A tap gesture rather than a Button, for the reason the reading's
            // stamp uses one: inside the pager's scroll view a plain Button
            // never fires.
            .onTapGesture(perform: action)
            .animation(.easeInOut(duration: 0.2), value: social.unreadActivity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("activity.title"))
            .accessibilityValue(
                social.unreadActivity > 0 ? L(count: social.unreadActivity, "activity.newCount") : ""
            )
            .accessibilityAddTraits(.isButton)
    }
}
