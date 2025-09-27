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

    init(viewModel: ChatViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        List {
            if viewModel.isLoading && viewModel.filteredThreads.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(.circular)
                        .padding(.vertical, Theme.spacingLarge)
                    Spacer()
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else if viewModel.filteredThreads.isEmpty {
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
        .sheet(isPresented: $viewModel.isPresentingNewChat) {
            NavigationStack {
                NewChatView(viewModel: viewModel) { thread in
                    viewModel.handleThreadUpdate(thread)
                    showToast("Conversation created")
                }
            }
        }
        .onChange(of: viewModel.errorMessage) { _, newValue in
            guard let newValue else { return }
            presentedError = newValue
        }
        .onDisappear { toastDismissTask?.cancel() }
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
        .background(Circle().fill(Theme.highlightedCardBackground))
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.1), radius: 4, y: 2)
    }

    private var placeholder: some View {
        Circle()
            .fill(Theme.primaryColor.opacity(0.14))
            .overlay(
                Text(initials(from: fallback))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Theme.primaryColor)
            )
    }

    private func initials(from name: String) -> String {
        let components = name.split(separator: " ")
        let initials = components.prefix(2).compactMap { $0.first }
        return initials.isEmpty ? "PI" : initials.map(String.init).joined().uppercased()
    }
}

#Preview("Threads") {
    let appState = AppState()
    appState.currentUser = .mock
    return NavigationStack {
        ThreadsView(viewModel: ChatViewModel(chatService: MockChatService(), appState: appState))
            .environmentObject(appState)
            .environment(\.di, DIContainer.makeMock())
    }
}
