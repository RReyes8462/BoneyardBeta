import Foundation
import SwiftUI
import FirebaseFirestore

struct ClimbLog: Codable, Identifiable {
    @DocumentID var id: String?
    var userID: String
    var email: String
    var comment: String
    var rating: Int
    var timestamp: Date
}

struct Climb: Codable, Identifiable {
    @DocumentID var id: String?
    var name: String
    var grade: String
    var color: String
    var x: CGFloat
    var y: CGFloat
    var gymID: String
    var updatedBy: String?
    var ascentCount: Int = 0
    var avgRating: Double = 0.0
    var section: String?
    // Map color string to SwiftUI Color
    var colorValue: Color {
        switch color.lowercased() {
        case "purple": return .purple
        case "red": return .red
        case "blue": return .blue
        case "green": return .green
        case "yellow": return .yellow
        case "orange": return .orange
        case "black": return .black
        case "white": return .white
        case "gray": return .gray
        default: return .gray
        }
    }
}
struct GradeVote: Codable, Identifiable, Equatable {
    @DocumentID var id: String?
    var userID: String
    var gradeVote: String
}

struct Comment: Identifiable, Codable {
    @DocumentID var id: String?
    var userID: String
    var text: String
    var timestamp: Date
}
struct VideoData: Identifiable, Codable{
    var id: String
    var url: String
    var uploaderID: String
    var uploaderEmail: String
    var likes: [String]
}
