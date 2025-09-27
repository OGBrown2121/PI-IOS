import SwiftUI
import PhotosUI
import UIKit

@MainActor
struct ChatDetailView: View {
    @StateObject private var viewModel: ChatDetailViewModel
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isShowingGroupSettings = false
    @State private var presentedError: String?

    init(viewModel: ChatDetailViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 0) {
            MessageListView(
                messages: viewModel.sortedMessages,
                currentUserId: viewModel.currentUserParticipant?.id
            )

            Divider()

            ComposerBar(
                draft: $viewModel.draftMessage,
                isSending: viewModel.isSendingMessage,
                sendAction: {
                    Task { await viewModel.sendTextMessage() }
                },
                photoPickerItem: $selectedPhotoItem
            )
            .padding(.horizontal, Theme.spacingMedium)
            .padding(.vertical, Theme.spacingSmall)
        }
        .navigationTitle(viewModel.thread.displayName(currentUserId: viewModel.currentUserParticipant?.id))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if viewModel.thread.isGroup {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isShowingGroupSettings = true
                    } label: {
                        Image(systemName: "person.3")
                    }
                }
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .sheet(isPresented: $isShowingGroupSettings) {
            GroupSettingsSheet(isPresented: $isShowingGroupSettings, viewModel: viewModel)
                .presentationDetents([.medium, .large])
        }
        .onChange(of: selectedPhotoItem) { _, newValue in
            guard let newValue else { return }
            Task { await loadPhoto(from: newValue) }
        }
        .onChange(of: viewModel.errorMessage) { _, newValue in
            guard let newValue else { return }
            presentedError = newValue
        }
        .alert(presentedError ?? "", isPresented: Binding(
            get: { presentedError != nil },
            set: { newValue in if !newValue { presentedError = nil } }
        ), actions: {
            Button("OK", role: .cancel) { presentedError = nil }
        })
        .task {
            await viewModel.refreshThread()
        }
    }

    private func loadPhoto(from item: PhotosPickerItem) async {
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                await viewModel.sendPhoto(data: data)
            }
        } catch {
            presentedError = error.localizedDescription
        }
        await MainActor.run {
            selectedPhotoItem = nil
        }
    }
}

private struct MessageListView: View {
    let messages: [ChatMessage]
    let currentUserId: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Theme.spacingMedium) {
                    ForEach(messages) { message in
                        MessageBubble(
                            message: message,
                            isCurrentUser: message.sender.id == currentUserId,
                            showSender: showSender(for: message)
                        )
                        .id(message.id)
                    }
                }
                .padding(.horizontal, Theme.spacingMedium)
                .padding(.vertical, Theme.spacingMedium)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .onChange(of: messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onAppear {
                scrollToBottom(proxy: proxy)
            }
        }
    }

    private func showSender(for message: ChatMessage) -> Bool {
        guard message.sender.id != currentUserId else { return false }
        return true
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let last = messages.last else { return }
        DispatchQueue.main.async {
            withAnimation {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}

private struct MessageBubble: View {
    let message: ChatMessage
    let isCurrentUser: Bool
    let showSender: Bool

    var body: some View {
        VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 6) {
            if showSender {
                Text(message.sender.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            bubbleContent
                .background(bubbleBackground)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.black.opacity(0.05), lineWidth: 0.5)
                )

            Text(message.sentAt, style: .time)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: isCurrentUser ? .trailing : .leading)
        .padding(isCurrentUser ? .leading : .trailing, 40)
    }

    @ViewBuilder
    private var bubbleContent: some View {
        switch message.content {
        case let .text(text):
            Text(text)
                .foregroundStyle(isCurrentUser ? Color.white : Color.primary)
                .padding(12)
        case let .photo(media, caption):
            VStack(alignment: .leading, spacing: 6) {
                AttachmentImage(media: media)
                    .frame(maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                if let caption, !caption.isEmpty {
                    Text(caption)
                        .foregroundStyle(isCurrentUser ? Color.white : Color.primary)
                }
            }
            .padding(10)
        }
    }

    private var bubbleBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(isCurrentUser ? Theme.primaryColor : Theme.cardBackground)
            .opacity(isCurrentUser ? 0.92 : 1.0)
    }
}

private struct AttachmentImage: View {
    let media: ChatMedia

    var body: some View {
        ZStack {
            if let data = media.imageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let url = media.remoteURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image.resizable().scaledToFill()
                    case .empty:
                        ZStack {
                            Color.gray.opacity(0.1)
                            ProgressView()
                        }
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
    }

    private var placeholder: some View {
        ZStack {
            Color.gray.opacity(0.1)
            Image(systemName: "photo")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ComposerBar: View {
    @Binding var draft: String
    let isSending: Bool
    let sendAction: () -> Void
    @Binding var photoPickerItem: PhotosPickerItem?

    var body: some View {
        HStack(alignment: .bottom, spacing: Theme.spacingSmall) {
            PhotosPicker(selection: $photoPickerItem, matching: .images) {
                Image(systemName: "photo")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.primaryColor)
                    .padding(8)
            }
            .buttonStyle(.plain)

            TextField("Message", text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .disabled(isSending)
                .onSubmit(sendAction)

            Button(action: sendAction) {
                if isSending {
                    ProgressView()
                        .progressViewStyle(.circular)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 20, weight: .semibold))
                }
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
        }
    }
}

@MainActor
private struct GroupSettingsSheet: View {
    @Binding var isPresented: Bool
    @ObservedObject var viewModel: ChatDetailViewModel

    @State private var name: String
    @State private var allowsEditing: Bool
    @State private var photo: ChatMedia?
    @State private var photoPickerItem: PhotosPickerItem?

    init(isPresented: Binding<Bool>, viewModel: ChatDetailViewModel) {
        _isPresented = isPresented
        self.viewModel = viewModel
        let settings = viewModel.thread.groupSettings
        _name = State(initialValue: settings?.name ?? viewModel.thread.displayName())
        _allowsEditing = State(initialValue: settings?.allowsParticipantEditing ?? true)
        _photo = State(initialValue: settings?.photo)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Group name")) {
                    TextField("Group name", text: $name)
                        .disabled(!viewModel.canEditGroupSettings)
                }

                Section(header: Text("Group photo")) {
                    let currentPhoto = photo
                    HStack {
                        GroupPhotoPreview(media: currentPhoto)
                        Spacer()
                        PhotosPicker(selection: $photoPickerItem, matching: .images) {
                            Label(currentPhoto == nil ? "Add photo" : "Change photo", systemImage: "photo")
                        }
                        .disabled(!viewModel.canEditGroupSettings)
                    }
                    if currentPhoto != nil {
                        Button("Remove photo", role: .destructive) {
                            photo = nil
                        }
                        .disabled(!viewModel.canEditGroupSettings)
                    }
                }

                Section {
                    Toggle("Allow participants to edit", isOn: $allowsEditing)
                        .disabled(!viewModel.canEditGroupSettings)
                    if !viewModel.canEditGroupSettings {
                        Text("Only the creator can change these settings.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Group Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        let currentName = name
                        let currentPhoto = photo
                        let currentAllows = allowsEditing
                        Task { @MainActor in
                            await viewModel.updateGroupSettings(
                                name: currentName,
                                photo: currentPhoto,
                                allowsParticipantEditing: currentAllows
                            )
                            if viewModel.errorMessage == nil {
                                isPresented = false
                            }
                        }
                    } label: {
                        if viewModel.isUpdatingSettings {
                            ProgressView()
                                .progressViewStyle(.circular)
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(!viewModel.canEditGroupSettings)
                }
            }
            .onChange(of: photoPickerItem) { _, newValue in
                guard let newValue else { return }
                Task { await loadPhoto(from: newValue) }
            }
        }
    }

    private func loadPhoto(from item: PhotosPickerItem) async {
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                await MainActor.run {
                    photo = ChatMedia(imageData: data)
                }
            }
        } catch {
            // ignore picker errors for now
        }
        await MainActor.run {
            photoPickerItem = nil
        }
    }
}

private struct GroupPhotoPreview: View {
    let media: ChatMedia?

    var body: some View {
        ZStack {
            if let data = media?.imageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let url = media?.remoteURL {
                AsyncImage(url: url) { phase in
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
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Theme.primaryColor.opacity(0.12))
            .overlay(
                Image(systemName: "photo")
                    .foregroundStyle(Theme.primaryColor)
            )
    }
}

#Preview("Chat Detail") {
    let appState = AppState()
    appState.currentUser = .mock
    let thread = ChatThread.mockList.first!
    return NavigationStack {
        ChatDetailView(
            viewModel: ChatDetailViewModel(
                thread: thread,
                chatService: MockChatService(),
                appState: appState
            )
        )
    }
}
