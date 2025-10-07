import SwiftUI
import Firebase
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import AVKit
import PhotosUI

// ============================================================
// MARK: - Main Climb Detail Sheet
// ============================================================

struct ClimbDetailSheet: View {
    var climb: Climb
    var onClose: () -> Void

    @EnvironmentObject var firebase: FirebaseManager
    @EnvironmentObject var auth: AuthManager

    // Logs + votes
    @State private var climbLogs: [ClimbLog] = []
    @State private var gradeVotes: [GradeVote] = []
    @State private var userVote: String? = nil
    @State private var canVote = false
    @State private var hasLogged = false
    @State private var userLog: ClimbLog? = nil
    @State private var localAvgRating: Double = 0.0
    @State private var localAscentCount: Int = 0
    @State private var rating: Int = 0
    @State private var commentText: String = ""

    // Videos + comments
    @State private var fullscreenVideo: VideoItem?
    @State private var allVideos: [VideoData] = []
    @State private var showVideoPicker = false
    @State private var selectedVideoURL: URL?
    @State private var isUploading = false
    @State private var uploadProgress: Double = 0.0
    @State private var videoToDelete: VideoData? = nil
    @State private var showDeleteConfirm = false

    // Toasts
    @State private var showSentToast = false
    @State private var showBetaToast = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // MARK: Header
                    Text(climb.name)
                        .font(.title.bold())
                    Text(climb.grade)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    HStack {
                        Text("Ascents: \(localAscentCount)")
                        Spacer()
                        Text("Avg Rating: \(String(format: "%.1f", localAvgRating)) ⭐️")
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                    Divider()

                    // ====================================================
                    // MARK: Log an Ascent
                    // ====================================================

                    VStack(alignment: .leading, spacing: 8) {
                        Text(hasLogged ? "Edit Your Ascent Log" : "Log an Ascent")
                            .font(.headline)

                        if hasLogged {
                            Text("You've already logged this climb. You can update your rating or comment below.")
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
                                    user: user
                                ) {
                                    hasLogged = true
                                    canVote = true
                                    showSentToast = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                        withAnimation { showSentToast = false }
                                    }
                                    hideKeyboard()
                                }
                            }
                        }) {
                            Label(hasLogged ? "Update Log" : "Submit Log",
                                  systemImage: hasLogged ? "square.and.pencil" : "plus.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(rating == 0)
                    }

                    Divider()

                    // ====================================================
                    // MARK: Recent Logs
                    // ====================================================

                    // MARK: Recent Logs
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent Logs")
                            .font(.headline)
                        
                        if climbLogs.isEmpty {
                            Text("No logs yet. Be the first to send it!")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(climbLogs.prefix(5)) { log in
                                DynamicLogRow(log: log)
                                Divider()
                            }
                        }
                    }
                    Divider()

                    // ====================================================
                    // MARK: Community Grade Consensus
                    // ====================================================

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Community Grade Consensus")
                            .font(.headline)

                        if !canVote {
                            Text("Log a send to cast your grade opinion!")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.bottom, 6)
                        }

                        let options = gradeOptionsForTag(climb.grade)

                        ForEach(options, id: \.self) { option in
                            HStack {
                                Button {
                                    guard canVote else { return }
                                    if let user = auth.user {
                                        firebase.submitGradeVote(for: climb.id ?? "", vote: option, user: user) {}
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
                                .disabled(!canVote)

                                GeometryReader { geo in
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.blue.opacity(0.3))
                                        .frame(width: geo.size.width * CGFloat(votePercent(option)), height: 8)
                                }
                                .frame(height: 8)
                                Text("\(Int(votePercent(option) * 100))%")
                                    .font(.caption)
                                    .frame(width: 40, alignment: .trailing)
                            }
                            .opacity(canVote ? 1 : 0.5)
                        }
                    }

                    Divider()

                    // ====================================================
                    // MARK: Beta Videos + Comments
                    // ====================================================

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
                                        Spacer()
                                        if video.uploaderID == auth.user?.uid {
                                            Button(role: .destructive) {
                                                videoToDelete = video
                                                showDeleteConfirm = true
                                            } label: {
                                                Image(systemName: "trash")
                                            }
                                        }
                                    }

                                    CommentListView(climbID: climb.id ?? "", videoID: video.id)
                                        .environmentObject(firebase)
                                        .environmentObject(auth)

                                    Divider()
                                }
                                .padding(.vertical, 6)
                            }
                        }
                    }

                    Button {
                        showVideoPicker = true
                    } label: {
                        Label("Upload New Beta Video", systemImage: "square.and.arrow.up.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .navigationTitle(climb.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Done") { onClose() }
            }
            .sheet(item: $fullscreenVideo) { video in
                AVPlayerView(url: video.url)
            }
            .sheet(isPresented: $showVideoPicker) {
                VideoPicker(selectedVideoURL: $selectedVideoURL) { url in
                    uploadVideo(url)
                }
            }
            // Upload overlay
            .overlay(alignment: .center) {
                if isUploading {
                    VStack(spacing: 10) {
                        ProgressView(value: uploadProgress, total: 1.0)
                            .frame(width: 200)
                        Text("Uploadingâ€¦ \(Int(uploadProgress * 100))%")
                    }
                    .padding(30)
                    .background(.ultraThinMaterial)
                    .cornerRadius(16)
                }
            }
            // Toasts
            .overlay(alignment: .bottom) {
                VStack {
                    if showSentToast {
                        Text("âœ… Sent!")
                            .padding()
                            .background(Color.green.opacity(0.9))
                            .cornerRadius(12)
                    }
                    if showBetaToast {
                        Text("âœ… Beta Uploaded!")
                            .padding()
                            .background(Color.blue.opacity(0.9))
                            .cornerRadius(12)
                    }
                }
                .foregroundColor(.white)
                .padding(.bottom, 40)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .alert("Delete Beta Video?",
               isPresented: $showDeleteConfirm,
               presenting: videoToDelete) { video in
            Button("Delete", role: .destructive) {
                firebase.deleteVideo(for: climb.id ?? "", videoID: video.id, videoURL: video.url) { _ in
                    videoToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) { videoToDelete = nil }
        } message: { video in
            Text("This will permanently delete your beta video.")
        }
        .onAppear {
            localAvgRating = climb.avgRating
            localAscentCount = climb.ascentCount
            loadAllVideos()
            listenToLogs()
            listenToGradeVotes()
            loadUserLog()
        }
    }

    // ============================================================
    // MARK: - Helpers
    // ============================================================
    private func gradeOptionsForTag(_ tag: String) -> [String] {
        if tag.contains("Pink Tag (V8+)") { return ["V8", "V9", "V10+"] }
        if tag.contains("Purple Tag (V6–8)") || tag.contains("Purple Tag (V6-8)") { return ["V6", "V7", "V8"] }
        if tag.contains("Green Tag (V4–6)") || tag.contains("Green Tag (V4-6)") { return ["V4", "V5", "V6"] }
        if tag.contains("Yellow Tag (V2–4)") || tag.contains("Yellow Tag (V2-4)") { return ["V2", "V3", "V4"] }
        if tag.contains("Red Tag (V0–V2)") || tag.contains("Red Tag (V0-2)") { return ["V0", "V1", "V2"] }
        if tag.contains("Blue Tag (VB–V0)") || tag.contains("Blue Tag (VB-V0)") { return ["VB", "V0"] }
        if tag.contains("White Tag (Ungraded)") { return ["VB-0", "V0-V2", "V2-4", "V4-6", "V6-8", "V8+"] }
        return ["Ungraded"]
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }

    private func uploadVideo(_ url: URL) {
        guard let climbID = climb.id else { return }
        let filename = "videos/\(UUID().uuidString).mp4"
        let ref = Storage.storage().reference().child(filename)
        isUploading = true
        uploadProgress = 0

        let uploadTask = ref.putFile(from: url, metadata: nil)
        uploadTask.observe(.progress) { snapshot in
            uploadProgress = snapshot.progress?.fractionCompleted ?? 0
        }
        uploadTask.observe(.success) { _ in
            ref.downloadURL { videoURL, _ in
                guard let videoURL = videoURL else { return }
                firebase.saveVideoMetadata(for: climbID, url: videoURL.absoluteString) { success in
                    withAnimation { isUploading = false }
                    if success {
                        loadAllVideos()
                        showBetaToast = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation { showBetaToast = false }
                        }
                    }
                }
            }
        }
        uploadTask.observe(.failure) { _ in
            withAnimation { isUploading = false }
        }
    }
    
    private func loadAllVideos() {
        guard let climbID = climb.id else { return }
        firebase.db.collection("climbs").document(climbID)
            .collection("videos")
            .order(by: "timestamp", descending: true)
            .addSnapshotListener { snap, _ in
                guard let docs = snap?.documents else { return }
                allVideos = docs.map { doc in
                    let d = doc.data()
                    return VideoData(
                        id: doc.documentID,
                        url: d["url"] as? String ?? "",
                        uploaderID: d["uploaderID"] as? String ?? "",
                        uploaderEmail: d["uploaderEmail"] as? String ?? "",
                        likes: d["likes"] as? [String] ?? []
                    )
                }
            }
    }

    private func listenToLogs() {
        guard let climbID = climb.id else { return }
        firebase.listenForClimbLogs(climbID: climbID) { logs in
            climbLogs = logs
            let ratings = logs.map { $0.rating }
            localAscentCount = ratings.count
            localAvgRating = ratings.isEmpty ? 0 :
                Double(ratings.reduce(0, +)) / Double(ratings.count)
        }
    }

    private func listenToGradeVotes() {
        guard let climbID = climb.id else { return }
        firebase.listenForGradeVotes(climbID: climbID) { votes in
            gradeVotes = votes
            if let user = auth.user {
                userVote = votes.first(where: { $0.userID == user.uid })?.gradeVote
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
                canVote = false
                return
            }
            if let log = try? doc.data(as: ClimbLog.self) {
                userLog = log
                hasLogged = true
                canVote = true
            }
        }
    }

    private func votePercent(_ option: String) -> Double {
        guard !gradeVotes.isEmpty else { return 0 }
        let count = Double(gradeVotes.filter { $0.gradeVote == option }.count)
        return count / Double(gradeVotes.count)
    }

    struct VideoItem: Identifiable { let id = UUID(); let url: URL }
}

// ============================================================
// MARK: - Comments Section (real-time + dynamic profiles)
// ============================================================
struct DynamicLogRow: View {
    var log: ClimbLog
    @State private var displayName: String = "Loading..."
    @State private var photoURL: String = ""
    private let db = Firestore.firestore()

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Profile Picture
            if let url = URL(string: photoURL), !photoURL.isEmpty {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Circle().fill(Color.gray.opacity(0.3))
                }
                .frame(width: 28, height: 28)
                .clipShape(Circle())
            } else {
                Circle().fill(Color.gray.opacity(0.3))
                    .frame(width: 28, height: 28)
                    .overlay(Image(systemName: "person.fill").font(.footnote))
            }

            // Log Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(displayName)
                        .font(.subheadline.bold())
                    Spacer()
                    Text("\(log.rating)⭐")
                        .foregroundColor(.yellow)
                }
                Text(log.comment)
                    .font(.footnote)
                Text(log.timestamp, style: .date)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .onAppear { fetchUserProfile() }
    }

    private func fetchUserProfile() {
        db.collection("users").document(log.userID)
            .addSnapshotListener { doc, _ in
                guard let data = doc?.data() else { return }
                displayName = data["displayName"] as? String ?? "Unknown"
                photoURL = data["photoURL"] as? String ?? ""
            }
    }
}

struct CommentListView: View {
    let climbID: String
    let videoID: String
    @EnvironmentObject var firebase: FirebaseManager
    @EnvironmentObject var auth: AuthManager
    @State private var comments: [Comment] = []
    @State private var showAll = false
    @State private var commentText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let shown = showAll ? comments : Array(comments.prefix(3))

            ForEach(shown) { comment in
                CommentRowLive(comment: comment, climbID: climbID, videoID: videoID)
            }

            if comments.count > 3 {
                Button(showAll ? "Show Less" : "Show More") {
                    withAnimation { showAll.toggle() }
                }
                .font(.footnote)
                .foregroundColor(.blue)
            }

            HStack {
                TextField("Add a comment...", text: $commentText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Button("Post") {
                    guard let user = auth.user, !commentText.isEmpty else { return }
                    Task {
                        try? await firebase.addComment(for: climbID, videoID: videoID, text: commentText, user: user)
                        commentText = ""
                    }
                }
            }
        }
        .onAppear {
            firebase.listenForComments(climbID: climbID, videoID: videoID) { newComments in
                comments = newComments
            }
        }
    }
}

// ============================================================
// MARK: - Individual Comment Row
// ============================================================

struct CommentRowLive: View {
    let comment: Comment
    let climbID: String
    let videoID: String
    @EnvironmentObject var firebase: FirebaseManager
    @EnvironmentObject var auth: AuthManager
    @State private var displayName = "Loading..."
    @State private var photoURL: String = ""

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if let url = URL(string: photoURL), !photoURL.isEmpty {
                AsyncImage(url: url) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Circle().fill(Color.gray.opacity(0.3))
                }
                .frame(width: 26, height: 26)
                .clipShape(Circle())
            } else {
                Circle().fill(Color.gray.opacity(0.3))
                    .frame(width: 26, height: 26)
                    .overlay(Image(systemName: "person.fill").font(.footnote))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.caption.bold())
                Text(comment.text)
                    .font(.footnote)
                Text(relativeTimeString(from: comment.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // delete button for owner
            if comment.userID == auth.user?.uid {
                Button {
                    Task {
                        try? await firebase.deleteComment(for: climbID,
                                                          videoID: videoID,
                                                          commentID: comment.id ?? "")
                    }
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                        .font(.system(size: 14))
                }
            }
        }
        .onAppear { fetchUser() }
    }

    private func fetchUser() {
        firebase.db.collection("users").document(comment.userID)
            .addSnapshotListener { doc, _ in
                guard let data = doc?.data() else { return }
                displayName = data["displayName"] as? String ?? "Unknown"
                photoURL = data["photoURL"] as? String ?? ""
            }
    }

    private func relativeTimeString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// ============================================================
// MARK: - Video Thumbnail & Player
// ============================================================

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
        .clipped()
    }

    private func generateThumbnail() {
        let asset = AVAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 1, preferredTimescale: 600)

        DispatchQueue.global().async {
            if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                let image = UIImage(cgImage: cgImage)
                DispatchQueue.main.async { self.thumbnail = image }
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

// ============================================================
// MARK: - Video Picker
// ============================================================

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
                    let tmp = FileManager.default.temporaryDirectory
                        .appendingPathComponent("\(UUID().uuidString).mp4")
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
