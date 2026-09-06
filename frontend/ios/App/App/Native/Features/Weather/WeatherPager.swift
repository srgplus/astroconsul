import SwiftUI

/// Horizontal pager over profiles with Weather's floating bottom bar: the
/// chart button on the left, page dots in the middle, the profile list on the
/// right. Generic over the page so previews can feed it seeded screens.
struct WeatherPager<Page: View>: View {

    let profiles: [ProfileSummary]
    @Binding var selection: String
    let primaryProfileId: String?
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
                onOpenList: onOpenList
            )
        }
    }
}

/// The bar itself. Translucent so the sky of the current page shows through,
/// exactly as Weather's does.
struct WeatherBottomBar: View {

    let count: Int
    let index: Int
    let primaryIndex: Int?
    var onSelectPage: (Int) -> Void
    var onOpenList: () -> Void

    var body: some View {
        HStack {
            // Balances the list button so the dots stay centred on screen.
            Color.clear
                .frame(width: 42, height: 42)

            dots
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)

            circleButton(icon: "list.bullet", label: "All profiles", action: onOpenList)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background {
            // Dark scheme inside the background so the blur stays dark over a
            // bright sky and the white glyphs keep their contrast.
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.18))
                .environment(\.colorScheme, .dark)
                .ignoresSafeArea()
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.14))
                .frame(height: 1)
        }
    }

    /// The primary profile takes Weather's location arrow; the rest are dots.
    private var dots: some View {
        WeatherPageDots(
            count: count,
            index: index,
            primaryIndex: primaryIndex,
            onSelect: onSelectPage
        )
        .frame(height: 30)
        .background(
            Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
        )
        .accessibilityLabel("Profile \(index + 1) of \(count)")
    }

    private func circleButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(
                    Circle().strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
                )
        }
        .accessibilityLabel(label)
    }
}
