import SwiftUI

/// The social line under a page's reading, all of it on one row.
///
/// On someone else's chart: how many follow the chart and how many its owner
/// follows, then one follow button — "Follow", "Follow back" or
/// "✓ Following", the way Instagram has one — and the heart for the state of
/// the sky on screen. Those numbers are numbers only: nobody reads another
/// person's lists, and an owner can hide the numbers in Settings.
///
/// On your own: the same two counts, each opening who they are, and the same
/// heart — you can like your own sky. Who liked it is in Activity, the bell
/// in the page's corner, and not behind the heart: a heart that looks the
/// same everywhere but opened a list only here was a trap.
struct SocialStrip: View {

    let profile: ProfileSummary
    let isOwn: Bool

    /// The state on screen — the feels-like word — and its index. A like is
    /// for this state: when the word changes, the heart is empty again.
    var feelsLike: String?
    var tii: Double?

    /// How many charts the account follows, for the count under one of its
    /// own: the list's own number, which an unfollow changes at once, where
    /// the listing's would wait for the next load. Other people's come from
    /// their payload.
    var followingCount: Int?

    /// Someone else's chart: whether the reader follows it, and what the
    /// button does from here. A page is always followed — the pager holds
    /// only charts the reader owns or follows — so a page wires `onUnfollow`
    /// and a preview wires `onFollow`. With neither there is no button.
    var isFollowing = true
    var isFollowWorking = false
    var onFollow: (() -> Void)?
    /// Handed up rather than acted on: the presenter asks before unfollowing,
    /// and the alert has to outlive a page the pager may tear down.
    var onUnfollow: ((ProfileSummary) -> Void)?

    var onOpenPeople: ((PeopleSheet.Tab) -> Void)?

    @ObservedObject private var social = SocialStore.shared
    @ObservedObject private var strings = L10n.shared
    @State private var likeError: String?
    @State private var likeTaps = 0

    private var state: String { SocialStore.state(feelsLike) }
    private var like: SocialStore.Like { social.like(for: profile, state: state) }

    var body: some View {
        WeatherGlassGroup(spacing: 6) {
            // One line: the people on the left, the follow button in the room
            // before the heart, and the heart always last, on the right. With
            // the counts hidden by their owner, the two that are left sit in
            // the middle instead of against the right edge.
            HStack(spacing: 6) {
                if showsCounts {
                    counts
                    Spacer(minLength: 0)
                }
                if !isOwn, onFollow != nil || onUnfollow != nil {
                    FollowButton(
                        isFollowing: isFollowing,
                        followsYou: profile.followsYou == true,
                        isWorking: isFollowWorking,
                        onFollow: onFollow,
                        onUnfollow: onUnfollow.map { unfollow in { unfollow(profile) } }
                    )
                    // First call on the width, so "Follow back" is spelled
                    // out whenever the counts can give up a little of theirs.
                    .layoutPriority(1)
                }
                likePill
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

    // MARK: - Counts

    /// Your own always show, a missing number counting as none. Anyone
    /// else's show only when their payload carries them: the API leaves them
    /// out for an owner who keeps them to themselves.
    private var showsCounts: Bool {
        isOwn || profile.followersCount != nil || profile.followingCount != nil
    }

    private var counts: some View {
        HStack(spacing: isOwn ? 6 : 14) {
            if let followers = isOwn ? (profile.followersCount ?? 0) : profile.followersCount {
                count(followers, noun: "social.followersNoun", label: "social.followersCount", tab: .followers)
            }
            if let following = isOwn ? (followingCount ?? profile.followingCount ?? 0) : profile.followingCount {
                count(following, noun: "social.followingNoun", label: "social.followingCount", tab: .following)
            }
        }
    }

    /// "12 followers": the number set heavier than the word, as a profile
    /// header sets it. On your own chart a glass capsule that opens the list;
    /// on anyone else's plain text on the sky, because there it is a fact
    /// and not a control, and glass would promise a tap. Allowed to shrink a
    /// little rather than push the heart off a narrow phone: the Russian
    /// words are long.
    @ViewBuilder
    private func count(_ count: Int, noun: String, label: String, tab: PeopleSheet.Tab) -> some View {
        let text = (
            Text("\(count) ").fontWeight(.semibold).monospacedDigit()
                + Text(L(count: count, noun)).foregroundColor(.white.opacity(0.8))
        )
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.75)

        if isOwn {
            text
                .font(.system(size: 13, design: .rounded))
                .padding(.horizontal, 12)
                .frame(height: Self.height)
                .weatherGlass(in: .capsule, tint: 0.2, interactive: true)
                .contentShape(Capsule())
                // A tap gesture rather than a Button, for the reason the
                // reading's stamp uses one: inside the pager's scroll view a
                // plain Button never fires.
                .onTapGesture { onOpenPeople?(tab) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L(count: count, label))
                .accessibilityAddTraits(.isButton)
        } else {
            text
                .font(.system(size: 14, design: .rounded))
                .frame(height: Self.height)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L(count: count, label))
        }
    }

    // MARK: - Likes

    /// The heart, on anyone's chart and on your own: filled and red once
    /// this state is liked, empty again when the state changes.
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
}

/// The one follow control on someone else's chart, the way Instagram has
/// one: "Follow" when neither of you follows the other, "Follow back" when
/// they follow you and you do not, "✓ Following" once you do. Whether someone
/// follows you is otherwise said only in your own Following list.
///
/// Solid white while it asks for something, because that is the one thing
/// the screen wants; quiet glass once it is done. "✓ Following" asks before
/// it unfollows, and is a label where nothing can be undone from here.
struct FollowButton: View {

    let isFollowing: Bool
    let followsYou: Bool
    var isWorking = false
    var onFollow: (() -> Void)?
    var onUnfollow: (() -> Void)?

    @ObservedObject private var strings = L10n.shared

    private var action: (() -> Void)? { isFollowing ? onUnfollow : onFollow }
    private var title: String {
        if isFollowing { return L("social.following") }
        return L(followsYou ? "social.followBackButton" : "social.follow")
    }

    var body: some View {
        Group {
            if isFollowing {
                content
                    .foregroundStyle(.white.opacity(0.9))
                    .weatherGlass(in: .capsule, tint: 0.2, interactive: action != nil)
            } else {
                content
                    .foregroundStyle(.black)
                    .background(Capsule().fill(.white))
            }
        }
        .contentShape(Capsule())
        // A tap gesture rather than a Button, for the reason the reading's
        // stamp uses one: inside the pager's scroll view a plain Button
        // never fires.
        .onTapGesture {
            guard !isWorking else { return }
            action?()
        }
        .animation(.easeInOut(duration: 0.2), value: isFollowing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint(isFollowing && onUnfollow != nil ? L("social.followingHint") : "")
        .accessibilityAddTraits(action == nil ? [] : .isButton)
    }

    private var content: some View {
        Group {
            if isWorking {
                ProgressView().controlSize(.small).tint(Theme.spinner)
            } else if isFollowing {
                Label(title, systemImage: "checkmark")
                    .labelStyle(.titleAndIcon)
            } else if followsYou {
                // "Подписаться в ответ" is long: where the line has no room
                // for it, the plain "Follow" still does the same thing.
                ViewThatFits(in: .horizontal) {
                    Text(title)
                    Text(L("social.follow"))
                }
            } else {
                Text(title)
            }
        }
        .font(.system(size: 13, weight: isFollowing ? .semibold : .bold, design: .rounded))
        .lineLimit(1)
        .padding(.horizontal, 12)
        .frame(height: SocialStrip.height)
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
