import SwiftUI

/// The accounts this reader has blocked, each with a way back. Pushed from
/// Settings, so it wears the form's own ground rather than the sky.
struct BlockedAccountsView: View {

    @ObservedObject private var strings = L10n.shared

    @State private var blocks: [BlockedAccount] = []
    @State private var isLoading = true
    @State private var errorText: String?
    @State private var unblocking: Set<Int> = []

    var body: some View {
        List {
            if isLoading && blocks.isEmpty {
                HStack {
                    Spacer()
                    ProgressView().tint(Theme.spinner)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if blocks.isEmpty {
                Section {
                    Text(L("blocked.empty"))
                        .foregroundStyle(Theme.textDim)
                } footer: {
                    Text(L("blocked.footer"))
                }
            } else {
                Section {
                    ForEach(blocks) { block in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(block.actor.displayName)
                                    .foregroundStyle(Theme.text)
                                if let handle = block.actor.username {
                                    Text("@\(handle)")
                                        .font(.footnote)
                                        .foregroundStyle(Theme.textDim)
                                }
                            }

                            Spacer()

                            if unblocking.contains(block.blockId) {
                                ProgressView().tint(Theme.spinner)
                            } else {
                                Button(L("blocked.unblock")) {
                                    Task { await unblock(block) }
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                } footer: {
                    Text(L("blocked.footer"))
                }
            }
        }
        .navigationTitle(L("blocked.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .alert(
            L("blocked.failed"),
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

    private func load() async {
        #if DEBUG
        if WeatherPreviewHarness.isEnabled {
            isLoading = false
            return
        }
        #endif
        isLoading = true
        defer { isLoading = false }
        do {
            blocks = try await APIClient.shared.fetchBlockedAccounts()
        } catch {
            guard !error.isCancellation else { return }
            NSLog("[Blocked] load failed: \(error.localizedDescription)")
            errorText = error.localizedDescription
        }
    }

    private func unblock(_ block: BlockedAccount) async {
        unblocking.insert(block.blockId)
        defer { unblocking.remove(block.blockId) }
        do {
            try await APIClient.shared.unblock(blockId: block.blockId)
            blocks.removeAll { $0.blockId == block.blockId }
        } catch {
            NSLog("[Blocked] unblock failed: \(error.localizedDescription)")
            errorText = error.localizedDescription
        }
    }
}
