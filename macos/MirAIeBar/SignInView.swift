import AppKit
import SwiftUI

struct SignInView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var identifier = ""
    @State private var password = ""
    @State private var busy = false
    @State private var errorText: String?
    @State private var completed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if completed {
                completion
            } else {
                form
            }
        }
        .padding(24)
        .frame(width: 380)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private var form: some View {
        Group {
            HStack(spacing: 10) {
                Image(systemName: "air.conditioner.horizontal")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("MirAIe Bar").font(.title3.weight(.semibold))
                    Text("Control your Panasonic ACs from the menu bar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            TextField("Mobile number or email", text: $identifier)
                .textFieldStyle(.roundedBorder)
            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .onSubmit { submit() }
            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }
            HStack {
                Spacer()
                if busy {
                    ProgressView().controlSize(.small)
                }
                Button("Sign In") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(busy || identifier.isEmpty || password.isEmpty)
            }
            Text("Credentials are stored locally with owner-only permissions. The app talks directly to the MirAIe cloud.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var completion: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.green)
                Text("You're signed in").font(.title3.weight(.semibold))
            }
            Text("Look for the AC icon in your menu bar. Click it to see your devices.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func submit() {
        guard !busy else { return }
        busy = true
        errorText = nil
        Task {
            do {
                try await model.signIn(
                    identifier: identifier.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: password
                )
                if model.phase == .ready {
                    completed = true
                } else {
                    errorText = model.lastError ?? "Signed in, but device sync failed"
                }
            } catch {
                errorText = error.localizedDescription
            }
            busy = false
        }
    }
}
