import SwiftUI

/// A profile you have found but not subscribed to yet, shown the way Weather
/// previews a city you searched for: its own sky, the reading in the middle,
/// a cross to back out and a plus to keep it.
///
/// Everything here comes from the search payload. The forecast endpoint
/// refuses a profile you neither own nor follow, so a preview asks for
/// nothing: what it can show is the last reading, the Big 3 and the birth
/// moment — enough to tell one Alex from another before subscribing.
struct ProfilePreviewSheet: View {

    let profile: ProfileSummary
    var isSubscribing: Bool = false
    /// A refused subscription, shown here rather than by the screen that
    /// presented this one: an alert raised behind a sheet never appears, so
    /// tapping the plus would look like it did nothing.
    @Binding var errorText: String?
    var onSubscribe: () -> Void

    init(
        profile: ProfileSummary,
        isSubscribing: Bool = false,
        errorText: Binding<String?> = .constant(nil),
        onSubscribe: @escaping () -> Void
    ) {
        self.profile = profile
        self.isSubscribing = isSubscribing
        _errorText = errorText
        self.onSubscribe = onSubscribe
    }

    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var strings = L10n.shared

    private var zone: TiiZone? { profile.latestTransit?.tii.map(TiiZone.init(tii:)) }
    private var state: SkyState? {
        zone.map { SkyState(label: profile.latestTransit?.feelsLike, zone: $0) }
    }

    var body: some View {
        ZStack {
            WeatherSky.cardGradient(for: zone).ignoresSafeArea()

            if let state {
                SkyVideo(state: state, phase: profile.profileId).ignoresSafeArea()
            }

            LinearGradient(
                colors: [.black.opacity(0.25), .clear, .black.opacity(0.35)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            ScrollView {
                VStack(spacing: 18) {
                    hero.padding(.top, 8)
                    bigThree
                    birth
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .top, spacing: 0) { chrome }
        }
        .foregroundStyle(.white)
        .presentationBackground(.black)
        .alert(
            L("search.followError"),
            isPresented: Binding(
                get: { errorText != nil },
                set: { if !$0 { errorText = nil } }
            )
        ) {
            Button(L("common.ok"), role: .cancel) { errorText = nil }
        } message: {
            Text(errorText ?? "")
        }
    }

    // MARK: - Chrome

    /// Cross on the left, plus on the right — the two answers this screen
    /// asks for, in the corners Weather puts them.
    private var chrome: some View {
        WeatherGlassGroup(spacing: 12) {
            HStack {
                circle(icon: "xmark", label: L("common.cancel")) { dismiss() }

                Spacer()

                Button(action: onSubscribe) {
                    Group {
                        if isSubscribing {
                            ProgressView().controlSize(.small).tint(Theme.spinner)
                        } else {
                            Image(systemName: "plus")
                                .font(.system(size: 17, weight: .semibold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(isSubscribing)
                .weatherGlass(in: .circle, interactive: true)
                .accessibilityLabel(L("search.subscribeTo", profile.profileName))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func circle(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .weatherGlass(in: .circle, interactive: true)
        .accessibilityLabel(label)
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 2) {
            Text(profile.profileName)
                .font(.system(size: 30, weight: .regular, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text("@\(profile.username)")
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))

            if let tii = profile.latestTransit?.tii {
                Text("\(Int(tii.rounded()))°")
                    .font(.system(size: 88, weight: .thin, design: .rounded))
                    .monospacedDigit()
                    .padding(.top, 2)

                if let feels = profile.latestTransit?.feelsLike {
                    Text(feels)
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                }
            } else {
                Text(L("profiles.noReading"))
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.top, 24)
            }

            if let place = profile.currentLocationName {
                Text(place)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    // MARK: - Cards

    @ViewBuilder
    private var bigThree: some View {
        if let summary = profile.natalSummary,
           summary.sun != nil || summary.moon != nil || summary.asc != nil {
            card(title: L("preview.bigThree"), icon: "circle.dotted") {
                VStack(spacing: 0) {
                    placement("Sun", glyph: AstroGlyph.object("Sun"), value: summary.sun)
                    placement("Moon", glyph: AstroGlyph.object("Moon"), value: summary.moon)
                    placement("ASC", glyph: AstroGlyph.object("ASC"), value: summary.asc)
                }
            }
        }
    }

    @ViewBuilder
    private var birth: some View {
        if profile.locationName != nil || profile.birthMoment != nil {
            card(title: L("preview.born"), icon: "mappin.and.ellipse") {
                VStack(alignment: .leading, spacing: 3) {
                    if let place = profile.locationName {
                        Text(place).font(.system(size: 15, design: .rounded))
                    }
                    if let moment = profile.birthMoment {
                        Text([moment.date, moment.time].joined(separator: ", "))
                            .font(.system(size: 15, design: .rounded))
                            .monospacedDigit()
                    }
                }
                .foregroundStyle(.white.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// One row of the big three. `id` is the object's own id — "Sun", "ASC" —
    /// so the row can both look up its name and tell whether it is the last of
    /// the three.
    @ViewBuilder
    private func placement(_ id: String, glyph: String, value: String?) -> some View {
        if let value {
            HStack(spacing: 10) {
                // "AC" is two characters wide where the planets are one, so
                // the column is sized for it — at 22pt it wrapped to two lines.
                Text(glyph)
                    .font(.system(size: 17))
                    .lineLimit(1)
                    .frame(width: 28, alignment: .leading)

                Text(Astro.object(id))
                    .font(.system(size: 15, design: .rounded))

                Spacer(minLength: 8)

                // The sign leads the string the chart builder produced
                // ("Aries 27°04'12\""), so the row can show its glyph, and
                // read the sign in the app's language, without parsing the
                // degrees back out of it.
                if let sign = value.split(separator: " ").first {
                    Text(AstroGlyph.sign(String(sign)))
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.75))
                }

                Text(Self.localizedSign(in: value))
                    .font(.system(size: 15, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
            }
            .padding(.vertical, 9)
            .overlay(alignment: .bottom) {
                if id != "ASC" {
                    Rectangle()
                        .fill(.white.opacity(0.12))
                        .frame(height: 1)
                }
            }
        }
    }

    /// "Aries 27°04'12\"" → "Овен 27°04'12\"". The chart builder puts the
    /// sign first and the degrees after it, so only the first word moves.
    private static func localizedSign(in value: String) -> String {
        let parts = value.split(separator: " ", maxSplits: 1)
        guard let head = parts.first, let sign = Astro.sign(String(head)) else { return value }
        return parts.count > 1 ? "\(sign) \(parts[1])" : sign
    }

    private func card<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                Text(title.uppercased())
                    .font(.system(size: 12, design: .rounded).weight(.semibold))
                    .tracking(0.6)
            }
            .foregroundStyle(.white.opacity(0.65))

            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .weatherGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), tint: 0.34)
    }
}
