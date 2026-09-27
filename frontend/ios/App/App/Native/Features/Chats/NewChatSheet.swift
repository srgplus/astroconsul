import SwiftUI

/// Who a new chat can be started with: the people whose own chart the reader
/// follows, and the people following any of the reader's, each shown as their
/// own chart. Charts kept for somebody else are not here: there is nobody
/// behind them to answer. Black, like the chats it opens from.
struct NewChatSheet: View {

    /// The person picked. The sheet closes itself after.
    var onPick: (SocialCard) -> Void

    init(onPick: @escaping (SocialCard) -> Void) {
        self.onPick = onPick
    }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var strings = L10n.shared
    @State private var people: [SocialCard]?
    @State private var errorText: String?
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private typealias Metrics = ChatsScreen.Metrics

    private var matches: [SocialCard] {
        let term = query.trimmingCharacters(in: .whitespaces).lowercased()
        let everyone = people ?? []
        guard !term.isEmpty else { return everyone }
        return everyone.filter { card in
            (card.profileName ?? "").lowercased().contains(term) || (card.username ?? "").lowercased().contains(term)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // At the top, as the chats have theirs, rather than where
                // iOS 26 puts a sheet's search: at the bottom, half off it.
                if people?.isEmpty == false {
                    ChatSearchField(prompt: L("chats.searchPrompt"), text: $query, focus: $searchFocused)
                        .padding(.horizontal, Metrics.side)
                        .padding(.top, 4)
                        .padding(.bottom, 8)
                }
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(L("chats.new"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(L("common.cancel"))
                }
            }
        }
        .tint(.white)
        .presentationBackground(Color.black)
        .environment(\.colorScheme, .dark)
        .task { await load() }
    }

    private func load() async {
        #if DEBUG
        if WeatherPreviewHarness.isEnabled {
            people = WeatherPreviewData.chats.map(\.peer)
            return
        }
        #endif
        do {
            people = try await APIClient.shared.fetchChatContacts()
        } catch {
            guard !error.isCancellation else { return }
            NSLog("[Chats] contacts failed: \(error.localizedDescription)")
            errorText = error.localizedDescription
        }
    }

    @ViewBuilder
    private var content: some View {
        if let errorText, people == nil {
            notice(title: L("chats.contactsFailed"), body: errorText)
        } else if people == nil {
            ProgressView()
                .tint(Theme.spinner)
        } else if people?.isEmpty == true {
            notice(title: L("chats.contactsEmptyTitle"), body: L("chats.contactsEmptyBody"))
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(matches, id: \.profileId) { card in
                        Button {
                            onPick(card)
                            dismiss()
                        } label: {
                            row(card)
                        }
                        .buttonStyle(ChatRowButtonStyle())

                        if card.profileId != matches.last?.profileId {
                            ChatRowSeparator()
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.immediately)
        }
    }

    /// A person as the chats draw one: the face, the name, the handle under it.
    private func row(_ card: SocialCard) -> some View {
        HStack(spacing: Metrics.faceGap) {
            ChatAvatar(card: card, size: Metrics.face)

            VStack(alignment: .leading, spacing: 1) {
                Text(card.displayName)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let username = card.username {
                    Text("@\(username)")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(white: 0.55))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, Metrics.side)
        .frame(minHeight: Metrics.row)
        .contentShape(Rectangle())
    }

    private func notice(title: String, body: String) -> some View {
        VStack(spacing: Theme.Spacing.base) {
            Image(systemName: "person.2")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(Color(white: 0.5))

            Text(title)
                .font(.system(.title3).weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(body)
                .font(.system(.subheadline))
                .foregroundStyle(Color(white: 0.6))
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Spacing.section)
    }
}
