import SwiftUI
import UIKit

struct SettingsView: View {

    @ObservedObject private var auth = AuthStore.shared
    @ObservedObject private var alerts = CategoryAlerts.shared
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.system.rawValue
    @AppStorage(CategoryAlerts.Key.enabled) private var alertsEnabled = CategoryAlerts.defaultEnabled
    @AppStorage(CategoryAlerts.Key.hour) private var alertHour = CategoryAlerts.defaultHour
    @AppStorage(CategoryAlerts.Key.minute) private var alertMinute = CategoryAlerts.defaultMinute

    /// The sky behind the glass, passed down from the screen that presented
    /// this one.
    var skyZone: TiiZone?

    /// Opens the WebView tab. Account deletion still lives there: that flow is
    /// what Apple reviewed under 5.1.1(v), so it is not reimplemented until
    /// the rest of the account screen is native.
    var onOpenWeb: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                notificationsSection
                appearanceSection
                aboutSection
            }
            .task { await alerts.syncState() }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(.body, design: .rounded).weight(.medium))
                }
            }
        }
        // Filled, not frosted. Settings is a form of system controls — a
        // segmented picker, a destructive button, labelled rows — and every
        // one of them is drawn for a background of a known colour. Over a
        // blurred sky they were all being propped up by hand.
        .presentationBackground(Theme.sheetBg)
    }

    private var accountSection: some View {
        Section {
            LabeledContent("Email") {
                Text(auth.email ?? "Not signed in")
                    .foregroundStyle(Theme.textDim)
            }

            Button("Sign out", role: .destructive) {
                auth.signOut()
            }

            Button("Manage account") { onOpenWeb() }
        } header: {
            Text("Account")
        } footer: {
            Text("Account deletion and subscription management open in the app's web view.")
        }
    }

    /// The one thing worth interrupting someone for: the day their weather
    /// stops being one of the twelve categories and becomes another.
    private var notificationsSection: some View {
        Section {
            Toggle("Category changes", isOn: $alertsEnabled)

            if alertsEnabled {
                if alerts.authorization == .denied {
                    Button("Turn on in iOS Settings") { openSystemSettings() }
                } else {
                    DatePicker(
                        "Time of day",
                        selection: alertTime,
                        displayedComponents: .hourAndMinute
                    )

                    LabeledContent("Scheduled") {
                        Text(alerts.scheduledCount == 1 ? "1 change" : "\(alerts.scheduledCount) changes")
                            .foregroundStyle(Theme.textDim)
                    }
                }
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text(notificationsFooter)
        }
        .onChange(of: alertsEnabled) { _, isOn in
            Task {
                if isOn { await alerts.requestAuthorization() }
                await alerts.refresh(force: true)
            }
        }
        .onChange(of: alertHour) { _, _ in Task { await alerts.reschedule() } }
        .onChange(of: alertMinute) { _, _ in Task { await alerts.reschedule() } }
    }

    private var notificationsFooter: String {
        if alertsEnabled, alerts.authorization == .denied {
            return "Notifications are switched off for big3.me in iOS Settings, so nothing can be scheduled."
        }
        return """
        Your cosmic weather reads as one of twelve categories, from Calm to \
        Explosive. Get a notification on the days ahead when it moves to a \
        different one, for the profile marked as yours.
        """
    }

    /// `@AppStorage` holds the hour and minute; `DatePicker` wants a `Date`.
    /// Anchored to today so the picker has a real day under it.
    private var alertTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: alertHour,
                    minute: alertMinute,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { picked in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: picked)
                alertHour = parts.hour ?? CategoryAlerts.defaultHour
                alertMinute = parts.minute ?? CategoryAlerts.defaultMinute
            }
        )
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $appearance) {
                ForEach(Appearance.allCases) { option in
                    Text(option.label).tag(option.rawValue)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version") {
                Text(Self.versionString).foregroundStyle(Theme.textDim)
            }
        }
    }

    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
