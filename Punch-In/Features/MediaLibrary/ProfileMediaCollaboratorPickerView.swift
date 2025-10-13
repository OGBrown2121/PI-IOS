import SwiftUI

struct ProfileMediaCollaboratorPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var searchViewModel: ProfileMediaCollaboratorSearchViewModel
    @Binding private var selectedCollaborators: [ProfileMediaCollaborator]

    init(
        searchViewModel: ProfileMediaCollaboratorSearchViewModel,
        selectedCollaborators: Binding<[ProfileMediaCollaborator]>
    ) {
        _searchViewModel = StateObject(wrappedValue: searchViewModel)
        _selectedCollaborators = selectedCollaborators
    }

    var body: some View {
        List {
            if selectedCollaborators.isEmpty == false {
                Section("Selected") {
                    ForEach(selectedCollaborators) { collaborator in
                        selectedCollaboratorRow(for: collaborator)
                    }
                }
            }

            Section("Search results") {
                if searchViewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if let message = searchViewModel.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                } else if searchViewModel.collaboratorResults.isEmpty {
                    Text("Start typing to search for artists, engineers, or studios.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(searchViewModel.collaboratorResults) { collaborator in
                        Button {
                            toggle(collaborator)
                        } label: {
                            HStack {
                                CollaboratorAvatar(collaborator: collaborator)
                                VStack(alignment: .leading) {
                                    Text(collaborator.displayName)
                                        .font(.subheadline.weight(.semibold))
                                    Text(collaboratorSubtitle(collaborator))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selectedCollaborators.contains(where: { $0.id == collaborator.id && $0.kind == collaborator.kind }) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Theme.primaryColor)
                                }
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $searchViewModel.query, placement: .navigationBarDrawer(displayMode: .automatic))
        .onSubmit(of: .search) {
            Task { await searchViewModel.search() }
        }
        .onChangeCompatibility(of: searchViewModel.query) {
            Task { await searchViewModel.search() }
        }
        .navigationTitle("Tag collaborators")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        .task {
            await searchViewModel.prepare()
        }
    }

    @ViewBuilder
    private func selectedCollaboratorRow(for collaborator: ProfileMediaCollaborator) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                CollaboratorAvatar(collaborator: collaborator)
                VStack(alignment: .leading, spacing: 2) {
                    Text(collaborator.displayName)
                        .font(.subheadline.weight(.semibold))
                    Text(collaboratorSubtitle(collaborator))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(role: .destructive) {
                    remove(collaborator)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.red.opacity(0.8))
                }
            }

            if let binding = roleBinding(for: collaborator) {
                Menu {
                    Button {
                        binding.wrappedValue = nil
                    } label: {
                        roleMenuRow(
                            title: "No contribution",
                            systemImage: "line.3.horizontal.decrease.circle",
                            isSelected: binding.wrappedValue == nil
                        )
                    }

                    ForEach(ProfileMediaCollaborator.Role.suggested(for: collaborator.kind)) { role in
                        Button {
                            binding.wrappedValue = role
                        } label: {
                            roleMenuRow(
                                title: role.displayTitle,
                                systemImage: role.systemImageName,
                                isSelected: binding.wrappedValue == role
                            )
                        }
                    }
                } label: {
                    Label(
                        collaborator.role?.displayTitle ?? "Set contribution",
                        systemImage: collaborator.role?.systemImageName ?? "tag"
                    )
                    .font(.caption.weight(.semibold))
                }
            }

            Text(collaborator.role.map { "Contribution: \($0.displayTitle)" } ?? "Contribution not set")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    private func toggle(_ collaborator: ProfileMediaCollaborator) {
        if selectedCollaborators.contains(where: { $0.id == collaborator.id && $0.kind == collaborator.kind }) {
            remove(collaborator)
        } else {
            var entry = collaborator
            if entry.kind == .studio, entry.role == nil {
                entry.role = .studio
            }
            selectedCollaborators.append(entry)
        }
    }

    private func remove(_ collaborator: ProfileMediaCollaborator) {
        selectedCollaborators.removeAll { $0.id == collaborator.id && $0.kind == collaborator.kind }
    }

    private func roleBinding(for collaborator: ProfileMediaCollaborator) -> Binding<ProfileMediaCollaborator.Role?>? {
        guard let index = selectedCollaborators.firstIndex(where: { $0.id == collaborator.id && $0.kind == collaborator.kind }) else {
            return nil
        }
        return Binding(
            get: { selectedCollaborators[index].role },
            set: { selectedCollaborators[index].role = $0 }
        )
    }

    @ViewBuilder
    private func roleMenuRow(title: String, systemImage: String, isSelected: Bool) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(Theme.primaryColor)
            }
        }
    }

    private func collaboratorSubtitle(_ collaborator: ProfileMediaCollaborator) -> String {
        switch collaborator.kind {
        case .user:
            return collaborator.accountType?.title ?? "Profile"
        case .studio:
            return "Studio"
        }
    }
}

private struct CollaboratorAvatar: View {
    let collaborator: ProfileMediaCollaborator

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.primaryColor.opacity(0.12))
                .frame(width: 36, height: 36)
            Image(systemName: iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.primaryColor)
        }
    }

    private var iconName: String {
        if let role = collaborator.role {
            return role.systemImageName
        }
        switch collaborator.kind {
        case .user:
            return "person.fill"
        case .studio:
            return "building.2.fill"
        }
    }
}
