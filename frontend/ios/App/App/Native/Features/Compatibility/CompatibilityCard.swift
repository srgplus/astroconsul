import SwiftUI

/// Compatibility between the profile whose page this is and someone else on
/// the account — the web's synastry widget, as the last card of the weather
/// screen.
///
/// It closes the page for the same reason the birth chart sits above it: every
/// card before this one is one person's own sky, and this is the first that
/// needs a second chart. Two taps to a number — pick a partner, and the score
/// is on the card by the time the names have been read — with the reading
/// itself a sheet away.
///
/// The pair is remembered per page, so the card opens on whoever it was left
/// on. See `CompatibilityViewModel`.
struct CompatibilityCard: View {

    let profile: ProfileSummary

    /// Everyone this pair could be made of: the account's own profiles and the
    /// ones it follows, minus the page's own. Handed in rather than fetched —
    /// the home screen has already loaded the list the pager is built from.
    var candidates: [ProfileSummary] = []

    /// The sky this page is drawn in, so the picker's glass carries its colour
    /// rather than frosting flat white.
    var skyState: SkyState?

    /// Where an account with nobody to compare against is sent. Nil on the
    /// harness, where the card states the case and offers no way out of it.
    var onFindPeople: (() -> Void)?

    @StateObject private var model: CompatibilityViewModel
    @ObservedObject private var strings = L10n.shared

    @State private var showsPicker = false
    @State private var showsReport = false

    init(
        profile: ProfileSummary,
        candidates: [ProfileSummary] = [],
        skyState: SkyState? = nil,
        onFindPeople: (() -> Void)? = nil
    ) {
        self.profile = profile
        self.candidates = candidates
        self.skyState = skyState
        self.onFindPeople = onFindPeople
        _model = StateObject(wrappedValue: CompatibilityViewModel())
    }

    #if DEBUG
    /// Autoclosure so the model is built on the main actor when SwiftUI
    /// installs the view, not at the call site.
    init(
        profile: ProfileSummary,
        candidates: [ProfileSummary] = [],
        skyState: SkyState? = nil,
        onFindPeople: (() -> Void)? = nil,
        model: @autoclosure @escaping () -> CompatibilityViewModel
    ) {
        self.profile = profile
        self.candidates = candidates
        self.skyState = skyState
        self.onFindPeople = onFindPeople
        _model = StateObject(wrappedValue: model())
    }
    #endif

    var body: some View {
        WeatherCard {
            header

            if candidates.isEmpty && model.partner == nil {
                nobodyToCompare
            } else if let partner = model.partner {
                pair(with: partner)
            } else {
                invitation
            }
        }
        .sheet(isPresented: $showsPicker) {
            PartnerPickerSheet(
                profile: profile,
                candidates: candidates,
                chosenId: model.partner?.profileId,
                skyState: skyState,
                onPick: { chosen in
                    Task { await model.select(chosen, for: profile) }
                }
            )
        }
        .sheet(isPresented: $showsReport) {
            if let report = model.report {
                CompatibilityReportSheet(report: report)
            }
        }
        // Puts back the pair this page was last read with. A page the reader
        // never swipes to asks for nothing.
        .task {
            await model.restore(profile: profile, among: candidates)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.2.circle")
                .font(.system(size: 12, weight: .semibold))

            Text(L("synastry.title").uppercased())
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .tracking(0.5)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer(minLength: 8)

            if model.partner != nil {
                partnerMenu
            }
        }
        .foregroundStyle(.white.opacity(0.7))
    }

    /// Changing the partner and dropping it, in the same place the page's own
    /// ••• sits. A menu rather than the web's little × on the avatar: at this
    /// size that cross is a 12pt target sitting on top of another one.
    private var partnerMenu: some View {
        Menu {
            Button {
                showsPicker = true
            } label: {
                Label(L("synastry.changePartner"), systemImage: "person.2.badge.gearshape")
            }

            Button(role: .destructive) {
                model.clear(for: profile)
            } label: {
                Label(L("synastry.removePartner"), systemImage: "person.badge.minus")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        // Same reason as the page's own menu: the popup is a system view in
        // the system's appearance, so a white tint leaves white glyphs beside
        // black labels.
        .tint(Theme.text)
        .accessibilityLabel(L("synastry.partnerOptions"))
    }

    // MARK: - No partner yet

    /// The two slots with the second one empty, which is the whole invitation:
    /// this person, times somebody.
    private var invitation: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                person(name: profile.profileName, side: .a)

                Text("\u{00D7}")
                    .font(.system(size: 17, weight: .light, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.bottom, 16)

                VStack(spacing: 6) {
                    PersonAvatarPlaceholder(size: Self.avatar)

                    Text(L("synastry.choose"))
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                .frame(width: Self.nameColumn)
            }
            .padding(.top, 14)

            Text(L("synastry.pickPrompt"))
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 2)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        // A tap gesture rather than a Button: inside the pager's scroll view a
        // plain-styled Button never fires.
        .onTapGesture { showsPicker = true }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(L("synastry.pickPrompt"))
    }

    /// An account of one, following nobody: there is no second chart to read,
    /// so the card says so and points at the one screen that fixes it.
    private var nobodyToCompare: some View {
        VStack(alignment: .leading, spacing: 10) {
            WeatherCardDivider()

            Text(L("synastry.noCandidates"))
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            if let onFindPeople {
                Text(L("synastry.findPeople"))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentShape(Rectangle())
                    .onTapGesture { onFindPeople() }
                    .accessibilityAddTraits(.isButton)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - A pair

    @ViewBuilder
    private func pair(with partner: ProfileSummary) -> some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                person(name: profile.profileName, side: .a)

                middle

                person(name: partner.profileName, side: .b)
            }
            .padding(.top, 12)

            if case .loaded = model.state, let report = model.report {
                CompatibilityMeters(
                    categories: report.scores.categories(.love)
                )

                openReport
            }

            if case let .failed(message) = model.state {
                Text(message)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                action(L("common.tryAgain")) {
                    Task { await model.load(profile: profile) }
                }
            }

            if case .idle = model.state {
                action(L("synastry.viewSynastry")) {
                    Task { await model.load(profile: profile) }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// The gauge, or whatever stands in its place while there is no number to
    /// draw: the ring keeps its size throughout, so the card does not resize
    /// under the reader as the report lands.
    @ViewBuilder
    private var middle: some View {
        VStack(spacing: 8) {
            ZStack {
                switch model.state {
                case .loaded:
                    if let scores = model.report?.scores {
                        CompatibilityGauge(score: scores.overall, size: Self.gauge)
                    }

                case .loading:
                    MinimalSpinner(size: 22, lineWidth: 2)

                case .idle, .failed:
                    Image(systemName: "sparkles")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(width: Self.gauge, height: Self.gauge)

            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: Self.gauge + 20)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(scoreSpoken)
    }

    /// The overall label the server wrote — "Magnetic", "Магнетизм" — set in
    /// caps like every other band on the page. Blank while there is no reading,
    /// so the line keeps its height and nothing shifts when the word arrives.
    private var label: String {
        guard case .loaded = model.state, let scores = model.report?.scores else { return " " }
        return scores.overallLabel.uppercased()
    }

    private var scoreSpoken: String {
        guard case .loaded = model.state, let scores = model.report?.scores else {
            return L("synastry.title")
        }
        return L("synastry.scoreA11y", scores.overall, scores.overallLabel)
    }

    private func person(name: String, side: SynastrySide) -> some View {
        VStack(spacing: 6) {
            PersonAvatar(name: name, side: side, size: Self.avatar)

            Text(name)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(width: Self.nameColumn)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
    }

    /// The way into the reading. The web's gradient button, in the app's own
    /// glass: a full-width capsule is the one thing on the card that is meant
    /// to be pressed, so it says so at full width.
    private var openReport: some View {
        action(L("synastry.openReport"), icon: "chevron.right") {
            showsReport = true
        }
    }

    private func action(
        _ title: String,
        icon: String? = nil,
        perform: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .opacity(0.7)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background {
            Capsule().fill(
                LinearGradient(
                    colors: [
                        Theme.scoreArcStart.opacity(0.55),
                        Theme.scoreArcEnd.opacity(0.55),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
        .overlay {
            Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 1)
        }
        .contentShape(Capsule())
        .onTapGesture(perform: perform)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(title)
    }

    private static let avatar: CGFloat = 48
    private static let gauge: CGFloat = 104
    /// Wide enough for a first name, narrow enough that two of them plus the
    /// gauge still fit a 4.7" screen.
    private static let nameColumn: CGFloat = 74
}

#if DEBUG
#Preview("Compatibility — loaded") {
    ZStack {
        WeatherSky.gradient(for: .active).ignoresSafeArea()

        ScrollView {
            CompatibilityCard(
                profile: WeatherPreviewData.profile,
                candidates: WeatherPreviewData.profiles,
                skyState: .flowing,
                model: CompatibilityViewModel(
                    previewPartner: WeatherPreviewData.partner,
                    previewReport: WeatherPreviewData.synastry
                )
            )
            .padding(16)
        }
    }
}

#Preview("Compatibility — empty") {
    ZStack {
        WeatherSky.gradient(for: .quiet).ignoresSafeArea()

        ScrollView {
            CompatibilityCard(
                profile: WeatherPreviewData.profile,
                candidates: WeatherPreviewData.profiles,
                skyState: .calm
            )
            .padding(16)
        }
    }
}
#endif
