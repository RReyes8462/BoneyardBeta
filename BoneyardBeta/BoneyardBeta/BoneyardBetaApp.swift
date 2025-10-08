import SwiftUI
import Firebase

@main
struct BoneyardBetaApp: App {
    @StateObject var firebase = FirebaseManager.shared
    @StateObject var auth = AuthManager()

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            if auth.user != nil {
                TabView {
                    ContentView()
                        .tabItem {
                            Label("Gym", systemImage: "figure.climbing")
                        }

                    LeaderboardView()
                        .tabItem {
                            Label("Leaderboard", systemImage: "trophy")
                        }
                }
                .environmentObject(firebase)
                .environmentObject(auth)
            } else {
                LoginView()
                    .environmentObject(firebase)
                    .environmentObject(auth)
            }
        }
    }
}
