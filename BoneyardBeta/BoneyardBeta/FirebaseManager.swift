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

    // MARK: - Log Climb Send (User)
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
            // Read current climb
            let climbDoc: DocumentSnapshot
            do {
                climbDoc = try transaction.getDocument(climbRef)
            } catch let fetchError as NSError {
                errorPointer?.pointee = fetchError
                return nil
            }

            // Safely unwrap existing data
            let currentAscentCount = (climbDoc.data()?["ascentCount"] as? Int) ?? 0
            let currentAvgRating = (climbDoc.data()?["avgRating"] as? Double) ?? 0.0

            // Compute new stats
            let newAscentCount = currentAscentCount + 1
            let newAvgRating = ((currentAvgRating * Double(currentAscentCount)) + rating) / Double(newAscentCount)

            // Update climb stats
            transaction.updateData([
                "ascentCount": newAscentCount,
                "avgRating": newAvgRating
            ], forDocument: climbRef)

            // Write user's log
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

    // MARK: - Stop Listening
    func stopListening() {
        listener?.remove()
    }
}
