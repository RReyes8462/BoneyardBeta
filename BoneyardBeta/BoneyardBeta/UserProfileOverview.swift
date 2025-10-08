//
//  UserProfileOverview.swift
//  BoneyardBeta
//
//  Created by Red Reyes on 10/8/25.
//


import SwiftUI
import FirebaseFirestore
import FirebaseStorage
import FirebaseAuth

struct UserProfileOverview: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var firebase: FirebaseManager

    @State private var totalSends: Int = 0
    @State private var sendsByGrade: [String: Int] = [:]
    @State private var videosByGrade: [String: [VideoData]] = [:]
    @State private var expandedGrades: Set<String> = []

    private let db = Firestore.firestore()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {

                // ===================================================
                // MARK: - Profile Header
                // ===================================================
                if let user = auth.user {
                    VStack(spacing: 8) {
                        AsyncImage(url: user.photoURL) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            Circle().fill(Color.gray.opacity(0.3))
                        }
                        .frame(width: 100, height: 100)
                        .clipShape(Circle())
                        .shadow(radius: 4)

                        Text(user.displayName ?? "Anonymous")
                            .font(.title2.bold())

                        Text(user.email ?? "")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    }
                    .padding(.top, 30)
                }

                Divider().padding(.horizontal)

                // ===================================================
                // MARK: - Stats Summary
                // ===================================================
                VStack(spacing: 10) {
                    Text("🧗 Total Sends: \(totalSends)")
                        .font(.title3.bold())

                    ForEach(sortedGrades(), id: \.self) { grade in
                        HStack {
                            Text(grade)
                            Spacer()
                            Text("\(sendsByGrade[grade] ?? 0)")
                        }
                        .font(.subheadline)
                        .padding(.horizontal)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)

                // ===================================================
                // MARK: - Expandable Video Sections
                // ===================================================
                VStack(alignment: .leading, spacing: 10) {
                    Text("🎥 Beta Videos")
                        .font(.headline)
                        .padding(.horizontal)

                    ForEach(sortedGrades(), id: \.self) { grade in
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expandedGrades.contains(grade) },
                                set: { expanded in
                                    if expanded {
                                        expandedGrades.insert(grade)
                                    } else {
                                        expandedGrades.remove(grade)
                                    }
                                }
                            ),
                            content: {
                                if let videos = videosByGrade[grade], !videos.isEmpty {
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 12) {
                                            ForEach(videos) { video in
                                                VideoPreview(video: video)
                                            }
                                        }
                                        .padding(.horizontal)
                                    }
                                } else {
                                    Text("No videos yet.")
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal)
                                }
                            },
                            label: {
                                HStack {
                                    Text(grade)
                                        .font(.subheadline.bold())
                                    Spacer()
                                    Text("\(videosByGrade[grade]?.count ?? 0)")
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal)
                            }
                        )
                        .padding(.vertical, 4)
                    }
                }
                .padding(.bottom, 30)
            }
            .padding(.horizontal)
        }
        .navigationTitle("My Profile")
        .onAppear(perform: loadUserStats)
    }

    // MARK: - Load User Stats
    private func loadUserStats() {
        guard let user = auth.user else { return }

        // 1️⃣ Get all logs for the current user
        db.collectionGroup("logs")
            .whereField("userID", isEqualTo: user.uid)
            .addSnapshotListener { snapshot, error in
                guard let docs = snapshot?.documents else { return }

                var gradeCounts: [String: Int] = [:]
                totalSends = docs.count

                for doc in docs {
                    let grade = doc["grade"] as? String ?? "Ungraded"
                    gradeCounts[grade, default: 0] += 1
                }

                sendsByGrade = gradeCounts
            }

        // 2️⃣ Get all videos uploaded by the current user
        db.collectionGroup("videos")
            .whereField("uploaderID", isEqualTo: user.uid)
            .addSnapshotListener { snapshot, error in
                guard let docs = snapshot?.documents else { return }

                var grouped: [String: [VideoData]] = [:]
                for doc in docs {
                    if let data = try? doc.data(as: VideoData.self) {
                        let grade = extractGrade(from: data.url) ?? "Ungraded"
                        grouped[grade, default: []].append(data)
                    }
                }
                videosByGrade = grouped
            }
    }

    // MARK: - Helpers
    private func sortedGrades() -> [String] {
        let gradeOrder = [
            "Blue Tag (VB–V0)",
            "Red Tag (V0–V2)",
            "Yellow Tag (V2–4)",
            "Green Tag (V4–6)",
            "Purple Tag (V6–8)",
            "Pink Tag (V8+)",
            "White Tag (Ungraded)"
        ]
        let existing = Array(sendsByGrade.keys).filter { gradeOrder.contains($0) }
        return gradeOrder.filter { existing.contains($0) }
    }

    private func extractGrade(from url: String) -> String? {
        // If you store grade info in the video doc, replace this with data.grade
        // This is a fallback in case it's embedded in the filename
        if url.lowercased().contains("vb") { return "Blue Tag (VB–V0)" }
        if url.lowercased().contains("v0") || url.lowercased().contains("v2") { return "Red Tag (V0–V2)" }
        if url.lowercased().contains("v4") { return "Yellow Tag (V2–4)" }
        if url.lowercased().contains("v6") { return "Green Tag (V4–6)" }
        if url.lowercased().contains("v8") { return "Purple Tag (V6–8)" }
        return "White Tag (Ungraded)"
    }
}

// MARK: - Video Preview Subview
struct VideoPreview: View {
    let video: VideoData

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Rectangle()
                    .fill(Color.black.opacity(0.2))
                    .frame(width: 120, height: 80)
                    .cornerRadius(8)
                    .overlay(
                        Image(systemName: "play.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .foregroundColor(.white)
                    )

                AsyncImage(url: URL(string: video.url)) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Color.gray.opacity(0.3)
                }
                .frame(width: 120, height: 80)
                .cornerRadius(8)
            }

            Text(video.uploaderEmail)
                .font(.caption2)
                .lineLimit(1)
        }
    }
}
