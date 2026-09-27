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
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.ignoresSafeArea())
                .navigationTitle(L("chats.new"))
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $query, prompt: L("chats.searchPrompt"))
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
            List {
                ForEach(matches, id: \.profileId) { card in
                    Button {
                        onPick(card)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            ChatAvatar(card: card, size: 44)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(card.displayName)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                if let username = card.username {
                                    Text("@\(username)")
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color(white: 0.55))
                                        .lineLimit(1)
                                }
                            }
                            .alignmentGuide(.listRowSeparatorLeading) { dimensions in dimensions[.leading] }

                            Spacer(minLength: 8)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.black)
                    .listRowSeparatorTint(Color(white: 0.2))
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
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
