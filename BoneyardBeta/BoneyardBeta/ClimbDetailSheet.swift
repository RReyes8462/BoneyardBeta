import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct ClimbDetailSheet: View {
    @EnvironmentObject var firebase: FirebaseManager
    @EnvironmentObject var auth: AuthManager

    let climb: Climb
    let onDismiss: () -> Void

    @State private var comment: String = ""
    @State private var rating: Int = 0
    @State private var message: String?
    @State private var isSubmitting = false

    var body: some View {
        NavigationView {
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

                if let message = message {
                    Text(message)
                        .foregroundColor(message.hasPrefix("✅") ? .green : .red)
                        .padding(.top, 6)
                }

                Spacer()

                // MARK: - Submit Button
                Button(action: submitLog) {
                    HStack {
                        if isSubmitting {
                            ProgressView()
                        }
                        Text("Submit Log")
                            .bold()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isSubmitting ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(isSubmitting)
            }
            .padding()
            .navigationTitle("Climb Details")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { onDismiss() }
                }
            }
        }
    }

    // MARK: - Log Submit Action
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
                    comment = ""
                    rating = 0
                } else {
                    message = "❌ Failed to log climb: \(error ?? "Unknown error")"
                }
            }
        }
    }
}
