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
                ContentView()
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
