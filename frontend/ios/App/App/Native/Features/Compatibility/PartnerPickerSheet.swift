import SwiftUI

/// Who to compare this page's chart against.
///
/// Only profiles the account already has: its own and the ones it follows. A
/// stranger's chart is not readable — the synastry route serves what the
/// account can see — so finding new people stays where it belongs, on the
/// search screen, and this sheet is a pick rather than a search of the world.
///
/// One flat list in the order the pager itself uses, own profiles first: it
/// runs to a handful of rows on most accounts, and a reader looking for their
/// partner knows which name they are after.
struct PartnerPickerSheet: View {

    let profile: ProfileSummary
    let candidates: [ProfileSummary]
    /// The partner already chosen, marked with a tick so a second visit says
    /// which row the card is currently reading.
    var chosenId: String?
    var skyState: SkyState?
    var onPick: (ProfileSummary) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var strings = L10n.shared
    @State private var query = ""

    private var results: [ProfileSummary] {
        candidates.filter { $0.matches(query) }
    }

    var body: some View {
        NavigationStack {
            list
                .navigationTitle(L("synastry.pickTitle"))
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $query, prompt: L("profiles.searchPrompt"))
                // Same as the profile list: the system bar's material stops
                // dead in a line across the rows, so it is hidden and the
                // glass behind the sheet carries the top instead.
                .hidingBarBackground()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(L("common.close")) { dismiss() }
                    }
                }
        }
        .tint(.white)
        .presentationDetents([.medium, .large])
        .presentationBackground { WeatherGlassBackdrop(state: skyState) }
        // The sheet stands on a frosted sky, not on a system background, so
        // its chrome is told which of the two it is: left to the device the
        // search field and the title resolve for a white page.
        .environment(\.colorScheme, .dark)
        .onAppear { SkyPlayerPool.shared.setPlaying(false, variant: .screen) }
        .onDisappear { SkyPlayerPool.shared.setPlaying(true, variant: .screen) }
    }

    private var list: some View {
        List {
            Section {
                ForEach(results) { candidate in
                    row(candidate)
                }

                if results.isEmpty {
                    Text(query.isEmpty ? L("synastry.noCandidates") : L("profiles.noMatch", query))
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            } header: {
                // The page's own half of the pair, so the sheet reads as
                // "Alena × …" rather than as a bare list of names.
                HStack(spacing: 8) {
                    PersonAvatar(name: profile.profileName, side: .a, size: 26)

                    Text(profile.profileName)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .tracking(0.4)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)

                    // The list completes the pair, so the header is one half
                    // of it and the times sign says a second is being picked.
                    Text("\u{00D7}")
                        .font(.system(size: 13, weight: .light, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.bottom, 2)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    private func row(_ candidate: ProfileSummary) -> some View {
        Button {
            onPick(candidate)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                PersonAvatar(name: candidate.profileName, side: .b, size: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.profileName)
                        .font(.system(size: 16, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text("@\(candidate.username)")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)

                        if let place = candidate.locationName {
                            Text("· \(place)")
                                .font(.system(size: 13, design: .rounded))
                                .foregroundStyle(.white.opacity(0.45))
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: 8)

                if candidate.profileId == chosenId {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(.white.opacity(0.12))
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }
}

#if DEBUG
#Preview("Partner picker") {
    PartnerPickerSheet(
        profile: WeatherPreviewData.profile,
        candidates: Array(WeatherPreviewData.profiles.dropFirst()),
        chosenId: WeatherPreviewData.partner.profileId,
        skyState: .flowing,
        onPick: { _ in }
    )
}
#endif
