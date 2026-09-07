import SwiftUI

/// What a fresh account lands on: no profiles, so no pager, and so no bottom
/// bar to reach the rest of the app from.
///
/// Without chrome of its own this screen was a dead end. The wordmark, the
/// plus and Settings all live on the profile list's toolbar, the profile list
/// opens from the pager's bottom bar, and the pager needs a profile to exist
/// before it draws one. A brand-new account could not search for a profile to
/// follow, and could not reach Settings — which is where signing out is.
///
/// The header is the list screen's, item for item, so the two read as the same
/// app: a new profile on the left, the wordmark in the middle, Settings on the
/// right. Search sits under it and opens the same screen the bottom bar's
/// magnifying glass does, because "find one to follow" is the other half of
/// what the hint offers.
struct WeatherEmptyState: View {

    var onCreateProfile: () -> Void
    var onOpenSearch: () -> Void
    var onOpenSettings: () -> Void

    /// Watched so the screen redraws when the language is switched in the
    /// Settings sheet it now opens itself.
    @ObservedObject private var strings = L10n.shared

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                searchField

                // Centred in whatever the header leaves, rather than in the
                // screen: a `Spacer` either side would put it under the
                // search field on a small phone.
                message
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, Theme.Spacing.loose)
        }
    }

    /// The list screen's toolbar, hand-built: there is no navigation stack
    /// here to hang one on, and a bar would draw its own material over a
    /// background that is already flat.
    private var header: some View {
        HStack(spacing: 0) {
            iconButton("plus", label: L("profiles.new"), action: onCreateProfile)

            Spacer(minLength: 0)

            // Fixed size so the mark keeps its own width and the two buttons,
            // equal at 44pt, leave it on the centre line.
            B3Wordmark(size: 24).fixedSize()

            Spacer(minLength: 0)

            iconButton("gearshape", label: L("settings.title"), action: onOpenSettings)
        }
        .padding(.top, 4)
    }

    /// A plain glyph with a 44pt tap target around it, the way the list
    /// screen's toolbar buttons read. Tinted `Theme.text` rather than white:
    /// this screen stands on the app background, which is light in the light
    /// appearance.
    private func iconButton(
        _ icon: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.text)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// A field to look at, a button to tap. The search screen owns the real
    /// one — keyboard, debounce, the subscribe flow — and a second live field
    /// here would be two of them to keep in step.
    private var searchField: some View {
        Button(action: onOpenSearch) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textDim)

                Text(L("profiles.searchPrompt"))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Theme.textDim)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Theme.line, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("home.searchProfiles"))
        .padding(.top, 8)
    }

    /// Both ways out of an empty account, named: the hint says there are two,
    /// the button takes the first, the field above takes the second.
    private var message: some View {
        VStack(spacing: Theme.Spacing.base) {
            Image(systemName: "person.2")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.textDim)

            Text(L("home.noProfiles"))
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.text)

            Text(L("home.noProfilesBody"))
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)

            Button(L("home.createProfile"), action: onCreateProfile)
                .font(.system(.body, design: .rounded).weight(.medium))
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .padding(.top, 4)
        }
        .padding(.horizontal, Theme.Spacing.tight)
    }
}

#Preview("Empty home") {
    WeatherEmptyState(
        onCreateProfile: {},
        onOpenSearch: {},
        onOpenSettings: {}
    )
}
