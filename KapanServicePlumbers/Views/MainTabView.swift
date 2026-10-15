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

            if session.user?.isAdmin == true {
                PlumbersListView()
                    .tabItem { Label("Plumbers", systemImage: "person.2") }
            }

            AccountView()
                .tabItem { Label("Account", systemImage: "person.circle") }
        }
        .tint(KapanTheme.orange)
    }
}
