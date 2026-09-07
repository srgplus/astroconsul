import SwiftUI

/// The first-run offer to turn category-change alerts on.
///
/// The feature shipped behind a switch in Settings, which is the one screen a
/// new account has no reason to open — so the app's only outward-facing thing
/// was off for everyone who never went looking for it. This asks once, on the
/// first run that reaches a loaded weather screen, and takes the answer either
/// way.
///
/// It is an in-app card and not the system prompt on its own. iOS grants one
/// permission sheet per install: spending it cold, over a screen the person
/// has just met, is how an app ends up permanently denied. The card says what
/// the alerts are for first, and only a tap on "Turn them on" spends it.
struct CategoryAlertsOffer: View {

    /// The profile the schedule will be built for — the one the home screen
    /// already holds, so accepting does not cost a round trip to find it.
    var profile: ProfileSummary?

    /// Called once the question is answered, whichever way. The presenter
    /// lowers the sheet; the answer is already on file by then.
    var onFinish: () -> Void

    @ObservedObject private var alerts = CategoryAlerts.shared
    @State private var working = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: Theme.Spacing.loose) {
                    icon
                    words
                }
                .padding(.horizontal, Theme.Spacing.section)
                .padding(.top, Theme.Spacing.section)
                .frame(maxWidth: .infinity)
            }
            // The card is short and the buttons belong at the bottom of the
            // sheet rather than under the last line of text, so the scroll
            // view takes the slack and they stay put.
            .scrollBounceBehavior(.basedOnSize)

            buttons
        }
        .presentationDetents([.medium])
        // Frosted, like the other sheets that sit over the weather page: the
        // sky carries on behind it, which is the thing being offered.
        .presentationBackground(.regularMaterial)
        .presentationDragIndicator(.hidden)
        // A question with two answers on it is not dismissed by swiping past
        // it — a swipe would leave `offered` unwritten and ask again tomorrow.
        .interactiveDismissDisabled()
    }

    private var icon: some View {
        Image(systemName: "bell.badge")
            .font(.system(size: 40, weight: .light))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(Theme.text)
            .accessibilityHidden(true)
    }

    private var words: some View {
        VStack(spacing: Theme.Spacing.base) {
            Text("Know when the weather turns")
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)

            Text(
                """
                Your cosmic weather reads as one of twelve categories, from \
                Calm to Explosive. We'll tell you on the days ahead when it \
                moves to a different one.
                """
            )
            .font(.system(.subheadline, design: .rounded))
            .foregroundStyle(Theme.textStrong)
            .multilineTextAlignment(.center)

            Text("Around midday, and only on the days it actually changes.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)
        }
    }

    private var buttons: some View {
        VStack(spacing: Theme.Spacing.tight) {
            Button {
                accept()
            } label: {
                ZStack {
                    // The label stays in the layout while the spinner runs, so
                    // the button does not change height mid-tap.
                    Text("Turn them on").opacity(working ? 0 : 1)
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
            .disabled(working)

            Button("Not now") {
                alerts.declineOffer()
                onFinish()
            }
            .font(.system(.body, design: .rounded))
            .foregroundStyle(Theme.textDim)
            .padding(.vertical, Theme.Spacing.tight)
            .disabled(working)
        }
        .padding(.horizontal, Theme.Spacing.section)
        .padding(.bottom, Theme.Spacing.loose)
    }

    private func accept() {
        working = true
        Task {
            // Closes on the answer, granted or refused. A refusal is the
            // system's own sheet and the person has just read it; holding this
            // card up afterwards to say so again is a lecture.
            await alerts.acceptOffer(profile: profile)
            working = false
            onFinish()
        }
    }
}

#if DEBUG
#Preview {
    Color.black
        .sheet(isPresented: .constant(true)) {
            CategoryAlertsOffer(profile: nil, onFinish: {})
        }
}
#endif
