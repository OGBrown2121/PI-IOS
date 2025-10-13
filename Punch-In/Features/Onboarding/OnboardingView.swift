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
        ZStack(alignment: .top) {
            onboardingBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacingLarge) {
                    heroHeader

                    if let errorMessage = viewModel.errorMessage {
                        errorCard(errorMessage)
                    }

                    accentCard(.warm, title: "Profile basics", systemImage: "person.crop.circle.badge.plus") {
                        profileImageSection
                        Divider()
                            .tint(Color.white.opacity(0.15))
                        usernameField
                        accountTypeSection
                    }

                    accentCard(.cool, title: "Details", systemImage: "slider.horizontal.3") {
                        primaryFields
                        Divider()
                            .tint(Color.white.opacity(0.08))
                        bioField
                    }

                    accentCard(.neutral, title: "Spotlights", systemImage: "sparkles") {
                        upcomingProjectsSection
                        Divider()
                            .tint(Color.primary.opacity(0.08))
                        upcomingEventsSection
                    }

                    accentCard(.warm, title: "Finish up", systemImage: "checkmark.circle") {
                        saveButton
                        if viewModel.isSaving {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(Theme.primaryGradientEnd)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }
                .padding(.horizontal, Theme.spacingLarge)
                .padding(.vertical, Theme.spacingXLarge)
            }
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

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSmall) {
            Text(mode.titleText)
                .font(.title.bold())
                .foregroundStyle(.white)
            Text(mode.descriptionText)
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, Theme.spacingLarge)
        .padding(.vertical, Theme.spacingLarge)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Theme.primaryGradientStart.opacity(0.9),
                    Theme.primaryGradientEnd.opacity(0.85)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Theme.primaryGradientEnd.opacity(0.2), radius: 16, x: 0, y: 12)
    }

    private func errorCard(_ message: String) -> some View {
        Text(message)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.spacingMedium)
            .padding(.vertical, Theme.spacingSmall)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.red.opacity(0.28), radius: 16, x: 0, y: 10)
    }

    private var profileImageSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSmall) {
            Text("Profile photo")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.9))

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
                            .foregroundStyle(Color.white.opacity(0.75))
                    } else {
                        Text("Shown on your public page. Images up to 8 MB.")
                            .font(.footnote)
                            .foregroundStyle(Color.white.opacity(0.75))
                    }
                }
            }
        }
    }

    private var usernameField: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSmall) {
            Text("Username")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.9))
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
                .foregroundStyle(Color.white.opacity(0.9))

            if viewModel.canEditAccountType {
                Menu {
                    ForEach(AccountType.allCases) { type in
                        Button {
                            viewModel.selectedAccountType = type
                        } label: {
                            if viewModel.selectedAccountType == type {
                                Label(type.title, systemImage: "checkmark")
                            } else {
                                Text(type.title)
                            }
                        }
                    }
                } label: {
                    selectorLabel(text: viewModel.selectedAccountType.title, isPlaceholder: false)
                }
                .buttonStyle(.plain)
            } else {
                Text(viewModel.selectedAccountType.title)
                    .font(.headline)
            }

            Text(viewModel.selectedAccountType.subtitle)
                .font(.footnote)
                .foregroundStyle(Color.white.opacity(0.75))
        }
    }

    @ViewBuilder
    private var primaryFields: some View {
        switch viewModel.selectedAccountType.profileFieldStyle {
        case .location:
            locationFields
        case .specialties:
            specialtyFields
        }
    }

    private var locationFields: some View {
        VStack(alignment: .leading, spacing: Theme.spacingLarge) {
            VStack(alignment: .leading, spacing: Theme.spacingSmall) {
                Text(viewModel.fieldOneLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
                TextField(viewModel.fieldOneLabel, text: $viewModel.fieldOne)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: Theme.spacingSmall) {
                Text(viewModel.fieldTwoLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
                Button {
                    activeSheet = .location
                } label: {
                    selectorLabel(text: viewModel.fieldTwo.isEmpty ? "Select location" : viewModel.fieldTwo,
                                  isPlaceholder: viewModel.fieldTwo.isEmpty)
                }
            }
        }
    }

    private var specialtyFields: some View {
        VStack(alignment: .leading, spacing: Theme.spacingLarge) {
            if viewModel.selectedAccountType.usesPrimaryOptions {
                primaryOptionsSelector
            }

            VStack(alignment: .leading, spacing: Theme.spacingSmall) {
                Text(viewModel.fieldTwoLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
                TextField(viewModel.fieldTwoLabel, text: $viewModel.fieldTwo)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var primaryOptionsSelector: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSmall) {
            Text(viewModel.fieldOneLabel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white)
            Button {
                activeSheet = .primaryOptions
            } label: {
                selectorLabel(text: primaryOptionsDisplayText,
                              isPlaceholder: viewModel.selectedPrimaryOptions.isEmpty)
            }
            if primaryOptionsLimit > 0 {
                Text("Select up to \(primaryOptionsLimit) options")
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.8))
            }
        }
    }

    private var bioField: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSmall) {
            Text("Public bio")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.9))
            TextField("Tell the community about yourself", text: $viewModel.publicBio, axis: .vertical)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var upcomingProjectsSection: some View {
        spotlightSection(
            title: "Upcoming projects",
            subtitle: "Pin works in progress or releases so collaborators know what’s next.",
            icon: "hammer",
            items: $viewModel.upcomingProjects,
            category: .project
        )
    }

    private var upcomingEventsSection: some View {
        spotlightSection(
            title: "Upcoming events",
            subtitle: "Share listening parties, sessions, or workshops people can join.",
            icon: "calendar",
            items: $viewModel.upcomingEvents,
            category: .event
        )
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

    private func spotlightSection(
        title: String,
        subtitle: String,
        icon: String,
        items: Binding<[ProfileSpotlight]>,
        category: ProfileSpotlight.Category
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingMedium) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.headline)
                Spacer()
                Button {
                    withAnimation {
                        viewModel.addSpotlight(for: category)
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.canAddSpotlight(for: category))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if category == .event {
                    Text(eventsExpirationText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if items.wrappedValue.isEmpty {
                Text("Nothing pinned yet. Add up to \(viewModel.maxSpotlightsPerCategory) \(category == .project ? "projects" : "events").")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, Theme.spacingSmall)
            } else {
                VStack(spacing: Theme.spacingMedium) {
                    ForEach(items.wrappedValue) { spotlight in
                        let spotlightBinding = binding(for: spotlight, in: items)
                        spotlightCard(
                            spotlight: spotlightBinding,
                            category: category,
                            onCancel: {
                                withAnimation {
                                    viewModel.removeSpotlight(id: spotlight.id, category: category)
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    private var eventsExpirationText: String {
        let days = ProfileSpotlight.eventVisibilityWindowDays
        if days <= 1 {
            return "Events automatically disappear the day after they happen."
        }
        return "Events automatically disappear \(days) days after their scheduled time."
    }

    private func spotlightCard(
        spotlight: Binding<ProfileSpotlight>,
        category: ProfileSpotlight.Category,
        onCancel: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingMedium) {
            HStack {
                Text(category.title)
                    .font(.headline.weight(.semibold))
                Spacer(minLength: 0)
                Button(role: .destructive) {
                    onCancel()
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                        .labelStyle(.titleAndIcon)
                }
            }

            VStack(alignment: .leading, spacing: Theme.spacingSmall) {
                Text("Title")
                    .font(.footnote.weight(.semibold))
                TextField("What’s the headline?", text: spotlight.title)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: Theme.spacingSmall) {
                Text("Description")
                    .font(.footnote.weight(.semibold))
                TextField("Give a short description", text: spotlight.detail, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
            }

            if category == .event {
                VStack(alignment: .leading, spacing: Theme.spacingSmall) {
                    Text("Location")
                        .font(.footnote.weight(.semibold))
                    TextField("Where is it happening?", text: spotlight.location)
                        .textFieldStyle(.roundedBorder)
                }
            }

            if category == .event {
                VStack(alignment: .leading, spacing: Theme.spacingSmall) {
                    Text("Scheduled for")
                        .font(.footnote.weight(.semibold))
                    DatePicker(
                        "",
                        selection: dateBinding(for: spotlight),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.compact)
                    .labelsHidden()
                }
            } else {
                Toggle(isOn: dateToggleBinding(for: spotlight)) {
                    Label("Add date", systemImage: "calendar.badge.plus")
                }

                if spotlight.wrappedValue.scheduledAt != nil {
                    DatePicker(
                        "Scheduled for",
                        selection: dateBinding(for: spotlight),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.compact)
                }
            }

            VStack(alignment: .leading, spacing: Theme.spacingSmall) {
                Text("Call to action")
                    .font(.footnote.weight(.semibold))
                TextField("Button label (optional)", text: spotlight.callToActionTitle)
                    .textFieldStyle(.roundedBorder)
                TextField("Link (optional)", text: urlBinding(for: spotlight))
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
            }
        }
        .padding(Theme.spacingLarge)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(spotlightBackground(for: category))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(spotlightStroke(for: category), lineWidth: 1)
        )
    }

    private func spotlightBackground(for category: ProfileSpotlight.Category) -> LinearGradient {
        switch category {
        case .project:
            return LinearGradient(
                colors: [
                    Theme.primaryGradientStart.opacity(0.16),
                    Theme.primaryGradientEnd.opacity(0.14)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .event:
            return LinearGradient(
                colors: [
                    Color.purple.opacity(0.16),
                    Color(red: 0.35, green: 0.45, blue: 0.98).opacity(0.14)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private func spotlightStroke(for category: ProfileSpotlight.Category) -> Color {
        switch category {
        case .project:
            return Theme.primaryGradientEnd.opacity(0.2)
        case .event:
            return Color.purple.opacity(0.24)
        }
    }

    private func dateToggleBinding(for spotlight: Binding<ProfileSpotlight>) -> Binding<Bool> {
        Binding(
            get: { spotlight.wrappedValue.scheduledAt != nil },
            set: { isOn in
                if isOn {
                    spotlight.wrappedValue.scheduledAt = spotlight.wrappedValue.scheduledAt ?? Date()
                } else {
                    spotlight.wrappedValue.scheduledAt = nil
                }
            }
        )
    }

    private func dateBinding(for spotlight: Binding<ProfileSpotlight>) -> Binding<Date> {
        Binding(
            get: { spotlight.wrappedValue.scheduledAt ?? Date() },
            set: { newValue in
                spotlight.wrappedValue.scheduledAt = newValue
            }
        )
    }

    private func urlBinding(for spotlight: Binding<ProfileSpotlight>) -> Binding<String> {
        Binding(
            get: {
                spotlight.wrappedValue.callToActionURL?.absoluteString ?? ""
            },
            set: { newValue in
                let trimmed = newValue.trimmed
                guard trimmed.isEmpty == false else {
                    spotlight.wrappedValue.callToActionURL = nil
                    return
                }

                if let url = URL(string: trimmed), url.scheme != nil {
                    spotlight.wrappedValue.callToActionURL = url
                } else if let url = URL(string: "https://\(trimmed)") {
                    spotlight.wrappedValue.callToActionURL = url
                } else {
                    spotlight.wrappedValue.callToActionURL = nil
                }
            }
        )
    }

    private func binding(
        for spotlight: ProfileSpotlight,
        in items: Binding<[ProfileSpotlight]>
    ) -> Binding<ProfileSpotlight> {
        Binding(
            get: {
                guard let index = items.wrappedValue.firstIndex(where: { $0.id == spotlight.id }) else {
                    return spotlight
                }
                return items.wrappedValue[index]
            },
            set: { newValue in
                guard let index = items.wrappedValue.firstIndex(where: { $0.id == spotlight.id }) else {
                    return
                }
                items.wrappedValue[index] = newValue
            }
        )
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
                .foregroundStyle(isPlaceholder ? Color.white.opacity(0.85) : Color.white)
                .multilineTextAlignment(.leading)
            Spacer()
            Image(systemName: "chevron.down")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.9))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            LinearGradient(
                colors: [
                    Theme.primaryGradientStart.opacity(0.4),
                    Theme.primaryGradientEnd.opacity(0.4)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.25), lineWidth: 1)
        )
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
        viewModel.selectedAccountType.primaryOptionsTitle
    }
}

private enum AccentCardStyle {
    case warm
    case cool
    case neutral

    var gradient: LinearGradient {
        switch self {
        case .warm:
            return LinearGradient(
                colors: [
                    Theme.primaryGradientStart.opacity(0.38),
                    Theme.primaryGradientEnd.opacity(0.28)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .cool:
            return LinearGradient(
                colors: [
                    Color(red: 0.35, green: 0.46, blue: 0.98).opacity(0.32),
                    Color(red: 0.32, green: 0.3, blue: 0.9).opacity(0.32)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .neutral:
            return LinearGradient(
                colors: [
                    Theme.cardBackground.opacity(0.96),
                    Theme.elevatedCardBackground.opacity(0.98)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    var strokeColor: Color {
        switch self {
        case .warm:
            return Theme.primaryGradientEnd.opacity(0.35)
        case .cool:
            return Color.blue.opacity(0.25)
        case .neutral:
            return Color.black.opacity(0.08)
        }
    }

    var titleColor: Color {
        switch self {
        case .neutral:
            return Color.primary
        default:
            return Color.white
        }
    }

    var shadowColor: Color {
        switch self {
        case .warm:
            return Theme.primaryGradientEnd.opacity(0.22)
        case .cool:
            return Color.blue.opacity(0.2)
        case .neutral:
            return Color.black.opacity(0.08)
        }
    }
}

private extension OnboardingView {
    private var onboardingBackground: some View {
        LinearGradient(
            colors: [
                Theme.primaryGradientStart.opacity(0.18),
                Color(uiColor: .systemBackground),
                Theme.primaryGradientEnd.opacity(0.14)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    @ViewBuilder
    private func accentCard(
        _ style: AccentCardStyle,
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingMedium) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(style.titleColor)
                .symbolRenderingMode(.hierarchical)
            content()
        }
        .padding(Theme.spacingLarge)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.gradient)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(style.strokeColor, lineWidth: 1)
        )
        .shadow(color: style.shadowColor, radius: 18, x: 0, y: 12)
    }
}

#Preview("Onboarding View") {
    let appState = AppState()
    appState.currentUser = UserProfile.mock
    return OnboardingView(viewModel: OnboardingViewModel(appState: appState, firestoreService: MockFirestoreService(), storageService: MockStorageService()))
        .environmentObject(appState)
        .environment(\.di, DIContainer.makeMock())
}
