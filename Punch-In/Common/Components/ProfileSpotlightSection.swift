import SwiftUI

struct ProfileSpotlightSection: View {
    let title: String
    let icon: String
    let spotlights: [ProfileSpotlight]
    let accentColor: Color

    var body: some View {
        Group {
            if spotlights.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: Theme.spacingMedium) {
                    Label(title, systemImage: icon)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(accentColor)

                    VStack(spacing: Theme.spacingMedium) {
                        ForEach(spotlights) { spotlight in
                            ProfileSpotlightRow(spotlight: spotlight, accentColor: accentColor)
                        }
                    }
                }
                .padding(Theme.spacingLarge)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Theme.cardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(accentColor.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 10)
            }
        }
    }
}

private struct ProfileSpotlightRow: View {
    let spotlight: ProfileSpotlight
    let accentColor: Color

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSmall) {
            Button {
                withAnimation(.easeInOut) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .center, spacing: Theme.spacingMedium) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(spotlight.title.isEmpty ? "Untitled" : spotlight.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)

                        HStack(spacing: 8) {
                            if let dateText = formattedDate {
                                pill(systemImage: "calendar", text: dateText)
                            }

                            if spotlight.location.trimmed.isEmpty == false {
                                pill(systemImage: "mappin.and.ellipse", text: spotlight.location)
                            }
                        }
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(accentColor)
                        .rotationEffect(isExpanded ? Angle(degrees: 180) : .zero)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: Theme.spacingSmall) {
                    if spotlight.detail.trimmed.isEmpty == false {
                        Text(spotlight.detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if let url = spotlight.callToActionURL {
                        Link(callToActionTitle, destination: url)
                            .buttonStyle(.borderedProminent)
                    } else if spotlight.callToActionTitle.trimmed.isEmpty == false {
                        pill(systemImage: "sparkles", text: spotlight.callToActionTitle)
                    }
                }
                .padding(.top, Theme.spacingSmall)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(Theme.spacingMedium)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(accentColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(accentColor.opacity(0.18), lineWidth: 1)
        )
    }

    private var callToActionTitle: String {
        let trimmed = spotlight.callToActionTitle.trimmed
        return trimmed.isEmpty ? "Learn more" : trimmed
    }

    private var formattedDate: String? {
        guard let date = spotlight.scheduledAt else { return nil }
        return date.formatted(.dateTime.month(.abbreviated).day().year().hour().minute())
    }

    @ViewBuilder
    private func pill(systemImage: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
            Text(text)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(accentColor.opacity(0.15))
        )
        .foregroundStyle(accentColor)
    }
}
