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
                        NavigationLink {
                            ChatDetailView(
                                viewModel: ChatDetailViewModel(
                                    thread: thread,
                                    chatService: di.chatService,
                                    appState: appState
                                ) { updatedThread in
                                    viewModel.handleThreadUpdate(updatedThread)
                                }
                            )
                        } label: {
                            ChatThreadRow(
                                thread: thread,
                                currentUserId: viewModel.currentUserId
                            )
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
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
                ChatDetailView(
                    viewModel: ChatDetailViewModel(
                        thread: thread,
                        chatService: di.chatService,
                        appState: appState
                    ) { updatedThread in
                        viewModel.handleThreadUpdate(updatedThread)
                    }
                )
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
