import Combine
import PhotosUI
import SwiftUI
import UIKit

struct OnboardingView: View {
    enum Mode {
        case onboarding
        case editing

        var titleText: String {
            switch self {
            case .onboarding:
                return "Complete your profile"
            case .editing:
                return "Edit your profile"
            }
        }

        var descriptionText: String {
            switch self {
            case .onboarding:
                return "Choose how you’ll use PunchIn and add details that will appear on your public page."
            case .editing:
                return "Update your public profile so collaborators know what you’re working on."
            }
        }

        var primaryActionTitle: String {
            switch self {
            case .onboarding:
                return "Continue"
            case .editing:
                return "Save changes"
            }
        }

        var savingTitle: String { "Saving…" }
    }

    private enum ActiveSheet: Identifiable {
        case location
        case primaryOptions

        var id: Int {
            switch self {
            case .location: return 0
            case .primaryOptions: return 1
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel: OnboardingViewModel
    private let mode: Mode
    @State private var activeSheet: ActiveSheet?
    @State private var profileImagePickerItem: PhotosPickerItem?
    @State private var profilePreviewImage: Image?
    @State private var profileImageData: Data?
    @State private var profileImageContentType = "image/jpeg"
    @State private var removeProfileImage = false

    init(viewModel: OnboardingViewModel, mode: Mode = .onboarding) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.mode = mode
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacingLarge) {
                header

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                profileImageSection
                usernameField
                accountTypeSection
                primaryFields
                bioField
                saveButton

                if viewModel.isSaving {
                    ProgressView()
                        .fullWidth()
                }
            }
            .padding(Theme.spacingLarge)
        }
        .toolbar {
            if mode == .editing {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onReceive(viewModel.$didSave.removeDuplicates()) { didSave in
            if didSave && mode == .editing {
                dismiss()
            }
        }
        .sheet(item: $activeSheet) { item in
            switch item {
            case .location:
                LocationPickerView { selection in
                    viewModel.setLocation(selection)
                }
            case .primaryOptions:
                MultiSelectListView(
                    title: primaryOptionsTitle,
                    options: primaryOptionsOptions,
                    selectionLimit: primaryOptionsLimit,
                    selections: $viewModel.selectedPrimaryOptions
                )
            }
        }
        .task(id: profileImagePickerItem) {
            guard let item = profileImagePickerItem else { return }
            await loadProfileImage(from: item)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSmall) {
            Text(mode.titleText)
                .font(Theme.headlineFont())
            Text(mode.descriptionText)
                .foregroundStyle(.secondary)
        }
    }

    private var profileImageSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSmall) {
            Text("Profile photo")
                .font(.subheadline.weight(.semibold))

            HStack(alignment: .center, spacing: Theme.spacingMedium) {
                profileImagePreview

                VStack(alignment: .leading, spacing: Theme.spacingSmall) {
                    PhotosPicker(selection: $profileImagePickerItem, matching: .images) {
                        Label("Select photo", systemImage: "photo")
                    }
                    .buttonStyle(.bordered)

                    if profilePreviewImage != nil {
                        Button("Clear selection") {
                            clearNewProfileImage()
                        }
                        .foregroundStyle(.red)
                    } else if removeProfileImage {
                        Button("Keep current photo") {
                            removeProfileImage = false
                            viewModel.errorMessage = nil
                        }
                        .buttonStyle(.bordered)
                    } else if currentProfileImageURL != nil {
                        Button("Remove photo") {
                            profilePreviewImage = nil
                            profileImageData = nil
                            profileImagePickerItem = nil
                            profileImageContentType = "image/jpeg"
                            removeProfileImage = true
                            viewModel.errorMessage = nil
                        }
                        .foregroundStyle(.red)
                    }

                    if removeProfileImage {
                        Text("The current photo will be removed after you save.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Shown on your public page. Images up to 8 MB.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var usernameField: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSmall) {
            Text("Username")
                .font(.subheadline.weight(.semibold))
            TextField("Username", text: $viewModel.username)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.none)
                .autocorrectionDisabled(true)
        }
    }

    private var accountTypeSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSmall) {
            Text("Account Type")
                .font(.subheadline.weight(.semibold))

            if viewModel.canEditAccountType {
                Picker("Account Type", selection: $viewModel.selectedAccountType) {
                    ForEach(AccountType.allCases) { type in
                        Text(type.title).tag(type)
                    }
                }
                .pickerStyle(.segmented)
            } else {
                Text(viewModel.selectedAccountType.title)
                    .font(.headline)
            }

            Text(viewModel.selectedAccountType.subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var primaryFields: some View {
        switch viewModel.selectedAccountType {
        case .studioOwner:
            studioOwnerFields
        case .artist:
            artistFields
        case .engineer:
            engineerFields
        }
    }

    private var studioOwnerFields: some View {
        VStack(alignment: .leading, spacing: Theme.spacingLarge) {
            VStack(alignment: .leading, spacing: Theme.spacingSmall) {
                Text(viewModel.fieldOneLabel)
                    .font(.subheadline.weight(.semibold))
                TextField(viewModel.fieldOneLabel, text: $viewModel.fieldOne)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: Theme.spacingSmall) {
                Text(viewModel.fieldTwoLabel)
                    .font(.subheadline.weight(.semibold))
                Button {
                    activeSheet = .location
                } label: {
                    selectorLabel(text: viewModel.fieldTwo.isEmpty ? "Select location" : viewModel.fieldTwo,
                                  isPlaceholder: viewModel.fieldTwo.isEmpty)
                }
            }
        }
    }

    private var artistFields: some View {
        VStack(alignment: .leading, spacing: Theme.spacingLarge) {
            primaryOptionsSelector

            VStack(alignment: .leading, spacing: Theme.spacingSmall) {
                Text(viewModel.fieldTwoLabel)
                    .font(.subheadline.weight(.semibold))
                TextField(viewModel.fieldTwoLabel, text: $viewModel.fieldTwo)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var engineerFields: some View {
        VStack(alignment: .leading, spacing: Theme.spacingLarge) {
            primaryOptionsSelector

            VStack(alignment: .leading, spacing: Theme.spacingSmall) {
                Text(viewModel.fieldTwoLabel)
                    .font(.subheadline.weight(.semibold))
                TextField(viewModel.fieldTwoLabel, text: $viewModel.fieldTwo)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var primaryOptionsSelector: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSmall) {
            Text(viewModel.fieldOneLabel)
                .font(.subheadline.weight(.semibold))
            Button {
                activeSheet = .primaryOptions
            } label: {
                selectorLabel(text: primaryOptionsDisplayText,
                              isPlaceholder: viewModel.selectedPrimaryOptions.isEmpty)
            }
            Text("Select up to \(primaryOptionsLimit) options")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var bioField: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSmall) {
            Text("Public bio")
                .font(.subheadline.weight(.semibold))
            TextField("Tell the community about yourself", text: $viewModel.publicBio, axis: .vertical)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var saveButton: some View {
        PrimaryButton(title: viewModel.isSaving ? mode.savingTitle : mode.primaryActionTitle) {
            Task {
                await viewModel.saveProfile(
                    profileImageData: profileImageData,
                    profileImageContentType: profileImageContentType,
                    removeProfileImage: shouldRemoveProfileImage
                )
            }
        }
        .disabled(!viewModel.isContinueEnabled || viewModel.isSaving)
    }

    private var profileImagePreview: some View {
        Group {
            if let image = profilePreviewImage {
                image
                    .resizable()
                    .scaledToFill()
            } else if let remoteURL = currentProfileImageURL, !removeProfileImage {
                AsyncImage(url: remoteURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholderAvatar
                    @unknown default:
                        placeholderAvatar
                    }
                }
            } else {
                placeholderAvatar
            }
        }
        .frame(width: 96, height: 96)
        .clipShape(Circle())
    }

    private var currentProfileImageURL: URL? {
        appState.currentUser?.profileImageURL
    }

    private var shouldRemoveProfileImage: Bool {
        removeProfileImage && profilePreviewImage == nil && profileImageData == nil && currentProfileImageURL != nil
    }

    private func clearNewProfileImage() {
        profilePreviewImage = nil
        profileImageData = nil
        profileImagePickerItem = nil
        profileImageContentType = "image/jpeg"
        removeProfileImage = false
        viewModel.errorMessage = nil
    }

    private func loadProfileImage(from item: PhotosPickerItem) async {
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data) {
                let processedData: (Data, String)?

                if let jpeg = uiImage.jpegData(compressionQuality: 0.85) {
                    processedData = (jpeg, "image/jpeg")
                } else if let png = uiImage.pngData() {
                    processedData = (png, "image/png")
                } else {
                    processedData = nil
                }

                guard let (finalData, contentType) = processedData else {
                    throw NSError(domain: "OnboardingView", code: -1)
                }

                guard finalData.count < 8 * 1024 * 1024 else {
                    throw NSError(domain: "OnboardingView", code: -3)
                }

                await MainActor.run {
                    profilePreviewImage = Image(uiImage: uiImage)
                    profileImageData = finalData
                    profileImageContentType = contentType
                    removeProfileImage = false
                    viewModel.errorMessage = nil
                }
            } else {
                throw NSError(domain: "OnboardingView", code: -2)
            }
        } catch {
            await MainActor.run {
                if (error as NSError).code == -3 {
                    viewModel.errorMessage = "Profile images need to be under 8 MB."
                } else {
                    viewModel.errorMessage = "We couldn't load that image. Try another file."
                }
                profileImagePickerItem = nil
            }
        }
    }

    private var placeholderAvatar: some View {
        let initials = initials(for: appState.currentUser)
        return ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Theme.primaryColor.opacity(0.25), Theme.primaryColor],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(initials)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
        }
    }

    private func initials(for profile: UserProfile?) -> String {
        guard let profile else { return "PI" }
        let name = profile.displayName.isEmpty ? profile.username : profile.displayName
        let components = name.split(separator: " ")
        if let first = components.first, let last = components.dropFirst().first, let firstInitial = first.first, let lastInitial = last.first {
            return String([firstInitial, lastInitial]).uppercased()
        } else if let first = components.first {
            return String(first.prefix(2)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    private func selectorLabel(text: String, isPlaceholder: Bool) -> some View {
        HStack {
            Text(text)
                .foregroundStyle(isPlaceholder ? .secondary : .primary)
                .multilineTextAlignment(.leading)
            Spacer()
            Image(systemName: "chevron.down")
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var primaryOptionsLimit: Int {
        viewModel.primaryOptionsLimit(for: viewModel.selectedAccountType)
    }

    private var primaryOptionsOptions: [String] {
        viewModel.primaryOptions(for: viewModel.selectedAccountType)
    }

    private var primaryOptionsDisplayText: String {
        if viewModel.selectedPrimaryOptions.isEmpty {
            return "Select up to \(primaryOptionsLimit) options"
        }
        return viewModel.selectedPrimaryOptions.joined(separator: ", ")
    }

    private var primaryOptionsTitle: String {
        switch viewModel.selectedAccountType {
        case .artist:
            return "Select Genres"
        case .engineer:
            return "Select Specialties"
        case .studioOwner:
            return "Select Options"
        }
    }
}

#Preview("Onboarding View") {
    let appState = AppState()
    appState.currentUser = UserProfile.mock
    return OnboardingView(viewModel: OnboardingViewModel(appState: appState, firestoreService: MockFirestoreService(), storageService: MockStorageService()))
        .environmentObject(appState)
        .environment(\.di, DIContainer.makeMock())
}
