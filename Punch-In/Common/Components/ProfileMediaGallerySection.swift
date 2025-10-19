import SwiftUI

struct ProfileMediaGallerySection: View {
    @Environment(\.di) private var di
    @EnvironmentObject private var appState: AppState

    let title: String
    let icon: String
    let accentColor: Color
    let items: [ProfileMediaItem]
    let capabilities: ProfileMediaCapabilities?

    @State private var selectedMedia: ProfileMediaItem?
    @State private var filter: Filter = .highlights
    @State private var currentHeroIndex: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMedium) {
            header

            if heroItems.isEmpty == false {
                ProfileMediaHeroCarousel(
                    items: heroItems,
                    accentColor: accentColor,
                    selection: $currentHeroIndex,
                    onSelect: { selectedMedia = $0 }
                )
                .frame(height: 260)
                .transition(.opacity)
            }

            if availableFilters.count > 1 {
                Picker("Media filter", selection: $filter) {
                    ForEach(availableFilters, id: \.self) { value in
                        Text(value.title).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: filter) { _ in
                    currentHeroIndex = 0
                }
            }

            if filteredItems.isEmpty {
                Text(filter.emptyStateText(capabilities: capabilities))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, Theme.spacingSmall)
            } else {
                LazyVGrid(columns: gridColumns, spacing: 16) {
                    ForEach(filteredItems) { item in
                        Button {
                            selectedMedia = item
                        } label: {
                            ProfileMediaTile(item: item, accentColor: accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, Theme.spacingSmall)
                .animation(.spring(response: 0.35, dampingFraction: 0.9), value: filteredItems.map(\.id))
            }
        }
        .sheet(item: $selectedMedia) { media in
            NavigationStack {
                ProfileMediaDetailView(
                    media: media,
                    firestoreService: di.firestoreService,
                    storageService: di.storageService,
                    reportService: di.reportService,
                    currentUserProvider: { appState.currentUser }
                )
            }
        }
        .onChange(of: items) { newItems in
            if Filter.available(for: newItems).contains(filter) == false {
                filter = .highlights
            }
            if currentHeroIndex >= heroItems.count {
                currentHeroIndex = max(heroItems.count - 1, 0)
            }
        }
    }
}

extension ProfileMediaGallerySection {
    enum Filter: Hashable {
        case highlights
        case photos
        case videos
        case all
    }
}

private extension ProfileMediaGallerySection {
    var header: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.headline.weight(.bold))
                .foregroundStyle(accentColor)
            Text(title)
                .font(.headline.weight(.semibold))
            Spacer()
            if totalVisualCount > 0 {
                Text("\(totalVisualCount) visual\(totalVisualCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var availableFilters: [Filter] {
        Filter.available(for: items)
    }

    var heroItems: [ProfileMediaItem] {
        let visualHighlights = highlightItems.filter { $0.format.isVisual }
        if visualHighlights.isEmpty {
            let visualFallback = items.filter { $0.format.isVisual }.sorted(by: recencySort)
            return Array(visualFallback.prefix(5))
        }
        return Array(visualHighlights.prefix(5))
    }

    var highlightItems: [ProfileMediaItem] {
        let pinnedVisuals = items.filter { $0.isPinned && $0.format.isVisual }.sorted(by: pinSort)
        if pinnedVisuals.isEmpty {
            let recents = items
                .filter { $0.format.isVisual }
                .sorted(by: recencySort)
            if recents.isEmpty {
                return Array(items.sorted(by: pinSort).prefix(6))
            }
            return Array(recents.prefix(6))
        }
        return pinnedVisuals
    }

    var filteredItems: [ProfileMediaItem] {
        switch filter {
        case .highlights:
            return highlightItems
        case .photos:
            return items.filter { $0.format.isPhotoLike }.sorted(by: pinSort)
        case .videos:
            return items.filter { $0.format == .video }.sorted(by: pinSort)
        case .all:
            return items.sorted(by: pinSort)
        }
    }

    var gridColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 160), spacing: 16, alignment: .top)
        ]
    }

    var totalVisualCount: Int {
        items.filter { $0.format.isVisual }.count
    }

    func pinSort(lhs: ProfileMediaItem, rhs: ProfileMediaItem) -> Bool {
        switch (lhs.pinnedRank, rhs.pinnedRank) {
        case let (l?, r?):
            if l == r {
                return lhs.updatedAt > rhs.updatedAt
            }
            return l < r
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    func recencySort(lhs: ProfileMediaItem, rhs: ProfileMediaItem) -> Bool {
        lhs.updatedAt > rhs.updatedAt
    }
}

private extension ProfileMediaGallerySection.Filter {
    static func available(for items: [ProfileMediaItem]) -> [ProfileMediaGallerySection.Filter] {
        var filters: [ProfileMediaGallerySection.Filter] = [.highlights]

        if items.contains(where: { $0.format.isPhotoLike }) {
            filters.append(.photos)
        }
        if items.contains(where: { $0.format == .video }) {
            filters.append(.videos)
        }
        if items.isEmpty == false {
            filters.append(.all)
        }

        return filters
    }

    var title: String {
        switch self {
        case .highlights:
            return "Highlights"
        case .photos:
            return "Photos"
        case .videos:
            return "Videos"
        case .all:
            return "All Media"
        }
    }

    func emptyStateText(capabilities: ProfileMediaCapabilities?) -> String {
        switch self {
        case .highlights:
            return capabilities?.pinnedEmptyState ?? "Add media from your settings to showcase visuals here."
        case .photos:
            return "No photo galleries uploaded yet."
        case .videos:
            return "No videos pinned yet. Upload a clip to spotlight your work."
        case .all:
            return "No media uploads yet. Add photos or videos to start building your gallery."
        }
    }
}

private struct ProfileMediaHeroCarousel: View {
    let items: [ProfileMediaItem]
    let accentColor: Color
    @Binding var selection: Int
    let onSelect: (ProfileMediaItem) -> Void

    var body: some View {
        TabView(selection: $selection) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                Button {
                    onSelect(item)
                } label: {
                    ProfileMediaHeroCard(item: item, accentColor: accentColor)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: items.count > 1 ? .automatic : .never))
        .animation(.easeInOut(duration: 0.25), value: selection)
    }
}

private struct ProfileMediaHeroCard: View {
    let item: ProfileMediaItem
    let accentColor: Color

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ProfileMediaVisual(item: item, accentColor: accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.6),
                            Color.black.opacity(0.2),
                            Color.black.opacity(0.05)
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title.isEmpty ? item.category.displayTitle : item.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if item.caption.isEmpty == false {
                    Text(item.caption)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(2)
                }

                Label(item.category.displayTitle, systemImage: item.format.iconName)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .foregroundStyle(.white)
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
        .shadow(color: accentColor.opacity(0.22), radius: 18, x: 0, y: 14)
    }
}

private struct ProfileMediaTile: View {
    let item: ProfileMediaItem
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProfileMediaVisual(item: item, accentColor: accentColor)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if item.isPinned {
                        Image(systemName: "star.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(radius: 6)
                            .padding(12)
                    }
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title.isEmpty ? item.category.displayTitle : item.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)

                if item.caption.isEmpty == false {
                    Text(item.caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Label(item.category.displayTitle, systemImage: item.format.iconName)
                .font(.caption.weight(.bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(accentColor.opacity(0.12), in: Capsule())
                .foregroundStyle(accentColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.cardBackground)
        )
        .shadow(color: Color.black.opacity(0.07), radius: 12, x: 0, y: 6)
    }
}

private struct ProfileMediaVisual: View {
    let item: ProfileMediaItem
    let accentColor: Color

    var body: some View {
        ZStack {
            switch item.format {
            case .photo, .gallery:
                if let url = item.mediaURL ?? item.thumbnailURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()
                        case .failure, .empty:
                            placeholder
                        @unknown default:
                            placeholder
                        }
                    }
                } else {
                    placeholder
                }
            case .video:
                if let url = item.thumbnailURL ?? item.coverArtURL ?? item.mediaURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()
                                .overlay(videoOverlay)
                        case .failure, .empty:
                            placeholder.overlay(videoOverlay)
                        @unknown default:
                            placeholder.overlay(videoOverlay)
                        }
                    }
                } else {
                    placeholder.overlay(videoOverlay)
                }
            case .audio:
                placeholder
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(accentColor.opacity(0.18))
            Image(systemName: item.format.iconName)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(accentColor)
        }
    }

    private var videoOverlay: some View {
        Image(systemName: "play.fill")
            .font(.system(size: 36, weight: .bold))
            .foregroundStyle(.white)
            .shadow(radius: 8)
    }
}

private extension ProfileMediaFormat {
    var isVisual: Bool {
        switch self {
        case .video, .photo, .gallery:
            return true
        case .audio:
            return false
        }
    }

    var isPhotoLike: Bool {
        switch self {
        case .photo, .gallery:
            return true
        case .audio, .video:
            return false
        }
    }
}
