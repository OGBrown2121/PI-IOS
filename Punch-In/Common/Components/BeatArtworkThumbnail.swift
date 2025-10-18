import SwiftUI

struct BeatArtworkThumbnail: View {
    let url: URL?
    var cornerRadius: CGFloat
    var placeholderSystemImage: String

    init(url: URL?, cornerRadius: CGFloat = 14, placeholderSystemImage: String = "waveform") {
        self.url = url
        self.cornerRadius = cornerRadius
        self.placeholderSystemImage = placeholderSystemImage
    }

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholder
                    case .empty:
                        ProgressView()
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Theme.primaryColor.opacity(0.1), lineWidth: 1)
        )
    }

    private var placeholder: some View {
        ZStack {
            Theme.highlightedCardBackground
            Image(systemName: placeholderSystemImage)
                .font(.title3)
                .foregroundStyle(Theme.primaryColor)
        }
    }
}

