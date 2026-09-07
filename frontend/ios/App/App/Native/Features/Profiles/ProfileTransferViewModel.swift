import Foundation
import UIKit

/// Backs the transfer sheet: takes an email address and asks the API for a
/// transfer invite.
///
/// Creating the invite hands nothing over — the profile stays where it is
/// until the recipient accepts it on the web, at the link this gets back.
@MainActor
final class ProfileTransferViewModel: ObservableObject {

    let profile: ProfileSummary

    @Published var email = ""
    @Published private(set) var isSending = false
    @Published private(set) var errorMessage: String?

    /// The invite once it exists. Its presence is what flips the sheet from
    /// the form to the confirmation.
    @Published private(set) var invite: APIClient.InviteResponse?

    /// The link was put on the pasteboard, so the button can say so.
    @Published private(set) var didCopyLink = false

    private let api: APIClient

    init(profile: ProfileSummary, api: APIClient = .shared) {
        self.profile = profile
        self.api = api
    }

    #if DEBUG
    /// Seeds the confirmation state, which previews and the
    /// `-uiPreviewWeather` harness have no API to reach for real.
    init(previewProfile profile: ProfileSummary, invite: APIClient.InviteResponse) {
        self.profile = profile
        self.api = .shared
        self.email = "friend@example.com"
        self.invite = invite
    }
    #endif

    var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Enough of an address to be worth a round trip. The API validates it
    /// properly; this only keeps the button from firing on obvious nonsense.
    var canSend: Bool {
        guard !isSending else { return false }
        let value = trimmedEmail
        guard let at = value.firstIndex(of: "@"), at != value.startIndex else { return false }
        let domain = value[value.index(after: at)...]
        return domain.contains(".") && !domain.hasSuffix(".") && !domain.contains("@")
    }

    func send() async {
        guard canSend else { return }

        isSending = true
        errorMessage = nil
        defer { isSending = false }

        do {
            invite = try await api.createProfileInvite(
                profileId: profile.profileId,
                email: trimmedEmail
            )
        } catch {
            NSLog("[ProfileTransfer] invite failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    func copyLink() {
        guard let url = invite?.inviteUrl else { return }
        UIPasteboard.general.string = url
        didCopyLink = true
    }
}
