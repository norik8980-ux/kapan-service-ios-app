import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        TabView {
            BookingsListView()
                .tabItem {
                    Label(
                        session.user?.isAdmin == true ? "All jobs" : "My jobs",
                        systemImage: "wrench.and.screwdriver"
                    )
                }

            // Flag ON → show for plumber and admin (API open board allows both;
            // claim stays field-role gated server-side).
            if session.features.isOpenJobsClaimEnabled,
               session.user?.canBrowseOpenJobs == true {
                OpenJobsListView()
                    .tabItem { Label("Open jobs", systemImage: "tray") }
            }

            if session.user?.isAdmin == true {
                PlumbersListView()
                    .tabItem { Label("Plumbers", systemImage: "person.2") }
            }

            AccountView()
                .tabItem { Label("Account", systemImage: "person.circle") }
        }
        .tint(KapanTheme.orange)
        .task {
            await session.refreshFeatures()
        }
    }
}
