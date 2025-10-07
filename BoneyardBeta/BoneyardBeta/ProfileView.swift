import SwiftUI
import FirebaseAuth
import FirebaseStorage
import FirebaseFirestore
import PhotosUI

struct ProfileView: View {
    @EnvironmentObject var auth: AuthManager

    @State private var displayName = ""
    @State private var photoURL: URL?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showSaveToast = false
    @State private var isSaving = false

    private let db = Firestore.firestore()

    var body: some View {
        Form {
            Section(header: Text("Profile Picture")) {
                HStack {
                    Spacer()
                    if let photoURL = photoURL {
                        AsyncImage(url: photoURL) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            ProgressView()
                        }
                        .frame(width: 100, height: 100)
                        .clipShape(Circle())
                        .shadow(radius: 4)
                    } else {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 100, height: 100)
                            .overlay(Image(systemName: "person.fill").font(.largeTitle))
                    }
                    Spacer()
                }

                PhotosPicker("Change Photo", selection: $selectedPhoto, matching: .images)
            }

            Section(header: Text("Display Name")) {
                TextField("Your name", text: $displayName)
                    .textInputAutocapitalization(.words)
                    .disableAutocorrection(true)
            }

            Section {
                Button {
                    Task { await saveProfile() }
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("Save Changes")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .navigationTitle("Edit Profile")
        .onAppear { loadUserProfile() }
        .onChange(of: selectedPhoto) { _ in
            Task { await uploadPhoto() }
        }
        .overlay(alignment: .bottom) {
            if showSaveToast {
                Text("✅ Profile Saved!")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.green.opacity(0.9))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .padding(.bottom, 40)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - Load Existing User Data
    private func loadUserProfile() {
        guard let user = auth.user else { return }
        displayName = user.displayName ?? ""
        photoURL = user.photoURL
    }

    // MARK: - Upload Profile Picture (new secure path)
    private func uploadPhoto() async {
        guard let data = try? await selectedPhoto?.loadTransferable(type: Data.self),
              let user = auth.user else { return }

        // Each user gets their own folder
        let ref = Storage.storage().reference().child("profile_pics/\(user.uid)/avatar.jpg")

        do {
            _ = try await ref.putDataAsync(data)
            let url = try await ref.downloadURL()
            photoURL = url
        } catch {
            print("❌ Error uploading photo:", error.localizedDescription)
        }
    }

    // MARK: - Save Profile Changes
    private func saveProfile() async {
        guard let user = auth.user else { return }
        isSaving = true

        let changeRequest = user.createProfileChangeRequest()
        changeRequest.displayName = displayName
        changeRequest.photoURL = photoURL

        do {
            try await changeRequest.commitChanges()
            try await db.collection("users").document(user.uid).setData([
                "displayName": displayName,
                "photoURL": photoURL?.absoluteString ?? "",
                "email": user.email ?? ""
            ], merge: true)
            withAnimation {
                showSaveToast = true
                isSaving = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation { showSaveToast = false }
            }
        } catch {
            print("❌ Error saving profile:", error.localizedDescription)
            isSaving = false
        }
    }
}
