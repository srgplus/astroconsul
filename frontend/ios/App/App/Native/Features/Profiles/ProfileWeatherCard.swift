import SwiftUI

/// A profile as a city card: the same shape Weather uses for its saved
/// locations, so the list and the detail screen read as one app. TII stands in
/// for temperature and the feels-like label for the condition.
struct ProfileWeatherCard: View {

    let profile: ProfileSummary
    let isPrimary: Bool

    @ObservedObject private var device = DeviceLocation.shared

    /// Whether this card is on screen.
    ///
    /// A `List` keeps a row's views alive long after the row has scrolled out
    /// of sight — measured on the harness, twenty rows for the eight cards you
    /// can see — so footage tied to the row's lifetime means twenty decoders
    /// running for seven visible skies, which is what made a long list stutter
    /// under the finger. The row's own appear and disappear do land on the
    /// boundary, so the clip hangs off those instead and the player goes back
    /// to `SkyPlayerPool` the moment the card leaves.
    @State private var isOnScreen = false

    private var tii: Double? { profile.latestTransit?.tii }
    private var zone: TiiZone? { tii.map(TiiZone.init(tii:)) }

    /// The same answer the detail screen's hero gives, so the two agree: this
    /// device's location on your own card, the transit location on the rest.
    private var location: String? {
        if isPrimary, let here = device.placeName {
            return here
        }
        return profile.currentLocationName
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(profile.profileName)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .lineLimit(1)

                    if isPrimary {
                        Image(systemName: "star.fill")
                            .font(.system(size: 11))
                            .opacity(0.85)
                            .accessibilityLabel("Primary profile")
                    }
                }

                Text("@\(profile.username)")
                    .font(.system(size: 13, design: .rounded))
                    .opacity(0.75)
                    .lineLimit(1)

                Spacer(minLength: 6)

                Text(profile.latestTransit?.feelsLike ?? "No reading yet")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .opacity(0.9)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                Text(temperature)
                    .font(.system(size: 42, weight: .thin, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)

                Spacer(minLength: 6)

                // The current location, matching the hero on the detail
                // screen. Birth location belongs to the profile, not to a
                // reading of today's sky.
                if let location {
                    Text(location)
                        .font(.system(size: 12, design: .rounded))
                        .opacity(0.75)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: 150, alignment: .trailing)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(height: 108)
        .background {
            ZStack {
                WeatherSky.cardGradient(for: zone)

                // Same footage as the profile's own screen, so tapping a card
                // lands on a sky the eye already recognises. A profile with no
                // reading has no zone and keeps the neutral gradient.
                if let zone {
                    if isOnScreen {
                        SkyVideo(zone: zone, variant: .card, phase: profile.profileId)
                    }

                    // The right-hand column sits over the brightest part of the
                    // sunlit clips, so the card carries its own scrim the way
                    // the full screen does.
                    LinearGradient(
                        colors: [.black.opacity(0.26), .black.opacity(0.06), .black.opacity(0.22)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
        .onAppear { isOnScreen = true }
        .onDisappear { isOnScreen = false }
    }

    private var temperature: String {
        guard let tii else { return "--°" }
        return "\(Int(tii.rounded()))°"
    }
}
