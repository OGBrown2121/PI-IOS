import SwiftUI

struct ProfileSummaryCard: View {
    let profile: UserProfile

    private var labels: [String] { profile.accountType.requiredFieldLabels }
    private var displayName: String { profile.displayName.isEmpty ? profile.username : profile.displayName }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMedium) {
            header

            if !profile.profileDetails.bio.isEmpty {
                Text(profile.profileDetails.bio)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if shouldShowHighlights {
                Divider()
                    .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: Theme.spacingMedium) {
                    if let firstLabel = labels.first, !profile.profileDetails.fieldOne.isEmpty {
                        summaryTag(title: firstLabel, value: profile.profileDetails.fieldOne)
                    }
                    if labels.count > 1 && !profile.profileDetails.fieldTwo.isEmpty {
                        summaryTag(title: labels[1], value: profile.profileDetails.fieldTwo)
                    }
                }
            }
        }
        .padding(Theme.spacingLarge)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Theme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Theme.primaryColor.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 8)
    }

    private var header: some View {
        HStack(spacing: Theme.spacingMedium) {
            avatar

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.title3.weight(.semibold))
                Text("@\(profile.username)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(profile.accountType.title.uppercased())
                .font(.caption.weight(.heavy))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .foregroundStyle(.white)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Theme.primaryGradientStart.opacity(0.95),
                                    Theme.primaryGradientEnd.opacity(0.9)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
                .shadow(color: Theme.primaryGradientEnd.opacity(0.25), radius: 6, y: 2)
        }
    }

    @ViewBuilder
    private var avatar: some View {
        Group {
            if let imageURL = profile.profileImageURL {
                AsyncImage(url: imageURL) { phase in
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
        .frame(width: 60, height: 60)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Theme.primaryColor.opacity(0.35), lineWidth: 2)
        )
        .shadow(color: Theme.primaryColor.opacity(0.15), radius: 8, y: 4)
    }

    private var placeholderAvatar: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [Theme.primaryGradientStart, Theme.primaryGradientEnd],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            Text(initials)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
        }
    }

    private var initials: String {
        let components = displayName.split(separator: " ")
        if let first = components.first, let last = components.dropFirst().first {
            return String(first.first!).uppercased() + String(last.first!).uppercased()
        } else if let first = components.first {
            return String(first.prefix(2)).uppercased()
        }
        return String(displayName.prefix(2)).uppercased()
    }

    private var shouldShowHighlights: Bool {
        (labels.first != nil && !profile.profileDetails.fieldOne.isEmpty) ||
        (labels.count > 1 && !profile.profileDetails.fieldTwo.isEmpty)
    }

    private func summaryTag(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(.white)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Theme.primaryGradientStart.opacity(0.85),
                                    Theme.primaryGradientEnd.opacity(0.85)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
        }
    }
}

#Preview("Profile Summary") {
    ProfileSummaryCard(profile: .mock)
        .padding()
        .background(Theme.appBackground)
}
