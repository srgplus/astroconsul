import SwiftUI

/// The profile's own settings: the name it is listed under and the birth data
/// every reading is cast from. Reached from the ••• menu on the weather page,
/// and only on a profile the viewer owns.
///
/// Saving recasts the chart, so the sheet asks its presenter to reload rather
/// than patching the list in place.
struct ProfileEditSheet: View {

    @StateObject private var model: ProfileEditViewModel

    /// The sky behind the glass, passed down from the page that opened this.
    var skyZone: TiiZone?

    var onSaved: () -> Void
    var onDeleted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showsDeleteConfirmation = false
    @State private var showsCoordinates = false
    @FocusState private var focused: Field?

    private enum Field: Hashable { case name, username, place }

    init(
        profile: ProfileSummary,
        skyZone: TiiZone? = nil,
        onSaved: @escaping () -> Void,
        onDeleted: @escaping () -> Void
    ) {
        _model = StateObject(wrappedValue: ProfileEditViewModel(profile: profile))
        self.skyZone = skyZone
        self.onSaved = onSaved
        self.onDeleted = onDeleted
    }

    #if DEBUG
    /// Autoclosure so the model is built on the main actor when SwiftUI
    /// installs the view, not at the call site.
    init(
        skyZone: TiiZone? = nil,
        onSaved: @escaping () -> Void = {},
        onDeleted: @escaping () -> Void = {},
        model: @autoclosure @escaping () -> ProfileEditViewModel
    ) {
        _model = StateObject(wrappedValue: model())
        self.skyZone = skyZone
        self.onSaved = onSaved
        self.onDeleted = onDeleted
    }
    #endif

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Edit Profile")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Close") { dismiss() }
                            .font(.system(.body, design: .rounded).weight(.medium))
                            .disabled(model.isSaving || model.isDeleting)
                    }
                }
        }
        .tint(Theme.text)
        .presentationBackground { WeatherGlassBackdrop(zone: skyZone) }
        .presentationDragIndicator(.visible)
        .task {
            // A seeded model (previews, harness) is already filled in.
            guard model.state == .loading else { return }
            await model.load()
        }
        .alert("Delete this profile?", isPresented: $showsDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    if await model.delete() {
                        onDeleted()
                        dismiss()
                    }
                }
            }
        } message: {
            Text("“\(model.profile.profileName)” and its natal chart are removed for good. This cannot be undone.")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            centered { ProgressView().controlSize(.large).tint(Theme.spinner) }

        case let .failed(message):
            centered {
                VStack(spacing: Theme.Spacing.base) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(Theme.textDim)

                    Text("Could not load this profile")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(Theme.text)

                    Text(message)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Theme.textDim)
                        .multilineTextAlignment(.center)

                    Button("Try again") { Task { await model.load() } }
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .padding(.top, 4)
                }
                .padding(Theme.Spacing.section)
            }

        case .ready:
            form
        }
    }

    private var form: some View {
        ScrollView {
            VStack(spacing: 20) {
                identityCard
                birthCard
                coordinatesCard

                if let message = model.errorMessage {
                    Text(message)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Theme.error)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                deleteButton
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { saveBar }
    }

    // MARK: - Cards

    private var identityCard: some View {
        card {
            row("Name") {
                TextField("Full name", text: $model.profileName)
                    .textContentType(.name)
                    .submitLabel(.next)
                    .focused($focused, equals: .name)
                    .onSubmit { focused = .username }
            }

            divider

            row("Username") {
                HStack(spacing: 1) {
                    Text("@").foregroundStyle(Theme.textDim)
                    TextField("username", text: $model.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused, equals: .username)
                }
            }
        }
    }

    private var birthCard: some View {
        VStack(spacing: 0) {
            card {
                row("Date") {
                    DatePicker(
                        "",
                        selection: $model.birthDate,
                        in: Self.earliestBirthday...Date(),
                        displayedComponents: .date
                    )
                    .labelsHidden()
                }

                divider

                row("Time") {
                    DatePicker("", selection: $model.birthTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }

                divider

                // The one field that needs the full width: a geocoded place
                // name runs to three commas, and the suggestions hang under it.
                VStack(alignment: .leading, spacing: 8) {
                    label("Birthplace")

                    HStack(spacing: 8) {
                        TextField("City, country", text: $model.locationName)
                            .autocorrectionDisabled()
                            .focused($focused, equals: .place)
                            .onChange(of: model.locationName) { _, _ in model.searchPlaces() }

                        if model.isSearching { MinimalSpinner(color: Theme.textDim) }
                    }
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Theme.text)

                    if model.locationNeedsResolving && model.suggestions.isEmpty && !model.isSearching {
                        Text("Pick a place from the list, or save and we will look this one up.")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Theme.textDim)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }

            suggestionList
        }
    }

    @ViewBuilder
    private var suggestionList: some View {
        if !model.suggestions.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(model.suggestions.enumerated()), id: \.element.id) { index, place in
                    if index > 0 { divider }

                    Button {
                        focused = nil
                        model.pick(place)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.textDim)

                            Text(place.displayName)
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(Theme.text)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(cardBackground)
            .padding(.top, 8)
        }
    }

    private var coordinatesCard: some View {
        card {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showsCoordinates.toggle() }
            } label: {
                HStack {
                    Text("Coordinates & Timezone")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Theme.text)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textDim)
                        .rotationEffect(.degrees(showsCoordinates ? 0 : -90))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showsCoordinates {
                divider
                readOnlyRow("Timezone", model.timezone.isEmpty ? "Not set" : model.timezone)
                divider
                readOnlyRow("Latitude", Self.coordinate(model.latitude))
                divider
                readOnlyRow("Longitude", Self.coordinate(model.longitude))

                Text("These come from the birthplace you pick, so they are never typed by hand.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }
        }
    }

    // MARK: - Actions

    private var saveBar: some View {
        Button {
            focused = nil
            Task {
                if await model.save() {
                    onSaved()
                    dismiss()
                }
            }
        } label: {
            HStack(spacing: 8) {
                // The fill is `Theme.text`, so the label and the arc are both
                // the page ground — white on a black button in light mode,
                // black on a white one in dark.
                if model.isSaving { MinimalSpinner(color: Theme.bg) }
                Text(model.isSaving ? "Saving…" : "Save Profile")
            }
            .font(.system(.body, design: .rounded).weight(.semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 50)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.text)
        .foregroundStyle(Theme.bg)
        .disabled(!model.canSave)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            focused = nil
            showsDeleteConfirmation = true
        } label: {
            HStack(spacing: 8) {
                if model.isDeleting {
                    MinimalSpinner(color: Theme.error)
                } else {
                    Image(systemName: "trash")
                }
                Text("Delete Profile")
            }
            .font(.system(.body, design: .rounded).weight(.medium))
            .foregroundStyle(Theme.error)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(cardBackground)
        .disabled(model.isSaving || model.isDeleting)
        .padding(.top, 4)
    }

    // MARK: - Pieces

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(cardBackground)
    }

    /// Translucent, never a solid fill: an opaque card would put a grey slab
    /// back over the frosted sky this sheet floats on.
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .stroke(Theme.line, lineWidth: 1)
            )
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.line)
            .frame(height: 1)
            .padding(.leading, 14)
    }

    private func row<Control: View>(
        _ title: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 12) {
            label(title)
                .frame(width: 92, alignment: .leading)

            control()
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func readOnlyRow(_ title: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            label(title)
                .frame(width: 92, alignment: .leading)

            Text(value)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Theme.textDim)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func label(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, design: .rounded).weight(.semibold))
            .foregroundStyle(Theme.textDim)
            .tracking(0.6)
    }

    private func centered<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack { content() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Nobody alive was born before this, and it keeps the wheel from spinning
    /// back through four digits of nothing.
    private static let earliestBirthday: Date = {
        DateComponents(calendar: .current, year: 1900, month: 1, day: 1).date ?? .distantPast
    }()

    private static func coordinate(_ value: Double) -> String {
        String(format: "%.5f", value)
    }
}

#if DEBUG
#Preview("Edit profile") {
    Color.black
        .sheet(isPresented: .constant(true)) {
            ProfileEditSheet(
                skyZone: .active,
                model: ProfileEditViewModel(previewProfile: WeatherPreviewData.profile)
            )
        }
}
#endif
