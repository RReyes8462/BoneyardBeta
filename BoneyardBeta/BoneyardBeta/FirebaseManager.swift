import Foundation
import Firebase
import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage
import Combine

@MainActor
class FirebaseManager: ObservableObject {
    static let shared = FirebaseManager()

    let db = Firestore.firestore()
    let storage = Storage.storage()

    private init() {}

    // MARK: - Video Metadata
    func saveVideoMetadata(for climb: Climb, url: String, completion: @escaping (Bool) -> Void) {
        guard let user = Auth.auth().currentUser else {
            completion(false)
            return
        }

        guard let climbID = climb.id else {
            print("❌ Missing climb ID.")
            completion(false)
            return
        }

        let videoData: [String: Any] = [
            "url": url,
            "uploaderID": user.uid,
            "uploaderEmail": user.email ?? "unknown",
            "climbID": climbID,
            "climbName": climb.name,
            "grade": climb.grade,
            "section": climb.section ?? "Unknown",
            "gymID": climb.gymID,
            "likes": [],
            "timestamp": Timestamp(date: Date())
        ]

        db.collection("climbs").document(climbID)
            .collection("videos")
            .addDocument(data: videoData) { err in
                if let err = err {
                    print("❌ Error saving video metadata:", err.localizedDescription)
                    completion(false)
                } else {
                    print("✅ Saved video metadata for climb:", climb.name)
                    completion(true)
                }
            }
    }


    // MARK: - Toggle Like
    func toggleLike(for climbID: String,
                    videoID: String,
                    userID: String,
                    completion: ((Bool) -> Void)? = nil) {
        let ref = db.collection("climbs").document(climbID)
            .collection("videos").document(videoID)

        ref.getDocument { doc, err in
            guard let data = doc?.data(), err == nil else {
                print("❌ Error reading likes:", err?.localizedDescription ?? "")
                completion?(false)
                return
            }

            var likes = data["likes"] as? [String] ?? []
            if likes.contains(userID) {
                likes.removeAll { $0 == userID }
            } else {
                likes.append(userID)
            }

            ref.updateData(["likes": likes]) { err in
                if let err = err {
                    print("❌ Failed to toggle like:", err.localizedDescription)
                    completion?(false)
                } else {
                    completion?(true)
                }
            }
        }
    }

    // MARK: - Delete Video
    func deleteVideo(for climbID: String,
                     videoID: String,
                     videoURL: String,
                     completion: ((Bool) -> Void)? = nil) {
        let ref = db.collection("climbs").document(climbID)
            .collection("videos").document(videoID)

        ref.delete { err in
            if let err = err {
                print("❌ Error deleting video document:", err.localizedDescription)
                completion?(false)
            } else {
                print("✅ Video Firestore document deleted.")
                let storageRef = self.storage.reference(forURL: videoURL)
                storageRef.delete { err in
                    if let err = err {
                        print("⚠️ Warning: video storage deletion failed:", err.localizedDescription)
                    }
                    completion?(true)
                }
            }
        }
    }

    // ======================================================
    // MARK: - Real-time Comment System
    // ======================================================

    // Live comment listener (returns registration so it can be stopped if needed)
    func listenForComments(climbID: String,
                           videoID: String,
                           onChange: @escaping ([Comment]) -> Void) -> ListenerRegistration {
        return db.collection("climbs").document(climbID)
            .collection("videos").document(videoID)
            .collection("comments")
            .order(by: "timestamp", descending: false)
            .addSnapshotListener { snapshot, err in
                if let err = err {
                    print("❌ listenForComments error:", err.localizedDescription)
                    return
                }
                guard let docs = snapshot?.documents else { return }
                let comments = docs.compactMap { try? $0.data(as: Comment.self) }
                onChange(comments)
            }
    }

    // Add comment (async/await)
    func addComment(for climbID: String,
                    videoID: String,
                    text: String,
                    user: User) async throws {
        let commentRef = db.collection("climbs").document(climbID)
            .collection("videos").document(videoID)
            .collection("comments").document()

        let comment = Comment(id: commentRef.documentID,
                              userID: user.uid,
                              text: text,
                              timestamp: Date())
        try commentRef.setData(from: comment)
        print("✅ Comment added successfully for \(videoID).")
    }

    // Delete comment
    func deleteComment(for climbID: String,
                       videoID: String,
                       commentID: String) async throws {
        let ref = db.collection("climbs").document(climbID)
            .collection("videos").document(videoID)
            .collection("comments").document(commentID)
        try await ref.delete()
        print("🗑️ Comment \(commentID) deleted successfully.")
    }

    // ======================================================
    // MARK: - User Profile Helpers
    // ======================================================

    func updateUserProfile(userID: String,
                           displayName: String?,
                           photoURL: String?,
                           completion: ((Bool) -> Void)? = nil) {
        var data: [String: Any] = [:]
        if let displayName = displayName { data["displayName"] = displayName }
        if let photoURL = photoURL { data["photoURL"] = photoURL }

        db.collection("users").document(userID).setData(data, merge: true) { err in
            if let err = err {
                print("❌ Failed to update profile:", err.localizedDescription)
                completion?(false)
            } else {
                print("✅ Profile updated for \(userID)")
                completion?(true)
            }
        }
    }

    func fetchUserProfile(userID: String, completion: @escaping (_ name: String?, _ photo: String?) -> Void) {
        db.collection("users").document(userID).getDocument { doc, _ in
            guard let data = doc?.data() else {
                completion(nil, nil)
                return
            }
            completion(data["displayName"] as? String,
                       data["photoURL"] as? String)
        }
    }
    // ======================================================
    // MARK: - Climb CRUD Operations (Fix for ContentView)
    // ======================================================

    func addClimb(_ climb: Climb) {
        guard let user = Auth.auth().currentUser else { return }
        var newClimb = climb
        newClimb.updatedBy = user.displayName ?? user.email ?? "Unknown"

        do {
            _ = try db.collection("climbs").addDocument(from: newClimb)
        } catch {
            print("❌ Error adding climb: \(error.localizedDescription)")
        }
    }

    func saveClimb(_ climb: Climb) {
        guard let id = climb.id else { return }
        guard let user = Auth.auth().currentUser else { return }
        var updatedClimb = climb
        updatedClimb.updatedBy = user.displayName ?? user.email ?? "Unknown"

        do {
            try db.collection("climbs").document(id).setData(from: updatedClimb, merge: true)
        } catch {
            print("❌ Error saving climb: \(error.localizedDescription)")
        }
    }

    func deleteClimb(_ climb: Climb, completion: ((Bool) -> Void)? = nil) {
        guard let id = climb.id else {
            print("⚠️ deleteClimb called without a climb ID.")
            completion?(false)
            return
        }

        db.collection("climbs").document(id).delete { err in
            if let err = err {
                print("❌ Error deleting climb:", err.localizedDescription)
                completion?(false)
            } else {
                print("🗑️ Climb \(id) deleted successfully.")
                completion?(true)
            }
        }
    }
    // ======================================================
    // MARK: - Climb Logs & Grade Votes
    // ======================================================

    // Save or update a user's ascent log
    // MARK: - Log Climb Ascent
    func logClimbAscent(
        for climb: Climb,
        rating: Int,
        comment: String,
        user: User,
        completion: @escaping () -> Void
    ) {
        guard let climbID = climb.id else { return }

        let logData: [String: Any] = [
            "userID": user.uid,
            "email": user.email ?? "",
            "rating": rating,
            "comment": comment,
            "timestamp": Timestamp(date: Date()),
            "grade": climb.grade
        ]

        // Save or update the user’s log under this climb
        db.collection("climbs").document(climbID)
            .collection("logs").document(user.uid)
            .setData(logData, merge: true) { err in
                if let err = err {
                    print("❌ Error logging ascent:", err.localizedDescription)
                    return
                }

                // Recalculate stats for the climb
                self.db.collection("climbs").document(climbID)
                    .collection("logs")
                    .getDocuments { snapshot, error in
                        guard let docs = snapshot?.documents else {
                            completion()
                            return
                        }

                        let ratings = docs.compactMap { $0["rating"] as? Int }
                        let avgRating = ratings.isEmpty ? 0.0 :
                            Double(ratings.reduce(0, +)) / Double(ratings.count)

                        self.db.collection("climbs").document(climbID)
                            .setData([
                                "avgRating": avgRating,
                                "ascentCount": ratings.count
                            ], merge: true) { err in
                                if let err = err {
                                    print("❌ Error updating climb stats:", err.localizedDescription)
                                } else {
                                    print("✅ Ascent logged for climb:", climb.name)
                                }
                                completion()
                            }
                    }
            }
    }
    // Listen for all logs for a climb
    func listenForClimbLogs(climbID: String,
                            onChange: @escaping ([ClimbLog]) -> Void) -> ListenerRegistration {
        return db.collection("climbs").document(climbID)
            .collection("logs")
            .order(by: "timestamp", descending: true)
            .addSnapshotListener { snap, _ in
                guard let docs = snap?.documents else { return }
                let logs = docs.compactMap { try? $0.data(as: ClimbLog.self) }
                onChange(logs)
            }
    }

    // Submit or update a grade vote
    func submitGradeVote(for climbID: String, vote: String, user: User, completion: (() -> Void)? = nil) {
        let climbRef = db.collection("climbs").document(climbID)
        let voteRef = climbRef.collection("gradeVotes").document(user.uid)

        climbRef.getDocument { doc, error in
            guard let data = doc?.data(),
                  let tag = data["grade"] as? String else {
                completion?()
                return
            }

            // ✅ Validate vote range based on tag
            let allowed = self.gradeOptionsForTag(tag)
            guard allowed.contains(vote) else {
                print("❌ Vote \(vote) is invalid for grade tag \(tag)")
                completion?()
                return
            }

            voteRef.setData([
                "userID": user.uid,
                "gradeVote": vote
            ], merge: true) { err in
                if let err = err {
                    print("❌ Error submitting grade vote:", err.localizedDescription)
                } else {
                    print("✅ Grade vote submitted successfully")
                }
                completion?()
            }
        }
    }

    // ✅ Helper (same logic as in ClimbDetailSheet)
    private func gradeOptionsForTag(_ tag: String) -> [String] {
        if tag.contains("Pink Tag (V8+)" ) { return ["V8", "V9", "V10+"] }
        if tag.contains("Purple Tag (V6–8)") || tag.contains("Purple Tag (V6-8)") { return ["V6", "V7", "V8"] }
        if tag.contains("Green Tag (V4–6)") || tag.contains("Green Tag (V4-6)") { return ["V4", "V5", "V6"] }
        if tag.contains("Yellow Tag (V2–4)") || tag.contains("Yellow Tag (V2-4)") { return ["V2", "V3", "V4"] }
        if tag.contains("Red Tag (V0–V2)") || tag.contains("Red Tag (V0-2)") { return ["V0", "V1", "V2"] }
        if tag.contains("Blue Tag (VB–V0)") || tag.contains("Blue Tag (VB-V0)") { return ["VB", "V0"] }
        if tag.contains("White Tag (Ungraded)") { return ["VB-0", "V0-V2", "V2-4", "V4-6", "V6-8", "V8+"] }
        return ["Ungraded"]
    }

    // Listen for grade votes
    func listenForGradeVotes(climbID: String,
                             onChange: @escaping ([GradeVote]) -> Void) -> ListenerRegistration {
        return db.collection("climbs").document(climbID)
            .collection("gradeVotes")
            .addSnapshotListener { snap, _ in
                guard let docs = snap?.documents else { return }
                let votes = docs.compactMap { try? $0.data(as: GradeVote.self) }
                onChange(votes)
            }
    }

}

