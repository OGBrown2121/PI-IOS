import Foundation

@MainActor
final class ChatDetailViewModel: ObservableObject {
    @Published private(set) var thread: ChatThread
    @Published var draftMessage: String = ""
    @Published var isSendingMessage = false
    @Published var isUpdatingSettings = false
    @Published var isUpdatingProject = false
    @Published var errorMessage: String?
    @Published var downloadInProgressFileId: String?
    @Published var uploadProgress: Double?

    private let chatService: any ChatService
    private let storageService: any StorageService
    private let appState: AppState
    private let onThreadUpdated: ((ChatThread) -> Void)?

    init(
        thread: ChatThread,
        chatService: any ChatService,
        storageService: any StorageService,
        appState: AppState,
        onThreadUpdated: ((ChatThread) -> Void)? = nil
    ) {
        self.thread = thread
        self.chatService = chatService
        self.storageService = storageService
        self.appState = appState
        self.onThreadUpdated = onThreadUpdated
    }

    var sortedMessages: [ChatMessage] {
        thread.messages.sorted(by: { $0.sentAt < $1.sentAt })
    }

    var project: ChatThread.Project? {
        thread.project
    }

    var currentUserParticipant: ChatParticipant? {
        guard let profile = appState.currentUser else { return nil }
        return ChatParticipant(user: profile)
    }

    var workspaceDrivePlan: UserProfile.DrivePlan {
        if let ownerPlan = projectOwnerDrivePlan {
            return ownerPlan
        }
        if let currentPlan = appState.currentUser?.drivePlan {
            return currentPlan
        }
        return .free
    }

    var storagePlanDescription: String {
        workspaceDrivePlan.storageDescription
    }

    private var projectOwnerDrivePlan: UserProfile.DrivePlan? {
        guard let ownerParticipant = thread.participants.first(where: { $0.id == thread.creatorId }) else {
            return nil
        }
        return drivePlan(for: ownerParticipant)
    }

    private func drivePlan(for participant: ChatParticipant) -> UserProfile.DrivePlan? {
        switch participant.kind {
        case let .user(profile):
            return profile.drivePlan
        case .studio:
            // Studios manage workspace storage centrally; treat as subscribed capacity.
            return .subscribed
        }
    }

    var canEditGroupSettings: Bool {
        guard let currentUserId = currentUserParticipant?.id else { return false }
        return thread.canParticipantEditSettings(currentUserId)
    }

    func refreshThread() async {
        errorMessage = nil
        do {
            let refreshed = try await chatService.thread(withId: thread.id)
            thread = refreshed
            onThreadUpdated?(refreshed)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func sendTextMessage() async {
        let text = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard let sender = currentUserParticipant else {
            errorMessage = "You need an active profile to send a message."
            return
        }
        errorMessage = nil
        isSendingMessage = true
        do {
            let message = try await chatService.sendMessage(
                threadId: thread.id,
                sender: sender,
                content: .text(text)
            )
            updateThread(with: message)
            draftMessage = ""
        } catch {
            errorMessage = error.localizedDescription
        }
        isSendingMessage = false
    }

    func sendPhoto(data: Data, caption: String? = nil) async {
        guard let sender = currentUserParticipant else {
            errorMessage = "You need an active profile to send a message."
            return
        }
        errorMessage = nil
        isSendingMessage = true
        let media = ChatMedia(imageData: data)
        do {
            let message = try await chatService.sendMessage(
                threadId: thread.id,
                sender: sender,
                content: .photo(media, caption: caption)
            )
            updateThread(with: message)
        } catch {
            errorMessage = error.localizedDescription
        }
        isSendingMessage = false
    }

    func updateGroupSettings(name: String, photo: ChatMedia?, allowsParticipantEditing: Bool) async {
        guard thread.isGroup else { return }
        guard canEditGroupSettings else {
            errorMessage = "Only the creator can change these settings."
            return
        }
        errorMessage = nil
        isUpdatingSettings = true
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let settings = ChatThread.GroupSettings(
            name: trimmedName.isEmpty ? thread.displayName() : trimmedName,
            photo: photo,
            allowsParticipantEditing: allowsParticipantEditing
        )
        do {
            let updated = try await chatService.updateGroupSettings(
                threadId: thread.id,
                groupSettings: settings
            )
            thread = updated
            onThreadUpdated?(updated)
        } catch {
            errorMessage = error.localizedDescription
        }
        isUpdatingSettings = false
    }

    func addTask(title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard var project = project else { return }
        let task = ChatThread.Project.Task(title: trimmed)
        project.tasks.append(task)
        await persist(project: project)
    }

    func toggleTaskCompletion(_ task: ChatThread.Project.Task) async {
        guard var project = project else { return }
        guard let index = project.tasks.firstIndex(where: { $0.id == task.id }) else { return }
        project.tasks[index].isComplete.toggle()
        await persist(project: project)
    }

    func removeTask(_ task: ChatThread.Project.Task) async {
        guard var project = project else { return }
        project.tasks.removeAll { $0.id == task.id }
        await persist(project: project)
    }

    func uploadProjectFile(data: Data, fileName: String, contentType: String?) async {
        guard var project = project else {
            errorMessage = "Project workspace not available."
            return
        }
        guard let uploader = currentUserParticipant else {
            errorMessage = "You need an active profile to upload files."
            return
        }

        let maxFileSize = 200 * 1024 * 1024 // 200 MB
        guard data.count <= maxFileSize else {
            errorMessage = "Files must be 200 MB or smaller."
            return
        }

        let sanitizedName = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitizedName.isEmpty else {
            errorMessage = "Provide a valid filename."
            return
        }

        let storageLimit = projectStorageLimit
        if storageLimit <= 0 {
            errorMessage = "File storage is only available with a subscribed Punch-In account. Upgrade to add files to this workspace."
            return
        }

        let newTotal = totalProjectFileSize + data.count
        if newTotal > storageLimit {
            let formattedLimit = ByteCountFormatter.string(fromByteCount: Int64(storageLimit), countStyle: .file)
            let planName = workspaceDrivePlan.displayName
            errorMessage = "\(planName) workspaces can store up to \(formattedLimit). Remove existing files or upgrade for more space."
            return
        }

        let fileId = UUID().uuidString
        let storageSafeName = sanitizedName
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "../", with: "")
            .replacingOccurrences(of: "./", with: "")
            .replacingOccurrences(of: "..", with: ".")
            .replacingOccurrences(of: "/", with: "-")
        let storagePath = "project-files/\(thread.id)/\(fileId)/\(storageSafeName)"
        let resolvedContentType = contentType ?? MimeType.fromFileExtension((sanitizedName as NSString).pathExtension) ?? "application/octet-stream"

        isUpdatingProject = true
        uploadProgress = 0
        errorMessage = nil
        do {
            let downloadURL = try await storageService.uploadFile(
                data: data,
                path: storagePath,
                contentType: resolvedContentType,
                progress: { value in
                    Task { @MainActor in
                        self.uploadProgress = value
                    }
                }
            )

            let file = ChatThread.Project.FileReference(
                id: fileId,
                name: sanitizedName,
                url: downloadURL,
                storagePath: storagePath,
                contentType: resolvedContentType,
                fileSize: data.count,
                uploadedAt: Date(),
                uploadedBy: uploader
            )
            project.files.append(file)
            let didPersist = await persist(project: project)
            if !didPersist {
                try? await storageService.deleteFile(at: storagePath)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isUpdatingProject = false
        uploadProgress = nil
    }

    func removeFile(_ file: ChatThread.Project.FileReference) async {
        guard var project = project else { return }
        project.files.removeAll { $0.id == file.id }
        let storagePath = file.storagePath
        let didPersist = await persist(project: project)
        if didPersist, let storagePath {
            try? await storageService.deleteFile(at: storagePath)
        }
    }

    func downloadURL(for file: ChatThread.Project.FileReference) async -> URL? {
        if project?.allowsDownloads == false && currentUserParticipant?.id != thread.creatorId {
            errorMessage = "Downloads are disabled by the project owner."
            return nil
        }
        if let storagePath = file.storagePath {
            downloadInProgressFileId = file.id
            defer { downloadInProgressFileId = nil }
            do {
                return try await storageService.downloadURL(for: storagePath)
            } catch {
                errorMessage = error.localizedDescription
                return nil
            }
        }
        return file.url
    }

    var totalProjectFileSize: Int {
        project?.files.reduce(0) { $0 + ($1.fileSize ?? 0) } ?? 0
    }

    var projectStorageLimit: Int { workspaceDrivePlan.storageLimitBytes }

    var hasProjectStorage: Bool {
        projectStorageLimit > 0
    }

    var formattedProjectStorageLimit: String? {
        guard projectStorageLimit > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(projectStorageLimit), countStyle: .file)
    }

    var storageUpgradeMessage: String {
        "Subscribe to Punch-In to unlock 10 GB of shared project storage."
    }

    var projectStorageFractionUsed: Double {
        guard projectStorageLimit > 0 else { return 0 }
        return Double(totalProjectFileSize) / Double(projectStorageLimit)
    }

    var remainingProjectStorage: Int {
        max(projectStorageLimit - totalProjectFileSize, 0)
    }

    func updateDownloadPermission(allowsDownloads: Bool) async {
        guard var project = project else { return }
        guard currentUserParticipant?.id == thread.creatorId else {
            errorMessage = "Only the project owner can change download access."
            return
        }
        if project.allowsDownloads == allowsDownloads { return }
        project.allowsDownloads = allowsDownloads
        await persist(project: project)
    }

    private func updateThread(with message: ChatMessage) {
        var updatedThread = thread
        updatedThread.messages.append(message)
        updatedThread.lastMessageAt = message.sentAt
        thread = updatedThread
        onThreadUpdated?(updatedThread)
    }

    @discardableResult
    private func persist(project: ChatThread.Project) async -> Bool {
        errorMessage = nil
        isUpdatingProject = true
        defer { isUpdatingProject = false }
        do {
            let updated = try await chatService.updateProject(threadId: thread.id, project: project)
            thread = updated
            onThreadUpdated?(updated)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
