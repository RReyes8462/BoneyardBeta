import Foundation
import FirebaseAuth
import FirebaseFirestore
import Combine

@MainActor
class AuthManager: ObservableObject {
    @Published var user: User?
    @Published var isAdmin: Bool = false
    @Published var isLoggedIn: Bool = false

    private let db = Firestore.firestore()
    private var userListener: ListenerRegistration?

    init() {
        // pick up current user on launch
        self.user = Auth.auth().currentUser
        self.isLoggedIn = (self.user != nil)
        if let uid = user?.uid {
            attachUserDocListener(uid: uid)
        }

        // keep in sync with auth changes
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            self.user = user
            self.isLoggedIn = (user != nil)
            self.isAdmin = false
            self.userListener?.remove()
            if let uid = user?.uid {
                self.attachUserDocListener(uid: uid)
            }
        }
    }

    private func attachUserDocListener(uid: String) {
        // live updates from /users/{uid}
        userListener = db.collection("users").document(uid).addSnapshotListener { [weak self] snap, err in
            guard let self else { return }
            if let err = err {
                print("⚠️ user doc listener error:", err.localizedDescription)
                self.isAdmin = false
                return
            }
            let data = snap?.data() ?? [:]
            let admin = data["isAdmin"] as? Bool ?? false
            self.isAdmin = admin
            // Debug prints to verify:
            print("👤 email:", Auth.auth().currentUser?.email ?? "nil",
                  "| uid:", uid,
                  "| isAdmin:", admin)
        }
    }

    // MARK: - Auth APIs
    func signIn(email: String, password: String) async throws {
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        self.user = result.user
        self.isLoggedIn = true
        // listener will attach via stateDidChange
    }

    func register(email: String, password: String) async throws {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        self.user = result.user
        self.isLoggedIn = true

        // create default user doc if missing
        try await db.collection("users").document(result.user.uid).setData([
            "email": email,
            "isAdmin": false
        ], merge: true)
        // listener will attach via stateDidChange
    }

    func signOut() {
        do {
            try Auth.auth().signOut()
        } catch {
            print("❌ signOut:", error.localizedDescription)
        }
        self.userListener?.remove()
        self.userListener = nil
        self.user = nil
        self.isLoggedIn = false
        self.isAdmin = false
    }
}
