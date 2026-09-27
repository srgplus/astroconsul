import SwiftUI

/// The social line under a page's reading, all of it on one row.
///
/// On someone else's chart: how many follow the chart and how many its owner
/// follows, centred, and under them one follow button — "Follow", "Follow
/// back" or "✓ Following", the way Instagram has one — "Message" when the
/// chart is its owner's own, and the heart for the state of the sky on
/// screen, with every like the chart has ever had beside it.
/// Those numbers are numbers only: nobody reads another person's lists, and
/// an owner can hide the numbers in Settings.
///
/// On your own: the same two counts, each opening who they are, and in the
/// heart's place how many likes the chart has had, as plain text by a white
/// heart. You cannot
/// like your own charts, so there is nothing there to tap, and glass would
/// promise a tap. Who liked it is in Activity, the bell in the page's corner.
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

    /// Someone's own chart, which is the one way to write to them: "Message"
    /// beside the follow button, as Instagram has it. Nil where there is
    /// nobody behind the chart to answer, or it is the reader's.
    var onMessage: (() -> Void)?

    @ObservedObject private var social = SocialStore.shared
    @ObservedObject private var strings = L10n.shared
    @State private var likeError: String?
    @State private var likeTaps = 0

    private var state: String { SocialStore.state(feelsLike) }
    private var like: SocialStore.Like { social.like(for: profile, state: state) }

    var body: some View {
        WeatherGlassGroup(spacing: 6) {
            if showsFollow || showsMessage {
                // The counts centred on a line of their own, and under them
                // everything that can be done with the person: follow,
                // message and the heart. "Message" goes down to its bubble
                // where the word leaves no room.
                VStack(spacing: 8) {
                    if showsCounts {
                        counts
                    }
                    ViewThatFits(in: .horizontal) {
                        actions(compactMessage: false)
                        actions(compactMessage: true)
                    }
                }
            } else {
                // Your own chart: the counts on the left, the heart on the
                // right.
                HStack(spacing: 6) {
                    if showsCounts {
                        counts
                        Spacer(minLength: 0)
                    }
                    heart
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

    private var showsFollow: Bool { !isOwn && (onFollow != nil || onUnfollow != nil) }
    private var showsMessage: Bool { !isOwn && onMessage != nil }

    /// Follow, Message and the heart on one line. Under the counts the two
    /// buttons share the width, the way Instagram lays out Following and
    /// Message; with the counts hidden by their owner, the line keeps to its
    /// own width in the middle.
    private func actions(compactMessage: Bool) -> some View {
        HStack(spacing: 6) {
            buttons(compactMessage: compactMessage, fillWidth: showsCounts)
            heart
        }
    }

    @ViewBuilder
    private func buttons(compactMessage: Bool, fillWidth: Bool) -> some View {
        if showsFollow {
            FollowButton(
                isFollowing: isFollowing,
                followsYou: profile.followsYou == true,
                isWorking: isFollowWorking,
                fillsWidth: fillWidth,
                onFollow: onFollow,
                onUnfollow: onUnfollow.map { unfollow in { unfollow(profile) } }
            )
            // First call on the width, so "Follow back" is spelled out
            // rather than cut. Not while it and "Message" share the line
            // evenly.
            .layoutPriority(fillWidth ? 0 : 1)
        }
        if showsMessage, let onMessage {
            MessageButton(isCompact: compactMessage, fillsWidth: fillWidth, action: onMessage)
        }
    }

    @ViewBuilder
    private var heart: some View {
        if isOwn {
            likesReceived
        } else {
            likePill
        }
    }

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

    /// The heart on someone else's chart: filled and red once this state is
    /// liked, empty again when the state changes, so the same person can like
    /// the chart again tomorrow or under a new word. The number beside it
    /// keeps every like and only grows. Without it the owner hid their
    /// numbers, and the heart stands alone.
    private var likePill: some View {
        HStack(spacing: 6) {
            Image(systemName: like.isLiked ? "heart.fill" : "heart")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(like.isLiked ? Theme.challenge : .white)
                .contentTransition(.symbolEffect(.replace))
            if let count = like.count {
                Text(LikeCount.short(count))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(value: Double(count)))
            }
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
        .accessibilityValue(like.count.map { L(count: $0, "social.likesCount") } ?? "")
        .accessibilityAddTraits(.isButton)
    }

    /// Your own chart's likes: a white heart and the number, on the sky the
    /// way someone else's counts are. White and empty rather than red: red is
    /// what a heart turns once you have tapped it, and this one cannot be
    /// tapped. A glass capsule here would look like the heart people tap on
    /// everyone else's page. The heart gives a small bounce when the number
    /// moves while the page is open.
    private var likesReceived: some View {
        let count = like.count ?? 0
        return HStack(spacing: 5) {
            Image(systemName: "heart")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .symbolEffect(.bounce, value: count)
            Text(LikeCount.short(count))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText(value: Double(count)))
        }
        .padding(.horizontal, 6)
        .frame(height: Self.height)
        .animation(.easeInOut(duration: 0.2), value: count)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L(count: count, "social.likesCount"))
    }
}

/// A like count short enough for the pill: 999, 1.2K, 12K, 1.2M. Rounded
/// down, the way the big apps do it, so 999,950 reads 999K rather than a
/// thousand thousand, and a count never shows more than it has.
enum LikeCount {
    static func short(_ count: Int) -> String {
        switch count {
        case ..<1_000:
            return "\(max(count, 0))"
        case ..<1_000_000:
            return scaled(count, by: 1_000, suffix: "K")
        default:
            return scaled(count, by: 1_000_000, suffix: "M")
        }
    }

    /// One decimal under ten of the unit, none above: 1.2K, 12K, 123K.
    private static func scaled(_ count: Int, by unit: Int, suffix: String) -> String {
        if count < unit * 10 {
            let tenths = count / (unit / 10)
            let whole = tenths / 10
            let fraction = tenths % 10
            return fraction == 0 ? "\(whole)\(suffix)" : "\(whole).\(fraction)\(suffix)"
        }
        return "\(count / unit)\(suffix)"
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
    /// An equal share of the line with "Message".
    var fillsWidth = false
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
        .frame(maxWidth: fillsWidth ? .infinity : nil)
        .frame(height: SocialStrip.height)
    }
}

/// "Message" on someone's own chart, in the quiet glass of "✓ Following"
/// beside it: the follow button asks for something, this one is simply there.
/// Where the line has no room for the word, the speech bubble alone.
struct MessageButton: View {

    /// The bubble alone, for a line with no room for the word.
    var isCompact = false
    /// An equal share of the line with the follow button.
    var fillsWidth = false
    var action: () -> Void

    @ObservedObject private var strings = L10n.shared

    var body: some View {
        Group {
            if isCompact {
                Image(systemName: "message")
                    .frame(width: SocialStrip.height)
            } else {
                Text(L("chats.message"))
                    .padding(.horizontal, 12)
                    .frame(maxWidth: fillsWidth ? .infinity : nil)
            }
        }
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .foregroundStyle(.white.opacity(0.9))
        .lineLimit(1)
        .frame(height: SocialStrip.height)
        .weatherGlass(in: .capsule, tint: 0.2, interactive: true)
        .contentShape(Capsule())
        // A tap gesture rather than a Button, for the reason the reading's
        // stamp uses one: inside the pager's scroll view a plain Button
        // never fires.
        .onTapGesture(perform: action)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("chats.message"))
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
                CornerCount(count: social.unreadActivity)
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

/// Beside the bell: the way into the chats, with the number of messages not
/// read yet riding on it the way the bell carries Activity's. Its own button
/// rather than a tab inside Activity, as Instagram keeps its messages apart
/// from its hearts: one is people talking to you, the other is news.
struct ChatsButton: View {

    var action: () -> Void

    @ObservedObject private var chats = ChatStore.shared
    @ObservedObject private var strings = L10n.shared

    /// The bell's own size, so the two read as a pair.
    private static let size: CGFloat = 36

    var body: some View {
        Image(systemName: "message.fill")
            .foregroundStyle(.white)
            .font(.system(size: 15, weight: .semibold))
            .frame(width: Self.size, height: Self.size)
            .contentShape(Circle())
            .weatherGlass(in: .circle, interactive: true)
            .overlay(alignment: .topTrailing) {
                CornerCount(count: chats.unreadCount)
            }
            // A tap gesture rather than a Button, for the bell's reason:
            // inside the pager's scroll view a plain Button never fires.
            .onTapGesture(perform: action)
            .animation(.easeInOut(duration: 0.2), value: chats.unreadCount)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("chats.title"))
            .accessibilityValue(chats.unreadCount > 0 ? L(count: chats.unreadCount, "chats.unreadCount") : "")
            .accessibilityAddTraits(.isButton)
    }
}

/// The red count on the corner of the bell and the chats button, while there
/// is anything new. Capped at 99 so it stays a dot's size.
struct CornerCount: View {

    let count: Int

    var body: some View {
        if count > 0 {
            Text("\(min(count, 99))")
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
}
