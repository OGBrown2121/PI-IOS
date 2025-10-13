import SwiftUI

struct EventsView: View {
    @State private var isShowingAlerts = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: Theme.spacingLarge) {
                heroSection

                upcomingSection
            }
            .padding(.horizontal, Theme.spacingLarge)
            .padding(.vertical, Theme.spacingLarge)
        }
        .background(Theme.appBackground)
        .navigationTitle("Events")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                AlertsButton { isShowingAlerts = true }
            }
            ToolbarItem(placement: .topBarTrailing) {
                ChatPillButton()
            }
        }
        .sheet(isPresented: $isShowingAlerts) {
            NavigationStack {
                AlertsView()
            }
        }
    }

    private var heroSection: some View {
        VStack(spacing: Theme.spacingMedium) {
            Text("Show up where the scene is happening.")
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)

            Text("Discover showcases, listening parties, and pop-ups hosted by the Punch-In community.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.spacingLarge)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Theme.elevatedCardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 12, y: 6)
    }

    private var upcomingSection: some View {
        VStack(spacing: Theme.spacingMedium) {
            Image(systemName: "sparkles")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Theme.primaryColor)

            Text("Event discovery is coming soon.")
                .font(.headline)

            Text("We’re curating drops now. Check back shortly to see a feed of live sessions and community gatherings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.spacingLarge)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

#if DEBUG
struct EventsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            EventsView()
        }
        .environmentObject(AppState())
        .environmentObject(AlertsCenter.preview())
    }
}
#endif
