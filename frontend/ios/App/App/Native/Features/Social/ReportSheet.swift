import SwiftUI

/// Reports a profile for a person to review, and blocks its owner in the same
/// step unless the reporter says not to.
///
/// A form of system controls on the sheet's own ground, like Settings: a list
/// of reasons to pick one from, a field for anything else, a switch. The
/// promise under it — reviewed within a day, the reporter not named — is the
/// one the Terms make. Filed from a chat, the report carries the chat's
/// latest messages, and the footer says so.
struct ReportSheet: View {

    let profile: ProfileSummary

    /// The chat the report is filed from, if it is.
    var chatId: Int? = nil

    /// Called once the report is filed, with whether the owner was blocked
    /// too, so the presenter can take a now-blocked chart off the screen.
    var onReported: (_ blocked: Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var strings = L10n.shared

    @State private var reason: ReportReason?
    @State private var details = ""
    @State private var alsoBlock = true
    @State private var isSending = false
    @State private var errorText: String?
    @State private var sent: Bool?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(ReportReason.allCases) { option in
                        Button {
                            reason = option
                        } label: {
                            HStack {
                                Text(option.label).foregroundStyle(Theme.text)
                                Spacer()
                                if reason == option {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                    }
                } header: {
                    Text(L("complaint.why", "@\(profile.username)"))
                }

                Section {
                    TextField(L("complaint.detailsPrompt"), text: $details, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text(L("complaint.details"))
                }

                Section {
                    Toggle(L("complaint.alsoBlock"), isOn: $alsoBlock)
                } footer: {
                    Text(L(chatId == nil ? "complaint.footer" : "complaint.footerChat"))
                }
            }
            .navigationTitle(L("complaint.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSending {
                        ProgressView().tint(Theme.spinner)
                    } else {
                        Button(L("complaint.send")) { Task { await send() } }
                            .fontWeight(.semibold)
                            .disabled(reason == nil)
                    }
                }
            }
            .alert(
                L("complaint.failed"),
                isPresented: Binding(
                    get: { errorText != nil },
                    set: { if !$0 { errorText = nil } }
                )
            ) {
                Button(L("common.ok"), role: .cancel) { errorText = nil }
            } message: {
                Text(errorText ?? "")
            }
            .alert(
                L("complaint.thanksTitle"),
                isPresented: Binding(
                    get: { sent != nil },
                    set: { if !$0 { finish() } }
                )
            ) {
                Button(L("common.ok"), role: .cancel) { finish() }
            } message: {
                Text(L(sent == true ? "complaint.thanksBlocked" : "complaint.thanksBody"))
            }
        }
        .presentationBackground(Theme.sheetBg)
        .interactiveDismissDisabled(isSending)
    }

    private func send() async {
        guard let reason, !isSending else { return }
        isSending = true
        defer { isSending = false }

        let note = details.trimmingCharacters(in: .whitespacesAndNewlines)

        #if DEBUG
        if WeatherPreviewHarness.isEnabled {
            sent = alsoBlock
            return
        }
        #endif

        do {
            let response = try await APIClient.shared.reportProfile(
                id: profile.profileId,
                reason: reason,
                details: note.isEmpty ? nil : note,
                block: alsoBlock,
                chatId: chatId
            )
            sent = response.blocked
        } catch {
            NSLog("[Report] failed for \(profile.profileId): \(error.localizedDescription)")
            errorText = error.localizedDescription
        }
    }

    /// The thank-you has been read: hand the outcome up and close.
    private func finish() {
        let blocked = sent ?? false
        sent = nil
        onReported(blocked)
        dismiss()
    }
}

/// The confirmation a block goes through, shared by every screen that offers
/// one, so the promise it makes is worded once.
struct BlockConfirmation: ViewModifier {

    @Binding var profile: ProfileSummary?
    var onBlocked: (ProfileSummary) -> Void

    @State private var errorText: String?

    func body(content: Content) -> some View {
        content
            .alert(
                L("block.title", profile?.profileName ?? ""),
                isPresented: Binding(
                    get: { profile != nil },
                    set: { if !$0 { profile = nil } }
                ),
                presenting: profile
            ) { target in
                Button(L("common.cancel"), role: .cancel) {}
                Button(L("block.confirm"), role: .destructive) {
                    Task { await block(target) }
                }
            } message: { _ in
                Text(L("block.body"))
            }
            .alert(
                L("block.failed"),
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

    private func block(_ target: ProfileSummary) async {
        #if DEBUG
        if WeatherPreviewHarness.isEnabled {
            onBlocked(target)
            return
        }
        #endif
        do {
            try await APIClient.shared.blockOwner(ofProfile: target.profileId)
            onBlocked(target)
        } catch {
            NSLog("[Block] failed for \(target.profileId): \(error.localizedDescription)")
            errorText = error.localizedDescription
        }
    }
}

extension View {

    /// Asks before blocking the owner of `profile`, blocks, and reports back.
    /// Set the binding to a profile to ask.
    func blockConfirmation(
        _ profile: Binding<ProfileSummary?>,
        onBlocked: @escaping (ProfileSummary) -> Void
    ) -> some View {
        modifier(BlockConfirmation(profile: profile, onBlocked: onBlocked))
    }
}
