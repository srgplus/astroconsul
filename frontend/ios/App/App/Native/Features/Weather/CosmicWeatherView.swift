import SwiftUI

/// Cosmic weather for one profile, laid out the way Apple Weather lays out a
/// city: the sky is the reading, TII stands in for temperature and the
/// feels-like label for "Cloudy". One forecast request feeds the whole screen.
struct CosmicWeatherView: View {

    let profile: ProfileSummary

    @StateObject private var model: CosmicWeatherViewModel
    @Environment(\.dismiss) private var dismiss

    init(profile: ProfileSummary) {
        self.profile = profile
        _model = StateObject(wrappedValue: CosmicWeatherViewModel())
    }

    #if DEBUG
    /// Autoclosure so the model is built on the main actor when SwiftUI
    /// installs the view, not at the call site.
    init(profile: ProfileSummary, model: @autoclosure @escaping () -> CosmicWeatherViewModel) {
        self.profile = profile
        _model = StateObject(wrappedValue: model())
    }
    #endif

    /// The sky needs a colour before the forecast lands, so fall back to the
    /// TII the profile list already carried in.
    private var zone: TiiZone {
        TiiZone(tii: model.today?.tii ?? profile.latestTransit?.tii ?? 0)
    }

    var body: some View {
        ZStack {
            WeatherSky.gradient(for: zone)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.4), value: zone)

            ScrollView {
                VStack(spacing: 18) {
                    hero
                        .padding(.top, 8)
                        .padding(.bottom, 6)

                    content
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .refreshable { await model.load(profileId: profile.profileId, showSpinner: false) }
        }
        .navigationBarTitleDisplayMode(.inline)
        // Transparent at the top, blurred once the hero scrolls under it —
        // the same protection Weather gives its content. The dark scheme keeps
        // the back button white against that blur in both themes.
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                        Text("Profiles")
                            .font(.system(size: 17, design: .rounded))
                    }
                    .foregroundStyle(.white)
                }
                .accessibilityLabel("Back to profiles")
            }
        }
        .tint(.white)
        .task {
            // A seeded model (previews, harness) is already loaded.
            guard model.state == .idle else { return }
            await model.load(profileId: profile.profileId)
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "location.fill")
                    .font(.system(size: 11, weight: .semibold))

                Text(subtitle.uppercased())
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .tracking(0.5)
                    .lineLimit(1)
            }
            .foregroundStyle(.white.opacity(0.75))

            Text(profile.profileName)
                .font(.system(size: 34, weight: .regular, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(temperature)
                .font(.system(size: 92, weight: .ultraLight, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .padding(.leading, 14)   // optical centring: the ° hangs right
                .padding(.vertical, -8)

            Text(model.today?.feelsLike ?? profile.latestTransit?.feelsLike ?? " ")
                .font(.system(size: 21, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))

            if let high = model.high, let low = model.low {
                Text("H:\(Int(high.rounded()))°  L:\(Int(low.rounded()))°")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
                    .monospacedDigit()
                    .accessibilityLabel(
                        "High \(Int(high.rounded())), low \(Int(low.rounded())) over the next \(model.days.count) days"
                    )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var subtitle: String {
        let location = profile.locationName ?? ""
        return location.isEmpty ? "@\(profile.username)" : location
    }

    private var temperature: String {
        guard let tii = model.today?.tii ?? profile.latestTransit?.tii else { return "--°" }
        return "\(Int(tii.rounded()))°"
    }

    // MARK: - Body states

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView()
                .controlSize(.large)
                .tint(Theme.spinner)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)

        case let .failed(message):
            WeatherCard {
                WeatherCardHeader(icon: "exclamationmark.triangle", title: "No forecast")
                    .padding(.bottom, 8)

                Text(message)
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Try again") {
                    Task { await model.load(profileId: profile.profileId) }
                }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.top, 10)
            }

        case .loaded:
            if let today = model.today, let high = model.high, let low = model.low {
                TodaySummaryCard(day: today)
                ForecastCard(days: model.days, low: low, high: high)
            } else {
                WeatherCard {
                    Text("No forecast days came back for this profile.")
                        .font(.system(size: 15, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
    }
}
