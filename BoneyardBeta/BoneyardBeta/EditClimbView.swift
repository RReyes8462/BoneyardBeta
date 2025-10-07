import SwiftUI
import FirebaseFirestore

struct EditClimbView: View {
    @State var climb: Climb
    var onSave: (Climb) -> Void
    var onDelete: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false
    
    // Available color options
    let colorOptions = ["red", "orange", "blue", "green", "purple", "yellow", "black", "white"]
    
    // Grade options with color-coded tags
    let gradeOptions: [(color: Color, label: String)] = [
        (.red, "Blue Tag (VB–V0)"),
        (.blue, "Red Tag (V0–V2)"),
        (.yellow, "Yellow Tag (V2–4)"),
        (.green, "Green Tag (V4–6)"),
        (.purple, "Purple Tag (V6–8)"),
        (.pink, "Pink Tag (V8+)"),
        (.white, "White Tag (Ungraded)")
    ]
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Climb Details")) {
                    TextField("Name", text: $climb.name)
                    
                    // Grade picker dropdown
                    Picker("Grade", selection: $climb.grade) {
                        ForEach(gradeOptions, id: \.label) { option in
                            HStack {
                                Circle()
                                    .fill(option.color)
                                    .frame(width: 16, height: 16)
                                Text(option.label)
                            }
                            .tag(option.label)
                        }
                    }
                    
                    // Color picker dropdown
                    Picker("Color", selection: $climb.color) {
                        ForEach(colorOptions, id: \.self) { colorName in
                            HStack {
                                Circle()
                                    .fill(colorFromString(colorName))
                                    .frame(width: 16, height: 16)
                                Text(colorName.capitalized)
                            }
                            .tag(colorName)
                        }
                    }
                }
                
                Section(header: Text("Meta")) {
                    Text("Gym: \(climb.gymID)")
                    Text("Updated by: \(climb.updatedBy)")
                }
                
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete Climb", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Edit Climb")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(climb)
                        dismiss()
                    }
                }
            }
            .alert("Delete Climb?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    onDelete()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete \(climb.name).")
            }
        }
    }
    
    private func colorFromString(_ name: String) -> Color {
        switch name.lowercased() {
        case "red": return .red
        case "blue": return .blue
        case "orange": return .orange
        case "green": return .green
        case "purple": return .purple
        case "yellow": return .yellow
        case "black": return .black
        case "white": return .gray
        case "pink": return .pink
        default: return .black
        }
    }
}
