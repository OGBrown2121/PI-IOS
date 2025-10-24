import SwiftUI
import UIKit

@MainActor
struct ThreadsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.di) private var di
    @StateObject private var viewModel: ChatViewModel
    @State private var toastMessage: String?
    @State private var toastDismissTask: Task<Void, Never>?
    @State private var presentedError: String?
    @State private var isShowingAlerts = false
    @State private var deepLinkedThread: ChatThread?
    @State private var threadPendingDeletion: ChatThread?

    init(viewModel: ChatViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        List {
            if viewModel.isLoading && viewModel.filteredThreads.isEmpty {
                loadingRow
            } else if viewModel.filteredThreads.isEmpty {
                emptyRow
            } else {
                Section(header: Text("Conversations")) {
                    ForEach(viewModel.filteredThreads) { thread in
                        threadNavigationRow(for: thread)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Messages")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                AlertsButton { isShowingAlerts = true }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.presentNewChat()
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("New chat")
            }
        }
        .searchable(text: $viewModel.threadSearchQuery, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search chats")
        .refreshable {
            await viewModel.refresh()
            await MainActor.run { showToast("Chats refreshed") }
        }
        .task {
            await viewModel.refresh()
        }
        .toast(message: $toastMessage, bottomInset: 100)
        .alert(presentedError ?? "", isPresented: Binding(
            get: { presentedError != nil },
            set: { newValue in if !newValue { presentedError = nil } }
        ), actions: {
            Button("OK", role: .cancel) { presentedError = nil }
        })
        .confirmationDialog(
            "Delete this chat?",
            item: $threadPendingDeletion,
            titleVisibility: .visible
        ) { thread in
            Button("Delete Chat", role: .destructive) {
                threadPendingDeletion = nil
                Task { @MainActor in
                    if await viewModel.deleteThread(thread) {
                        showToast("Chat deleted")
                    }
                }
            }

            Button("Cancel", role: .cancel) {
                threadPendingDeletion = nil
            }
        } message: { _ in
            Text("This removes the chat from your inbox.")
        }
        .sheet(isPresented: $isShowingAlerts) {
            NavigationStack {
                AlertsView()
            }
        }
        .sheet(isPresented: $viewModel.isPresentingNewChat) {
            NavigationStack {
                NewChatView(viewModel: viewModel) { thread in
                    viewModel.handleThreadUpdate(thread)
                    showToast("Conversation created")
                }
            }
        }
        .sheet(item: $deepLinkedThread) { thread in
            NavigationStack {
                chatDetailDestination(for: thread)
            }
        }
        .onChange(of: viewModel.errorMessage) { _, newValue in
            guard let newValue else { return }
            presentedError = newValue
        }
        .onChange(of: appState.pendingChatThread) { _, newValue in
            guard let newValue else { return }
            viewModel.handleThreadUpdate(newValue)
            deepLinkedThread = newValue
            appState.pendingChatThread = nil
        }
        .onDisappear { toastDismissTask?.cancel() }
    }

    private var loadingRow: some View {
        HStack {
            Spacer()
            ProgressView()
                .progressViewStyle(.circular)
                .padding(.vertical, Theme.spacingLarge)
            Spacer()
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var emptyRow: some View {
        VStack(spacing: Theme.spacingMedium) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 42))
                .foregroundStyle(Theme.primaryColor.opacity(0.8))
            Text("No conversations yet")
                .font(.headline)
            Text("Start a chat to collaborate with artists, engineers, or studios.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.vertical, Theme.spacingXLarge)
        .frame(maxWidth: .infinity)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private func chatDetailDestination(for thread: ChatThread) -> some View {
        ChatDetailView(viewModel: makeChatDetailViewModel(for: thread))
    }

    @ViewBuilder
    private func threadNavigationRow(for thread: ChatThread) -> some View {
        NavigationLink {
            chatDetailDestination(for: thread)
        } label: {
            ChatThreadRow(
                thread: thread,
                currentUserId: viewModel.currentUserId
            )
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .swipeActions(allowsFullSwipe: false) {
            muteActionButton(for: thread)
            deleteActionButton(for: thread)
        }
    }

    @ViewBuilder
    private func muteActionButton(for thread: ChatThread) -> some View {
        let isMuted = thread.isMuted(by: viewModel.currentUserId)
        Button {
            Task { @MainActor in
                if let result = await viewModel.toggleMute(for: thread) {
                    showToast(result ? "Chat muted" : "Chat unmuted")
                }
            }
        } label: {
            Label(
                isMuted ? "Unmute" : "Mute",
                systemImage: isMuted ? "bell.fill" : "bell.slash"
            )
        }
        .tint(Theme.primaryColor)
    }

    @ViewBuilder
    private func deleteActionButton(for thread: ChatThread) -> some View {
        Button(role: .destructive) {
            threadPendingDeletion = thread
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    @MainActor
    private func makeChatDetailViewModel(for thread: ChatThread) -> ChatDetailViewModel {
        ChatDetailViewModel(
            thread: thread,
            chatService: di.chatService,
            storageService: di.storageService,
            appState: appState,
            onThreadUpdated: { updatedThread in
                viewModel.handleThreadUpdate(updatedThread)
            },
            onThreadDeleted: { deletedId in
                viewModel.removeThread(withId: deletedId)
                showToast("Chat deleted")
            }
        )
    }

    @MainActor
    private func showToast(_ message: String) {
        toastDismissTask?.cancel()
        withAnimation { toastMessage = message }
        toastDismissTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                withAnimation { toastMessage = nil }
            }
        }
    }
}

private struct ChatThreadRow: View {
    let thread: ChatThread
    let currentUserId: String?

    var body: some View {
        HStack(spacing: Theme.spacingMedium) {
            ChatAvatarView(media: thread.displayImage(currentUserId: currentUserId), fallback: thread.displayName(currentUserId: currentUserId))
                .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(thread.displayName(currentUserId: currentUserId))
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    if let date = thread.lastMessageAt {
                        Text(date.formattedShort())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let preview = thread.lastMessagePreview {
                    Text(preview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    Text("No messages yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if thread.isMuted(by: currentUserId) {
                    HStack(spacing: 6) {
                        Image(systemName: "bell.slash.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Muted")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if thread.isGroup {
                    HStack(spacing: 6) {
                        Image(systemName: thread.allowsParticipantEditing ? "person.3.sequence" : "lock")
                            .font(.caption)
                            .foregroundStyle(thread.allowsParticipantEditing ? Theme.primaryColor : .secondary)
                        Text(thread.allowsParticipantEditing ? "Participants can edit" : "Locked by creator")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, Theme.spacingSmall)
    }
}

private struct ChatAvatarView: View {
    let media: ChatMedia?
    let fallback: String

    var body: some View {
        ZStack {
            if let imageData = media?.imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let remoteURL = media?.remoteURL {
                AsyncImage(url: remoteURL) { phase in
                    switch phase {
                    case let .success(image):
                        image.resizable().scaledToFill()
                    case .empty:
                        ProgressView().progressViewStyle(.circular)
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemFill))
            Text(String(fallback.prefix(1)))
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
        }
    }
}
