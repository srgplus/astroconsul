import SwiftUI

/// Horizontal pager over profiles with Weather's floating bottom bar: page
/// dots in a capsule at the centre, the profile list on the right, the left
/// slot held empty for a second button. Generic over the page so previews can
/// feed it seeded screens.
struct WeatherPager<Page: View>: View {

    let profiles: [ProfileSummary]
    @Binding var selection: String
    let primaryProfileId: String?

    /// Bottom safe-area inset, passed in because the pager draws full bleed
    /// and can no longer read it for itself.
    var bottomInset: CGFloat = 0

    var onOpenSearch: () -> Void
    var onOpenList: () -> Void
    @ViewBuilder var page: (ProfileSummary) -> Page

    private var index: Int {
        profiles.firstIndex { $0.profileId == selection } ?? 0
    }

    var body: some View {
        TabView(selection: $selection) {
            ForEach(profiles) { profile in
                page(profile)
                    .tag(profile.profileId)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        // Full bleed first, then the bar is re-inset on top of it, so each
        // page's sky reaches the status bar and the home indicator.
        .ignoresSafeArea()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            WeatherBottomBar(
                count: profiles.count,
                index: index,
                primaryIndex: profiles.firstIndex { $0.profileId == primaryProfileId },
                onSelectPage: { position in
                    guard profiles.indices.contains(position) else { return }
                    selection = profiles[position].profileId
                },
                bottomInset: bottomInset,
                onOpenSearch: onOpenSearch,
                onOpenList: onOpenList
            )
        }
    }
}

/// The bar itself: no slab of background, just glass controls floating over
/// the sky, the way Weather's bar reads on iOS 26.
struct WeatherBottomBar: View {

    let count: Int
    let index: Int
    let primaryIndex: Int?
    var onSelectPage: (Int) -> Void
    var bottomInset: CGFloat = 0
    var onOpenSearch: () -> Void
    var onOpenList: () -> Void

    /// Both circles and the dot capsule share one height so the row reads as
    /// a single band.
    private static let control: CGFloat = 44
    /// The dot capsule hugs the dots, so it is shorter than the buttons.
    private static let dots: CGFloat = 32
    /// Between the controls, and the width the empty left slot mirrors.
    private static let gap: CGFloat = 10

    /// How much of the page the bar covers. It floats over the sky rather
    /// than sitting under it, so a scrolling page pads its content by this
    /// much to keep the last row clear of the glass.
    static func height(bottomInset: CGFloat) -> CGFloat {
        8 + control + bottomMargin(for: bottomInset)
    }

    /// Just above the home indicator rather than on it; on a device without
    /// one the bar keeps a plain margin.
    private static func bottomMargin(for inset: CGFloat) -> CGFloat {
        inset > 0 ? inset - 14 : 10
    }

    var body: some View {
        WeatherGlassGroup(spacing: 14) {
            HStack(spacing: Self.gap) {
                // One button each side, which is what keeps the dots on the
                // centre line of the screen — and what leaves the capsule its
                // width. Both on the right cost it about three dots.
                circleButton(icon: "magnifyingglass", label: "Search profiles", action: onOpenSearch)

                Spacer(minLength: 0)

                dots

                Spacer(minLength: 0)

                circleButton(icon: "list.bullet", label: "All profiles", action: onOpenList)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, Self.bottomMargin(for: bottomInset))
    }

    /// The primary profile takes Weather's location arrow; the rest are dots.
    ///
    /// The capsule is the app's glass, the same surface the list button sits
    /// on, so the two read as one bar. It hugs the dots rather than filling
    /// the row: a full-height capsule around a line of 7pt dots looks like a
    /// button that lost its label.
    private var dots: some View {
        WeatherPageDots(
            count: count,
            index: index,
            primaryIndex: primaryIndex,
            onSelect: onSelectPage
        )
        .frame(height: Self.dots)
        .padding(.horizontal, 10)
        .weatherGlass(in: .capsule)
        .frame(height: Self.control)
        .accessibilityLabel("Profile \(index + 1) of \(count)")
    }

    private func circleButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: Self.control, height: Self.control)
        }
        .weatherGlass(in: .circle, interactive: true)
        .accessibilityLabel(label)
    }
}
