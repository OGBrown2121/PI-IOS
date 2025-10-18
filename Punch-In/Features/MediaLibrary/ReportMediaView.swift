import PhotosUI
import SwiftUI
import UIKit

@MainActor
final class ReportMediaViewModel: ObservableObject {
    @Published var selectedReason: UserReport.Reason = .spam
    @Published var details: String = "" {
        didSet {
            if details.count > 500 {
                details = String(details.prefix(500))
            }
        }
    }
    @Published private(set) var isSubmitting = false
    @Published var errorMessage: String?
    @Published private(set) var submissionSucceeded = false
    @Published private(set) var evidencePhotos: [EvidencePhoto] = []

    let media: ProfileMediaItem
    private let reportService: any ReportService
    private let storageService: any StorageService
    private let currentUserProvider: () -> UserProfile?

    static let maxEvidencePhotoCount = 4
    static let maxEvidencePhotoFileSizeBytes = 5 * 1024 * 1024

    struct EvidencePhoto: Identifiable, Equatable {
        let id: UUID
        let data: Data
        let contentType: String
        let fileExtension: String

        static func == (lhs: EvidencePhoto, rhs: EvidencePhoto) -> Bool {
            lhs.id == rhs.id
        }
    }

    init(
        media: ProfileMediaItem,
        reportService: any ReportService,
        storageService: any StorageService,
        currentUserProvider: @escaping () -> UserProfile?
    ) {
        self.media = media
        self.reportService = reportService
        self.storageService = storageService
        self.currentUserProvider = currentUserProvider
    }

    var mediaDisplayName: String {
        let fallback = media.displayCategoryTitle
        let trimmed = media.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    var reportActionTitle: String {
        media.format == .audio ? "Report song" : "Report upload"
    }

    var subjectNoun: String {
        media.format == .audio ? "song" : "upload"
    }

    var requiresDetails: Bool {
        selectedReason.requiresDetails
    }

    var isDetailsValid: Bool {
        let trimmed = details.trimmingCharacters(in: .whitespacesAndNewlines)
        guard requiresDetails else { return true }
        return trimmed.count >= 10
    }

    var canSubmit: Bool {
        guard isSubmitting == false else { return false }
        guard isDetailsValid else { return false }
        guard let reporter = currentUserProvider(), reporter.id != media.ownerId else { return false }
        return true
    }

    var canAddMoreEvidencePhotos: Bool {
        evidencePhotos.count < Self.maxEvidencePhotoCount
    }

    func addEvidencePhoto(data: Data, contentType: String, fileExtension: String) {
        guard canAddMoreEvidencePhotos else { return }
        let photo = EvidencePhoto(
            id: UUID(),
            data: data,
            contentType: contentType,
            fileExtension: fileExtension
        )
        evidencePhotos.append(photo)
    }

    func removeEvidencePhoto(_ photo: EvidencePhoto) {
        evidencePhotos.removeAll { $0.id == photo.id }
    }

    func previewImage(for photo: EvidencePhoto) -> Image? {
        guard let uiImage = UIImage(data: photo.data) else { return nil }
        return Image(uiImage: uiImage)
    }

    func submit() async {
        guard isSubmitting == false else { return }

        errorMessage = nil

        guard let reporter = currentUserProvider(), reporter.id != media.ownerId else {
            errorMessage = "You need to be signed in to report this \(subjectNoun)."
            return
        }

        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        if requiresDetails && trimmedDetails.count < 10 {
            errorMessage = "Share a few more details so we can follow up."
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        submissionSucceeded = false

        let reportId = UUID().uuidString
        var evidenceURLs: [URL] = []
        var uploadedPaths: [String] = []

        do {
            if evidencePhotos.isEmpty == false {
                for photo in evidencePhotos {
                    let filename = "\(photo.id.uuidString).\(photo.fileExtension)"
                    let path = "media-reports/\(reporter.id)/\(reportId)/evidence/\(filename)"
                    let url = try await storageService.uploadFile(
                        data: photo.data,
                        path: path,
                        contentType: photo.contentType
                    )
                    evidenceURLs.append(url)
                    uploadedPaths.append(path)
                }
            }

            let report = MediaReport(
                id: reportId,
                mediaId: media.id,
                ownerId: media.ownerId,
                reporterUserId: reporter.id,
                reason: selectedReason,
                details: trimmedDetails,
                evidencePhotoURLs: evidenceURLs
            )

            try await reportService.submitMediaReport(report)
            submissionSucceeded = true
            evidencePhotos.removeAll()
        } catch {
            if uploadedPaths.isEmpty == false {
                for path in uploadedPaths {
                    try? await storageService.deleteFile(at: path)
                }
            }
            errorMessage = error.localizedDescription
        }
    }
}

struct ReportMediaView: View {
    @ObservedObject var viewModel: ReportMediaViewModel
    var onSubmitted: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isDetailsFocused: Bool
    @State private var evidencePickerItem: PhotosPickerItem?

    private let evidenceThumbnailSize: CGFloat = 92

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(viewModel.mediaDisplayName)
                            .font(.headline)
                        Text("Report this \(viewModel.subjectNoun) if it violates our guidelines. We'll review and take action if necessary.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                    .padding(.vertical, 4)
                }

                Section("Reason") {
                    ForEach(UserReport.Reason.allCases) { reason in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.selectedReason = reason
                            }
                        } label: {
                            HStack(alignment: .top, spacing: Theme.spacingMedium) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(reason.title)
                                        .foregroundStyle(.primary)
                                    Text(reason.guidance)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: viewModel.selectedReason == reason ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(viewModel.selectedReason == reason ? Theme.primaryColor : Color.secondary.opacity(0.4))
                            }
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(reason.title)
                    }
                }

                Section("Details") {
                    VStack(alignment: .leading, spacing: 6) {
                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $viewModel.details)
                                .focused($isDetailsFocused)
                                .frame(minHeight: 140)
                                .padding(.horizontal, -4)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.secondary.opacity(0.08))
                                )

                            if viewModel.details.isEmpty {
                                Text("Share why this \(viewModel.subjectNoun) breaks the rules. Do not include private info.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 12)
                                    .padding(.horizontal, 10)
                            }
                        }

                        HStack {
                            if viewModel.requiresDetails {
                                Text("Minimum 10 characters for this reason.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Adding details helps us respond faster.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text("\(viewModel.details.count)/500")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                                .accessibilityLabel("Character count \(viewModel.details.count) of 500")
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Evidence (optional)") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Attach up to \(ReportMediaViewModel.maxEvidencePhotoCount) photos (max \(evidenceFileSizeDescription) each).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        if viewModel.evidencePhotos.isEmpty {
                            Text("Screenshots or photos help us review your report faster.")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Theme.spacingSmall) {
                                ForEach(viewModel.evidencePhotos) { photo in
                                    evidenceThumbnail(for: photo)
                                }

                                if viewModel.canAddMoreEvidencePhotos {
                                    PhotosPicker(selection: $evidencePickerItem, matching: .images) {
                                        addEvidencePlaceholder
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if let errorMessage = viewModel.errorMessage, errorMessage.isEmpty == false {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding(.vertical, 4)
                    }
                }
            }
            .disabled(viewModel.isSubmitting)
            .navigationTitle(viewModel.reportActionTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            await viewModel.submit()
                            if viewModel.submissionSucceeded {
                                onSubmitted?()
                                dismiss()
                            }
                        }
                    } label: {
                        if viewModel.isSubmitting {
                            ProgressView()
                        } else {
                            Text("Submit")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(viewModel.canSubmit == false)
                }
            }
            .onAppear {
                if viewModel.requiresDetails {
                    isDetailsFocused = true
                }
            }
            .onChange(of: evidencePickerItem) { _, newValue in
                guard let newValue else { return }
                Task { await loadEvidencePhoto(from: newValue) }
            }
        }
    }

    private var evidenceFileSizeDescription: String {
        let megabytes = Double(ReportMediaViewModel.maxEvidencePhotoFileSizeBytes) / (1024 * 1024)
        if megabytes.rounded() == megabytes {
            return String(format: "%.0f MB", megabytes)
        } else {
            return String(format: "%.1f MB", megabytes)
        }
    }

    private var addEvidencePlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.primaryColor)
            Text("Add photo")
                .font(.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        }
        .frame(width: evidenceThumbnailSize, height: evidenceThumbnailSize)
        .frame(minHeight: evidenceThumbnailSize)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1.2, dash: [6, 4]))
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Add evidence photo")
    }

    @ViewBuilder
    private func evidenceThumbnail(for photo: ReportMediaViewModel.EvidencePhoto) -> some View {
        ZStack(alignment: .topTrailing) {
            if let preview = viewModel.previewImage(for: photo) {
                preview
                    .resizable()
                    .scaledToFill()
                    .frame(width: evidenceThumbnailSize, height: evidenceThumbnailSize)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.black.opacity(0.08))
                    )
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
                    .frame(width: evidenceThumbnailSize, height: evidenceThumbnailSize)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.removeEvidencePhoto(photo)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(
                        Circle()
                            .fill(Color.black.opacity(0.7))
                    )
                    .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
            }
            .padding(6)
            .accessibilityLabel("Remove photo")
        }
        .frame(width: evidenceThumbnailSize, height: evidenceThumbnailSize)
    }

    private func loadEvidencePhoto(from item: PhotosPickerItem) async {
        enum EvidencePhotoError: Error {
            case invalidImage
            case tooLarge
        }

        do {
            guard viewModel.canAddMoreEvidencePhotos else {
                await MainActor.run {
                    viewModel.errorMessage = "You can attach up to \(ReportMediaViewModel.maxEvidencePhotoCount) photos."
                    evidencePickerItem = nil
                }
                return
            }

            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                throw EvidencePhotoError.invalidImage
            }

            guard let processed = process(image: image) else {
                throw EvidencePhotoError.invalidImage
            }

            guard processed.data.count <= ReportMediaViewModel.maxEvidencePhotoFileSizeBytes else {
                throw EvidencePhotoError.tooLarge
            }

            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.25)) {
                    viewModel.addEvidencePhoto(
                        data: processed.data,
                        contentType: processed.contentType,
                        fileExtension: processed.fileExtension
                    )
                }
                viewModel.errorMessage = nil
                evidencePickerItem = nil
            }
        } catch EvidencePhotoError.tooLarge {
            await MainActor.run {
                viewModel.errorMessage = "Photos must be under \(evidenceFileSizeDescription)."
                evidencePickerItem = nil
            }
        } catch {
            await MainActor.run {
                viewModel.errorMessage = "We couldn't add that photo. Try a different file."
                evidencePickerItem = nil
            }
        }
    }

    private func process(image: UIImage) -> (data: Data, contentType: String, fileExtension: String)? {
        if let jpegData = image.jpegData(compressionQuality: 0.82) {
            return (jpegData, "image/jpeg", "jpg")
        }

        if let pngData = image.pngData() {
            return (pngData, "image/png", "png")
        }

        return nil
    }
}

#if DEBUG
struct ReportMediaView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ReportMediaView(
                viewModel: ReportMediaViewModel(
                    media: .init(
                        ownerId: "owner",
                        title: "Demo Song",
                        format: .audio,
                        category: .song,
                        ratings: [:],
                        isShared: true,
                        isRadioEligible: false
                    ),
                    reportService: MockReportService(),
                    storageService: MockStorageService(),
                    currentUserProvider: { UserProfile.mock }
                )
            )
        }
    }
}
#endif
