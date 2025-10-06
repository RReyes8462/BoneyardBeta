import SwiftUI
import FirebaseFirestore

struct EditClimbView: View {
    @State var climb: Climb
    var onSave: (Climb) -> Void
    var onDelete: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false
    
    // Available color options
    let colorOptions = ["red", "blue", "green", "purple", "yellow", "gray", "white"]

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Climb Details")) {
                    TextField("Name", text: $climb.name)
                    TextField("Grade", text: $climb.grade)
                    
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
        case "green": return .green
        case "purple": return .purple
        case "yellow": return .yellow
        case "gray": return .gray
        case "white": return .white
        default: return .black
        }
    }
}
