import SwiftUI

/// When and where to read the sky — the native form of the web's "Transit
/// Settings" dialog, opened from the stamp under the profile's name.
///
/// A chart is fixed; a transit is not, so a reading is only ever a reading of
/// some moment somewhere. The screen assumes the present and the profile's own
/// place until this says otherwise, and everything downstream of it — the
/// report, the forecast window, the Moon — follows the choice.
///
/// Built as a plain grouped `Form` in a half-height sheet with Cancel and a
/// confirm tick, because that is what a form asking for four values looks like
/// on this platform: the row heights, the inset hairlines and the pickers all
/// come from the system rather than from constants that only nearly match.
struct TransitSettingsSheet: View {

    /// What the screen is reading now, so the form opens on it rather than on
    /// a blank of its own.
    let current: TransitMoment
    /// Whether the screen is on a chosen moment or simply on the present.
    let isChosen: Bool
    let onApply: (TransitMoment) -> Void
    let onReset: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var instant: Date
    @State private var zone: TimeZone
    @State private var locationName: String?
    @State private var latitude: Double?
    @State private var longitude: Double?

    @State private var query = ""
    @State private var results: [PlaceCandidate] = []
    @State private var searching = false
    @State private var searchTask: Task<Void, Never>?

    init(
        current: TransitMoment,
        isChosen: Bool,
        onApply: @escaping (TransitMoment) -> Void,
        onReset: @escaping () -> Void
    ) {
        self.current = current
        self.isChosen = isChosen
        self.onApply = onApply
        self.onReset = onReset
        _instant = State(initialValue: current.instant)
        _zone = State(initialValue: current.zone)
        _locationName = State(initialValue: current.locationName)
        _latitude = State(initialValue: current.latitude)
        _longitude = State(initialValue: current.longitude)
    }

    var body: some View {
        NavigationStack {
            Form {
                moment
                place

                if isChosen {
                    Section {
                        Button("Read the present moment") {
                            onReset()
                            dismiss()
                        }
                    }
                    .listRowBackground(Color.primary.opacity(0.06))
                }
            }
            // No title. Cancel and a tick either side of two labelled
            // sections say what the sheet is for; a title over them is a
            // caption on a picture of itself.
            .navigationBarTitleDisplayMode(.inline)
            // The form's own grouped background is opaque and would cover the
            // frosted sheet underneath it; the rows keep a light raise of
            // their own so they still read as grouped.
            .scrollContentBackground(.hidden)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Ink, not blue. Blue is the colour of the thing that
                    // happens when you are done; leaving is not that.
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.text)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onApply(
                            TransitMoment(
                                instant: instant,
                                zone: zone,
                                locationName: locationName,
                                latitude: latitude,
                                longitude: longitude
                            )
                        )
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .accessibilityLabel("Read this moment")
                }
            }
        }
        // The weather page tints everything under it white for the sky, and a
        // form is not on the sky.
        .tint(.blue)
        .presentationDetents([.medium, .large])
        // Frosted rather than filled: this sheet is short, sits over the page
        // it is about, and the page carries on behind it. `regular` and not
        // `ultraThin` — the thin one lets enough of the sky's video through
        // that the labels have to compete with rain.
        .presentationBackground(.regularMaterial)
        // A grabber under Cancel and a tick is a third thing saying the sheet
        // can be got rid of.
        .presentationDragIndicator(.hidden)
        .onDisappear { searchTask?.cancel() }
    }

    // MARK: - When

    private var moment: some View {
        Section {
            DatePicker("Date", selection: $instant, displayedComponents: .date)
            DatePicker("Time", selection: $instant, displayedComponents: .hourAndMinute)
        } header: {
            Text("Moment")
        } footer: {
            Text(zone.identifier)
        }
        .listRowBackground(Color.primary.opacity(0.06))
        // Read in the zone the reading is cast for, not the device's, so nine
        // in the morning means nine where the chart is being read.
        .environment(\.timeZone, zone)
    }

    // MARK: - Where

    private var place: some View {
        Section {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("Search city", text: $query)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onChange(of: query) { _, value in search(value) }

                if searching {
                    MinimalSpinner(size: 14, color: .secondary)
                } else if !query.isEmpty {
                    Button {
                        query = ""
                        results = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear")
                }
            }

            if results.isEmpty {
                LabeledContent("Place") {
                    Text(locationName ?? "The profile's own")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }

            ForEach(results) { candidate in
                Button {
                    select(candidate)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(candidate.displayName)
                            .foregroundStyle(Color.primary)
                            .multilineTextAlignment(.leading)

                        if let identifier = candidate.timezone {
                            Text(identifier)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Place")
        }
        .listRowBackground(Color.primary.opacity(0.06))
    }

    // MARK: - Search

    /// Debounced, because the endpoint geocodes and the field is typed into.
    private func search(_ text: String) {
        searchTask?.cancel()
        let term = text.trimmingCharacters(in: .whitespaces)

        guard term.count >= 2 else {
            results = []
            searching = false
            return
        }

        searching = true
        searchTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }

            do {
                let found = try await APIClient.shared.searchLocations(query: term)
                guard !Task.isCancelled else { return }
                results = found
            } catch {
                NSLog("[Weather] location search failed for \(term): \(error.localizedDescription)")
                results = []
            }
            searching = false
        }
    }

    private func select(_ candidate: PlaceCandidate) {
        locationName = candidate.displayName
        latitude = candidate.latitude
        longitude = candidate.longitude

        // The place carries its zone, and the clock has to move with it: the
        // hour on the picker is a wall clock reading, so the instant shifts
        // when the wall it hangs on does.
        if let identifier = candidate.timezone, let moved = TimeZone(identifier: identifier) {
            instant = instant.addingTimeInterval(
                Double(zone.secondsFromGMT(for: instant) - moved.secondsFromGMT(for: instant))
            )
            zone = moved
        }

        query = ""
        results = []
    }
}
