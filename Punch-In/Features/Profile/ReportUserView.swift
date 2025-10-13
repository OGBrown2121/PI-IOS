import SwiftUI

@MainActor
final class ReportUserViewModel: ObservableObject {
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

    private let reportService: any ReportService
    private let currentUserProvider: () -> UserProfile?
    let reportedUser: UserProfile

    init(
        reportedUser: UserProfile,
        reportService: any ReportService,
        currentUserProvider: @escaping () -> UserProfile?
    ) {
        self.reportedUser = reportedUser
        self.reportService = reportService
        self.currentUserProvider = currentUserProvider
    }

    var reportedDisplayName: String {
        let displayName = reportedUser.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if displayName.isEmpty {
            return "@\(reportedUser.username)"
        }
        return displayName
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
        guard let reporter = currentUserProvider(), reporter.id != reportedUser.id else { return false }
        return true
    }

    func submit() async {
        guard isSubmitting == false else { return }

        errorMessage = nil

        guard let reporter = currentUserProvider(), reporter.id != reportedUser.id else {
            errorMessage = "You need to be signed in to report a user."
            return
        }

        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        if requiresDetails && trimmedDetails.count < 10 {
            errorMessage = "Share a few more details so we can follow up."
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        let report = UserReport(
            reportedUserId: reportedUser.id,
            reporterUserId: reporter.id,
            reason: selectedReason,
            details: trimmedDetails
        )

        do {
            try await reportService.submitReport(report)
            submissionSucceeded = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ReportUserView: View {
    @ObservedObject var viewModel: ReportUserViewModel
    var onSubmitted: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isDetailsFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(viewModel.reportedDisplayName)
                            .font(.headline)
                        Text("@\(viewModel.reportedUser.username)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("We’ll review this report and take action if it violates our community guidelines.")
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
                                Text("Include relevant messages, links, or context. Do not share private info.")
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
            .navigationTitle("Report \(viewModel.reportedDisplayName)")
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
                            }
                            if viewModel.submissionSucceeded {
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
        }
    }
}

#if DEBUG
struct ReportUserView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ReportUserView(
                viewModel: ReportUserViewModel(
                    reportedUser: .mock,
                    reportService: MockReportService(),
                    currentUserProvider: { .mockEngineer }
                )
            )
        }
    }
}
#endif
