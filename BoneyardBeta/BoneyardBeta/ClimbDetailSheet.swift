import SwiftUI
import Firebase
import AVKit
import PhotosUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

// MARK: - Video Model
struct VideoData: Identifiable {
    var id: String
    var url: String
    var uploaderID: String
    var uploaderEmail: String
    var likes: [String]
    var comments: [[String: Any]]
}

// MARK: - Main Climb Detail Sheet
struct ClimbDetailSheet: View {
    var climb: Climb
    var onClose: () -> Void
    @State private var gradeVotes: [GradeVote] = []
    @State private var userVote: String? = nil

    @EnvironmentObject var firebase: FirebaseManager
    @EnvironmentObject var auth: AuthManager

    @State private var fullscreenVideo: VideoItem?
    @State private var allVideos: [VideoData] = []
    @State private var climbLogs: [ClimbLog] = []

    // Log form state
    @State private var userLog: ClimbLog? = nil
    @State private var hasLogged = false
    @State private var rating: Int = 0
    @State private var commentText: String = ""

    // Video comment text per video
    @State private var commentTexts: [String: String] = [:] // ✅ separate comments per video

    // Video upload state
    @State private var showVideoPicker = false
    @State private var selectedVideoURL: URL?
    @State private var isUploading = false
    @State private var uploadProgress: Double = 0.0

    // Local stats
    @State private var localAvgRating: Double = 0.0
    @State private var localAscentCount: Int = 0

    // Toasts
    @State private var showSentToast = false
    @State private var showBetaToast = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // MARK: Climb Info
                    Text(climb.name)
                        .font(.title.bold())
                    Text(climb.grade)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    HStack {
                        Text("Ascents: \(localAscentCount)")
                        Spacer()
                        Text("Avg Rating: \(String(format: "%.1f", localAvgRating)) ⭐️")
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .animation(.easeInOut(duration: 0.3), value: localAscentCount)
                    .animation(.easeInOut(duration: 0.3), value: localAvgRating)

                    Divider()

                    // MARK: Log or Edit Ascent
                    VStack(alignment: .leading, spacing: 8) {
                        Text(hasLogged ? "Edit Your Ascent Log" : "Log an Ascent")
                            .font(.headline)

                        if hasLogged {
                            Text("You’ve already logged this climb. You can update your rating or comment below.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            ForEach(1...5, id: \.self) { star in
                                Image(systemName: star <= rating ? "star.fill" : "star")
                                    .foregroundColor(.yellow)
                                    .onTapGesture { rating = star }
                            }
                        }

                        TextField("Write a comment...", text: $commentText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())

                        Button(action: {
                            if let user = auth.user, rating > 0 {
                                firebase.logClimbAscent(
                                    for: climb,
                                    rating: rating,
                                    comment: commentText,
                                    user: user,
                                    completion: {

                                        // Optimistic local update
                                        if let i = climbLogs.firstIndex(where: { $0.userID == user.uid }) {
                                            climbLogs[i].rating = rating
                                            climbLogs[i].comment = commentText
                                            climbLogs[i].timestamp = Date()
                                        } else {
                                            climbLogs.insert(ClimbLog(
                                                id: user.uid,
                                                userID: user.uid,
                                                email: user.email ?? "unknown",
                                                comment: commentText,
                                                rating: rating,
                                                timestamp: Date()
                                            ), at: 0)
                                        }

                                        let ratings = climbLogs.map { $0.rating }
                                        let ascentCount = ratings.count
                                        let avgRating = Double(ratings.reduce(0, +)) / Double(ascentCount)
                                        localAvgRating = avgRating
                                        localAscentCount = ascentCount

                                        // Sync to Firestore
                                        if let climbID = climb.id {
                                            firebase.db.collection("climbs").document(climbID).updateData([
                                                "avgRating": avgRating,
                                                "ascentCount": ascentCount
                                            ])
                                        }
                                    }
                                )

                                hasLogged = true
                                showSentToast = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    withAnimation { showSentToast = false }
                                }
                                hideKeyboard()
                            }
                        }) {
                            Label(hasLogged ? "Update Log" : "Submit Log",
                                  systemImage: hasLogged ? "square.and.pencil" : "plus.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(rating == 0)
                    }

                    Divider()

                    // MARK: Recent Logs
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent Logs")
                            .font(.headline)
                        if climbLogs.isEmpty {
                            Text("No logs yet. Be the first to send it!")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(climbLogs.prefix(5)) { log in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(log.email)
                                            .font(.subheadline.bold())
                                        Spacer()
                                        Text("\(log.rating)⭐")
                                            .foregroundColor(.yellow)
                                    }
                                    Text(log.comment)
                                        .font(.footnote)
                                    Text(log.timestamp, style: .date)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 4)
                                Divider()
                            }
                        }
                    }
                    Divider()

                    // MARK: Grade Consensus Poll
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Community Grade Consensus")
                            .font(.headline)
                        let gradeOptions = climb.grade.contains("Pink Tag (V8+)") ? ["V8", "V9", "V10+"] :
                                           climb.grade.contains("Purple Tag (V6–8)") ? ["V6", "V7", "V8"] :
                                           climb.grade.contains("Green Tag (V4–6)") ? ["V4", "V5", "V6"] :
                                           climb.grade.contains("Yellow Tag (V2–4)") ? ["V2", "V3", "V4"] :
                                           climb.grade.contains("Red Tag (V0–V2)") ? ["V0", "V1", "V2"] :
                                           climb.grade.contains("Blue Tag (VB–V0)") ? ["V0", "V1"] :
                                           climb.grade.contains("White Tag (Ungraded)") ? ["V0", "V1"] :
                                           ["Ungraded"]

                        if gradeVotes.isEmpty {
                            Text("No votes yet. Cast the first one!")
                                .foregroundColor(.secondary)
                        }

                        ForEach(gradeOptions, id: \.self) { option in
                            HStack {
                                Button {
                                    if let user = auth.user {
                                        firebase.submitGradeVote(for: climb.id ?? "", vote: option, user: user) {
                                            loadGradeVotes()
                                        }
                                    }
                                } label: {
                                    Text(option)
                                        .font(.headline)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(userVote == option ? Color.blue : Color.gray.opacity(0.2))
                                        )
                                        .foregroundColor(userVote == option ? .white : .primary)
                                }

                                // progress bar for this option
                                GeometryReader { geo in
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.blue.opacity(0.3))
                                        .frame(width: geo.size.width * CGFloat(votePercent(option)), height: 8)
                                        .animation(.easeInOut(duration: 0.3), value: gradeVotes)
                                }
                                .frame(height: 8)
                                Text("\(Int(votePercent(option) * 100))%")
                                    .font(.caption)
                                    .frame(width: 40, alignment: .trailing)
                            }
                        }
                    }

                    Divider()

                    // MARK: Beta Videos
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Beta Videos")
                            .font(.headline)

                        if allVideos.isEmpty {
                            Text("No beta videos yet.")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(allVideos) { video in
                                VStack(alignment: .leading, spacing: 8) {
                                    Button {
                                        fullscreenVideo = VideoItem(url: URL(string: video.url)!)
                                    } label: {
                                        VideoThumbnailView(videoURL: URL(string: video.url)!)
                                            .frame(height: 160)
                                            .cornerRadius(10)
                                    }

                                    HStack {
                                        Button {
                                            if let user = auth.user {
                                                firebase.toggleLike(for: climb.id ?? "", videoID: video.id, userID: user.uid) { _ in }
                                            }
                                        } label: {
                                            HStack {
                                                Image(systemName: video.likes.contains(auth.user?.uid ?? "") ? "heart.fill" : "heart")
                                                    .foregroundColor(video.likes.contains(auth.user?.uid ?? "") ? .red : .gray)
                                                Text("\(video.likes.count)")
                                            }
                                        }
                                        .buttonStyle(BorderlessButtonStyle())

                                        Spacer()

                                        if video.uploaderID == auth.user?.uid {
                                            Button(role: .destructive) {
                                                firebase.deleteVideo(for: climb.id ?? "", videoID: video.id, videoURL: video.url) { _ in }
                                            } label: {
                                                Image(systemName: "trash")
                                            }
                                        }
                                    }

                                    // MARK: Video Comments (per video)
                                    VStack(alignment: .leading, spacing: 6) {
                                        ForEach(Array(video.comments.enumerated()), id: \.offset) { _, comment in
                                            if let text = comment["text"] as? String,
                                               let email = comment["email"] as? String {
                                                Text("\(email): \(text)")
                                                    .font(.footnote)
                                                    .foregroundColor(.secondary)
                                            }
                                        }

                                        HStack {
                                            TextField(
                                                "Add a comment...",
                                                text: Binding(
                                                    get: { commentTexts[video.id] ?? "" },
                                                    set: { commentTexts[video.id] = $0 }
                                                )
                                            )
                                            .textFieldStyle(RoundedBorderTextFieldStyle())

                                            Button("Post") {
                                                guard let user = auth.user else { return }
                                                let text = commentTexts[video.id] ?? ""
                                                guard !text.isEmpty else { return }

                                                firebase.addComment(for: climb.id ?? "", videoID: video.id, text: text, user: user) { _ in
                                                    commentTexts[video.id] = ""
                                                    hideKeyboard() // ✅ dismiss keyboard
                                                }
                                            }
                                        }
                                    }
                                    Divider()
                                }
                                .padding(.vertical, 6)
                            }
                        }
                    }

                    // MARK: Upload New Video
                    Button {
                        showVideoPicker = true
                    } label: {
                        Label("Upload New Beta Video", systemImage: "square.and.arrow.up.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(climb.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Done") { onClose() }
            }
            .sheet(item: $fullscreenVideo) { video in
                AVPlayerView(url: video.url)
            }
            .onAppear {
                localAvgRating = climb.avgRating
                localAscentCount = climb.ascentCount
                loadAllVideos()
                loadClimbLogs()
                loadUserLog()
                listenForClimbUpdates()
                loadGradeVotes()
            }
            .sheet(isPresented: $showVideoPicker) {
                VideoPicker(selectedVideoURL: $selectedVideoURL) { url in
                    uploadVideo(url)
                }
            }
            // MARK: - Overlays
            .overlay(alignment: .center) {
                if isUploading {
                    VStack(spacing: 10) {
                        ProgressView(value: uploadProgress, total: 1.0)
                            .progressViewStyle(.linear)
                            .frame(width: 200)
                            .tint(.blue)
                        Text("Uploading… \(Int(uploadProgress * 100))%")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .padding(30)
                    .background(.ultraThinMaterial)
                    .cornerRadius(16)
                    .shadow(radius: 10)
                }
            }
            .overlay(alignment: .bottom) {
                if showSentToast {
                    Text("✅ Sent!")
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.green.opacity(0.9))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .padding(.bottom, 30)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if showBetaToast {
                    Text("✅ Beta Uploaded!")
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.blue.opacity(0.9))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .padding(.bottom, 80)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    // MARK: - Upload Video with Progress
    private func uploadVideo(_ url: URL) {
        guard let climbID = climb.id else { return }

        let filename = "videos/\(UUID().uuidString).mp4"
        let ref = Storage.storage().reference().child(filename)

        isUploading = true
        uploadProgress = 0.0
        print("📤 Starting upload to Firebase Storage: \(filename)")

        let uploadTask = ref.putFile(from: url, metadata: nil)

        uploadTask.observe(.progress) { snapshot in
            if let progress = snapshot.progress {
                uploadProgress = progress.fractionCompleted
            }
        }

        uploadTask.observe(.success) { _ in
            print("✅ Upload success, fetching download URL...")
            ref.downloadURL { videoURL, err in
                if let err = err {
                    print("❌ Failed to get video URL:", err.localizedDescription)
                    withAnimation { isUploading = false }
                    return
                }

                guard let videoURL = videoURL else {
                    print("❌ Video URL is nil.")
                    withAnimation { isUploading = false }
                    return
                }

                firebase.saveVideoMetadata(for: climbID, url: videoURL.absoluteString) { success in
                    withAnimation { isUploading = false }
                    if success {
                        print("✅ Video metadata saved for climb \(climbID).")
                        loadAllVideos()
                        showBetaToast = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation { showBetaToast = false }
                        }
                    } else {
                        print("❌ Failed to save video metadata.")
                    }
                }
            }
        }

        uploadTask.observe(.failure) { snapshot in
            if let err = snapshot.error {
                print("❌ Upload failed:", err.localizedDescription)
            }
            withAnimation { isUploading = false }
        }
    }

    // MARK: - Firestore Listeners + Loaders
    private func listenForClimbUpdates() {
        guard let climbID = climb.id else { return }
        firebase.db.collection("climbs").document(climbID)
            .addSnapshotListener { snapshot, _ in
                guard let data = snapshot?.data() else { return }
                if let updatedAscentCount = data["ascentCount"] as? Int,
                   let updatedAvgRating = data["avgRating"] as? Double {
                    withAnimation {
                        localAscentCount = updatedAscentCount
                        localAvgRating = updatedAvgRating
                    }
                }
            }
    }

    private func loadClimbLogs() {
        guard let climbID = climb.id else { return }
        firebase.db.collection("climbs").document(climbID)
            .collection("logs")
            .order(by: "timestamp", descending: true)
            .addSnapshotListener { snap, _ in
                guard let docs = snap?.documents else { return }
                climbLogs = docs.compactMap { doc -> ClimbLog? in
                    try? doc.data(as: ClimbLog.self)
                }
            }
    }

    private func loadUserLog() {
        guard let climbID = climb.id, let user = auth.user else { return }
        let ref = firebase.db.collection("climbs").document(climbID)
            .collection("logs").document(user.uid)
        ref.getDocument { doc, _ in
            guard let doc = doc, doc.exists else {
                hasLogged = false
                userLog = nil
                return
            }
            if let existing = try? doc.data(as: ClimbLog.self) {
                userLog = existing
                hasLogged = true
                rating = existing.rating
                commentText = existing.comment
            }
        }
    }
    private func loadGradeVotes() {
        guard let climbID = climb.id else { return }
        firebase.db.collection("climbs").document(climbID)
            .collection("gradeVotes")
            .addSnapshotListener { snap, _ in
                guard let docs = snap?.documents else { return }
                gradeVotes = docs.compactMap { try? $0.data(as: GradeVote.self) }

                if let user = auth.user {
                    userVote = gradeVotes.first(where: { $0.userID == user.uid })?.gradeVote
                }
            }
    }

    private func votePercent(_ option: String) -> Double {
        guard !gradeVotes.isEmpty else { return 0 }
        let count = Double(gradeVotes.filter { $0.gradeVote == option }.count)
        return count / Double(gradeVotes.count)
    }

    private func loadAllVideos() {
        guard let climbID = climb.id else { return }
        firebase.db.collection("climbs").document(climbID)
            .collection("videos")
            .order(by: "timestamp", descending: true)
            .addSnapshotListener { snap, _ in
                guard let docs = snap?.documents else { return }
                allVideos = docs.compactMap { doc -> VideoData? in
                    let d = doc.data()
                    return VideoData(
                        id: doc.documentID,
                        url: d["url"] as? String ?? "",
                        uploaderID: d["uploaderID"] as? String ?? "",
                        uploaderEmail: d["uploaderEmail"] as? String ?? "",
                        likes: d["likes"] as? [String] ?? [],
                        comments: d["comments"] as? [[String: Any]] ?? []
                    )
                }
            }
    }

    // MARK: - Dismiss Keyboard Helper
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

/////////////////////////////////////////////////////
// MARK: - Video Support Views
/////////////////////////////////////////////////////

struct VideoItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct VideoThumbnailView: View {
    var videoURL: URL
    @State private var thumbnail: UIImage? = nil

    var body: some View {
        ZStack {
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .overlay(ProgressView())
            }
        }
        .onAppear { generateThumbnail() }
    }

    private func generateThumbnail() {
        let asset = AVAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 1, preferredTimescale: 600)

        DispatchQueue.global().async {
            if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                let image = UIImage(cgImage: cgImage)
                DispatchQueue.main.async {
                    self.thumbnail = image
                }
            }
        }
    }
}

struct AVPlayerView: View {
    var url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VideoPlayer(player: AVPlayer(url: url))
                .edgesIgnoringSafeArea(.all)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

struct VideoPicker: UIViewControllerRepresentable {
    @Binding var selectedVideoURL: URL?
    var onPicked: (URL) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .videos
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: VideoPicker

        init(_ parent: VideoPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let item = results.first?.itemProvider else { return }
            
            if item.hasItemConformingToTypeIdentifier("public.movie") {
                item.loadFileRepresentation(forTypeIdentifier: "public.movie") { url, _ in
                    guard let url = url else { return }
                    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
                    try? FileManager.default.copyItem(at: url, to: tmp)
                    DispatchQueue.main.async {
                        self.parent.selectedVideoURL = tmp
                        self.parent.onPicked(tmp)
                    }
                }
            }
        }
    }
}
