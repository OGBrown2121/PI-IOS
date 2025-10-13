import SwiftUI

struct ProfileMediaUploadBanner: View {
    @EnvironmentObject private var uploadManager: ProfileMediaUploadManager

    var body: some View {
        if let state = uploadManager.activeUpload {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    icon(for: state.format)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)

                        Text(statusText(for: state))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()
                }

                progressView(for: state)
                    .tint(Theme.primaryColor)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .shadow(color: Color.black.opacity(0.15), radius: 10, y: 4)
            .padding(.horizontal, 16)
        }
    }

    private func icon(for format: ProfileMediaFormat) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Theme.cardBackground)
            .frame(width: 44, height: 44)
            .overlay {
                Image(systemName: format.iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.primaryColor)
            }
    }

    @ViewBuilder
    private func progressView(for state: ProfileMediaUploadManager.UploadState) -> some View {
        switch state.phase {
        case .failed:
            ProgressView(value: 1)
                .progressViewStyle(.linear)
                .tint(Color.red)
        case .success:
            ProgressView(value: 1)
                .progressViewStyle(.linear)
        default:
            if let progress = state.progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
            }
        }
    }

    private func statusText(for state: ProfileMediaUploadManager.UploadState) -> String {
        switch state.phase {
        case .preparing:
            return "Preparing upload…"
        case .uploading:
            if let progress = state.progress {
                let percent = Int(round(progress * 100))
                return "Uploading… \(percent)%"
            }
            return "Uploading…"
        case .processing:
            return "Finalizing upload…"
        case .success:
            return "Upload complete"
        case let .failed(message):
            return message
        }
    }
}
