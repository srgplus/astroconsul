import SwiftUI
import UIKit

struct SettingsView: View {

    @ObservedObject private var auth = AuthStore.shared
    @ObservedObject private var alerts = CategoryAlerts.shared
    /// Watched, not just read: this is the screen the language is changed on,
    /// so its own labels have to follow the switch as it is flipped.
    @ObservedObject private var strings = L10n.shared
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.system.rawValue
    @AppStorage(CategoryAlerts.Key.enabled) private var alertsEnabled = CategoryAlerts.defaultEnabled
    @AppStorage(CategoryAlerts.Key.hour) private var alertHour = CategoryAlerts.defaultHour
    @AppStorage(CategoryAlerts.Key.minute) private var alertMinute = CategoryAlerts.defaultMinute
    @AppStorage(CategoryAlerts.Key.cadence) private var cadence = CategoryAlerts.defaultCadence

    /// The outcome of the test row, shown as an alert. Without it the tap does
    /// nothing visible for five seconds, which is the same complaint the row
    /// exists to answer.
    @State private var testMessage: String?

    /// The sky behind the glass, passed down from the screen that presented
    /// this one.
    var skyState: SkyState?

    @State private var confirmsDelete = false
    @State private var isDeleting = false
    @State private var deleteError: String?

    /// Whether other people see this account's followers and following
    /// counts. Nil until the server has answered, so the switch never shows a
    /// guess it would then flip back.
    @State private var showsCounts: Bool?
    @State private var countsError: String?

    /// Whether a like, or a new follower, is pushed to this phone. Nil until
    /// the server has answered, like the counts switch.
    @State private var pushLikes: Bool?
    @State private var pushFollows: Bool?

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                notificationsSection
                appearanceSection
                languageSection
                communitySection
                aboutSection
                deleteAccountSection
            }
            .task { await alerts.syncState() }
            .alert(
                L("settings.testAlert"),
                isPresented: Binding(
                    get: { testMessage != nil },
                    set: { if !$0 { testMessage = nil } }
                ),
                presenting: testMessage
            ) { _ in
                Button(L("common.ok"), role: .cancel) {}
            } message: { message in
                Text(message)
            }
            .navigationTitle(L("settings.title"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("common.done")) { dismiss() }
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
            LabeledContent(L("settings.email")) {
                Text(auth.email ?? L("settings.notSignedIn"))
                    .foregroundStyle(Theme.textDim)
            }

            Button(L("settings.signOut"), role: .destructive) {
                Task {
                    // First, while the token still works: this phone stops
                    // getting the account's pushes.
                    await PushNotifications.shared.unregister()
                    auth.signOut()
                }
            }
        } header: {
            Text(L("settings.account"))
        }
    }

    /// The one irreversible thing on the screen, and the last row of the last
    /// section — far enough from Sign out that a thumb reaching for one cannot
    /// land on the other, and reached only by scrolling past everything else.
    private var deleteAccountSection: some View {
        Section {
            Button(L("settings.deleteAccount"), role: .destructive) { confirmsDelete = true }
                .disabled(isDeleting)
        } footer: {
            Text(L("settings.accountFooter"))
        }
        // An alert rather than a confirmation dialog: inside a Form row the
        // dialog is drawn as a popover, and a popover leaves the cancel button
        // out, so the only button offered would be the destructive one.
        .alert(
            L("settings.deleteAccountTitle"),
            isPresented: $confirmsDelete
        ) {
            Button(L("settings.deleteAccountKeep"), role: .cancel) {}
            Button(L("settings.deleteAccount"), role: .destructive) {
                Task { await performDelete() }
            }
        } message: {
            Text(L("settings.deleteAccountBody"))
        }
        .alert(
            L("settings.deleteAccountFailed"),
            isPresented: Binding(
                get: { deleteError != nil },
                set: { if !$0 { deleteError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
    }

    /// Deletes the account, then signs out and closes the sheet. Signing out
    /// locally would be enough to empty the screen, but the order matters: the
    /// request needs the access token that `signOut` throws away.
    private func performDelete() async {
        isDeleting = true
        do {
            try await APIClient.shared.deleteAccount()
            await PushNotifications.shared.unregister()
            auth.signOut()
            dismiss()
        } catch {
            NSLog("[Settings] account deletion failed: \(error)")
            deleteError = error.localizedDescription
        }
        isDeleting = false
    }

    /// Which of the twelve categories the day reads as, at the hour set here —
    /// every day, or only on the days it turns into a different one.
    private var notificationsSection: some View {
        Section {
            Toggle(L("settings.weatherAlerts"), isOn: $alertsEnabled)

            if alertsEnabled {
                if alerts.authorization == .denied {
                    Button(L("settings.openIosSettings")) { openSystemSettings() }
                } else {
                    Picker(L("settings.cadence"), selection: $cadence) {
                        ForEach(CategoryAlerts.Cadence.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.menu)

                    DatePicker(
                        L("settings.timeOfDay"),
                        selection: alertTime,
                        displayedComponents: .hourAndMinute
                    )

                    // Counted in the unit the cadence actually schedules by:
                    // "4 changes" over a fortnight is the honest number on one
                    // setting and a wrong one on the other.
                    LabeledContent(L("settings.scheduled")) {
                        Text(L(count: alerts.scheduledCount, scheduledNoun))
                            .foregroundStyle(Theme.textDim)
                    }

                    // The count says how far the queue reaches; the date says
                    // when the next banner actually lands. Both, because a
                    // fortnight on file is not a promise about tomorrow —
                    // today's alert is gone once its hour has passed.
                    if let next = alerts.nextAlert {
                        LabeledContent(L("settings.nextAlert")) {
                            Text(next, format: Self.nextFormat)
                                .foregroundStyle(Theme.textDim)
                        }
                    }

                    if alerts.hasStoredDays {
                        Button(L("settings.sendTest")) { sendTest() }
                    }
                }
            }
        } header: {
            Text(L("settings.notifications"))
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
        .onChange(of: cadence) { _, _ in Task { await alerts.reschedule() } }
    }

    /// "Tue 9 Sep at 12:00" — weekday and day, so the row can be checked
    /// against the clock rather than taken on trust.
    private static let nextFormat = Date.FormatStyle()
        .weekday(.abbreviated)
        .day()
        .month(.abbreviated)
        .hour()
        .minute()

    private func sendTest() {
        Task {
            let sent = await alerts.sendTestAlert()
            testMessage = L(sent ? "settings.testSent" : "settings.testFailed")
        }
    }

    /// "days" on the daily setting, "changes" on the other.
    private var scheduledNoun: String {
        cadence == .daily ? "common.dayCount" : "common.change"
    }

    private var notificationsFooter: String {
        if alertsEnabled, alerts.authorization == .denied {
            return L("settings.notificationsDenied")
        }
        return L(cadence == .daily ? "settings.footerDaily" : "settings.footerChanges")
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
        Section(L("settings.appearance")) {
            Picker(L("settings.theme"), selection: $appearance) {
                ForEach(Appearance.allCases) { option in
                    Text(option.label).tag(option.rawValue)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    /// The app is read in one language and lived in another often enough that
    /// the device setting is not the last word. `System` is the default and
    /// follows the device; the other two override it, for the native screens
    /// and the web ones alike.
    private var languageSection: some View {
        Section {
            Picker(L("settings.language"), selection: $strings.language) {
                ForEach(AppLanguage.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text(L("settings.language"))
        } footer: {
            Text(L("settings.languageFooter"))
        }
    }

    /// Whether others see your counts, who you have blocked, the rules
    /// everyone here agreed to, and a person to write to — the last of App
    /// Review's four requirements for a social network being published
    /// contact details a user can actually reach.
    private var communitySection: some View {
        Section {
            if auth.isSignedIn {
                Toggle(isOn: showsCountsBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("settings.showCounts"))
                        Text(L("settings.showCountsHint"))
                            .font(.footnote)
                            .foregroundStyle(Theme.textDim)
                    }
                }
                .disabled(showsCounts == nil)

                Toggle(L("settings.pushLikes"), isOn: pushBinding(.likes))
                    .disabled(pushLikes == nil)
                Toggle(L("settings.pushFollows"), isOn: pushBinding(.follows))
                    .disabled(pushFollows == nil)

                // The switches above are the server's; the phone's own
                // permission is the other half, and only iOS can give it back.
                if alerts.authorization == .denied, pushLikes == true || pushFollows == true {
                    Button(L("settings.openIosSettings")) { openSystemSettings() }
                }
            }

            NavigationLink(L("blocked.title")) {
                BlockedAccountsView()
            }

            Link(destination: Legal.termsURL) {
                Label(L("settings.guidelines"), systemImage: "doc.text")
            }

            Link(destination: Legal.privacyURL) {
                Label(L("settings.privacy"), systemImage: "hand.raised")
            }

            Link(destination: Legal.supportMail) {
                Label(L("settings.contact"), systemImage: "envelope")
            }
        } header: {
            Text(L("settings.community"))
        } footer: {
            Text(L("settings.communityFooter", Legal.supportEmail))
        }
        .task { await loadCountsSetting() }
        .alert(
            L("settings.showCountsFailed"),
            isPresented: Binding(
                get: { countsError != nil },
                set: { if !$0 { countsError = nil } }
            )
        ) {
            Button(L("common.ok"), role: .cancel) {}
        } message: {
            Text(countsError ?? "")
        }
    }

    /// Flipped at once and saved behind it; a refused save puts the switch
    /// back where the server has it and says why.
    private var showsCountsBinding: Binding<Bool> {
        Binding(
            get: { showsCounts ?? true },
            set: { isOn in
                let before = showsCounts
                showsCounts = isOn
                Task {
                    do {
                        showsCounts = try await APIClient.shared.updateSocialSettings(showCounts: isOn).showCounts
                    } catch {
                        NSLog("[Settings] saving the counts setting failed: \(error.localizedDescription)")
                        showsCounts = before
                        if !error.isCancellation { countsError = error.localizedDescription }
                    }
                }
            }
        )
    }

    private enum PushKind {
        case likes
        case follows
    }

    /// Flipped at once and saved behind it, like the counts switch. Turning
    /// one on where the phone has never been asked puts the question now.
    private func pushBinding(_ kind: PushKind) -> Binding<Bool> {
        Binding(
            get: { (kind == .likes ? pushLikes : pushFollows) ?? true },
            set: { isOn in
                let before = kind == .likes ? pushLikes : pushFollows
                setPush(kind, isOn)
                Task {
                    do {
                        let saved = try await APIClient.shared.updateSocialSettings(
                            pushLikes: kind == .likes ? isOn : nil,
                            pushFollows: kind == .follows ? isOn : nil
                        )
                        pushLikes = saved.pushLikes ?? pushLikes
                        pushFollows = saved.pushFollows ?? pushFollows
                        if isOn {
                            await PushNotifications.shared.askIfUndetermined()
                        }
                    } catch {
                        NSLog("[Settings] saving the push setting failed: \(error.localizedDescription)")
                        setPush(kind, before)
                        if !error.isCancellation { countsError = error.localizedDescription }
                    }
                }
            }
        )
    }

    private func setPush(_ kind: PushKind, _ value: Bool?) {
        switch kind {
        case .likes: pushLikes = value
        case .follows: pushFollows = value
        }
    }

    private func loadCountsSetting() async {
        guard auth.isSignedIn else { return }
        do {
            let settings = try await APIClient.shared.fetchSocialSettings()
            showsCounts = settings.showCounts
            pushLikes = settings.pushLikes ?? true
            pushFollows = settings.pushFollows ?? true
        } catch {
            guard !error.isCancellation else { return }
            NSLog("[Settings] loading the counts setting failed: \(error.localizedDescription)")
        }
    }

    private var aboutSection: some View {
        Section(L("settings.about")) {
            LabeledContent(L("settings.version")) {
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
