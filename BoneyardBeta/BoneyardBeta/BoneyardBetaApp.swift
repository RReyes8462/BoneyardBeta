import SwiftUI
import Firebase

@main
struct BoneyardBetaApp: App {
    @StateObject var auth = AuthManager()
    @StateObject var firebase = FirebaseManager.shared

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            if auth.user != nil {
                ContentView()
                    .environmentObject(auth)
                    .environmentObject(firebase)
            } else {
                LoginView()
                    .environmentObject(auth)
                    .environmentObject(firebase)
            }
        }
    }
}
