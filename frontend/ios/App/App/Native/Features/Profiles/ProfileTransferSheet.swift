import SwiftUI

/// Gifts a profile to someone else. Reached from the edit sheet, and only on
/// a profile the viewer owns.
///
/// Nothing moves when this sheet is used: it creates an invite and mails a
/// link. Ownership changes only once the recipient signs in and accepts, so
/// the sheet's job ends at "the invitation is on its way".
struct ProfileTransferSheet: View {

    @StateObject private var model: ProfileTransferViewModel

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var strings = L10n.shared
    @FocusState private var emailFocused: Bool

    init(profile: ProfileSummary) {
        _model = StateObject(wrappedValue: ProfileTransferViewModel(profile: profile))
    }

    #if DEBUG
    /// Autoclosure so the model is built on the main actor when SwiftUI
    /// installs the view, not at the call site.
    init(model: @autoclosure @escaping () -> ProfileTransferViewModel) {
        _model = StateObject(wrappedValue: model())
    }
    #endif

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(L("transfer.title"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L(model.invite == nil ? "common.cancel" : "common.done")) { dismiss() }
                            .font(.system(.body, design: .rounded).weight(.medium))
                            .foregroundStyle(Theme.text)
                            .disabled(model.isSending)
                    }
                }
        }
        .tint(Theme.text)
        .presentationBackground(Theme.sheetBg)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let invite = model.invite {
                    sent(invite)
                } else {
                    form
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Form

    private var form: some View {
        VStack(spacing: 20) {
            profileCard

            VStack(alignment: .leading, spacing: 10) {
                label(L("transfer.sendTo"))

                // Spelled out as a prompt rather than a title so the hint
                // reads dim like every other placeholder in the app; a plain
                // title picks up the field's tint and comes out blue.
                TextField(
                    "",
                    text: $model.email,
                    prompt: Text(L("transfer.emailPlaceholder")).foregroundColor(Theme.textDim)
                )
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.send)
                    .focused($emailFocused)
                    .onSubmit { submit() }
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .background(cardBackground)
            }

            Text(L("transfer.footer"))
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Theme.textDim)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            if let message = model.errorMessage {
                Text(message)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Theme.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: submit) {
                HStack(spacing: 8) {
                    if model.isSending {
                        MinimalSpinner(color: .white)
                    }
                    Text(L(model.isSending ? "transfer.sending" : "transfer.send"))
                }
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .disabled(!model.canSend)
            .padding(.top, 4)
        }
        .onAppear { emailFocused = true }
    }

    /// Which profile is being given away. The sheet is opened from inside that
    /// profile's own editor, but this is a one-way door for the person on the
    /// other end, so it says the name out loud.
    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            label(L("transfer.profile"))

            Text(model.profile.profileName)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.text)

            Text("@\(model.profile.username)")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(cardBackground)
    }

    // MARK: - Sent

    private func sent(_ invite: APIClient.InviteResponse) -> some View {
        VStack(spacing: 16) {
            Image(systemName: invite.emailSent ? "paperplane.fill" : "link")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.ok)
                .padding(.top, 12)

            Text(L(invite.emailSent ? "transfer.sent" : "transfer.created"))
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.text)

            Text(
                invite.emailSent
                    ? L("transfer.sentBody", model.trimmedEmail, model.profile.profileName)
                    : L("transfer.createdBody", model.profile.profileName)
            )
            .font(.system(.subheadline, design: .rounded))
            .foregroundStyle(Theme.textDim)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)

            Button {
                model.copyLink()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: model.didCopyLink ? "checkmark" : "doc.on.doc")
                    Text(L(model.didCopyLink ? "transfer.linkCopied" : "transfer.copyLink"))
                }
                .font(.system(.body, design: .rounded).weight(.medium))
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(cardBackground)

            ShareLink(item: invite.inviteUrl) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                    Text(L("transfer.shareLink"))
                }
                .font(.system(.body, design: .rounded).weight(.medium))
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(cardBackground)
        }
    }

    // MARK: - Pieces

    private func submit() {
        emailFocused = false
        Task { await model.send() }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Theme.sheetCard)
    }

    private func label(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, design: .rounded).weight(.semibold))
            .foregroundStyle(Theme.textDim)
            .tracking(0.6)
    }
}

#if DEBUG
#Preview("Transfer profile") {
    Color.black
        .sheet(isPresented: .constant(true)) {
            ProfileTransferSheet(model: ProfileTransferViewModel(profile: WeatherPreviewData.profile))
        }
}

#Preview("Transfer profile — sent") {
    Color.black
        .sheet(isPresented: .constant(true)) {
            ProfileTransferSheet(
                model: ProfileTransferViewModel(
                    previewProfile: WeatherPreviewData.profile,
                    invite: APIClient.InviteResponse(
                        token: "preview",
                        inviteUrl: "https://big3.me/invite/preview",
                        emailSent: true
                    )
                )
            )
        }
}
#endif
