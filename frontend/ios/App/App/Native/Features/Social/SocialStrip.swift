import SwiftUI

/// The social line under a page's reading.
///
/// On someone else's chart: a heart to like the state of the sky on screen,
/// "Following", which asks before it unfollows, and "Follows you" when the
/// chart's owner follows you back. On your own: how many liked the state on
/// screen, opening Activity where likes live, and how many follow the chart,
/// opening who follows it and whom you follow. Activity itself, which is the
/// whole account's, is the bell in the page's corner.
struct SocialStrip: View {

    let profile: ProfileSummary
    let isOwn: Bool

    /// The state on screen — the feels-like word — and its index. A like is
    /// for this state: when the word changes, the heart is empty again.
    var feelsLike: String?
    var tii: Double?

    var onOpenLikes: (() -> Void)?
    var onOpenPeople: ((PeopleSheet.Tab) -> Void)?
    /// Handed up rather than acted on: the presenter asks before unfollowing,
    /// the same question the ••• menu's Unfollow gets.
    var onUnfollow: ((ProfileSummary) -> Void)?

    @ObservedObject private var social = SocialStore.shared
    @ObservedObject private var strings = L10n.shared
    @State private var likeError: String?
    @State private var likeTaps = 0

    private var state: String { SocialStore.state(feelsLike) }
    private var like: SocialStore.Like { social.like(for: profile, state: state) }

    var body: some View {
        WeatherGlassGroup(spacing: 8) {
            HStack(spacing: 8) {
                // The heart always last, on the right: the people first, then
                // what they made of the sky.
                if isOwn {
                    pill(
                        icon: "person.2.fill",
                        text: "\(profile.followersCount ?? 0)",
                        label: L(count: profile.followersCount ?? 0, "social.followersCount")
                    ) { onOpenPeople?(.followers) }

                    pill(
                        icon: "heart.fill",
                        text: "\(like.count)",
                        label: L(count: like.count, "social.likesCount")
                    ) { onOpenLikes?() }
                } else {
                    if let onUnfollow {
                        FollowingPill { onUnfollow(profile) }
                    }

                    if profile.followsYou == true {
                        FollowsYouTag()
                    }

                    likePill
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

    static let height: CGFloat = 34

    /// The heart on someone else's chart: filled and red once this state is
    /// liked, empty again when the state changes.
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
                if let error = await social.toggleLike(profile, state: state, tii: tii) {
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

/// "Following", on a chart the reader follows. Quiet glass with a check, so it
/// reads as a state rather than a call to action; a tap asks before
/// unfollowing.
struct FollowingPill: View {

    /// Nil where there is nothing to do from here — a preview, which cannot
    /// unfollow — and the pill is then a label.
    var action: (() -> Void)?

    var body: some View {
        Label(L("social.following"), systemImage: "checkmark")
            .labelStyle(.titleAndIcon)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 14)
            .frame(height: SocialStrip.height)
            .weatherGlass(in: .capsule, tint: 0.2, interactive: action != nil)
            .contentShape(Capsule())
            .onTapGesture { action?() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("social.following"))
            .accessibilityHint(action == nil ? "" : L("social.followingHint"))
            .accessibilityAddTraits(action == nil ? [] : .isButton)
    }
}

/// "Follow", on a chart the reader does not follow yet: filled white, the one
/// solid control on the sky, because it is the one thing the screen asks for.
struct FollowPill: View {

    var isWorking = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isWorking {
                    ProgressView().controlSize(.small).tint(Theme.spinner)
                } else {
                    Label(L("social.follow"), systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                }
            }
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(.black)
            .padding(.horizontal, 16)
            .frame(height: SocialStrip.height)
            .background(Capsule().fill(.white))
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
        .accessibilityLabel(L("social.follow"))
    }
}

/// "Follows you": a label, not a control.
struct FollowsYouTag: View {
    var body: some View {
        Text(L("social.followsYou"))
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 12)
            .frame(height: SocialStrip.height)
            .weatherGlass(in: .capsule, tint: 0.1)
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
