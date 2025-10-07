import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import Combine

final class FirebaseManager: ObservableObject {
    static let shared = FirebaseManager()

    @Published var isAdmin: Bool = false
    private let db = Firestore.firestore()
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    // MARK: - Video Upload
    func uploadBetaVideo(for climbID: String, videoURL: URL, completion: @escaping (Bool, String?) -> Void) {
        guard let user = Auth.auth().currentUser else {
            completion(false, "User not authenticated")
            return
        }

        // Check file exists
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            completion(false, "File not found at path: \(videoURL.lastPathComponent)")
            return
        }

        let storageRef = Storage.storage().reference()
            .child("beta_videos/\(climbID)/\(user.uid).mp4")

        print("📤 Starting upload to \(storageRef.fullPath)")

        let uploadTask = storageRef.putFile(from: videoURL, metadata: nil) { metadata, error in
            if let error = error {
                print("❌ Upload error:", error.localizedDescription)
                completion(false, error.localizedDescription)
                return
            }

            // Wait briefly before getting download URL
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                storageRef.downloadURL { url, error in
                    if let error = error {
                        print("❌ Failed to get downloadURL:", error.localizedDescription)
                        completion(false, error.localizedDescription)
                        return
                    }

                    guard let url = url else {
                        completion(false, "Missing download URL")
                        return
                    }

                    print("✅ Video uploaded, URL: \(url.absoluteString)")

                    let logRef = self.db.collection("climbs")
                        .document(climbID)
                        .collection("logs")
                        .document(user.uid)

                    logRef.setData([
                        "videoURL": url.absoluteString,
                        "videoUploadedAt": FieldValue.serverTimestamp()
                    ], merge: true) { error in
                        if let error = error {
                            print("❌ Failed to save video URL:", error.localizedDescription)
                            completion(false, error.localizedDescription)
                        } else {
                            print("✅ Video URL saved to Firestore logs")
                            completion(true, nil)
                        }
                    }
                }
            }
        }

        uploadTask.observe(.progress) { snapshot in
            let percent = Double(snapshot.progress?.completedUnitCount ?? 0)
                        / Double(snapshot.progress?.totalUnitCount ?? 1) * 100
            print("📈 Upload progress: \(String(format: "%.1f", percent))%")
        }
    }

    // MARK: - Log Climb Send
    func logClimbSend(climbID: String, comment: String, rating: Double, completion: @escaping (Bool, String?) -> Void) {
        guard let user = Auth.auth().currentUser else {
            completion(false, "User not authenticated")
            return
        }

        let logRef = db.collection("climbs")
            .document(climbID)
            .collection("logs")
            .document(user.uid)

        let climbRef = db.collection("climbs").document(climbID)

        db.runTransaction({ (transaction, errorPointer) -> Any? in
            let climbDoc: DocumentSnapshot
            do {
                climbDoc = try transaction.getDocument(climbRef)
            } catch let fetchError as NSError {
                errorPointer?.pointee = fetchError
                return nil
            }

            let ascentCount = (climbDoc.data()?["ascentCount"] as? Int) ?? 0
            let avgRating = (climbDoc.data()?["avgRating"] as? Double) ?? 0.0

            let newAscentCount = ascentCount + 1
            let newAvgRating = ((avgRating * Double(ascentCount)) + rating) / Double(newAscentCount)

            transaction.updateData([
                "ascentCount": newAscentCount,
                "avgRating": newAvgRating
            ], forDocument: climbRef)

            transaction.setData([
                "comment": comment,
                "rating": rating,
                "timestamp": FieldValue.serverTimestamp(),
                "userID": user.uid,
                "userEmail": user.email ?? "unknown"
            ], forDocument: logRef, merge: true)

            return nil
        }) { (_, error) in
            if let error = error {
                print("❌ Failed to log climb:", error.localizedDescription)
                completion(false, error.localizedDescription)
            } else {
                print("✅ Logged climb successfully")
                completion(true, nil)
            }
        }
    }

    // MARK: - Fetch User Log
    func fetchUserLog(for climbID: String, completion: @escaping ([String: Any]?) -> Void) {
        guard let user = Auth.auth().currentUser else {
            completion(nil)
            return
        }

        let logRef = db.collection("climbs")
            .document(climbID)
            .collection("logs")
            .document(user.uid)

        logRef.getDocument { doc, error in
            if let doc = doc, doc.exists {
                completion(doc.data())
            } else {
                completion(nil)
            }
        }
    }

    // MARK: - Climb CRUD
    func addClimb(gymID: String, updatedBy: String) {
        let newClimb: [String: Any] = [
            "name": "New Climb",
            "grade": "V0",
            "color": "gray",
            "x": 500,
            "y": 350,
            "gymID": gymID,
            "updatedBy": updatedBy,
            "ascentCount": 0,
            "avgRating": 0.0
        ]
        db.collection("climbs").addDocument(data: newClimb)
    }

    func saveClimb(_ climb: Climb) {
        guard let id = climb.id else { return }
        do {
            try db.collection("climbs").document(id).setData(from: climb, merge: true)
        } catch {
            print("❌ Save error:", error)
        }
    }

    func deleteClimb(_ climb: Climb) {
        guard let id = climb.id else { return }
        db.collection("climbs").document(id).delete { err in
            if let err = err {
                print("❌ Delete error:", err)
            } else {
                print("🗑️ Deleted climb \(climb.name)")
            }
        }
    }
}
