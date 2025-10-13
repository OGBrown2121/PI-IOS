import SwiftUI
import PhotosUI
import UIKit

@MainActor
struct ChatDetailView: View {
    @StateObject private var viewModel: ChatDetailViewModel
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isShowingGroupSettings = false
    @State private var selectedParticipant: ChatParticipant?
    @State private var presentedError: String?

    init(viewModel: ChatDetailViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 0) {
            MessageListView(
                messages: viewModel.sortedMessages,
                currentUserId: viewModel.currentUserParticipant?.id,
                onParticipantSelected: { participant in
                    selectedParticipant = participant
                }
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
            } else if let participant = otherParticipants.first {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        selectedParticipant = participant
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
                    .accessibilityLabel("View participant profile")
                }
            }
        }
        .background(Theme.appBackground)
        .sheet(isPresented: $isShowingGroupSettings) {
            GroupSettingsSheet(
                isPresented: $isShowingGroupSettings,
                viewModel: viewModel
            )
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $selectedParticipant) { participant in
            NavigationStack {
                ParticipantDetailContainer(participant: participant)
            }
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

    private var otherParticipants: [ChatParticipant] {
        let currentId = viewModel.currentUserParticipant?.id
        return viewModel.thread.participants.filter { participant in
            guard let currentId else { return true }
            return participant.id != currentId
        }
    }
}

private struct MessageListView: View {
    let messages: [ChatMessage]
    let currentUserId: String?
    let onParticipantSelected: (ChatParticipant) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Theme.spacingMedium) {
                    ForEach(messages) { message in
                        MessageBubble(
                            message: message,
                            isCurrentUser: message.sender.id == currentUserId,
                            showSender: showSender(for: message),
                            onSenderTapped: onParticipantSelected
                        )
                        .id(message.id)
                    }
                }
                .padding(.horizontal, Theme.spacingMedium)
                .padding(.vertical, Theme.spacingMedium)
            }
            .background(Theme.appBackground)
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
    let onSenderTapped: (ChatParticipant) -> Void

    var body: some View {
        VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 6) {
            if showSender {
                Button {
                    onSenderTapped(message.sender)
                } label: {
                    Text(message.sender.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .underline()
                }
                .buttonStyle(.plain)
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
                Section(header: Text("Participants")) {
                    ForEach(viewModel.thread.participants) { participant in
                        NavigationLink {
                            ParticipantDetailContainer(participant: participant)
                        } label: {
                            ParticipantRow(
                                participant: participant,
                                isCurrentUser: participant.id == viewModel.currentUserParticipant?.id,
                                showsNavigationIndicator: true
                            )
                        }
                    }
                }

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

private struct ParticipantRow: View {
    let participant: ChatParticipant
    let isCurrentUser: Bool
    var showsNavigationIndicator: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                if let subtitle = participant.secondaryText, subtitle.isEmpty == false {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if showsNavigationIndicator {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private var displayName: String {
        isCurrentUser ? "You" : participant.displayName
    }

    private var iconName: String {
        switch participant.kind {
        case .user:
            return "person"
        case .studio:
            return "building.2"
        }
    }
}

@MainActor
private struct ParticipantDetailContainer: View {
    let participant: ChatParticipant

    var body: some View {
        switch participant.kind {
        case let .user(profile):
            userDestination(for: profile)
        case let .studio(studio):
            ChatStudioDetailHost(studio: studio)
        }
    }

    @ViewBuilder
    private func userDestination(for profile: UserProfile) -> some View {
        if profile.accountType.isEngineer {
            EngineerDetailView(engineerId: profile.id, profile: profile)
        } else if profile.accountType.isStudioOwner {
            StudioOwnerProfileSummaryView(profile: profile)
        } else {
            ArtistDetailView(artistId: profile.id, profile: profile)
        }
    }
}

private struct StudioOwnerProfileSummaryView: View {
    let profile: UserProfile

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacingLarge) {
                avatar
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(Theme.primaryColor)

                VStack(spacing: Theme.spacingSmall) {
                    Text(displayName)
                        .font(.title3.weight(.semibold))
                    Text("This studio owner hasn’t listed a public studio yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if profile.profileDetails.bio.isEmpty == false {
                    VStack(alignment: .leading, spacing: Theme.spacingSmall) {
                        Text("About")
                            .font(.headline)
                        Text(profile.profileDetails.bio)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Theme.cardBackground)
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .padding(Theme.spacingLarge)
        }
        .background(Theme.appBackground)
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var displayName: String {
        let raw = profile.displayName.isEmpty ? profile.username : profile.displayName
        return raw.isEmpty ? "Studio Owner" : raw
    }

    @ViewBuilder
    private var avatar: some View {
        if let url = profile.profileImageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 72)
                        .clipShape(Circle())
                case .empty:
                    ProgressView()
                case .failure:
                    initialsView
                @unknown default:
                    initialsView
                }
            }
        } else {
            initialsView
        }
    }

    private var initialsView: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [Theme.primaryGradientStart, Theme.primaryGradientEnd],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 72, height: 72)
            .overlay {
                Text(initials)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
            }
    }

    private var initials: String {
        let base = profile.displayName.isEmpty ? profile.username : profile.displayName
        let components = base.split(separator: " ")
        if let firstChar = components.first?.first {
            if let secondChar = components.dropFirst().first?.first {
                return String([firstChar, secondChar]).uppercased()
            }
            return String(firstChar).uppercased()
        }
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count >= 2 {
            return String(trimmed.prefix(2)).uppercased()
        }
        return "SO"
    }
}

@MainActor
private struct ChatStudioDetailHost: View {
    @Environment(\.di) private var di

    let studio: Studio

    @State private var resolvedStudio: Studio?
    @State private var hasLoaded = false
    @State private var loadErrorMessage: String?

    var body: some View {
        let studioToDisplay = resolvedStudio ?? studio

        StudioDetailView(studio: studioToDisplay)
            .id(studioIdentityKey(for: studioToDisplay))
            .task {
                await loadStudioIfNeeded()
            }
            .overlay(alignment: .bottom) {
                if let message = loadErrorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding()
                }
            }
    }

    private func loadStudioIfNeeded() async {
        guard hasLoaded == false else { return }
        hasLoaded = true
        do {
            if let fetched = try await di.firestoreService.loadStudio(withId: studio.id) {
                resolvedStudio = fetched
                loadErrorMessage = nil
            }
        } catch {
            loadErrorMessage = error.localizedDescription
        }
    }

    private func studioIdentityKey(for studio: Studio) -> String {
        let sortedEngineers = studio.approvedEngineerIds.sorted().joined(separator: ",")
        return "\(studio.id)#\(sortedEngineers)#\(studio.name)"
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
