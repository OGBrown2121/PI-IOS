import SwiftUI

struct ProfileMediaLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var uploadManager: ProfileMediaUploadManager
    @StateObject private var viewModel: ProfileMediaLibraryViewModel
    @State private var editorDraft: ProfileMediaDraft?
    @State private var selectedMedia: ProfileMediaItem?
    @State private var toastMessage: String?
    @State private var isShowingErrorAlert = false
    @State private var selectedTab: MediaLibraryTab = .myFiles
    @State private var formatFilter: MediaLibraryFormatFilter = .all

    init(viewModel: ProfileMediaLibraryViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        List {
            filterSection
            pinnedSection(for: pinnedItemsForCurrentTab)
            librarySection(for: libraryItemsForCurrentTab)
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Media Library")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                EditButton()
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    editorDraft = viewModel.makeDraft()
                } label: {
                    Label("Add media", systemImage: "plus")
                }
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            await viewModel.refresh()
        }
        .alert("Upload failed", isPresented: $isShowingErrorAlert, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(viewModel.uploadErrorMessage ?? "Please try again.")
        })
        .sheet(item: $editorDraft) { draft in
            NavigationStack {
                ProfileMediaEditorView(
                    draft: draft,
                    capabilities: viewModel.mediaCapabilities ?? defaultCapabilities,
                    onSave: handleSave,
                    onDelete: { item in
                        await viewModel.delete(item)
                    },
                    collaboratorSearchFactory: { viewModel.makeCollaboratorSearchViewModel() },
                    isPinLimitReached: viewModel.isPinLimitReached
                )
            }
        }
        .sheet(item: $selectedMedia) { media in
            NavigationStack {
                ProfileMediaDetailView(
                    media: media,
                    firestoreService: viewModel.firestoreService,
                    storageService: viewModel.storageService,
                    currentUserProvider: viewModel.currentUserProvider,
                    libraryViewModel: viewModel
                )
            }
        }
        .toast(message: $toastMessage, bottomInset: 60)
        .onChangeCompatibility(of: selectedTab) { newValue in
            if newValue == .shared {
                formatFilter = .all
            }
        }
        .onChangeCompatibility(of: viewModel.uploadErrorMessage) { newValue in
            isShowingErrorAlert = newValue != nil
        }
        .onChangeCompatibility(of: uploadManager.activeUpload?.phase) { phase in
            guard let phase else { return }
            switch phase {
            case .success:
                if let title = uploadManager.activeUpload?.title {
                    toastMessage = "\"\(title)\" uploaded"
                } else {
                    toastMessage = "Upload complete"
                }
            case .failed:
                isShowingErrorAlert = true
                toastMessage = nil
            default:
                break
            }
        }
    }

    private var filterSection: some View {
        let options = formatPickerOptions
        return Section {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Library view", selection: $selectedTab) {
                    ForEach(MediaLibraryTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                if selectedTab == .myFiles && options.count > 1 {
                    Picker("File type", selection: $formatFilter) {
                        ForEach(options) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .padding(.vertical, 4)
        }
        .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private func pinnedSection(for items: [ProfileMediaItem]) -> some View {
        Section(header: sectionHeader(title: viewModel.mediaCapabilities?.pinnedSectionTitle ?? "Pinned")) {
            if items.isEmpty {
                Text(pinnedEmptyMessage())
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items) { item in
                    ProfileMediaRow(
                        item: item,
                        onEdit: { openEditor(for: item) },
                        onTogglePin: { toggled in
                            Task { await viewModel.setPinned(!toggled.isPinned, for: toggled) }
                        },
                        onDelete: {
                            Task { await viewModel.delete(item) }
                        }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { selectedMedia = item }
                }
                .onMove { indices, newOffset in
                    guard canReorderPinned else { return }
                    handlePinnedMove(from: indices, to: newOffset)
                }
                .moveDisabled(canReorderPinned == false)
            }
        }
    }

    @ViewBuilder
    private func librarySection(for items: [ProfileMediaItem]) -> some View {
        Section(header: sectionHeader(title: selectedTab == .myFiles ? "Library" : "Shared Files")) {
            if items.isEmpty {
                Text(libraryEmptyMessage(for: items))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items) { item in
                    ProfileMediaRow(
                        item: item,
                        onEdit: { openEditor(for: item) },
                        onTogglePin: { toggled in
                            Task { await viewModel.setPinned(!toggled.isPinned, for: toggled) }
                        },
                        onDelete: {
                            Task { await viewModel.delete(item) }
                        }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { selectedMedia = item }
                }
            }
        }
    }

    private var pinnedItemsForCurrentTab: [ProfileMediaItem] {
        filtered(items: viewModel.pinnedItems)
    }

    private var libraryItemsForCurrentTab: [ProfileMediaItem] {
        filtered(items: viewModel.libraryItems)
    }

    private var activeFormatFilter: MediaLibraryFormatFilter {
        selectedTab == .myFiles ? formatFilter : .all
    }

    private var isFilteringByFormat: Bool {
        selectedTab == .myFiles && formatFilter != .all
    }

    private var canReorderPinned: Bool {
        isFilteringByFormat == false
    }

    private func filtered(items: [ProfileMediaItem]) -> [ProfileMediaItem] {
        items
            .filter { selectedTab == .shared ? $0.isShared : true }
            .filter { activeFormatFilter.matches($0) }
    }

    private func pinnedEmptyMessage() -> String {
        if isFilteringByFormat && viewModel.pinnedItems.isEmpty == false {
            return "No pinned files match this file type yet."
        }
        return viewModel.mediaCapabilities?.pinnedEmptyState ?? "Pin uploads to feature them on your profile."
    }

    private func libraryEmptyMessage(for filteredItems: [ProfileMediaItem]) -> String {
        switch selectedTab {
        case .myFiles:
            if isFilteringByFormat && viewModel.libraryItems.isEmpty == false {
                return "No files match this file type yet."
            }
            return "Uploads you add will appear here for quick editing."
        case .shared:
            let sharedLibrary = viewModel.mediaItems.filter { $0.isShared && $0.pinnedRank == nil }
            if sharedLibrary.isEmpty {
                return "No uploads yet. Add media to share it on your profile."
            }
            return "All of your shared uploads are pinned right now. Add more without pinning to list them here."
        }
    }

    private var formatPickerOptions: [MediaLibraryFormatFilter] {
        var formats = viewModel.mediaCapabilities?.allowedFormats ?? ProfileMediaFormat.allCases
        formats.append(contentsOf: viewModel.mediaItems.map(\.format))
        var filters = Set<MediaLibraryFormatFilter>([.all, formatFilter])
        for format in formats {
            if let filter = MediaLibraryFormatFilter(format: format) {
                filters.insert(filter)
            }
        }
        let ordered: [MediaLibraryFormatFilter] = [.all, .audio, .video, .photo, .gallery]
        return ordered.filter { filters.contains($0) }
    }

    private enum MediaLibraryTab: String, CaseIterable, Identifiable {
        case myFiles
        case shared

        var id: String { rawValue }

        var title: String {
            switch self {
            case .myFiles:
                return "My Files"
            case .shared:
                return "Shared Files"
            }
        }
    }

    private enum MediaLibraryFormatFilter: String, Identifiable {
        case all
        case audio
        case video
        case photo
        case gallery

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all:
                return "All"
            case .audio:
                return "Audio"
            case .video:
                return "Video"
            case .photo:
                return "Photo"
            case .gallery:
                return "Gallery"
            }
        }

        func matches(_ item: ProfileMediaItem) -> Bool {
            switch self {
            case .all:
                return true
            case .audio:
                return item.format == .audio
            case .video:
                return item.format == .video
            case .photo:
                return item.format == .photo
            case .gallery:
                return item.format == .gallery
            }
        }

        init?(format: ProfileMediaFormat) {
            switch format {
            case .audio:
                self = .audio
            case .video:
                self = .video
            case .photo:
                self = .photo
            case .gallery:
                self = .gallery
            }
        }
    }

    private func handlePinnedMove(from source: IndexSet, to destination: Int) {
        var pinned = viewModel.pinnedItems
        pinned.move(fromOffsets: source, toOffset: destination)
        Task {
            await viewModel.updatePinnedOrder(pinned.map(\.id))
        }
    }

    private func handleSave(_ draft: ProfileMediaDraft) async -> Bool {
        let success = await viewModel.save(draft: draft)
        if success {
            if draft.requiresAssetUpload {
                toastMessage = "Uploading \"\(draft.displayTitle)\"…"
            } else {
                toastMessage = draft.mediaItem == nil ? "Media saved" : "Media updated"
            }
        } else {
            isShowingErrorAlert = true
        }
        return success
    }

    private func openEditor(for item: ProfileMediaItem) {
        editorDraft = viewModel.makeDraft(for: item)
    }

    private func sectionHeader(title: String) -> some View {
        Text(title)
            .font(.headline.weight(.semibold))
    }

    private var defaultCapabilities: ProfileMediaCapabilities {
        ProfileMediaCapabilities(
            allowedFormats: ProfileMediaFormat.allCases,
            defaultCategories: ProfileMediaCategory.allCases,
            pinLimit: 6,
            pinnedSectionTitle: "Pinned",
            pinnedEmptyState: "Pin uploads to highlight them."
        )
    }
}

private struct ProfileMediaRow: View {
    let item: ProfileMediaItem
    let onEdit: () -> Void
    let onTogglePin: (ProfileMediaItem) -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                iconView
                    .foregroundStyle(item.format == .photo ? Theme.primaryColor : Theme.secondaryColor)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title.isEmpty ? "Untitled" : item.title)
                        .font(.subheadline.weight(.semibold))
                    Text(item.displayCategoryTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if item.isPinned {
                    Image(systemName: "star.fill")
                        .foregroundStyle(Theme.primaryColor)
                }
            }

            if item.caption.isEmpty == false {
                Text(item.caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if item.collaborators.isEmpty == false {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(item.collaborators) { collaborator in
                            Label(collaborator.displayName, systemImage: collaborator.kind == .studio ? "building.2" : "person")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(Theme.primaryColor.opacity(0.12))
                                )
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button {
                onEdit()
            } label: {
                Label("Edit", systemImage: "square.and.pencil")
            }
            Button {
                onTogglePin(item)
            } label: {
                Label(item.isPinned ? "Unpin" : "Pin to profile", systemImage: "star")
            }
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                onTogglePin(item)
            } label: {
                Label(item.isPinned ? "Unpin" : "Pin", systemImage: "star.fill")
            }
            .tint(item.isPinned ? .gray : Theme.primaryColor)
        }
    }

    @ViewBuilder
    private var iconView: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Theme.cardBackground)
            .overlay {
                Image(systemName: item.format.iconName)
            }
    }
}
