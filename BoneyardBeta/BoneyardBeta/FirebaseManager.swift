import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

class FirebaseManager: ObservableObject {
    static let shared = FirebaseManager()
    private init() {}

    @Published var climbs: [Climb] = []
    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    // MARK: - Listen for Climbs
    func listenForClimbs() {
        listener?.remove()
        listener = db.collection("climbs")
            .whereField("gymID", isEqualTo: "urbana boulders")
            .addSnapshotListener { snapshot, _ in
                guard let snapshot = snapshot else { return }
                do {
                    self.climbs = try snapshot.documents.map { try $0.data(as: Climb.self) }
                } catch {
                    print("❌ Decode error:", error)
                }
            }
    }

    // MARK: - Save / Delete Climbs (Admin)
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

    func addClimb(gymID: String, updatedBy: String) {
        let newClimb = Climb(
            id: nil,
            name: "New Climb",
            grade: "V0",
            color: "gray",
            x: 500,
            y: 375,
            gymID: gymID,
            updatedBy: updatedBy
        )
        do {
            _ = try db.collection("climbs").addDocument(from: newClimb)
        } catch {
            print("❌ Add error:", error)
        }
    }

    // MARK: - Log Climb Send (1 log per user)
    func logClimbSend(
        climbID: String,
        comment: String,
        rating: Double,
        completion: @escaping (Bool, String?) -> Void
    ) {
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
            // Fetch climb document
            let climbDoc: DocumentSnapshot
            do {
                climbDoc = try transaction.getDocument(climbRef)
            } catch let fetchError as NSError {
                errorPointer?.pointee = fetchError
                return nil
            }

            // Check if user already has a log
            var hadPreviousLog = false
            var previousRating = 0.0
            do {
                let existingLog = try transaction.getDocument(logRef)
                if existingLog.exists,
                   let prevRating = existingLog.data()?["rating"] as? Double {
                    hadPreviousLog = true
                    previousRating = prevRating
                }
            } catch { }

            // Read climb stats
            let currentAscentCount = (climbDoc.data()?["ascentCount"] as? Int) ?? 0
            let currentAvgRating = (climbDoc.data()?["avgRating"] as? Double) ?? 0.0

            var newAscentCount = currentAscentCount
            var totalRating = currentAvgRating * Double(currentAscentCount)

            if hadPreviousLog {
                // Replace user’s previous rating
                totalRating = totalRating - previousRating + rating
            } else {
                // Add new log
                newAscentCount += 1
                totalRating += rating
            }

            let newAvgRating = newAscentCount > 0 ? (totalRating / Double(newAscentCount)) : 0.0

            // Update climb stats
            transaction.updateData([
                "ascentCount": newAscentCount,
                "avgRating": newAvgRating
            ], forDocument: climbRef)

            // Update user's log
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
                print("✅ Logged climb successfully (single log per user)")
                completion(true, nil)
            }
        }
    }

    // MARK: - Fetch User Log
    func fetchUserLog(for climbID: String, completion: @escaping (String?, Double?) -> Void) {
        guard let user = Auth.auth().currentUser else {
            completion(nil, nil)
            return
        }

        let logRef = db.collection("climbs")
            .document(climbID)
            .collection("logs")
            .document(user.uid)

        logRef.getDocument { doc, _ in
            if let data = doc?.data() {
                let comment = data["comment"] as? String
                let rating = data["rating"] as? Double
                completion(comment, rating)
            } else {
                completion(nil, nil)
            }
        }
    }

    func stopListening() {
        listener?.remove()
    }
}
