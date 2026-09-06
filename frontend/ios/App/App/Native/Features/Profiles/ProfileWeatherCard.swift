import SwiftUI

/// A profile as a city card: the same shape Weather uses for its saved
/// locations, so the list and the detail screen read as one app. TII stands in
/// for temperature and the feels-like label for the condition.
struct ProfileWeatherCard: View {

    let profile: ProfileSummary
    let isPrimary: Bool

    private var tii: Double? { profile.latestTransit?.tii }
    private var zone: TiiZone? { tii.map(TiiZone.init(tii:)) }

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

                if let location = profile.locationName, !location.isEmpty {
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
                    SkyVideo(zone: zone, variant: .card, phase: profile.profileId)

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
    }

    private var temperature: String {
        guard let tii else { return "--°" }
        return "\(Int(tii.rounded()))°"
    }
}
