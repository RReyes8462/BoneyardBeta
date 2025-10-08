import SwiftUI
import FirebaseFirestore

struct LeaderboardView: View {
    @EnvironmentObject var firebase: FirebaseManager
    @EnvironmentObject var auth: AuthManager

    @State private var leaderboard: [UserStats] = []
    @State private var showSidebar = false
    @State private var showLogoutConfirm = false
    @State private var showProfile = false

    // Cache to avoid refetching user info repeatedly
    @State private var userCache: [String: (name: String, photo: String?)] = [:]

    struct UserStats: Identifiable {
        var id: String { userID }
        let userID: String
        let displayName: String
        let photoURL: String?
        let totalClimbs: Int
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .leading) {
                if showSidebar {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture { withAnimation { showSidebar = false } }
                        .zIndex(1)
                }

                mainContent
                    .blur(radius: showSidebar ? 5 : 0)
                    .disabled(showSidebar)

                if showSidebar {
                    sidebar.transition(.move(edge: .leading)).zIndex(2)
                }
            }
            .animation(.easeInOut, value: showSidebar)
            .alert("Sign Out?", isPresented: $showLogoutConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Sign Out", role: .destructive) { auth.signOut() }
            }
        }
    }

    // MARK: - Main Content
    private var mainContent: some View {
        VStack(alignment: .leading) {
            HStack {
                Button {
                    withAnimation { showSidebar.toggle() }
                } label: {
                    Image(systemName: "line.horizontal.3")
                        .font(.system(size: 28))
                        .foregroundStyle(.primary)
                        .padding(.horizontal)
                }

                Text("🏆 Leaderboard")
                    .font(.title2.bold())

                Spacer()
            }
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .shadow(radius: 0.5)
            if leaderboard.isEmpty {
                Spacer()
                ProgressView("Loading...")
                Spacer()
            } else {
                List(leaderboard) { user in
                    HStack(spacing: 12) {
                        if let url = user.photoURL, let imageURL = URL(string: url) {
                            AsyncImage(url: imageURL) { img in
                                img.resizable().scaledToFill()
                            } placeholder: {
                                Circle().fill(Color.gray.opacity(0.3))
                            }
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                        } else {
                            Circle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 44, height: 44)
                                .overlay(Image(systemName: "person.fill").foregroundColor(.white))
                        }

                        VStack(alignment: .leading) {
                            Text(user.displayName)
                                .font(.headline)
                            Text("\(user.totalClimbs) total sends")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                        Text("#\(leaderboard.firstIndex(where: { $0.id == user.id })! + 1)")
                            .font(.title3.bold())
                            .foregroundColor(.blue)
                    }
                    .padding(.vertical, 6)
                }
                .listStyle(.plain)
            }
        }
        .onAppear(perform: startLiveLeaderboard)
    }

    // MARK: - Sidebar
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            NavigationLink(destination: ProfileView().environmentObject(auth), isActive: $showProfile) {
                EmptyView()
            }

            Text("Menu")
                .font(.headline)
                .padding(.top, 40)
                .padding(.horizontal)

            Button {
                showProfile = true
                withAnimation { showSidebar = false }
            } label: {
                Label("Edit Profile", systemImage: "person.crop.circle")
                    .padding(.horizontal)
            }

            Button(role: .destructive) {
                showLogoutConfirm = true
                withAnimation { showSidebar = false }
            } label: {
                Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
                    .padding(.horizontal)
            }

            Spacer()
        }
        .frame(width: 240)
        .frame(maxHeight: .infinity)
        .background(Color(.systemGray6))
        .edgesIgnoringSafeArea(.all)
    }

    // MARK: - Live Firestore Updates with Caching
    private func startLiveLeaderboard() {
        let db = firebase.db

        db.collectionGroup("logs").addSnapshotListener { snapshot, error in
            guard let logs = snapshot?.documents else { return }

            // 1️⃣ Aggregate total logs per user
            var counts: [String: Int] = [:]
            for log in logs {
                let userID = log["userID"] as? String ?? ""
                counts[userID, default: 0] += 1
            }

            // 2️⃣ Build leaderboard using cache + selective fetches
            var updated: [UserStats] = []
            let group = DispatchGroup()

            for (userID, count) in counts {
                if let cached = userCache[userID] {
                    updated.append(
                        UserStats(
                            userID: userID,
                            displayName: cached.name,
                            photoURL: cached.photo,
                            totalClimbs: count
                        )
                    )
                } else {
                    group.enter()
                    db.collection("users").document(userID).getDocument { doc, _ in
                        let data = doc?.data() ?? [:]
                        let name = data["displayName"] as? String ?? "Unknown"
                        let photo = data["photoURL"] as? String
                        userCache[userID] = (name, photo)
                        updated.append(UserStats(userID: userID, displayName: name, photoURL: photo, totalClimbs: count))
                        group.leave()
                    }
                }
            }

            group.notify(queue: .main) {
                leaderboard = updated.sorted { $0.totalClimbs > $1.totalClimbs }
            }
        }
    }
}
