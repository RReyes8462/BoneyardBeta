import SwiftUI
import Firebase

struct SidebarMenu: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var firebase: FirebaseManager

    @Binding var showSidebar: Bool
    @Binding var showLogoutConfirm: Bool
    @Binding var showProfile: Bool
    @Binding var showProfileOverview: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Hidden navigation links for both pages
            NavigationLink(
                destination: ProfileView()
                    .environmentObject(auth)
                    .environmentObject(firebase),
                isActive: $showProfile
            ) { EmptyView() }

            NavigationLink(
                destination: UserProfileOverview()
                    .environmentObject(auth)
                    .environmentObject(firebase),
                isActive: $showProfileOverview
            ) { EmptyView() }

            // ---------------------------
            // MARK: - Menu Header
            // ---------------------------
            Text("Menu")
                .font(.headline)
                .padding(.top, 40)
                .padding(.horizontal)

            // ---------------------------
            // MARK: - View Profile
            // ---------------------------
            Button {
                showProfileOverview = true
                withAnimation { showSidebar = false }
            } label: {
                Label("View Profile", systemImage: "person.fill.viewfinder")
                    .padding(.horizontal)
            }

            // ---------------------------
            // MARK: - Edit Profile
            // ---------------------------
            Button {
                showProfile = true
                withAnimation { showSidebar = false }
            } label: {
                Label("Edit Profile", systemImage: "pencil.circle")
                    .padding(.horizontal)
            }

            // ---------------------------
            // MARK: - Logout
            // ---------------------------
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
}
