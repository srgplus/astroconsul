import SwiftUI

/// "Which chart is yours?": asked while the account owns charts and none of
/// them is marked as its own.
///
/// The primary profile is more than page one. It gets the weather alerts, it
/// is "your chart" in Activity, and it is the card other people see the
/// account as when it follows or likes them — without one, that card is
/// whichever chart the account touched last, which can be somebody's mother.
///
/// The server settles the plain case itself: an account's first chart becomes
/// its own. This covers the rest, one sheet for all of them — a chart given
/// to an empty account, an account from before the rule, an own chart that
/// was given away or deleted. With one chart it is already selected, so the
/// answer is a single tap; with several the reader picks. None of them being
/// the reader's is an answer too, and it leads to making the one that is.
struct PrimaryProfilePrompt: View {

    /// The charts the account owns, in the order the list shows them.
    let profiles: [ProfileSummary]

    /// Marks the chosen chart as the account's own. A failure comes back so
    /// the sheet can say so and stay up for another try.
    var onChoose: (ProfileSummary) async -> Error?

    /// "My chart isn't here": the presenter opens the new-profile form, and
    /// what it makes becomes the account's own.
    var onAddOwn: () -> Void

    /// Called once the sheet is done with, whichever way. The presenter lowers
    /// it; when it may be asked again is already on file.
    var onFinish: () -> Void

    @ObservedObject private var strings = L10n.shared
    @State private var selection: String?
    @State private var working = false
    @State private var failed = false

    init(
        profiles: [ProfileSummary],
        onChoose: @escaping (ProfileSummary) async -> Error?,
        onAddOwn: @escaping () -> Void,
        onFinish: @escaping () -> Void
    ) {
        self.profiles = profiles
        self.onChoose = onChoose
        self.onAddOwn = onAddOwn
        self.onFinish = onFinish
        // One chart is the obvious answer, so it is given; with several,
        // picking one for the reader would be a guess.
        _selection = State(initialValue: profiles.count == 1 ? profiles.first?.profileId : nil)
    }

    private var chosen: ProfileSummary? {
        profiles.first { $0.profileId == selection }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: Theme.Spacing.loose) {
                    icon
                    words
                    rows

                    if failed {
                        Text(L("primary.failed"))
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(Theme.error)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, Theme.Spacing.section)
                .padding(.top, Theme.Spacing.section)
                .frame(maxWidth: .infinity)
            }
            // The buttons stay at the bottom of the sheet and the charts
            // scroll above them, which only happens once there are more of
            // them than the detent holds.
            .scrollBounceBehavior(.basedOnSize)

            buttons
        }
        .presentationDetents([detent])
        // Frosted, like the other sheets that go up over the weather page.
        .presentationBackground(.regularMaterial)
        .presentationDragIndicator(.hidden)
    }

    /// Measured to the content for up to three charts; past that the sheet
    /// takes the screen and the rows scroll.
    private var detent: PresentationDetent {
        switch profiles.count {
        case ...1: return .height(452)
        case 2: return .height(524)
        case 3: return .height(596)
        default: return .large
        }
    }

    private var icon: some View {
        Image(systemName: "person.crop.circle.badge.checkmark")
            .font(.system(size: 40, weight: .light))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(Theme.text)
            .accessibilityHidden(true)
    }

    private var words: some View {
        VStack(spacing: Theme.Spacing.tight) {
            Text(L(profiles.count == 1 ? "primary.titleOne" : "primary.title"))
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)

            Text(L("primary.body"))
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textStrong)
                .multilineTextAlignment(.center)
        }
    }

    private var rows: some View {
        VStack(spacing: Theme.Spacing.tight) {
            ForEach(profiles) { profile in
                row(profile)
            }
        }
    }

    /// A native button per chart: rows in a scroll view take their taps from
    /// a `Button`, never a gesture, or the first tap goes to the scroll.
    private func row(_ profile: ProfileSummary) -> some View {
        let isSelected = profile.profileId == selection

        return Button {
            selection = profile.profileId
            failed = false
        } label: {
            HStack(spacing: Theme.Spacing.base) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? Color.blue : Theme.textDim)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(profile.profileName)
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)

                        Text("@\(profile.username)")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Theme.textDim)
                            .lineLimit(1)
                    }

                    if let birth = birthLine(profile) {
                        Text(birth)
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(Theme.textDim)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(isSelected ? 0.10 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? Color.blue.opacity(0.6) : Color.clear, lineWidth: 1.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(working)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// When and where the chart's person was born: what tells your own chart
    /// from a namesake's, where the Big 3 would not.
    private func birthLine(_ profile: ProfileSummary) -> String? {
        let place = profile.locationName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = [profile.birthMoment?.date, place].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var buttons: some View {
        VStack(spacing: 2) {
            Button {
                choose()
            } label: {
                ZStack {
                    // The label keeps its place while the spinner runs, so
                    // the button does not change height mid-tap.
                    Text(L("primary.choose")).opacity(working ? 0 : 1)
                    if working {
                        ProgressView().tint(.white)
                    }
                }
                .font(.system(.body, design: .rounded).weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            // Greyed only while nothing is chosen. Not while saving: a white
            // spinner on a grey fill is a spinner nobody can see, and
            // `choose()` guards the second tap itself.
            .disabled(chosen == nil)
            .padding(.bottom, Theme.Spacing.tight)

            Button(L("primary.addOwn")) {
                onAddOwn()
            }
            .font(.system(.body, design: .rounded))
            .foregroundStyle(Theme.text)
            .padding(.vertical, Theme.Spacing.tight)
            .disabled(working)

            Button(L("primary.later")) {
                onFinish()
            }
            .font(.system(.body, design: .rounded))
            .foregroundStyle(Theme.textDim)
            .padding(.vertical, Theme.Spacing.tight)
            .disabled(working)
        }
        .padding(.horizontal, Theme.Spacing.section)
        .padding(.bottom, Theme.Spacing.base)
    }

    private func choose() {
        guard !working, let chosen else { return }
        working = true
        failed = false
        Task {
            let error = await onChoose(chosen)
            working = false
            if error == nil {
                onFinish()
            } else {
                failed = true
            }
        }
    }
}

/// When "Which chart is yours?" may go up again.
///
/// Once a day while the question stands, answered or not: "Not now" is a
/// real answer, and a sheet on every launch would be a toll on the accounts
/// that only keep other people's charts. Stamped when the sheet is shown, so
/// an app killed with it up does not ask again on the next open.
enum PrimaryPromptSchedule {

    private static let key = "primaryPrompt.shownAt"

    /// Under a day, so an app opened each morning at roughly the same time
    /// asks each morning rather than every other one.
    private static let interval: TimeInterval = 20 * 60 * 60

    static var isDue: Bool {
        let last = UserDefaults.standard.double(forKey: key)
        return last == 0 || Date().timeIntervalSince1970 - last >= interval
    }

    static func markShown() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key)
    }

    /// Signing out: the next account on this phone gets its own day.
    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

#if DEBUG
#Preview("One chart") {
    Color.black
        .sheet(isPresented: .constant(true)) {
            PrimaryProfilePrompt(
                profiles: [WeatherPreviewData.profile],
                onChoose: { _ in nil },
                onAddOwn: {},
                onFinish: {}
            )
        }
}

#Preview("Several charts") {
    Color.black
        .sheet(isPresented: .constant(true)) {
            PrimaryProfilePrompt(
                profiles: Array(WeatherPreviewData.profiles.prefix(3)),
                onChoose: { _ in nil },
                onAddOwn: {},
                onFinish: {}
            )
        }
}
#endif
