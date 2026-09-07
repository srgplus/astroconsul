import SwiftUI

/// The profile's own settings: the name it is listed under and the birth data
/// every reading is cast from. Reached from the ••• menu on the weather page
/// on a profile the viewer owns, and from the plus on the profile list for a
/// profile that does not exist yet.
///
/// Saving casts the chart, so the sheet asks its presenter to reload rather
/// than patching the list in place.
struct ProfileEditSheet: View {

    @StateObject private var model: ProfileEditViewModel

    /// The sky behind the glass, passed down from the page that opened this.
    var skyZone: TiiZone?

    var onSaved: () -> Void
    var onDeleted: () -> Void

    /// The new profile, handed back so the list can turn straight to it.
    /// Called instead of `onSaved` and only when the sheet was opened blank.
    var onCreated: (ProfileSummary) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var strings = L10n.shared
    @State private var showsDeleteConfirmation = false
    @State private var showsCoordinates = false
    /// The profile the transfer sheet is offering. Held rather than a flag:
    /// a new profile has none, and there is nothing to hand over until it is
    /// saved.
    @State private var transferring: ProfileSummary?
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
        self.onCreated = { _ in }
    }

    /// A blank form for a profile that does not exist yet. Same fields, same
    /// geocoding; the save posts instead of patching and there is nothing to
    /// delete.
    init(skyZone: TiiZone? = nil, onCreated: @escaping (ProfileSummary) -> Void) {
        _model = StateObject(wrappedValue: ProfileEditViewModel())
        self.skyZone = skyZone
        self.onSaved = {}
        self.onDeleted = {}
        self.onCreated = onCreated
    }

    #if DEBUG
    /// Autoclosure so the model is built on the main actor when SwiftUI
    /// installs the view, not at the call site.
    init(
        skyZone: TiiZone? = nil,
        onSaved: @escaping () -> Void = {},
        onDeleted: @escaping () -> Void = {},
        onCreated: @escaping (ProfileSummary) -> Void = { _ in },
        model: @autoclosure @escaping () -> ProfileEditViewModel
    ) {
        _model = StateObject(wrappedValue: model())
        self.skyZone = skyZone
        self.onSaved = onSaved
        self.onDeleted = onDeleted
        self.onCreated = onCreated
    }
    #endif

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(L(model.isCreating ? "edit.newTitle" : "edit.title"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L("common.close")) { dismiss() }
                            .font(.system(.body, design: .rounded).weight(.medium))
                            .foregroundStyle(Theme.text)
                            .disabled(model.isSaving || model.isDeleting)
                    }

                    // Saving is the confirm, so it sits where a confirm sits.
                    // As a full-width button under the form it was the only
                    // thing on screen that needed its own bar, and the bar
                    // covered the bottom of the fields it was saving.
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            focused = nil
                            Task {
                                guard let saved = await model.save() else { return }
                                if model.isCreating { onCreated(saved) } else { onSaved() }
                                dismiss()
                            }
                        } label: {
                            if model.isSaving {
                                MinimalSpinner(color: .white)
                            } else {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.white)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .disabled(!model.canSave)
                        .accessibilityLabel(L("edit.save"))
                    }
                }
        }
        .tint(Theme.text)
        // Filled, not frosted. This is a form of system controls — text
        // fields, date pickers, a destructive row — and every one of them is
        // drawn for a background of a known colour.
        .presentationBackground(Theme.sheetBg)
        .presentationDragIndicator(.hidden)
        .task {
            // A seeded model (previews, harness) is already filled in.
            guard model.state == .loading else { return }
            await model.load()
        }
        .sheet(item: $transferring) { profile in
            ProfileTransferSheet(profile: profile)
        }
        .alert(L("edit.deleteTitle"), isPresented: $showsDeleteConfirmation) {
            Button(L("common.cancel"), role: .cancel) {}
            Button(L("common.delete"), role: .destructive) {
                Task {
                    if await model.delete() {
                        onDeleted()
                        dismiss()
                    }
                }
            }
        } message: {
            Text(L("edit.deleteBody", model.profileName))
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

                    Text(L("edit.loadFailed"))
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(Theme.text)

                    Text(message)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Theme.textDim)
                        .multilineTextAlignment(.center)

                    Button(L("common.tryAgain")) { Task { await model.load() } }
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

                // Nothing to hand over or destroy on a profile that does
                // not exist yet.
                if !model.isCreating {
                    transferButton
                    deleteButton
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Cards

    private var identityCard: some View {
        card {
            row(L("edit.name")) {
                TextField(L("edit.fullName"), text: $model.profileName)
                    .textContentType(.name)
                    .submitLabel(.next)
                    .focused($focused, equals: .name)
                    .onSubmit { focused = .username }
            }

            divider

            row(L("edit.username")) {
                HStack(spacing: 1) {
                    Text("@").foregroundStyle(Theme.textDim)
                    TextField(L("edit.usernamePlaceholder"), text: $model.username)
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
                row(L("edit.date")) {
                    DatePicker(
                        "",
                        selection: $model.birthDate,
                        in: Self.earliestBirthday...Date(),
                        displayedComponents: .date
                    )
                    .labelsHidden()
                }

                divider

                row(L("edit.time")) {
                    DatePicker("", selection: $model.birthTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }

                divider

                // The one field that needs the full width: a geocoded place
                // name runs to three commas, and the suggestions hang under it.
                VStack(alignment: .leading, spacing: 8) {
                    label(L("edit.birthplace"))

                    HStack(spacing: 8) {
                        TextField(L("edit.birthplacePlaceholder"), text: $model.locationName)
                            .autocorrectionDisabled()
                            .focused($focused, equals: .place)
                            .onChange(of: model.locationName) { _, _ in model.searchPlaces() }

                        if model.isSearching { MinimalSpinner(color: Theme.textDim) }
                    }
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Theme.text)

                    if model.locationNeedsResolving && model.suggestions.isEmpty && !model.isSearching {
                        Text(L("edit.pickPlace"))
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
                    Text(L("edit.coordinates"))
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
                readOnlyRow(L("edit.timezone"), model.timezone.isEmpty ? L("common.notSet") : model.timezone)
                divider
                readOnlyRow(L("edit.latitude"), Self.coordinate(model.latitude))
                divider
                readOnlyRow(L("edit.longitude"), Self.coordinate(model.longitude))

                Text(L("edit.coordinatesFooter"))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }
        }
    }

    // MARK: - Actions

    /// Gifting the profile to someone else. It sits above the delete row and
    /// is drawn in ordinary text: handing a profile over is not destructive
    /// here — the invite only offers it, and nothing moves until it is
    /// accepted on the web.
    private var transferButton: some View {
        Button {
            focused = nil
            transferring = model.profile
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "gift")
                Text(L("transfer.title"))

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textDim)
            }
            .font(.system(.body, design: .rounded).weight(.medium))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 14)
            .frame(height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(cardBackground)
        .disabled(model.isSaving || model.isDeleting)
        .padding(.top, 4)
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
                Text(L("edit.deleteButton"))
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

    /// A step in tone from the sheet's own ground, and nothing else. That is
    /// how the system separates a grouped panel from what it sits on; the
    /// hairline this used to carry was a second, weaker answer to a question
    /// already answered, and it is what made the cards look drawn on rather
    /// than raised.
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Theme.sheetCard)
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
