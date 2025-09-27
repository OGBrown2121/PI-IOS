import SwiftUI
import PhotosUI
import UIKit

@MainActor
struct NewChatView: View {
    @ObservedObject var viewModel: ChatViewModel
    let onThreadCreated: (ChatThread) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var groupPhotoPickerItem: PhotosPickerItem?

    var body: some View {
        List {
            Section {
                TextField(
                    "Search users or studios",
                    text: Binding(
                        get: { viewModel.participantQuery },
                        set: { viewModel.updateParticipantQuery($0) }
                    )
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            }

            if !viewModel.selectedParticipants.isEmpty {
                Section(header: Text("Selected")) {
                    SelectedParticipantsGrid(participants: viewModel.selectedParticipants) { participant in
                        viewModel.removeParticipant(participant)
                    }
                }
            }

            Section(header: Text(viewModel.participantQuery.isEmpty ? "Suggestions" : "Results")) {
                if viewModel.participantResults.isEmpty {
                    Text("No matches yet. Try a different name or keyword.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, Theme.spacingSmall)
                } else {
                    ForEach(viewModel.participantResults) { participant in
                        Button {
                            viewModel.toggleParticipantSelection(participant)
                        } label: {
                            ParticipantRow(participant: participant, isSelected: viewModel.selectedParticipants.contains(participant))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            let groupPhoto = viewModel.newChatGroupPhoto
            let groupName = viewModel.newChatGroupName
            if viewModel.isNewChatGroup {
                Section(header: Text("Group settings"), footer: Text("As the creator you can decide whether other participants may change these details later.")) {
                    TextField("Group name", text: $viewModel.newChatGroupName)
                        .textInputAutocapitalization(.words)
                    PhotosPicker(selection: $groupPhotoPickerItem, matching: .images) {
                        HStack {
                            GroupThumbnail(media: groupPhoto, title: groupName)
                            Text(groupPhoto == nil ? "Add group photo" : "Change group photo")
                            Spacer()
                            if groupPhoto != nil {
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    if groupPhoto != nil {
                        Button(role: .destructive) {
                            viewModel.updateGroupPhoto(nil)
                        } label: {
                            Label("Remove photo", systemImage: "trash")
                        }
                    }
                    Toggle("Allow participants to edit name & photo", isOn: $viewModel.newChatAllowsParticipantEditing)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("New Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    viewModel.dismissNewChat()
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { @MainActor in
                        if let thread = await viewModel.createThread() {
                            onThreadCreated(thread)
                            dismiss()
                        }
                    }
                } label: {
                    let isCreating = viewModel.isCreatingThread
                    if isCreating {
                        ProgressView()
                    } else {
                        let buttonTitle = viewModel.isNewChatGroup ? "Create" : "Start"
                        Text(buttonTitle)
                            .fontWeight(.semibold)
                    }
                }
                .disabled(viewModel.selectedParticipants.isEmpty || viewModel.isCreatingThread)
            }
        }
        .onChange(of: groupPhotoPickerItem) { _, newValue in
            guard let newValue else { return }
            Task { await loadGroupPhoto(from: newValue) }
        }
    }

    private func loadGroupPhoto(from item: PhotosPickerItem) async {
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                await MainActor.run {
                    viewModel.updateGroupPhoto(ChatMedia(imageData: data))
                }
            }
        } catch {
            // Swallow errors silently for now; picker will remain available
        }
        await MainActor.run {
            groupPhotoPickerItem = nil
        }
    }
}

private struct ParticipantRow: View {
    let participant: ChatParticipant
    let isSelected: Bool

    var body: some View {
        HStack(spacing: Theme.spacingMedium) {
            ParticipantAvatar(participant: participant)
                .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 4) {
                Text(participant.displayName)
                    .font(.body.weight(.semibold))
                if let secondary = participant.secondaryText {
                    Text(secondary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                .foregroundStyle(isSelected ? Theme.primaryColor : Color.secondary)
                .font(.system(size: 20, weight: .semibold))
        }
        .padding(.vertical, Theme.spacingSmall)
    }
}

private struct SelectedParticipantsGrid: View {
    let participants: [ChatParticipant]
    let removeAction: (ChatParticipant) -> Void

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(participants) { participant in
                HStack(spacing: 10) {
                    ParticipantAvatar(participant: participant)
                        .frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(participant.displayName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        if let secondary = participant.secondaryText {
                            Text(secondary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Button {
                        removeAction(participant)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.secondary)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.elevatedCardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Theme.primaryColor.opacity(0.1), lineWidth: 1)
                        )
                )
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ParticipantAvatar: View {
    let participant: ChatParticipant

    var body: some View {
        ZStack {
            if let url = participant.avatarURL {
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
        .frame(width: 42, height: 42)
        .clipShape(Circle())
        .overlay(
            Circle().stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }

    private var placeholder: some View {
        Circle()
            .fill(Theme.primaryColor.opacity(0.18))
            .overlay(
                Text(initials)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.primaryColor)
            )
    }

    private var initials: String {
        let components = participant.displayName.split(separator: " ")
        let initials = components.prefix(2).compactMap { $0.first }
        return initials.isEmpty ? "PI" : initials.map(String.init).joined().uppercased()
    }
}

private struct GroupThumbnail: View {
    let media: ChatMedia?
    let title: String

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
        .frame(width: 44, height: 44)
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

#Preview("New Chat") {
    let appState = AppState()
    appState.currentUser = .mock
    let vm = ChatViewModel(chatService: MockChatService(), appState: appState)
    return NavigationStack {
        NewChatView(viewModel: vm) { _ in }
    }
}
