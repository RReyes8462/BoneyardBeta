import Foundation
import Firebase
import FirebaseFirestore
import FirebaseStorage
import Combine
import FirebaseAuth

final class FirebaseManager: ObservableObject {
    static let shared = FirebaseManager()
    let db = Firestore.firestore()
    let storage = Storage.storage()

    private init() {}
}

// MARK: - Core Climb Logging + Stats
extension FirebaseManager {

    /// Log or update a user's ascent for a climb.
    func logClimbAscent(for climb: Climb,
                        rating: Int,
                        comment: String,
                        user: User,
                        completion: (() -> Void)? = nil) {
        guard let climbID = climb.id else { return }

        let logRef = db.collection("climbs").document(climbID)
            .collection("logs").document(user.uid)

        let log = ClimbLog(
            userID: user.uid,
            email: user.email ?? "unknown",
            comment: comment,
            rating: rating,
            timestamp: Date()
        )

        do {
            try logRef.setData(from: log) { error in
                if let error = error {
                    print("❌ Error saving log:", error.localizedDescription)
                } else {
                    print("✅ Log saved or updated for \(climb.name)")
                    completion?() // Update UI immediately
                    self.updateClimbStats(climbID: climbID)
                }
            }
        } catch {
            print("❌ Encoding error:", error.localizedDescription)
        }
    }

    /// Recalculate the average rating and ascent count for a climb.
    func updateClimbStats(climbID: String) {
        let logsRef = db.collection("climbs").document(climbID).collection("logs")

        logsRef.getDocuments { snapshot, error in
            if let error = error {
                print("❌ Error fetching logs for stats:", error.localizedDescription)
                return
            }

            guard let docs = snapshot?.documents else { return }
            let ratings = docs.compactMap { $0.data()["rating"] as? Int }

            guard !ratings.isEmpty else {
                self.db.collection("climbs").document(climbID)
                    .updateData(["avgRating": 0.0, "ascentCount": 0])
                return
            }

            let avg = Double(ratings.reduce(0, +)) / Double(ratings.count)
            let count = ratings.count

            self.db.collection("climbs").document(climbID)
                .updateData([
                    "avgRating": avg,
                    "ascentCount": count
                ]) { err in
                    if let err = err {
                        print("❌ Failed to update climb stats:", err.localizedDescription)
                    } else {
                        print("✅ Climb stats updated successfully.")
                    }
                }
        }
    }
}

// MARK: - Video Management
extension FirebaseManager {

    /// Save metadata for a new beta video.
    func saveVideoMetadata(for climbID: String,
                           url: String,
                           completion: ((Bool) -> Void)? = nil) {
        guard let user = Auth.auth().currentUser else { return }

        let ref = db.collection("climbs").document(climbID)
            .collection("videos").document()

        let data: [String: Any] = [
            "url": url,
            "uploaderID": user.uid,
            "uploaderEmail": user.email ?? "unknown",
            "likes": [],
            "comments": [],
            "timestamp": Timestamp(date: Date())
        ]

        ref.setData(data) { err in
            if let err = err {
                print("❌ Error saving video metadata:", err.localizedDescription)
                completion?(false)
            } else {
                print("✅ Video metadata saved.")
                completion?(true)
            }
        }
    }

    /// Toggle like for a given video.
    func toggleLike(for climbID: String,
                    videoID: String,
                    userID: String,
                    completion: ((Bool) -> Void)? = nil) {
        let ref = db.collection("climbs").document(climbID)
            .collection("videos").document(videoID)

        db.runTransaction({ (transaction, errorPointer) -> Any? in
            let snapshot: DocumentSnapshot
            do {
                snapshot = try transaction.getDocument(ref)
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }

            guard var likes = snapshot.data()?["likes"] as? [String] else { return nil }

            if likes.contains(userID) {
                likes.removeAll { $0 == userID }
            } else {
                likes.append(userID)
            }

            transaction.updateData(["likes": likes], forDocument: ref)
            return nil
        }) { (_, error) in
            if let error = error {
                print("❌ Transaction failed:", error.localizedDescription)
                completion?(false)
            } else {
                print("✅ Like toggled for video \(videoID)")
                completion?(true)
            }
        }
    }

    /// Add a comment to a video.
    func addComment(for climbID: String,
                    videoID: String,
                    text: String,
                    user: User,
                    completion: ((Bool) -> Void)? = nil) {
        let ref = db.collection("climbs").document(climbID)
            .collection("videos").document(videoID)

        ref.updateData([
            "comments": FieldValue.arrayUnion([
                ["email": user.email ?? "unknown",
                 "text": text,
                 "timestamp": Timestamp(date: Date())]
            ])
        ]) { err in
            if let err = err {
                print("❌ Error adding comment:", err.localizedDescription)
                completion?(false)
            } else {
                print("✅ Comment added to video \(videoID)")
                completion?(true)
            }
        }
    }

    /// Delete a video (metadata + storage file).
    func deleteVideo(for climbID: String,
                     videoID: String,
                     videoURL: String,
                     completion: ((Bool) -> Void)? = nil) {
        let videoRef = db.collection("climbs").document(climbID)
            .collection("videos").document(videoID)

        videoRef.delete { err in
            if let err = err {
                print("❌ Error deleting video metadata:", err.localizedDescription)
                completion?(false)
            } else {
                print("✅ Video metadata deleted.")
                let storageRef = Storage.storage().reference(forURL: videoURL)
                storageRef.delete { storageErr in
                    if let storageErr = storageErr {
                        print("⚠️ Warning: Could not delete video file:", storageErr.localizedDescription)
                    } else {
                        print("✅ Video file deleted from Storage.")
                    }
                    completion?(true)
                }
            }
        }
    }
    func addClimb(gymID: String, updatedBy: String) {
           let ref = db.collection("climbs").document()
           let newClimb = Climb(
               id: ref.documentID,
               name: "New Climb",
               grade: "V0",
               color: "gray",
               x: 100,
               y: 100,
               gymID: gymID,
               updatedBy: updatedBy,
               ascentCount: 0,
               avgRating: 0.0
           )

           do {
               try ref.setData(from: newClimb)
               print("✅ Added new climb to Firestore.")
           } catch {
               print("❌ Error adding climb:", error.localizedDescription)
           }
       }

       func saveClimb(_ climb: Climb) {
           guard let climbID = climb.id else { return }
           do {
               try db.collection("climbs").document(climbID).setData(from: climb)
               print("✅ Climb saved successfully.")
           } catch {
               print("❌ Error saving climb:", error.localizedDescription)
           }
       }

       func deleteClimb(_ climb: Climb) {
           guard let climbID = climb.id else { return }
           db.collection("climbs").document(climbID).delete { err in
               if let err = err {
                   print("❌ Error deleting climb:", err.localizedDescription)
               } else {
                   print("✅ Climb deleted successfully.")
               }
           }
       }
}

