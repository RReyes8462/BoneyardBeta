import SwiftUI
import FirebaseAuth

struct LoginView: View {
    @EnvironmentObject var auth: AuthManager
    @State private var email = ""
    @State private var password = ""
    @State private var isRegistering = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 25) {
            Text("Boneyard Beta")
                .font(.largeTitle.bold())
                .padding(.top, 60)

            TextField("Email", text: $email)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)
                .frame(maxWidth: 320)

            SecureField("Password", text: $password)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)
                .frame(maxWidth: 320)

            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .font(.footnote)
            }

            Button {
                Task {
                    do {
                        if isRegistering {
                            try await auth.register(email: email, password: password)
                        } else {
                            try await auth.signIn(email: email, password: password)
                        }
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            } label: {
                Text(isRegistering ? "Create Account" : "Sign In")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .frame(maxWidth: 320)
            }
            .padding(.top, 8)

            Button {
                isRegistering.toggle()
            } label: {
                Text(isRegistering
                     ? "Already have an account? Sign in"
                     : "Don't have an account? Register")
                    .font(.footnote)
                    .foregroundColor(.blue)
            }

            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
    }
}
