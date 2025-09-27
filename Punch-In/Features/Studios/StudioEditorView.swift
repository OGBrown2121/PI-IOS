import PhotosUI
import SwiftUI
import UIKit

struct StudioEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let existingStudio: Studio?
    let onSave: (StudioEditorData) async -> String?

    @State private var name: String
    @State private var city: String
    @State private var address: String
    @State private var hourlyRate: String
    @State private var rooms: String
    @State private var amenitiesText: String

    @State private var coverPickerItem: PhotosPickerItem?
    @State private var logoPickerItem: PhotosPickerItem?
    @State private var coverPreviewImage: Image?
    @State private var logoPreviewImage: Image?
    @State private var coverImageData: Data?
    @State private var logoImageData: Data?
    @State private var coverImageContentType = "image/jpeg"
    @State private var logoImageContentType = "image/png"
    @State private var removeCoverImage = false
    @State private var removeLogoImage = false
    @State private var hasHydratedExistingStudio = false

    @State private var isSaving = false
    @State private var errorMessage: String?

    init(existingStudio: Studio?, onSave: @escaping (StudioEditorData) async -> String?) {
        self.existingStudio = existingStudio
        self.onSave = onSave
        _name = State(initialValue: existingStudio?.name ?? "")
        _city = State(initialValue: existingStudio?.city ?? "")
        _address = State(initialValue: existingStudio?.address ?? "")
        _hourlyRate = State(initialValue: existingStudio?.hourlyRate.flatMap { String($0) } ?? "")
        _rooms = State(initialValue: existingStudio?.rooms.flatMap { String($0) } ?? "")
        _amenitiesText = State(initialValue: existingStudio?.amenities.joined(separator: ", ") ?? "")
        _hasHydratedExistingStudio = State(initialValue: existingStudio != nil)
    }

    private var isValid: Bool {
        !name.trimmed.isEmpty && !city.trimmed.isEmpty
    }

    var body: some View {
        Form {
            detailsSection
            sessionsSection
            appearanceSection
            amenitiesSection

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(existingStudio == nil ? "Add Studio" : "Edit Studio")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isSaving ? "Saving…" : "Save") {
                    Task { await save() }
                }
                .disabled(!isValid || isSaving)
            }
        }
        .task(id: coverPickerItem) {
            guard let item = coverPickerItem else { return }
            await loadImage(from: item, assignToCover: true)
        }
        .task(id: logoPickerItem) {
            guard let item = logoPickerItem else { return }
            await loadImage(from: item, assignToCover: false)
        }
        .onAppear { hydrateExistingStudioIfNeeded(force: false) }
        .task(id: existingStudio?.id) {
            hydrateExistingStudioIfNeeded(force: true)
        }
    }

    private var detailsSection: some View {
        Section(header: Text("Studio Details")) {
            TextField("Studio name", text: $name)
                .textInputAutocapitalization(.words)

            NavigationLink {
                LocationPickerView { selection in
                    city = selection
                }
            } label: {
                HStack {
                    Text("City")
                    Spacer()
                    Text(city.isEmpty ? "Select location" : city)
                        .foregroundStyle(city.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .multilineTextAlignment(.trailing)
                }
            }

            TextField("Street address", text: $address)
                .textInputAutocapitalization(.words)
        }
    }

    private var sessionsSection: some View {
        Section(header: Text("Sessions")) {
            TextField("Hourly rate (USD)", text: $hourlyRate)
                .keyboardType(.decimalPad)
            TextField("Number of rooms", text: $rooms)
                .keyboardType(.numberPad)
        }
    }

    private var appearanceSection: some View {
        Section(header: Text("Appearance")) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Cover image")
                    .font(.footnote.weight(.semibold))
                coverPreview
                HStack {
                    PhotosPicker(selection: $coverPickerItem, matching: .images) {
                        Label("Select", systemImage: "photo")
                    }
                    .buttonStyle(.bordered)

                    if hasCoverImage {
                        Button("Remove") {
                            coverPreviewImage = nil
                            coverImageData = nil
                            removeCoverImage = true
                            coverImageContentType = "image/jpeg"
                            coverPickerItem = nil
                        }
                        .foregroundStyle(.red)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Logo")
                    .font(.footnote.weight(.semibold))
                logoPreview
                HStack {
                    PhotosPicker(selection: $logoPickerItem, matching: .images) {
                        Label("Select", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(.bordered)

                    if hasLogoImage {
                        Button("Remove") {
                            logoPreviewImage = nil
                            logoImageData = nil
                            removeLogoImage = true
                            logoImageContentType = "image/png"
                            logoPickerItem = nil
                        }
                        .foregroundStyle(.red)
                    }
                }
            }
        }
    }

    private var amenitiesSection: some View {
        Section(header: Text("Amenities")) {
            TextField("Comma separated list", text: $amenitiesText)
        }
    }

    private var hasCoverImage: Bool {
        coverPreviewImage != nil || (existingStudio?.coverImageURL != nil && !removeCoverImage)
    }

    private var hasLogoImage: Bool {
        logoPreviewImage != nil || (existingStudio?.logoImageURL != nil && !removeLogoImage)
    }

    private var coverPreview: some View {
        Group {
            if let image = coverPreviewImage {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else if let coverURL = existingStudio?.coverImageURL, !removeCoverImage {
                AsyncImage(url: coverURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(height: 140)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholderCover
                    @unknown default:
                        placeholderCover
                    }
                }
                .frame(height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                placeholderCover
            }
        }
    }

    private var placeholderCover: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(uiColor: .secondarySystemGroupedBackground))
            .frame(height: 140)
            .overlay(
                Image(systemName: "photo")
                    .font(.title)
                    .foregroundStyle(.secondary)
            )
    }

    private var logoPreview: some View {
        Group {
            if let image = logoPreviewImage {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 96, height: 96)
                    .clipShape(Circle())
            } else if let logoURL = existingStudio?.logoImageURL, !removeLogoImage {
                AsyncImage(url: logoURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(width: 96, height: 96)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholderLogo
                    @unknown default:
                        placeholderLogo
                    }
                }
                .frame(width: 96, height: 96)
                .clipShape(Circle())
            } else {
                placeholderLogo
            }
        }
    }

    private var placeholderLogo: some View {
        Circle()
            .fill(Color(uiColor: .secondarySystemGroupedBackground))
            .frame(width: 96, height: 96)
            .overlay(
                Image(systemName: "music.note.house")
                    .font(.title)
                    .foregroundStyle(.secondary)
            )
    }

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil

        let editorData = StudioEditorData(
            name: name.trimmed,
            city: city.trimmed,
            address: address.trimmed,
            hourlyRate: hourlyRate.trimmed,
            rooms: rooms.trimmed,
            amenities: amenitiesText,
            existingCoverURL: existingStudio?.coverImageURL,
            existingLogoURL: existingStudio?.logoImageURL,
            newCoverImageData: coverImageData,
            newLogoImageData: logoImageData,
            coverImageContentType: coverImageContentType,
            logoImageContentType: logoImageContentType,
            removeCoverImage: removeCoverImage,
            removeLogoImage: removeLogoImage
        )

        let error = await onSave(editorData)
        if let error {
            errorMessage = error
        } else {
            dismiss()
        }

        isSaving = false
    }

    private func loadImage(from item: PhotosPickerItem, assignToCover: Bool) async {
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data) {
                let processed: (Data, String)?

                if assignToCover {
                    if let jpeg = uiImage.jpegData(compressionQuality: 0.85) {
                        processed = (jpeg, "image/jpeg")
                    } else {
                        processed = nil
                    }
                } else {
                    if let png = uiImage.pngData() {
                        processed = (png, "image/png")
                    } else if let jpeg = uiImage.jpegData(compressionQuality: 0.9) {
                        processed = (jpeg, "image/jpeg")
                    } else {
                        processed = nil
                    }
                }

                guard let (finalData, contentType) = processed else { return }

                await MainActor.run {
                    let image = Image(uiImage: uiImage)
                    if assignToCover {
                        coverPreviewImage = image
                        coverImageData = finalData
                        coverImageContentType = contentType
                        removeCoverImage = false
                    } else {
                        logoPreviewImage = image
                        logoImageData = finalData
                        logoImageContentType = contentType
                        removeLogoImage = false
                    }
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = "We couldn't load that image. Try another file."
            }
        }
    }

    private func hydrateExistingStudioIfNeeded(force: Bool) {
        guard let studio = existingStudio else { return }
        guard force || !hasHydratedExistingStudio else { return }

        name = studio.name
        city = studio.city
        address = studio.address
        hourlyRate = studio.hourlyRate.flatMap { String($0) } ?? ""
        rooms = studio.rooms.flatMap { String($0) } ?? ""
        amenitiesText = studio.amenities.joined(separator: ", ")
        removeCoverImage = false
        removeLogoImage = false
        hasHydratedExistingStudio = true
    }
}

struct StudioEditorData {
    var name: String
    var city: String
    var address: String
    var hourlyRate: String
    var rooms: String
    var amenities: String
    var existingCoverURL: URL?
    var existingLogoURL: URL?
    var newCoverImageData: Data?
    var newLogoImageData: Data?
    var coverImageContentType: String
    var logoImageContentType: String
    var removeCoverImage: Bool
    var removeLogoImage: Bool

    var numericHourlyRate: Double? { Double(hourlyRate.replacingOccurrences(of: ",", with: "")) }
    var numericRooms: Int? { Int(rooms) }
    var amenitiesList: [String] {
        amenities
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
