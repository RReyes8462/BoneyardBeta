import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import PhotosUI
import AVKit

struct ClimbDetailSheet: View {
    @EnvironmentObject var firebase: FirebaseManager
    @EnvironmentObject var auth: AuthManager

    let climb: Climb
    let onDismiss: () -> Void

    @State private var comment: String = ""
    @State private var rating: Int = 0
    @State private var message: String?
    @State private var isSubmitting = false
    @State private var selectedVideo: PhotosPickerItem? = nil
    @State private var videoURL: URL?

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

                    Divider()

                    // MARK: - Log Input
                    Text("Log your climb:")
                        .font(.headline)
                    TextEditor(text: $comment)
                        .frame(height: 100)
                        .padding(6)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)

                    Text("Rate this climb:")
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

                    Divider()

                    // MARK: - Video Upload Section
                    Text("Upload Beta Video:")
                        .font(.headline)

                    if let videoURL = videoURL {
                        VideoPlayer(player: AVPlayer(url: videoURL))
                            .frame(height: 200)
                            .cornerRadius(10)
                    }

                    PhotosPicker(selection: $selectedVideo, matching: .videos, photoLibrary: .shared()) {
                        Label("Select Video", systemImage: "video.fill.badge.plus")
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .onChange(of: selectedVideo) { newItem in
                        handleVideoSelection(newItem)
                    }

                    if let message = message {
                        Text(message)
                            .foregroundColor(.gray)
                            .padding(.top, 6)
                    }

                    // MARK: - Submit Button
                    Button(action: submitLog) {
                        HStack {
                            if isSubmitting { ProgressView() }
                            Text("Submit Log").bold()
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(isSubmitting)
                }
                .padding()
            }
            .navigationTitle("Climb Details")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { onDismiss() }
                }
            }
            .onAppear { loadExistingLog() }
        }
    }

    // MARK: - Load User Log
    private func loadExistingLog() {
        firebase.fetchUserLog(for: climb.id ?? "") { data in
            if let data = data {
                if let existingComment = data["comment"] as? String {
                    comment = existingComment
                }
                if let existingRating = data["rating"] as? Double {
                    rating = Int(existingRating)
                }
                if let existingVideo = data["videoURL"] as? String,
                   let url = URL(string: existingVideo) {
                    videoURL = url
                }
            }
        }
    }

    // MARK: - Handle Video Selection
    private func handleVideoSelection(_ newItem: PhotosPickerItem?) {
        guard let newItem = newItem else { return }

        Task {
            do {
                // 1. Try to load as URL directly
                if let fileURL = try? await newItem.loadTransferable(type: URL.self) {
                    await convertAndUploadVideo(from: fileURL)
                    return
                }

                // 2. Fallback to loading as Data (if URL not available)
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString + ".mov")
                    try data.write(to: tempURL)
                    await convertAndUploadVideo(from: tempURL)
                    return
                }

                await MainActor.run {
                    message = "⚠️ Unable to load selected video. Try exporting locally first."
                }
            } catch {
                await MainActor.run {
                    message = "❌ Video selection failed: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Convert & Upload Video
    private func convertAndUploadVideo(from inputURL: URL) async {
        await MainActor.run {
            message = "⏳ Converting video..."
        }

        convertVideoToMP4(inputURL: inputURL) { outputURL in
            guard let mp4URL = outputURL else {
                message = "❌ Failed to convert video to MP4."
                return
            }

            DispatchQueue.main.async {
                self.videoURL = mp4URL
                self.message = "⏳ Uploading video..."

                firebase.uploadBetaVideo(for: climb.id ?? "", videoURL: mp4URL) { success, error in
                    if success {
                        message = "✅ Video uploaded successfully!"
                    } else {
                        message = "❌ Video upload failed: \(error ?? "Unknown error")"
                    }
                }
            }
        }
    }

    // MARK: - Video Conversion
    private func convertVideoToMP4(inputURL: URL, completion: @escaping (URL?) -> Void) {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mp4")

        let asset = AVAsset(url: inputURL)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality) else {
            completion(nil)
            return
        }

        export.outputURL = outputURL
        export.outputFileType = .mp4
        export.exportAsynchronously {
            DispatchQueue.main.async {
                completion(export.status == .completed ? outputURL : nil)
            }
        }
    }

    // MARK: - Submit Log
    private func submitLog() {
        guard let _ = auth.user else {
            message = "You must be logged in to log a climb."
            return
        }
        guard !comment.trimmingCharacters(in: .whitespaces).isEmpty else {
            message = "Please enter a comment."
            return
        }

        isSubmitting = true
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
}
