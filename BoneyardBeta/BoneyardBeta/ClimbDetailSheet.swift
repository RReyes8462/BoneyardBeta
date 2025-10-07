import SwiftUI
import AVKit
import PhotosUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Identifiable wrapper for fullscreen videos
struct VideoItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ClimbDetailSheet: View {
    @EnvironmentObject var firebase: FirebaseManager
    @EnvironmentObject var auth: AuthManager

    let climb: Climb
    let onDismiss: () -> Void

    @State private var comment: String = ""
    @State private var rating: Int = 0
    @State private var isSubmitting = false
    @State private var message: String?
    @State private var selectedVideo: PhotosPickerItem?
    @State private var selectedVideoURL: URL?
    @State private var allVideos: [String] = []
    @State private var userLog: [String: Any]?
    @State private var fullscreenVideo: VideoItem?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // MARK: - Header
                    HStack {
                        VStack(alignment: .leading) {
                            Text(climb.name)
                                .font(.title2)
                                .bold()
                            Text(climb.grade)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(climb.color.capitalized)
                            .padding(8)
                            .background(climb.colorValue.opacity(0.2))
                            .cornerRadius(8)
                    }

                    Divider()

                    // MARK: - Stats
                    HStack {
                        VStack {
                            Text("\(climb.ascentCount)")
                                .font(.title)
                                .bold()
                            Text("Ascents")
                                .font(.caption)
                        }
                        Spacer()
                        VStack {
                            Text(String(format: "%.1f", climb.avgRating))
                                .font(.title)
                                .bold()
                            Text("Rating")
                                .font(.caption)
                        }
                    }
                    .padding(.vertical, 8)

                    Divider()

                    // MARK: - Log input
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Your Log")
                            .font(.headline)

                        TextEditor(text: $comment)
                            .frame(height: 100)
                            .padding(6)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)

                        Text("Your Rating")
                            .font(.headline)
                        HStack {
                            ForEach(1...5, id: \.self) { star in
                                Image(systemName: rating >= star ? "star.fill" : "star")
                                    .foregroundColor(.yellow)
                                    .font(.title2)
                                    .onTapGesture {
                                        rating = star
                                    }
                            }
                        }
                    }

                    Button(action: submitLog) {
                        HStack {
                            if isSubmitting { ProgressView() }
                            Text("Submit Log")
                                .bold()
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(isSubmitting)

                    if let message = message {
                        Text(message)
                            .foregroundColor(.gray)
                            .padding(.top, 6)
                    }

                    Divider()

                    // MARK: - Upload Section
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Upload a Beta Video")
                            .font(.headline)

                        PhotosPicker(selection: $selectedVideo, matching: .videos) {
                            Label("Choose Video", systemImage: "video.badge.plus")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.orange)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        .onChange(of: selectedVideo) { newItem in
                            Task {
                                if let newItem = newItem {
                                    await handleVideoSelection(newItem)
                                }
                            }
                        }

                        if let videoURL = selectedVideoURL {
                            Text("Selected: \(videoURL.lastPathComponent)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Button("Upload Video") {
                                uploadVideo(videoURL)
                            }
                            .padding(.top, 4)
                        }
                    }

                    Divider()

                    // MARK: - Display Beta Videos
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Beta Videos")
                            .font(.headline)
                        if allVideos.isEmpty {
                            Text("No beta videos yet.")
                                .foregroundColor(.secondary)
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    ForEach(allVideos, id: \.self) { videoURL in
                                        Button {
                                            fullscreenVideo = VideoItem(url: URL(string: videoURL)!)
                                        } label: {
                                            VideoThumbnailView(videoURL: URL(string: videoURL)!)
                                                .frame(width: 200, height: 140)
                                                .cornerRadius(10)
                                        }
                                    }
                                }
                                .padding(.vertical, 8)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Climb Details")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { onDismiss() }
                }
            }
        }
        .onAppear {
            loadUserLog()
            loadAllVideos()
        }
        .fullScreenCover(item: $fullscreenVideo) { item in
            FullscreenVideoPlayer(videoURL: item.url)
        }
    }

    // MARK: - Submit Log
    private func submitLog() {
        guard let user = auth.user else {
            message = "You must be logged in to log a climb."
            return
        }
        guard !comment.trimmingCharacters(in: .whitespaces).isEmpty else {
            message = "Please enter a comment before submitting."
            return
        }

        isSubmitting = true
        message = nil

        firebase.logClimbSend(
            climbID: climb.id ?? "",
            comment: comment,
            rating: Double(rating)
        ) { success, error in
            DispatchQueue.main.async {
                isSubmitting = false
                if success {
                    message = "✅ Climb logged!"
                } else {
                    message = "❌ Failed to log climb: \(error ?? "Unknown error")"
                }
            }
        }
    }

    // MARK: - Handle Video Selection
    private func handleVideoSelection(_ item: PhotosPickerItem) async {
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
                try data.write(to: tmpURL)
                selectedVideoURL = tmpURL
                print("🎥 Video saved temporarily at \(tmpURL)")
            }
        } catch {
            print("❌ Failed to load video:", error.localizedDescription)
        }
    }

    // MARK: - Upload Video
    private func uploadVideo(_ url: URL) {
        guard let climbID = climb.id else { return }
        firebase.uploadBetaVideo(for: climbID, videoURL: url) { success, error in
            if success {
                message = "✅ Video uploaded successfully!"
                selectedVideo = nil
                selectedVideoURL = nil
                loadAllVideos()
            } else {
                message = "❌ Upload failed: \(error ?? "Unknown error")"
            }
        }
    }

    // MARK: - Load User Log
    private func loadUserLog() {
        firebase.fetchUserLog(for: climb.id ?? "") { data in
            DispatchQueue.main.async {
                self.userLog = data
                if let data = data {
                    self.comment = data["comment"] as? String ?? ""
                    self.rating = Int(data["rating"] as? Double ?? 0)
                }
            }
        }
    }

    // MARK: - Load All Videos
    private func loadAllVideos() {
        guard let climbID = climb.id else { return }
        firebase.db.collection("climbs").document(climbID)
            .collection("logs")
            .getDocuments { snapshot, error in
                guard let docs = snapshot?.documents else { return }
                var urls: [String] = []
                for doc in docs {
                    if let userVideos = doc.data()["betaVideos"] as? [String] {
                        urls.append(contentsOf: userVideos)
                    }
                }
                DispatchQueue.main.async {
                    self.allVideos = urls
                }
            }
    }
}

// MARK: - Inline Video Preview
struct VideoThumbnailView: View {
    let videoURL: URL
    var body: some View {
        ZStack {
            VideoPlayer(player: AVPlayer(url: videoURL))
                .onAppear { AVPlayer(url: videoURL).pause() }
            Image(systemName: "play.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 35, height: 35) // 🎯 smaller and cleaner
                .foregroundColor(.white)
                .shadow(radius: 4)
        }
    }
}

// MARK: - Fullscreen Player
struct FullscreenVideoPlayer: View {
    let videoURL: URL
    @Environment(\.dismiss) var dismiss
    @State private var player: AVPlayer? = nil

    var body: some View {
        NavigationView {
            if let player = player {
                VideoPlayer(player: player)
                    .onAppear { player.play() }
                    .onDisappear {
                        player.pause()
                        player.replaceCurrentItem(with: nil) // 🧹 stop playback when dismissed
                    }
                    .edgesIgnoringSafeArea(.all)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") {
                                player.pause()
                                player.replaceCurrentItem(with: nil)
                                dismiss()
                            }
                            .bold()
                        }
                    }
            } else {
                ProgressView("Loading video...")
                    .onAppear {
                        player = AVPlayer(url: videoURL)
                    }
            }
        }
    }
}
