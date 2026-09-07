import SwiftUI

/// Search across profiles, the way Weather searches cities: type, and the
/// screen answers in two halves — the profiles you already have at the top,
/// the ones you could subscribe to below. Reached from the bottom bar.
///
/// The saved half is filtered out of the list model, which already holds it,
/// so it answers on the keystroke. The other half is a request, and the
/// screen waits a beat before making it.
struct ProfileSearchScreen: View {

    @ObservedObject var list: ProfileListViewModel
    @StateObject private var model: ProfileSearchViewModel

    /// Picking a profile that is already saved just turns the pager to it.
    var onSelect: (ProfileSummary) -> Void

    /// The sky of the page this screen was opened from, so the glass behind it
    /// carries that colour.
    var skyState: SkyState?

    init(
        list: ProfileListViewModel,
        onSelect: @escaping (ProfileSummary) -> Void,
        skyState: SkyState? = nil
    ) {
        self.list = list
        self.onSelect = onSelect
        self.skyState = skyState
        _model = StateObject(wrappedValue: ProfileSearchViewModel())
    }

    #if DEBUG
    /// Autoclosure so the model is built on the main actor when SwiftUI
    /// installs the view, not at the call site.
    init(
        list: ProfileListViewModel,
        onSelect: @escaping (ProfileSummary) -> Void,
        skyState: SkyState? = nil,
        model: @autoclosure @escaping () -> ProfileSearchViewModel
    ) {
        self.list = list
        self.onSelect = onSelect
        self.skyState = skyState
        _model = StateObject(wrappedValue: model())
    }
    #endif

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var strings = L10n.shared
    @State private var query = ""
    @State private var preview: ProfileSummary?
    @FocusState private var isFocused: Bool

    private var term: String { query.trimmingCharacters(in: .whitespaces) }

    private var mine: [ProfileSummary] { list.ownProfiles.filter { $0.matches(term) } }
    private var following: [ProfileSummary] { list.followedProfiles.filter { $0.matches(term) } }

    /// Remote matches minus everything already on the saved list. The search
    /// route drops the caller's own profiles but returns followed ones, and
    /// offering a plus next to a profile you already follow is a lie.
    private var discoveries: [ProfileSummary] {
        let saved = list.savedProfileIds
        return model.discoveries.filter { !saved.contains($0.profileId) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // A plain title rather than a navigation bar: this screen pushes
            // nothing, and a bar here draws its own material and paints the
            // title in the system's colour, which over the sky came out black.
            Text(L("search.title"))
                .font(.system(size: 17, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.top, 18)
                .padding(.bottom, 12)

            results
        }
        .tint(.white)
        .safeAreaInset(edge: .bottom, spacing: 0) { searchBar }
        .presentationBackground { WeatherGlassBackdrop(state: skyState) }
        // Same reason as the profile list: this screen stands on a frosted
        // night sky, and left to the device's appearance the text field and
        // the keyboard resolve for a white page.
        .environment(\.colorScheme, .dark)
        .task {
            await model.loadSuggestions()
            // The screen exists to be typed into, so it opens with the
            // keyboard up rather than asking for a tap first.
            isFocused = true
        }
        // Debounced: `.task(id:)` cancels the in-flight search on the next
        // keystroke, so a fast typist makes one request, not one per letter.
        .task(id: query) {
            guard !term.isEmpty else {
                await model.search("")
                return
            }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await model.search(term)
        }
        .sheet(item: $preview) { profile in
            ProfilePreviewSheet(
                profile: profile,
                isSubscribing: model.following.contains(profile.profileId),
                errorText: $model.followError,
                onSubscribe: {
                    Task {
                        if await model.follow(profile, using: list) {
                            preview = nil
                            close(selecting: profile)
                        }
                    }
                }
            )
        }
        // Only while no preview is up: both screens watch the same error, and
        // presenting this one over an open sheet makes SwiftUI close the sheet
        // to show it — so a plus tapped inside the preview would throw the
        // user back to the list.
        .alert(
            L("search.followError"),
            isPresented: Binding(
                get: { model.followError != nil && preview == nil },
                set: { if !$0 { model.followError = nil } }
            )
        ) {
            Button(L("common.ok"), role: .cancel) { model.followError = nil }
        } message: {
            Text(model.followError ?? "")
        }
    }

    // MARK: - Results

    private var results: some View {
        List {
            if !mine.isEmpty {
                section(L("profiles.mine"), profiles: mine) { saved($0) }
            }

            if !following.isEmpty {
                section(L("profiles.following"), profiles: following) { saved($0) }
            }

            if !discoveries.isEmpty {
                section(L(term.isEmpty ? "search.discover" : "search.new"), profiles: discoveries) {
                    discovery($0)
                }
            }

            status
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private var status: some View {
        switch model.state {
        case .searching where discoveries.isEmpty:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(Theme.spinner)
                Text(L("search.searching"))
            }
            .modifier(StatusRow())

        case let .failed(text):
            Text(text).modifier(StatusRow())

        case .suggestions where mine.isEmpty && following.isEmpty && discoveries.isEmpty:
            Text(L("search.hint")).modifier(StatusRow())

        case .results where mine.isEmpty && following.isEmpty && discoveries.isEmpty:
            Text(L("profiles.noMatch", term)).modifier(StatusRow())

        default:
            EmptyView()
        }
    }

    private func section<Row: View>(
        _ title: String,
        profiles: [ProfileSummary],
        @ViewBuilder row: @escaping (ProfileSummary) -> Row
    ) -> some View {
        Section {
            ForEach(profiles) { profile in
                row(profile)
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(.white.opacity(0.12))
                    .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
            }
        } header: {
            Text(title.uppercased())
                .font(.system(size: 12, design: .rounded).weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))
                .tracking(0.6)
        }
    }

    // MARK: - Rows

    /// A profile already on the list: tapping it turns the pager to its page,
    /// so it shows its reading instead of a subscribe button.
    private func saved(_ profile: ProfileSummary) -> some View {
        Button {
            close(selecting: profile)
        } label: {
            HStack(spacing: 12) {
                ProfileSearchLabel(profile: profile, term: term)

                Spacer(minLength: 8)

                if let tii = profile.latestTransit?.tii {
                    Text("\(Int(tii.rounded()))°")
                        .font(.system(size: 20, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// A profile not saved yet: tapping the row opens a preview to look at
    /// first, the plus subscribes without one.
    private func discovery(_ profile: ProfileSummary) -> some View {
        HStack(spacing: 12) {
            Button {
                preview = profile
            } label: {
                HStack(spacing: 12) {
                    ProfileSearchLabel(profile: profile, term: term)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            subscribeButton(profile)
        }
    }

    private func subscribeButton(_ profile: ProfileSummary) -> some View {
        Button {
            Task {
                if await model.follow(profile, using: list) {
                    close(selecting: profile)
                }
            }
        } label: {
            Group {
                if model.following.contains(profile.profileId) {
                    ProgressView().controlSize(.small).tint(Theme.spinner)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .weatherGlass(in: .circle, interactive: true)
        .accessibilityLabel(L("search.subscribeTo", profile.profileName))
    }

    // MARK: - Search bar

    /// Weather's search field: at the bottom, over the sky, with the close
    /// button beside it rather than a Cancel word inside the row.
    private var searchBar: some View {
        WeatherGlassGroup(spacing: 12) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))

                    TextField(
                        "",
                        text: $query,
                        prompt: Text(L("profiles.searchPrompt")).foregroundColor(.white.opacity(0.55))
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .foregroundStyle(.white)
                    .focused($isFocused)

                    if !query.isEmpty {
                        Button {
                            query = ""
                            isFocused = true
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L("search.clear"))
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .weatherGlass(in: .capsule)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .weatherGlass(in: .circle, interactive: true)
                .accessibilityLabel(L("search.close"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        // The list scrolls behind the field, so without this a half-cut row
        // shows in the strip below it and reads as a layout mistake.
        .background {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.55), location: 0.45),
                    .init(color: .black.opacity(0.92), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }

    private func close(selecting profile: ProfileSummary) {
        onSelect(profile)
        dismiss()
    }
}

/// Name and handle with the typed term picked out, the way Weather bolds the
/// matched part of a city name and greys the rest.
private struct ProfileSearchLabel: View {

    let profile: ProfileSummary
    let term: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(highlight(profile.profileName))
                .font(.system(size: 17, design: .rounded))
                .lineLimit(1)

            HStack(spacing: 6) {
                Text(highlight("@\(profile.username)"))
                    .font(.system(size: 13, design: .rounded))
                    .lineLimit(1)

                if let place = profile.currentLocationName ?? profile.locationName {
                    Text("· \(place)")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
        }
    }

    private func highlight(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        attributed.foregroundColor = .white.opacity(0.62)

        guard !term.isEmpty,
              let range = attributed.range(of: term, options: [.caseInsensitive])
        else {
            // Nothing typed: the row is not a match of anything, so it reads
            // at full strength rather than as one long unmatched tail.
            if term.isEmpty { attributed.foregroundColor = .white }
            return attributed
        }

        attributed[range].foregroundColor = .white
        attributed[range].inlinePresentationIntent = .stronglyEmphasized
        return attributed
    }
}

/// A one-line message in the results list — searching, failed, or nothing
/// found — sitting on the sky rather than on a row background.
private struct StatusRow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 15, design: .rounded))
            .foregroundStyle(.white.opacity(0.65))
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20))
    }
}
