import SwiftUI
import Firebase

@main
struct BoneyardBetaApp: App {
    @StateObject var firebase = FirebaseManager.shared
    @StateObject var auth = AuthManager()
    @State private var showProfileOverview = false

    @State private var showSidebar = false
    @State private var showLogoutConfirm = false
    @State private var showProfile = false

    init() { FirebaseApp.configure() }

    var body: some Scene {
        WindowGroup {
            if auth.user != nil {
                ZStack(alignment: .leading) {
                    TabView {
                        ContentView(
                            showSidebar: $showSidebar,
                            showLogoutConfirm: $showLogoutConfirm,
                            showProfile: $showProfile,
                            showProfileOverview: $showProfileOverview
                        )
                        .tabItem {
                            Label("Gym", systemImage: "figure.climbing")
                        }

                        LeaderboardView(
                            showSidebar: $showSidebar,
                            showLogoutConfirm: $showLogoutConfirm,
                            showProfile: $showProfile,
                            showProfileOverview: $showProfileOverview
                        )
                        .tabItem {
                            Label("Leaderboard", systemImage: "trophy")
                        }
                    }
                    .environmentObject(firebase)
                    .environmentObject(auth)

                    if showSidebar {
                        SidebarMenu(
                            showSidebar: $showSidebar,
                            showLogoutConfirm: $showLogoutConfirm,
                            showProfile: $showProfile,
                            showProfileOverview: $showProfileOverview
                        )
                        .environmentObject(firebase)
                        .environmentObject(auth)
                        .transition(.move(edge: .leading))
                        .zIndex(2)
                    }
                }
                .animation(.easeInOut, value: showSidebar)
                .alert("Sign Out?", isPresented: $showLogoutConfirm) {
                    Button("Cancel", role: .cancel) {}
                    Button("Sign Out", role: .destructive) {
                        auth.signOut()
                    }
                }
            } else {
                LoginView()
                    .environmentObject(firebase)
                    .environmentObject(auth)
            }
        }
    }
}
